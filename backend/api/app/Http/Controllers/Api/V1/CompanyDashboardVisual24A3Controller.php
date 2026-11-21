<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;
use Carbon\Carbon;

/** Dashboard visual 24A.3: datos reales de solo lectura; sin migraciones. */
final class CompanyDashboardVisual24A3Controller extends Controller
{
    private function safe(string $table, array $cols): bool
    {
        if (!Schema::hasTable($table)) return false;
        foreach ($cols as $column) if (!Schema::hasColumn($table, $column)) return false;
        return true;
    }

    public function show(Request $request, int $company): JsonResponse
    {
        $uid = (int) $request->user()->id;
        if (!DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $uid)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists()) abort(404);
        $permitted = DB::table('user_roles as ur')->join('roles as r', function ($j): void {
            $j->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $uid)
            ->where('p.code', 'company.view')->exists();
        if (!$permitted) abort(403);
        $data = $request->validate(['branch_id' => ['sometimes','integer','min:1'], 'offset' => ['sometimes','integer','min:0']]);
        $branch = isset($data['branch_id']) ? (int) $data['branch_id'] : null;
        if ($branch !== null && !DB::table('branches')->where('company_id', $company)
            ->where('id', $branch)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal no disponible.']);
        }
        $tz = 'America/Tegucigalpa';
        if ($branch !== null && Schema::hasColumn('branches', 'timezone')) {
            $candidate = (string) (DB::table('branches')->where('company_id', $company)->where('id', $branch)->value('timezone') ?? '');
            if (in_array($candidate, timezone_identifiers_list(), true)) $tz = $candidate;
        }
        $now = now($tz);
        $today = $now->toDateString();
        $start = $now->copy()->startOfDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $end = $now->copy()->addDay()->startOfDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $startWeek = $now->copy()->subDays(6)->startOfDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $warnings = [];
        $trend = [];
        for ($i = 6; $i >= 0; $i--) {
            $day = $now->copy()->subDays($i)->toDateString();
            $trend[$day] = ['date' => $day, 'sales' => null, 'expenses' => null];
        }
        if ($this->safe('pos_sales', ['company_id','branch_id','status','posted_at','total'])) {
            foreach ($trend as &$entry) $entry['sales'] = 0.0;
            unset($entry);
            $q = DB::table('pos_sales')->where('company_id', $company)->where('status', 'POSTED')
                ->where('posted_at','>=',$startWeek)->where('posted_at','<',$end);
            if ($branch !== null) $q->where('branch_id',$branch);
            if (Schema::hasColumn('pos_sales','deleted_at')) $q->whereNull('deleted_at');
            foreach ($q->cursor(['posted_at','total']) as $s) {
                $key = Carbon::parse($s->posted_at, 'UTC')->setTimezone($tz)->toDateString();
                if (isset($trend[$key])) $trend[$key]['sales'] += (float) $s->total;
            }
        } else $warnings[] = 'Ventas POS no disponibles';
        if ($this->safe('cash_movements',['company_id','session_id','direction','amount','created_at']) &&
            $this->safe('cash_sessions',['company_id','register_id']) &&
            $this->safe('cash_registers',['company_id','branch_id'])) {
            foreach ($trend as &$entry) $entry['expenses'] = 0.0;
            unset($entry);
            $q = DB::table('cash_movements as m')
                ->join('cash_sessions as s', function ($j): void {$j->on('s.id','=','m.session_id')->on('s.company_id','=','m.company_id');})
                ->join('cash_registers as r', function ($j): void {$j->on('r.id','=','s.register_id')->on('r.company_id','=','m.company_id');})
                ->where('m.company_id',$company)->where('m.direction','OUT')
                ->where('m.created_at','>=',$startWeek)->where('m.created_at','<',$end);
            if ($branch !== null) $q->where('r.branch_id',$branch);
            if (Schema::hasColumn('cash_movements','deleted_at')) $q->whereNull('m.deleted_at');
            foreach ($q->cursor(['m.created_at','m.amount']) as $m) {
                $key = Carbon::parse($m->created_at, 'UTC')->setTimezone($tz)->toDateString();
                if (isset($trend[$key])) $trend[$key]['expenses'] += (float) $m->amount;
            }
        } else $warnings[] = 'Gastos no disponibles';

        $production = null;
        if ($this->safe('wash_orders',['id','company_id','branch_id','status','completed_at']) &&
            $this->safe('wash_assignments',['order_id','employee_id','company_id']) &&
            $this->safe('employees',['id','company_id','full_name'])) {
            $q = DB::table('wash_assignments as a')->join('wash_orders as o', function ($j): void {
                $j->on('o.id','=','a.order_id')->on('o.company_id','=','a.company_id');
            })->join('employees as e',function ($j): void {
                $j->on('e.id','=','a.employee_id')->on('e.company_id','=','a.company_id');
            })->where('a.company_id',$company)->whereIn('o.status',['TERMINADO','ENTREGADO'])
                ->where('o.completed_at','>=',$start)->where('o.completed_at','<',$end);
            if ($branch !== null) $q->where('o.branch_id',$branch);
            if (Schema::hasColumn('wash_orders','deleted_at')) $q->whereNull('o.deleted_at');
            $production = $q->select('e.id','e.full_name',DB::raw('COUNT(DISTINCT o.id) as completed'))
                ->groupBy('e.id','e.full_name')->orderByDesc('completed')->orderBy('e.full_name')->limit(30)->get()
                ->map(fn($r) => ['id'=>(int)$r->id,'name'=>(string)$r->full_name,'completed'=>(int)$r->completed])->all();
        } else $warnings[] = 'Productividad por lavador no disponible';

        $services = null;
        if ($this->safe('wash_orders',['company_id','service_id','status','completed_at','branch_id']) &&
            $this->safe('wash_services',['id','company_id','name'])) {
            $q=DB::table('wash_orders as o')->join('wash_services as w', function ($j): void {
                $j->on('o.service_id','=','w.id')->on('o.company_id','=','w.company_id');
            })->where('o.company_id',$company)->whereIn('o.status',['TERMINADO','ENTREGADO'])
                ->where('o.completed_at','>=',$start)->where('o.completed_at','<',$end);
            if ($branch !== null) $q->where('o.branch_id',$branch);
            if (Schema::hasColumn('wash_orders','deleted_at')) $q->whereNull('o.deleted_at');
            $services=$q->select('w.id','w.name',DB::raw('COUNT(*) as total'))->groupBy('w.id','w.name')
                ->orderByDesc('total')->orderBy('w.id')->limit(12)->get()
                ->map(fn($r)=>['name'=>(string)$r->name,'count'=>(int)$r->total])->all();
        } else $warnings[]='Servicios completados no disponibles';

        $topItem = null;
        if ($this->safe('pos_sales',['id','company_id','status','posted_at','branch_id']) &&
            $this->safe('pos_sale_items',['company_id','sale_id','item_id','name_snapshot','quantity','line_total'])) {
            $q=DB::table('pos_sale_items as i')->join('pos_sales as s',function ($j): void {
                $j->on('s.id','=','i.sale_id')->on('s.company_id','=','i.company_id');
            })->where('s.company_id',$company)->where('s.status','POSTED')
                ->where('s.posted_at','>=',$start)->where('s.posted_at','<',$end);
            if ($branch !== null) $q->where('s.branch_id',$branch);
            $r=$q->select('i.item_id','i.name_snapshot',DB::raw('SUM(i.quantity) as units'),
                DB::raw('SUM(i.line_total) as revenue'))->groupBy('i.item_id','i.name_snapshot')
                ->orderByDesc('units')->orderBy('i.item_id')->first();
            if ($r) $topItem=['id'=>(int)$r->item_id,'name'=>(string)$r->name_snapshot,'units'=>(float)$r->units,'revenue'=>(float)$r->revenue];
        } else $warnings[]='Ranking POS no disponible';

        $bookings = null;
        $bookingsTotal = null;
        if ($this->safe('wash_bookings',['id','company_id','branch_id','local_date','start_at_utc','status','vehicle_id']) &&
            $this->safe('vehicles',['id','company_id','client_id','brand','model']) &&
            $this->safe('clients',['id','company_id','full_name'])) {
            $q=DB::table('wash_bookings as b')->join('vehicles as v',function($j):void{
                $j->on('v.id','=','b.vehicle_id')->on('v.company_id','=','b.company_id');
            })->join('clients as c',function($j):void{
                $j->on('c.id','=','v.client_id')->on('c.company_id','=','b.company_id');
            })->where('b.company_id',$company)->where('b.local_date',$today)->where('b.status','CONFIRMED');
            if ($branch !== null) $q->where('b.branch_id',$branch);
            if (Schema::hasColumn('wash_bookings','deleted_at')) $q->whereNull('b.deleted_at');
            $bookingsTotal=(clone $q)->count();
            $bookings=$q->orderBy('b.start_at_utc')->limit(25)->get(['b.id','b.start_at_utc','v.brand','v.model','c.full_name'])
                ->map(fn($r)=>['id'=>(int)$r->id,'time'=>Carbon::parse($r->start_at_utc,'UTC')->setTimezone($tz)->format('H:i'),
                    'vehicle'=>trim(($r->brand ?? '').' '.($r->model ?? '')),'client'=>(string)$r->full_name])->all();
        } else $warnings[]='Reservas detalladas no disponibles';

        $active = null;
        $activeTotal = null;
        $offset = 0;
        if ($this->safe('wash_orders',['id','company_id','branch_id','status','vehicle_id','bay_id']) &&
            $this->safe('vehicles',['id','company_id','brand','model']) &&
            $this->safe('wash_bays',['id','company_id','name'])) {
            $q=DB::table('wash_orders as o')->join('vehicles as v',function($j):void{
                $j->on('v.id','=','o.vehicle_id')->on('v.company_id','=','o.company_id');
            })->leftJoin('wash_bays as b',function($j):void{
                $j->on('b.id','=','o.bay_id')->on('b.company_id','=','o.company_id');
            })->where('o.company_id',$company)->where('o.status','EN_PROCESO');
            if ($branch !== null) $q->where('o.branch_id',$branch);
            if (Schema::hasColumn('wash_orders','deleted_at')) $q->whereNull('o.deleted_at');
            $activeTotal=(clone $q)->count();
            $offset=$activeTotal>0?((int)($data['offset']??0))%$activeTotal:0;
            $rows=(clone $q)->orderBy('o.id')->offset($offset)->limit(4)
                ->get(['o.id','o.bay_id','o.vehicle_id','b.name as bay','v.brand','v.model']);
            $orderIds=$rows->pluck('id')->all();
            $names=[];
            if ($orderIds && $this->safe('wash_assignments',['company_id','order_id','employee_id','is_active']) &&
                $this->safe('employees',['id','company_id','full_name'])) {
                $assignments=DB::table('wash_assignments as a')->join('employees as e',function($j):void{
                    $j->on('e.id','=','a.employee_id')->on('e.company_id','=','a.company_id');
                })->where('a.company_id',$company)->where('a.is_active',true)
                    ->whereIn('a.order_id',$orderIds)->get(['a.order_id','e.full_name']);
                foreach ($assignments as $assignment) $names[(int)$assignment->order_id][]=(string)$assignment->full_name;
            }
            $photoVehicleIds = [];
            if ($this->safe('company_entity_photos',['company_id','owner_type','owner_id','media_asset_id'])) {
                $vehicleIds = $rows->pluck('vehicle_id')->filter()->unique()->values()->all();
                if ($vehicleIds) {
                    $photoVehicleIds = DB::table('company_entity_photos')
                        ->where('company_id', $company)->where('owner_type', 'vehicles')
                        ->whereIn('owner_id', $vehicleIds)
                        ->pluck('owner_id')->map(fn($id) => (int) $id)->all();
                }
            }
            $active=$rows->map(fn($r)=>['id'=>(int)$r->id,'bay'=>$r->bay,
                'vehicle_id'=>(int)$r->vehicle_id,
                'photo_available'=>in_array((int)$r->vehicle_id, $photoVehicleIds, true),
                'vehicle'=>trim(($r->brand??'').' '.($r->model??'')),
                'washers'=>$names[(int)$r->id]??[], 'progress'=>null,'stage'=>null])->all();
        } else $warnings[]='Lavados en vivo detallados no disponibles';
        $financialB25J = CompanyDashboardFinanceB25J::summary($company, $branch, $tz);
        $trend = $financialB25J['trend'];
        $production = $financialB25J['production'];
        $warnings = array_merge($warnings, $financialB25J['warnings']);
        return response()->json(['data'=>[
            'date'=>$today, 'timezone'=>$tz, 'business_hour'=>(int)$now->format('G'), 'scope'=>['company_id'=>$company,'branch_id'=>$branch],
            'production'=>$production,'services'=>$services,'top_item'=>$topItem,
            'trend'=>array_values($trend),'bookings'=>$bookings,'bookings_total'=>$bookingsTotal,
            'active'=>$active,'active_total'=>$activeTotal,'active_offset'=>$offset,
            'production_note'=>'Comisiones por servicio cobradas y atribuibles al lavador principal con asistencia registrada en la fecha del trabajo.',
            'trend_note'=>'Últimos 7 días: servicios cobrados, gastos categorizados y comisiones con asistencia.',
            'warnings'=>$warnings,
        ]]);
    }
    /** Búsqueda global acotada por empresa y sucursal; solo consulta catálogos existentes. */
    public function search(Request $request, int $company): JsonResponse
    {
        $uid = (int) $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $uid)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404);
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id','=','ur.role_id')->on('r.company_id','=','ur.company_id');
        })->join('role_permission as rp','rp.role_id','=','r.id')
            ->join('permissions as p','p.id','=','rp.permission_id')
            ->where('ur.company_id',$company)->where('ur.user_id',$uid)
            ->where('p.code','company.view')->exists();
        if (!$allowed) abort(403);
        $input=$request->validate(['q'=>['required','string','min:2','max:70'],
            'branch_id'=>['sometimes','integer','min:1']]);
        $branch=isset($input['branch_id'])?(int)$input['branch_id']:null;
        if ($branch !== null && !DB::table('branches')->where('company_id',$company)
            ->where('id',$branch)->where('is_active',true)->exists()) {
            throw ValidationException::withMessages(['branch_id'=>'Sucursal no disponible.']);
        }
        $needle=trim((string)$input['q']);
        $pattern='%'.addcslashes($needle,'%_\\').'%';
        $found=[];
        if ($this->safe('clients',['company_id','full_name'])) {
            $q=DB::table('clients')->where('company_id',$company)->where('full_name','like',$pattern);
            if (Schema::hasColumn('clients','deleted_at')) $q->whereNull('deleted_at');
            foreach($q->orderBy('full_name')->limit(6)->get(['id','full_name']) as $r) {
                $found[]=['kind'=>'Cliente','label'=>(string)$r->full_name,'destination'=>'Clientes'];
            }
        }
        if ($this->safe('vehicles',['company_id','brand','model','plate'])) {
            $q=DB::table('vehicles')->where('company_id',$company)->where(function($q) use ($pattern):void {
                $q->where('brand','like',$pattern)->orWhere('model','like',$pattern)->orWhere('plate','like',$pattern);
            });
            if (Schema::hasColumn('vehicles','deleted_at')) $q->whereNull('deleted_at');
            foreach($q->orderBy('id')->limit(6)->get(['id','brand','model','plate']) as $r) {
                $found[]=['kind'=>'Vehículo','label'=>trim(($r->brand??'').' '.($r->model??'').' '.($r->plate??'')),
                    'destination'=>'Vehículos'];
            }
        }
        if ($this->safe('wash_orders',['company_id','branch_id','tracking_code'])) {
            $q=DB::table('wash_orders')->where('company_id',$company)->where('tracking_code','like',$pattern);
            if($branch !== null) $q->where('branch_id',$branch);
            if (Schema::hasColumn('wash_orders','deleted_at')) $q->whereNull('deleted_at');
            foreach($q->orderByDesc('id')->limit(6)->get(['id','tracking_code']) as $r) {
                $found[]=['kind'=>'Lavado','label'=>(string)$r->tracking_code,'destination'=>'Órdenes de lavado'];
            }
        }
        if ($this->safe('wash_bookings',['company_id','branch_id','booking_code'])) {
            $q=DB::table('wash_bookings')->where('company_id',$company)->where('booking_code','like',$pattern);
            if($branch !== null) $q->where('branch_id',$branch);
            if (Schema::hasColumn('wash_bookings','deleted_at')) $q->whereNull('deleted_at');
            foreach($q->orderByDesc('id')->limit(6)->get(['id','booking_code']) as $r) {
                $found[]=['kind'=>'Reserva','label'=>(string)$r->booking_code,'destination'=>'Reservas'];
            }
        }
        return response()->json(['data'=>['items'=>$found]]);
    }

}
