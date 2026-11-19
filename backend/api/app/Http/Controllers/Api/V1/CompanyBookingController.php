<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;
use Illuminate\Support\Str;

/** Agenda administrativa: 4 CRUD. Sin portal publico ni Raspberry. */
class CompanyBookingController extends Controller
{
    private const TABLES = [
        'bookings' => 'wash_bookings',
        'blocks' => 'booking_blocks',
        'shifts' => 'staff_shifts',
        'roster' => 'staff_shift_assignments',
    ];

    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $userId = $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $userId)
            ->where('p.code', $permission)->exists();
        if (!$allowed) abort(403, 'No autorizado.');
    }

    private function table(string $resource): string
    {
        return self::TABLES[$resource] ?? abort(404, 'Modulo no disponible.');
    }

    private function scoped(string $resource, int $company)
    {
        return DB::table($this->table($resource))->where('company_id', $company)->whereNull('deleted_at');
    }

    private function row(string $resource, int $company, int $id): object
    {
        return $this->scoped($resource, $company)->where('id', $id)->first() ?? abort(404, 'Registro no encontrado.');
    }

    private function branch(int $company, int $branchId, bool $lock = false): object
    {
        $query = DB::table('branches')->where('company_id', $company)->where('id', $branchId)->where('is_active', true);
        if ($lock) $query->lockForUpdate();
        $branch = $query->first();
        if (!$branch) throw ValidationException::withMessages(['branch_id' => 'La sucursal no existe o no está activa.']);
        try { new \DateTimeZone($branch->timezone); }
        catch (\Throwable $e) { throw ValidationException::withMessages(['branch_id' => 'La zona horaria de la sucursal no es válida.']); }
        return $branch;
    }

    private function bay(int $company, int $branchId, int $bayId): void
    {
        if (!DB::table('wash_bays')->where('company_id', $company)->where('branch_id', $branchId)
            ->where('id', $bayId)->whereNull('deleted_at')->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['bay_id' => 'El puesto debe estar activo en la sucursal seleccionada.']);
        }
    }

    private function vehicle(int $company, int $id): void
    {
        if (!DB::table('vehicles as v')->join('clients as c', function ($join): void {
            $join->on('v.client_id','=','c.id')->on('v.company_id','=','c.company_id');
        })->where('v.company_id', $company)->where('v.id', $id)->whereNull('v.deleted_at')->whereNull('c.deleted_at')
            ->where('v.is_active', true)->where('c.is_active', true)->exists()) {
            throw ValidationException::withMessages(['vehicle_id' => 'Selecciona un vehículo con cliente activo.']);
        }
    }

    private function service(int $company, int $id): object
    {
        $row = DB::table('wash_services')->where('company_id', $company)->where('id', $id)
            ->whereNull('deleted_at')->where('is_active', true)->first();
        if (!$row) throw ValidationException::withMessages(['service_id' => 'Selecciona un servicio activo.']);
        return $row;
    }

    private function timeRange(object $branch, string $date, string $from, ?string $end = null, ?int $minutes = null): array
    {
        $timezone = $branch->timezone;
        $start = CarbonImmutable::parse($date.' '.$from, $timezone);
        $finish = $end !== null ? CarbonImmutable::parse($date.' '.$end, $timezone) : $start->addMinutes($minutes ?? 0);
        // Rechazar turnos que crucen medianoche y horas inexistentes (DST).
        if ($start->format('Y-m-d H:i') !== $date.' '.$from ||
            ($end !== null && $finish->format('Y-m-d H:i') !== $date.' '.$end) ||
            $finish->lessThanOrEqualTo($start) || $finish->toDateString() !== $date) {
            throw ValidationException::withMessages(['start_time' => 'Intervalo horario no válido o fuera del día.']);
        }
        return [$start, $finish, $start->setTimezone('UTC')->format('Y-m-d H:i:s'),
            $finish->setTimezone('UTC')->format('Y-m-d H:i:s')];
    }

    private function ensureBookingWindow(int $company, object $branch, CarbonImmutable $start, CarbonImmutable $end): void
    {
        if ($start->lessThan(CarbonImmutable::now($branch->timezone)) ||
            $start->greaterThan(CarbonImmutable::now($branch->timezone)->addDays(180))) {
            throw ValidationException::withMessages(['local_date' => 'La reserva debe estar entre ahora y los próximos 180 días.']);
        }
        $day = (int) $start->dayOfWeek; // mismo convenio que company_business_hours
        $date = $start->toDateString();
        $special = DB::table('company_special_hours')->where('company_id', $company)->where('special_date', $date)->first();
        $regular = DB::table('company_business_hours')->where('company_id', $company)->where('day_of_week', $day)->first();
        $hours = $special ?? $regular;
        if (!$hours || $hours->is_closed || !$hours->opens_at || !$hours->closes_at) {
            throw ValidationException::withMessages(['start_time' => 'La sucursal no tiene horario de atención disponible.']);
        }
        $open = substr($hours->opens_at, 0, 5);
        $close = substr($hours->closes_at, 0, 5);
        if ($start->format('H:i') < $open || $end->format('H:i') > $close) {
            throw ValidationException::withMessages(['start_time' => 'El lavado no cabe completo dentro del horario de atención.']);
        }
        if (!$special && $regular && $regular->break_starts_at && $regular->break_ends_at) {
            $pauseFrom = substr($regular->break_starts_at, 0, 5);
            $pauseTo = substr($regular->break_ends_at, 0, 5);
            if ($start->format('H:i') < $pauseTo && $end->format('H:i') > $pauseFrom) {
                throw ValidationException::withMessages(['start_time' => 'El servicio se cruza con el descanso del negocio.']);
            }
        }
    }

    private function checkCapacity(int $company, object $branch, int $bayId, int $vehicleId, CarbonImmutable $start,
        CarbonImmutable $end, string $utcFrom, string $utcTo, ?int $ignoreBooking = null): void
    {
        $branchId = (int) $branch->id;
        $conflict = $this->scoped('blocks', $company)->where('branch_id', $branchId)->where('is_active', true)
            ->where(function ($q) use ($bayId): void { $q->whereNull('bay_id')->orWhere('bay_id', $bayId); })
            ->where('start_at_utc', '<', $utcTo)->where('end_at_utc', '>', $utcFrom)->exists();
        if ($conflict) throw ValidationException::withMessages(['start_time' => 'El puesto o la sucursal está bloqueado en ese intervalo.']);
        $sameBay = $this->scoped('bookings', $company)->where('branch_id', $branchId)
            ->where('bay_id', $bayId)->where('status', 'CONFIRMED')
            ->where('start_at_utc','<',$utcTo)->where('end_at_utc','>',$utcFrom);
        if ($ignoreBooking !== null) $sameBay->where('id','!=',$ignoreBooking);
        if ($sameBay->exists()) throw ValidationException::withMessages(['start_time' => 'Ya existe una reserva confirmada para ese puesto.']);
        $sameVehicle = $this->scoped('bookings', $company)->where('vehicle_id', $vehicleId)
            ->where('status', 'CONFIRMED')->where('start_at_utc', '<', $utcTo)->where('end_at_utc', '>', $utcFrom);
        if ($ignoreBooking !== null) $sameVehicle->where('id', '!=', $ignoreBooking);
        if ($sameVehicle->exists()) throw ValidationException::withMessages(['vehicle_id' => 'El vehículo ya tiene otra reserva en ese intervalo.']);
        // Una orden operativa en el puesto impide reservarlo en el momento actual.
        if ($start->lessThan(CarbonImmutable::now($branch->timezone)->addHours(1)) &&
            DB::table('wash_orders')->where('company_id',$company)->where('branch_id',$branchId)
                ->where('bay_id',$bayId)->whereIn('status',['EN_ESPERA','ASIGNADO','EN_PROCESO'])->exists()) {
            throw ValidationException::withMessages(['bay_id' => 'El puesto está ocupado por una orden activa.']);
        }
        $date = $start->toDateString();
        $day = (int) $start->dayOfWeek;
        $employees = DB::table('staff_shift_assignments as a')
            ->join('staff_shifts as s', function ($join): void {
                $join->on('s.id','=','a.shift_id')->on('s.company_id','=','a.company_id');
            })->join('employees as e', function ($join): void {
                $join->on('e.id','=','a.employee_id')->on('e.company_id','=','a.company_id');
            })->where('a.company_id',$company)->where('a.branch_id',$branchId)
            ->whereNull('a.deleted_at')->where('a.is_active',true)
            ->whereNull('s.deleted_at')->where('s.is_active',true)
            ->where('s.day_of_week',$day)->where('s.starts_at','<=',$start->format('H:i:s'))
            ->where('s.ends_at','>=',$end->format('H:i:s'))
            ->where('a.effective_from','<=',$date)
            ->where(fn ($q) => $q->whereNull('a.effective_to')->orWhere('a.effective_to','>=',$date))
            ->whereNull('e.deleted_at')->where('e.is_active',true)->whereIn('e.position',['washer','supervisor'])
            ->distinct()->count('e.id');
        if ($employees < 1) throw ValidationException::withMessages(['start_time' => 'No hay lavadores en turno que cubran el lavado completo.']);
        $concurrent = $this->scoped('bookings',$company)->where('branch_id',$branchId)
            ->where('status','CONFIRMED')->where('start_at_utc','<',$utcTo)->where('end_at_utc','>',$utcFrom);
        if ($ignoreBooking !== null) $concurrent->where('id','!=',$ignoreBooking);
        if ($concurrent->count() >= $employees) {
            throw ValidationException::withMessages(['start_time' => 'La capacidad de lavadores para ese intervalo está agotada.']);
        }
    }

    private function event(int $company, int $bookingId, string $action, ?string $from, ?string $to, int $userId): void
    {
        DB::table('booking_events')->insert(['company_id'=>$company,'booking_id'=>$bookingId,'action'=>$action,
            'from_status'=>$from,'to_status'=>$to,'actor_user_id'=>$userId,'occurred_at'=>now()]);
    }

    private function decorated(string $resource, int $company, object $row): array
    {
        $data = (array) $row;
        if (in_array($resource,['bookings','blocks'],true)) {
            $branch = DB::table('branches')->where('company_id',$company)->where('id',$row->branch_id)->first();
            $tz = $branch?->timezone ?? ($row->timezone_id ?? 'America/Tegucigalpa');
            $data['local_date'] = CarbonImmutable::parse($row->start_at_utc,'UTC')->setTimezone($tz)->format('Y-m-d');
            $data['start_time'] = CarbonImmutable::parse($row->start_at_utc,'UTC')->setTimezone($tz)->format('H:i');
            $data['end_time'] = CarbonImmutable::parse($row->end_at_utc,'UTC')->setTimezone($tz)->format('H:i');
            $data['branch_name'] = $branch?->name;
        }
        if ($resource === 'bookings') {
            $v=DB::table('vehicles')->where('company_id',$company)->where('id',$row->vehicle_id)->first();
            $data['vehicle_label']=$v ? trim(implode(' ',array_filter([$v->brand,$v->model,$v->plate]))) : '';
            $data['service_name']=DB::table('wash_services')->where('company_id',$company)->where('id',$row->service_id)->value('name');
        }
        if ($resource === 'roster') {
            $data['employee_name']=DB::table('employees')->where('company_id',$company)->where('id',$row->employee_id)->value('full_name');
            $data['shift_name']=DB::table('staff_shifts')->where('company_id',$company)->where('id',$row->shift_id)->value('name');
        }
        return $data;
    }

    /** Agenda: listado real por fecha, sin alterar el CRUD existente. */
    public function agenda24D(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $filters=$request->validate([
            'date'=>['required','date_format:Y-m-d'],
            'branch_id'=>['sometimes','integer','min:1'],
            'limit'=>['sometimes','integer','between:1,50'],
        ]);
        // A booking only stores start_at_utc, not local_date. The branch timezone determines dates.
        $branchId=(int)($filters['branch_id']??0);
        if ($branchId<1) throw ValidationException::withMessages(['branch_id'=>'Selecciona una sucursal.']);
        $branch=$this->branch($company,$branchId);
        $tz=$branch->timezone;
        $day=$filters['date'];
        $from=CarbonImmutable::parse($day.' 00:00:00',$tz)->setTimezone('UTC')->format('Y-m-d H:i:s');
        $to=CarbonImmutable::parse($day.' 00:00:00',$tz)->addDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $todayLocal=CarbonImmutable::now($tz)->toDateString();
        $todayFrom=CarbonImmutable::parse($todayLocal.' 00:00:00',$tz)->setTimezone('UTC')->format('Y-m-d H:i:s');
        $todayTo=CarbonImmutable::parse($todayLocal.' 00:00:00',$tz)->addDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $base=$this->scoped('bookings',$company)->where('branch_id',$branchId);
        $selectedCount=(clone $base)->where('status','CONFIRMED')->where('start_at_utc','>=',$from)
            ->where('start_at_utc','<',$to)->count();
        $todayCount=(clone $base)->where('status','CONFIRMED')->where('start_at_utc','>=',$todayFrom)
            ->where('start_at_utc','<',$todayTo)->count();
        $upcoming=(clone $base)->where('status','CONFIRMED')
            ->where('start_at_utc','>=',CarbonImmutable::now('UTC')->format('Y-m-d H:i:s'))
            ->orderBy('start_at_utc')->limit($filters['limit']??20)->get();
        $weekStart=CarbonImmutable::parse($day.' 00:00:00',$tz)->startOfWeek();
        $weekFrom=$weekStart->setTimezone('UTC')->format('Y-m-d H:i:s');
        $weekTo=$weekStart->addWeek()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $weekBookings=(clone $base)->where('status','CONFIRMED')
            ->where('start_at_utc','>=',$weekFrom)->where('start_at_utc','<',$weekTo)
            ->orderBy('start_at_utc')->limit(100)->get()
            ->map(fn($row)=>$this->decorated('bookings',$company,$row));
        $result=$upcoming->map(function($row) use ($company) {
            $data=$this->decorated('bookings',$company,$row);
            $v=DB::table('vehicles as v')->leftJoin('clients as c',function($j):void {
                $j->on('c.id','=','v.client_id')->on('c.company_id','=','v.company_id');
            })->where('v.company_id',$company)->where('v.id',$row->vehicle_id)
                ->select('v.brand','v.model','v.plate','v.client_id','c.full_name as client_name')->first();
            $data['vehicle_brand']=$v?->brand;
            $data['vehicle_model']=$v?->model;
            $data['vehicle_plate']=$v?->plate;
            $data['client_name']=$v?->client_name;
            $data['client_id']=$v?->client_id;
            return $data;
        });
        return response()->json([
            'data'=>$result->values(),
            'confirmed_on_date'=>$selectedCount,
            'today_count'=>$todayCount,
            'week_bookings'=>$weekBookings->values(),
            'selected_date'=>$day,
        ]);
    }

    /** Horarios verificables. La confirmación POST vuelve a validar con lock de sucursal. */
    public function availability24D(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $f=$request->validate([
            'branch_id'=>['required','integer','min:1'],
            'vehicle_id'=>['required','integer','min:1'],
            'service_id'=>['required','integer','min:1'],
            'date'=>['required','date_format:Y-m-d'],
        ]);
        $branchId=(int)$f['branch_id'];
        $branch=$this->branch($company,$branchId);
        $this->vehicle($company,(int)$f['vehicle_id']);
        $service=$this->service($company,(int)$f['service_id']);
        $minutes=(int)$service->duration_minutes;
        if ($minutes<=0 || $minutes>1440) {
            throw ValidationException::withMessages(['service_id'=>'La duración del servicio no es válida.']);
        }
        $date=$f['date'];
        $selected=CarbonImmutable::parse($date.' 12:00',$branch->timezone);
        if ($selected->lessThan(CarbonImmutable::now($branch->timezone)->startOfDay()) ||
            $selected->greaterThan(CarbonImmutable::now($branch->timezone)->addDays(180)->endOfDay())) {
            throw ValidationException::withMessages(['date'=>'La fecha está fuera del período reservable.']);
        }
        $regularDay=(int)$selected->dayOfWeek;
        $hours=DB::table('company_special_hours')->where('company_id',$company)
            ->where('special_date',$date)->first()
            ??DB::table('company_business_hours')->where('company_id',$company)
                ->where('day_of_week',$regularDay)->first();
        if (!$hours || $hours->is_closed || !$hours->opens_at || !$hours->closes_at) {
            return response()->json(['date'=>$date,'duration_minutes'=>$minutes,'slots'=>[],
                'message'=>'No hay horario de atención configurado para la fecha.']);
        }
        $bays=DB::table('wash_bays')->where('company_id',$company)->where('branch_id',$branchId)
            ->whereNull('deleted_at')->where('is_active',true)->orderBy('id')->pluck('id');
        if ($bays->isEmpty()) {
            return response()->json(['date'=>$date,'duration_minutes'=>$minutes,'slots'=>[],
                'message'=>'No existen puestos activos en la sucursal.']);
        }
        $open=substr($hours->opens_at,0,5);
        $close=substr($hours->closes_at,0,5);
        $first=CarbonImmutable::parse($date.' '.$open,$branch->timezone);
        $last=CarbonImmutable::parse($date.' '.$close,$branch->timezone);
        $slots=[];
        // Intervalos de selección de 30 min; el horario de operación siempre proviene de BD.
        for ($cursor=$first; $cursor->lessThan($last) && count($slots)<48; $cursor=$cursor->addMinutes(30)) {
            $clock=$cursor->format('H:i');
            $availableBay=null;
            $error=null;
            try {
                [$start,$end,$utcFrom,$utcTo]=$this->timeRange($branch,$date,$clock,null,$minutes);
                $this->ensureBookingWindow($company,$branch,$start,$end);
                foreach ($bays as $bay) {
                    try {
                        $this->checkCapacity($company,$branch,(int)$bay,(int)$f['vehicle_id'],
                            $start,$end,$utcFrom,$utcTo);
                        $availableBay=(int)$bay;
                        break;
                    } catch (ValidationException $e) {
                        $error=collect($e->errors())->flatten()->first();
                    }
                }
            } catch (ValidationException $e) {
                $error=collect($e->errors())->flatten()->first();
            }
            $slots[]=['time'=>$clock,'available'=>$availableBay!==null,
                'bay_id'=>$availableBay,'reason'=>$availableBay===null?$error:null];
        }
        return response()->json(['date'=>$date,'duration_minutes'=>$minutes,'slots'=>$slots,
            'available_count'=>count(array_filter($slots,fn($v)=>$v['available']))]);
    }

    public function options(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        return response()->json(['data'=>[
            'branches'=>DB::table('branches')->where('company_id',$company)->where('is_active',true)->select('id','name','timezone')->orderBy('name')->get(),
            'bays'=>DB::table('wash_bays')->where('company_id',$company)->whereNull('deleted_at')->where('is_active',true)->select('id','branch_id','name','code')->get(),
            'vehicles'=>DB::table('vehicles')->where('company_id',$company)->whereNull('deleted_at')->where('is_active',true)->select('id','brand','model','plate')->get(),
            'services'=>DB::table('wash_services')->where('company_id',$company)->whereNull('deleted_at')->where('is_active',true)->select('id','name','price','duration_minutes')->get(),
            'employees'=>DB::table('employees')->where('company_id',$company)->whereNull('deleted_at')->where('is_active',true)->whereIn('position',['washer','supervisor'])->select('id','full_name')->get(),
            'shifts'=>$this->scoped('shifts',$company)->where('is_active',true)->select('id','branch_id','name','day_of_week')->get(),
        ]]);
    }

    public function index(Request $request, int $company, string $resource): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $this->table($resource);
        $filters=$request->validate(['q'=>['sometimes','nullable','string','max:120'],
            'branch_id'=>['sometimes','integer','min:1'],'page'=>['sometimes','integer','min:1'],
            'per_page'=>['sometimes','integer','between:1,50']]);
        $query=$this->scoped($resource,$company);
        if (isset($filters['branch_id'])) $query->where('branch_id',$filters['branch_id']);
        $q=trim((string)($filters['q']??''));
        if ($q!=='') {
            $field=match($resource) {'bookings'=>'booking_code','blocks'=>'reason','shifts'=>'name','roster'=>'notes'};
            $query->where($field,'like','%'.$q.'%');
        }
        $result=$query->orderByDesc('id')->paginate($filters['per_page']??10)->toArray();
        $result['data']=array_map(fn ($v)=>$this->decorated($resource,$company,(object)$v),$result['data']);
        return response()->json($result);
    }

    public function show(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        return response()->json(['data'=>$this->decorated($resource,$company,$this->row($resource,$company,$record))]);
    }

    private function validateShift(array $data): void
    {
        if (isset($data['starts_at'],$data['ends_at']) && $data['starts_at'] >= $data['ends_at']) {
            throw ValidationException::withMessages(['ends_at'=>'La salida debe ser posterior a la entrada, dentro del mismo día.']);
        }
    }

    private function validateRoster(int $company, int $shiftId, int $employeeId, string $from, ?string $to, ?int $exclude=null): object
    {
        $shift=$this->scoped('shifts',$company)->where('id',$shiftId)->where('is_active',true)->first();
        if (!$shift) throw ValidationException::withMessages(['shift_id'=>'Selecciona un turno activo.']);
        if (!DB::table('employees')->where('company_id',$company)->where('id',$employeeId)->whereNull('deleted_at')
            ->where('is_active',true)->whereIn('position',['washer','supervisor'])->exists()) {
            throw ValidationException::withMessages(['employee_id'=>'El lavador no está activo.']);
        }
        if ($to!==null && $to<$from) throw ValidationException::withMessages(['effective_to'=>'La fecha final es anterior a la fecha inicial.']);
        $other=DB::table('staff_shift_assignments as a')->join('staff_shifts as s',function ($join):void {
            $join->on('s.id','=','a.shift_id')->on('s.company_id','=','a.company_id');
        })->where('a.company_id',$company)->where('a.employee_id',$employeeId)->where('a.is_active',true)
            ->whereNull('a.deleted_at')->whereNull('s.deleted_at')->where('s.is_active',true)
            ->where('s.day_of_week',$shift->day_of_week)->where('s.starts_at','<',$shift->ends_at)
            ->where('s.ends_at','>',$shift->starts_at)->where('a.effective_from','<=',$to??'9999-12-31')
            ->where(fn($q)=>$q->whereNull('a.effective_to')->orWhere('a.effective_to','>=',$from));
        if ($exclude!==null) $other->where('a.id','!=',$exclude);
        if ($other->exists()) throw ValidationException::withMessages(['employee_id'=>'El lavador tiene otro turno superpuesto.']);
        return $shift;
    }

    private function ensureNoAffectedBookings(int $company, int $branchId): void
    {
        // No dejar sin personal reservas futuras mediante ediciones o bajas de turnos.
        if ($this->scoped('bookings',$company)->where('branch_id',$branchId)->where('status','CONFIRMED')
            ->where('start_at_utc','>=',now('UTC')->format('Y-m-d H:i:s'))->exists()) {
            throw ValidationException::withMessages(['data'=>'Hay reservas futuras; cancélalas o reprográmalas antes de cambiar turnos asignados.']);
        }
    }

    private function storeOrUpdate(Request $request,int $company,string $resource,?int $record=null): array
    {
        $creating=$record===null;
        $old=$creating?null:$this->row($resource,$company,$record);
        if ($resource==='shifts') {
            $rules=['branch_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'name'=>[$creating?'required':'sometimes','required','string','max:120'],
                'day_of_week'=>[$creating?'required':'sometimes','integer','between:0,6'],
                'starts_at'=>[$creating?'required':'sometimes','date_format:H:i'],
                'ends_at'=>[$creating?'required':'sometimes','date_format:H:i'],
                'is_active'=>['sometimes','boolean'],'notes'=>['sometimes','nullable','string','max:500']];
            $data=$request->validate($rules);
            if (!$creating && array_key_exists('branch_id',$data) && $data['branch_id']!=$old->branch_id)
                throw ValidationException::withMessages(['branch_id'=>'No se puede mover un turno entre sucursales.']);
            $branchId=(int)($old?->branch_id??$data['branch_id']); $this->branch($company,$branchId,true);
            $values=array_merge((array)($old??[]),$data); $this->validateShift($values);
            if (!$creating && $this->scoped('roster',$company)->where('shift_id',$record)->where('is_active',true)->exists()) {
                if (array_intersect(['day_of_week','starts_at','ends_at','is_active'],array_keys($data))) {
                    throw ValidationException::withMessages(['data' => 'Libera las asignaciones antes de modificar el horario o desactivar este turno.']);
                }
            }
            if (!$creating) unset($data['branch_id']);
        } elseif ($resource==='roster') {
            $rules=['shift_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'employee_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'effective_from'=>[$creating?'required':'sometimes','date_format:Y-m-d'],
                'effective_to'=>['sometimes','nullable','date_format:Y-m-d'],
                'is_active'=>['sometimes','boolean'],'notes'=>['sometimes','nullable','string','max:500']];
            $data=$request->validate($rules);
            $shiftId=(int)($data['shift_id']??$old?->shift_id);
            $shift=$this->scoped('shifts',$company)->where('id',$shiftId)->first();
            if (!$shift) throw ValidationException::withMessages(['shift_id'=>'Turno desconocido.']);
            $this->branch($company,(int)$shift->branch_id,true);
            $values=array_merge((array)($old??[]),$data);
            $this->validateRoster($company,$shiftId,(int)$values['employee_id'],$values['effective_from'], $values['effective_to']??null,$record);
            if (!$creating) $this->ensureNoAffectedBookings($company,(int)$old->branch_id);
            $data['branch_id']=$shift->branch_id;
        } elseif ($resource==='blocks') {
            $data=$request->validate(['branch_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'bay_id'=>['sometimes','nullable','integer','min:1'],
                'local_date'=>[$creating?'required':'sometimes','date_format:Y-m-d'],
                'start_time'=>[$creating?'required':'sometimes','date_format:H:i'],
                'end_time'=>[$creating?'required':'sometimes','date_format:H:i'],
                'reason'=>[$creating?'required':'sometimes','required','string','max:200'],
                'is_active'=>['sometimes','boolean']]);
            if (!$creating && isset($data['branch_id']) && $data['branch_id']!=$old->branch_id)
                throw ValidationException::withMessages(['branch_id'=>'El bloqueo no puede cambiar de sucursal.']);
            $branchId=(int)($old?->branch_id??$data['branch_id']);
            $branch=$this->branch($company,$branchId,true);
            $v=array_merge($old ? $this->decorated('blocks',$company,$old):[],$data);
            [$start,$end,$utcStart,$utcEnd]=$this->timeRange($branch,$v['local_date'],$v['start_time'],$v['end_time']);
            $bayId=$v['bay_id']??null; if ($bayId!==null) $this->bay($company,$branchId,(int)$bayId);
            if (($v['is_active']??true) && $this->scoped('bookings',$company)->where('branch_id',$branchId)
                ->where('status','CONFIRMED')->where('start_at_utc','<',$utcEnd)->where('end_at_utc','>',$utcStart)
                ->when($bayId!==null,fn($q)=>$q->where('bay_id',$bayId))->exists()) {
                throw ValidationException::withMessages(['start_time'=>'El bloqueo afectaría reservas confirmadas.']);
            }
            $data=['branch_id'=>$branchId,'bay_id'=>$bayId,'start_at_utc'=>$utcStart,'end_at_utc'=>$utcEnd,
                'reason'=>$v['reason'],'is_active'=>$v['is_active']??true];
            if (!$creating) unset($data['branch_id']);
        } else { // bookings
            $data=$request->validate(['branch_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'bay_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'vehicle_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'service_id'=>[$creating?'required':'sometimes','integer','min:1'],
                'local_date'=>[$creating?'required':'sometimes','date_format:Y-m-d'],
                'start_time'=>[$creating?'required':'sometimes','date_format:H:i'],
                'notes'=>['sometimes','nullable','string','max:1000']]);
            if (!$creating && $old->status!=='CONFIRMED') throw ValidationException::withMessages(['data'=>'Solo pueden editarse reservas confirmadas.']);
            if (!$creating && DB::table('booking_order_links_24n7')->where('company_id',$company)
                ->where('booking_id',$record)->exists()) {
                throw ValidationException::withMessages(['booking'=>'La reserva ya fue recibida y tiene orden operativa.']);
            }
            if (!$creating && isset($data['branch_id']) && $data['branch_id']!=$old->branch_id)
                throw ValidationException::withMessages(['branch_id'=>'No es posible mover reservas de sucursal.']);
            $branchId=(int)($old?->branch_id??$data['branch_id']);
            $branch=$this->branch($company,$branchId,true);
            $v=array_merge($old ? $this->decorated('bookings',$company,$old):[],$data);
            $bayId=(int)$v['bay_id']; $vehicleId=(int)$v['vehicle_id']; $serviceId=(int)$v['service_id'];
            $this->bay($company,$branchId,$bayId);
            $this->vehicle($company,$vehicleId);
            $service=$this->service($company,$serviceId);
            // Mantener precio/duracion aceptados si solo se edita una reserva;
            // cambiar el servicio crea una nueva cotizacion basada en el catalogo actual.
            $reuseSnapshot = !$creating && $serviceId === (int)$old->service_id && $vehicleId === (int)$old->vehicle_id;
            $duration = $reuseSnapshot ? (int)$old->estimated_minutes : (int)$service->duration_minutes;
            $price = $reuseSnapshot ? $old->quoted_price : \App\Support\ServiceTariff24F::resolve($company,$serviceId,$vehicleId,$service->price);
            [$start,$end,$utcStart,$utcEnd]=$this->timeRange($branch,$v['local_date'],$v['start_time'],null,$duration);
            $this->ensureBookingWindow($company,$branch,$start,$end);
            $this->checkCapacity($company,$branch,$bayId,$vehicleId,$start,$end,$utcStart,$utcEnd,$record);
            $data=['branch_id'=>$branchId,'bay_id'=>$bayId,'vehicle_id'=>$vehicleId,'service_id'=>$serviceId,
                'start_at_utc'=>$utcStart,'end_at_utc'=>$utcEnd,'local_date'=>$start->toDateString(),
                'timezone_id'=>$branch->timezone,'quoted_price'=>$price,'estimated_minutes'=>$duration,
                'notes'=>$v['notes']??null];
            if (!$creating) { unset($data['branch_id']); $data['version']=$old->version+1; }
            else { $data['status']='CONFIRMED';$data['version']=1;
                $data['public_id']=(string)Str::uuid();$data['booking_code']='RSV-'.strtoupper(bin2hex(random_bytes(10))); }
        }
        if (!$creating && !$data) throw ValidationException::withMessages(['data'=>'Indica algún campo para actualizar.']);
        if ($creating) { $data['company_id']=$company; $data['created_at']=now(); }
        $data['updated_at']=now();
        if ($creating) $id=DB::table($this->table($resource))->insertGetId($data);
        else { DB::table($this->table($resource))->where('company_id',$company)->where('id',$record)->update($data); $id=$record; }
        if ($resource==='bookings') $this->event($company,$id,$creating?'CREATED':'UPDATED',$old?->status,'CONFIRMED',(int)$request->user()->id);
        return $this->decorated($resource,$company,$this->row($resource,$company,$id));
    }

    public function store(Request $request,int $company,string $resource):JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.update'); $this->table($resource);
        $data=DB::transaction(fn()=>$this->storeOrUpdate($request,$company,$resource));
        return response()->json(['message'=>'Registro creado.','data'=>$data],201);
    }

    public function update(Request $request,int $company,string $resource,int $record):JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.update'); $this->table($resource);
        $data=DB::transaction(fn()=>$this->storeOrUpdate($request,$company,$resource,$record));
        return response()->json(['message'=>'Registro actualizado.','data'=>$data]);
    }

    public function destroy(Request $request,int $company,string $resource,int $record):JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.update'); $this->table($resource);
        DB::transaction(function()use($request,$company,$resource,$record):void {
            $row=$this->row($resource,$company,$record);
            $branchId=(int)$row->branch_id;
            $this->branch($company,$branchId,true);
            if ($resource==='shifts' && $this->scoped('roster',$company)->where('shift_id',$record)->where('is_active',true)->exists()) {
                throw ValidationException::withMessages(['shift_id'=>'Libera primero las asignaciones del turno.']);
            }
            if ($resource==='roster') $this->ensureNoAffectedBookings($company,$branchId);
            if ($resource==='bookings') {
                if (DB::table('booking_order_links_24n7')->where('company_id',$company)
                    ->where('booking_id',$record)->exists()) {
                    throw ValidationException::withMessages(['booking'=>'No se puede cancelar una reserva con vehículo recibido.']);
                }
                DB::table('wash_bookings')->where('id',$record)->where('company_id',$company)
                    ->update(['status'=>'CANCELLED','version'=>$row->version+1,'updated_at'=>now(),'deleted_at'=>now()]);
                $this->event($company,$record,'CANCELLED',$row->status,'CANCELLED',(int)$request->user()->id);
            } else {
                DB::table($this->table($resource))->where('id',$record)->where('company_id',$company)
                    ->update(['deleted_at'=>now(),'updated_at'=>now()]);
            }
        });
        return response()->json(['message'=>'Registro eliminado de los activos.']);
    }

    public function history(Request $request,int $company,int $booking):JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        if (!DB::table('wash_bookings')->where('company_id',$company)->where('id',$booking)->exists()) abort(404);
        return response()->json(['data'=>DB::table('booking_events')->where('company_id',$company)
            ->where('booking_id',$booking)->orderBy('id')->get()]);
    }
}
