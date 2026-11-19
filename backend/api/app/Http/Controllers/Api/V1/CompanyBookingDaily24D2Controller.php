<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** Asignación previa de reservas: NO crea ni inicia órdenes de lavado. */
class CompanyBookingDaily24D2Controller extends Controller
{
    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $userId = $request->user()->id;
        if (!DB::table('company_user')->join('companies', 'companies.id','=','company_user.company_id')
            ->where('company_user.company_id',$company)->where('company_user.user_id',$userId)
            ->where('company_user.status','active')->where('companies.is_active',true)->exists()) abort(404);
        $allowed = DB::table('user_roles as ur')->join('roles as r',function($j):void {
            $j->on('r.id','=','ur.role_id')->on('r.company_id','=','ur.company_id');
        })->join('role_permission as rp','rp.role_id','=','r.id')->join('permissions as p','p.id','=','rp.permission_id')
            ->where('ur.company_id',$company)->where('ur.user_id',$userId)->where('p.code',$permission)->exists();
        if (!$allowed) abort(403);
    }

    private function branch(int $company, int $branchId): object
    {
        $branch=DB::table('branches')->where('id',$branchId)->where('company_id',$company)->where('is_active',true)->first();
        if (!$branch) abort(404,'Sucursal no disponible.');
        return $branch;
    }

    private function bookingsForDay(int $company, int $branchId, string $date, string $tz)
    {
        $from=CarbonImmutable::parse($date.' 00:00:00',$tz)->utc()->format('Y-m-d H:i:s');
        $to=CarbonImmutable::parse($date.' 00:00:00',$tz)->addDay()->utc()->format('Y-m-d H:i:s');
        return DB::table('wash_bookings as b')->join('vehicles as v',function($j):void {
            $j->on('v.id','=','b.vehicle_id')->on('v.company_id','=','b.company_id');
        })->leftJoin('clients as c',function($j):void {
            $j->on('c.id','=','v.client_id')->on('c.company_id','=','v.company_id');
        })->join('wash_services as s',function($j):void {
            $j->on('s.id','=','b.service_id')->on('s.company_id','=','b.company_id');
        })->leftJoin('booking_daily_assignments as a',function($j):void {
            $j->on('a.booking_id','=','b.id')->on('a.company_id','=','b.company_id')
                ->on('a.booking_start_utc','=','b.start_at_utc');
        })->leftJoin('employees as e','e.id','=','a.employee_id')
            ->leftJoin('booking_order_links_24n7 as link', function($j):void {
                $j->on('link.booking_id','=','b.id')->on('link.company_id','=','b.company_id');
            })
            ->where('b.company_id',$company)->where('b.branch_id',$branchId)->whereNull('b.deleted_at')
            ->where('b.status','CONFIRMED')->whereNull('link.order_id')->where('b.start_at_utc','>=',$from)->where('b.start_at_utc','<',$to)
            ->select('b.id','b.booking_code','b.start_at_utc','b.end_at_utc','b.bay_id','b.vehicle_id',
                'v.brand','v.model','v.plate','c.full_name as client_name','s.name as service_name',
                'a.employee_id','e.full_name as employee_name')->orderBy('b.start_at_utc')->orderBy('b.id');
    }

    public function overview(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $f=$request->validate(['branch_id'=>['required','integer','min:1']]);
        $branch=$this->branch($company,(int)$f['branch_id']);
        $today=CarbonImmutable::now($branch->timezone)->toDateString();
        $tomorrow=CarbonImmutable::now($branch->timezone)->addDay()->toDateString();
        $todayRows=$this->bookingsForDay($company,(int)$branch->id,$today,$branch->timezone)->get();
        $tomorrowRows=$this->bookingsForDay($company,(int)$branch->id,$tomorrow,$branch->timezone)->get();
        $present = function ($rows) use ($branch) {
            return $rows->map(function ($row) use ($branch) {
                $entry = (array) $row;
                $entry['local_time'] = CarbonImmutable::parse($row->start_at_utc, 'UTC')
                    ->setTimezone($branch->timezone)->format('h:i A');
                return $entry;
            })->values();
        };
        $readIds=DB::table('booking_reminder_reads')->where('company_id',$company)->where('branch_id',$branch->id)
            ->where('user_id',$request->user()->id)->where('target_date',$tomorrow)->pluck('booking_id')->all();
        $unread=$tomorrowRows->reject(fn($row)=>in_array((int)$row->id,array_map('intval',$readIds),true));
        $staff=DB::table('employees')->where('company_id',$company)->whereNull('deleted_at')
            ->where('is_active',true)->whereIn('position',['washer','supervisor'])->orderBy('full_name')
            ->get(['id','full_name']);
        return response()->json([
            'branch_id'=>(int)$branch->id,'local_today'=>$today,'local_tomorrow'=>$tomorrow,
            'pending_count'=>$todayRows->whereNull('employee_id')->count(),
            'today'=>$present($todayRows),'tomorrow'=>$present($unread),
            'tomorrow_acknowledged'=>$unread->isEmpty(),'employees'=>$staff,
        ]);
    }

    /** Una reserva puede tener un lavador asignado; el lavador no puede cubrir citas solapadas. */
    public function assign(Request $request, int $company, int $booking): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.update');
        $f=$request->validate(['employee_id'=>['required','integer','min:1']]);
        $employeeId=(int)$f['employee_id'];
        $result=DB::transaction(function()use($company,$booking,$employeeId,$request):array {
            $b=DB::table('wash_bookings')->where('id',$booking)->where('company_id',$company)
                ->whereNull('deleted_at')->lockForUpdate()->first();
            if(!$b || $b->status!=='CONFIRMED') throw ValidationException::withMessages(['booking_id'=>'Reserva no confirmada.']);
            $branch=DB::table('branches')->where('id',$b->branch_id)->where('company_id',$company)
                ->where('is_active',true)->lockForUpdate()->first();
            if(!$branch) throw ValidationException::withMessages(['branch_id'=>'Sucursal no disponible.']);
            if(CarbonImmutable::parse($b->start_at_utc,'UTC')->setTimezone($branch->timezone)->toDateString()
                !==CarbonImmutable::now($branch->timezone)->toDateString()) {
                throw ValidationException::withMessages(['booking_id'=>'Solo se asignan aquí las reservas de hoy.']);
            }
            $employee=DB::table('employees')->where('company_id',$company)->where('id',$employeeId)
                ->lockForUpdate()->whereNull('deleted_at')->where('is_active',true)
                ->whereIn('position',['washer','supervisor'])->first();
            if(!$employee) throw ValidationException::withMessages(['employee_id'=>'Lavador no disponible.']);
            $date=CarbonImmutable::parse($b->start_at_utc,'UTC')->setTimezone($branch->timezone)->toDateString();
            $from=CarbonImmutable::parse($b->start_at_utc,'UTC')->setTimezone($branch->timezone)->format('H:i:s');
            $to=CarbonImmutable::parse($b->end_at_utc,'UTC')->setTimezone($branch->timezone)->format('H:i:s');
            $day=(int)CarbonImmutable::parse($date,$branch->timezone)->dayOfWeek;
            $roster=DB::table('staff_shift_assignments as a')->join('staff_shifts as s',function($j):void {
                $j->on('s.id','=','a.shift_id')->on('s.company_id','=','a.company_id');
            })->where('a.company_id',$company)->where('a.branch_id',$b->branch_id)
                ->where('a.employee_id',$employeeId)->where('a.is_active',true)->whereNull('a.deleted_at')
                ->where('s.is_active',true)->whereNull('s.deleted_at')->where('s.day_of_week',$day)
                ->where('s.starts_at','<=',$from)->where('s.ends_at','>=',$to)
                ->where('a.effective_from','<=',$date)
                ->where(fn($q)=>$q->whereNull('a.effective_to')->orWhere('a.effective_to','>=',$date))->exists();
            if(!$roster) throw ValidationException::withMessages(['employee_id'=>'El lavador no cubre la cita en su turno.']);
            $conflict=DB::table('booking_daily_assignments as a')->join('wash_bookings as b',function($j):void {
                $j->on('b.id','=','a.booking_id')->on('b.company_id','=','a.company_id')
                    ->on('b.start_at_utc','=','a.booking_start_utc');
            })->where('a.company_id',$company)->where('a.employee_id',$employeeId)
                ->where('a.booking_id','!=',$booking)->where('b.status','CONFIRMED')->whereNull('b.deleted_at')
                ->where('b.start_at_utc','<',$b->end_at_utc)->where('b.end_at_utc','>',$b->start_at_utc)->exists();
            if($conflict) throw ValidationException::withMessages(['employee_id'=>'El lavador tiene otra cita en este horario.']);
            DB::table('booking_daily_assignments')->updateOrInsert(
                ['company_id'=>$company,'booking_id'=>$booking],
                ['branch_id'=>$b->branch_id,'employee_id'=>$employeeId,'booking_start_utc'=>$b->start_at_utc,
                 'assigned_by'=>$request->user()->id,'updated_at'=>now(),'created_at'=>now()]
            );
            return ['booking_id'=>$booking,'employee_id'=>$employeeId];
        });
        return response()->json(['message'=>'Reserva asignada; el lavado no se ha iniciado.','data'=>$result]);
    }

    public function acknowledgeTomorrow(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request,$company,'company.view');
        $f=$request->validate(['branch_id'=>['required','integer','min:1']]);
        $branch=$this->branch($company,(int)$f['branch_id']);
        $tomorrow=CarbonImmutable::now($branch->timezone)->addDay()->toDateString();
        $rows=$this->bookingsForDay($company,(int)$branch->id,$tomorrow,$branch->timezone)->get();
        $entries=$rows->map(fn($row)=>[
            'company_id'=>$company,'branch_id'=>$branch->id,'user_id'=>$request->user()->id,
            'booking_id'=>$row->id,'target_date'=>$tomorrow,'created_at'=>now(),'updated_at'=>now(),
        ])->all();
        if($entries!==[]) DB::table('booking_reminder_reads')->insertOrIgnore($entries);
        return response()->json(['message'=>'Recordatorio revisado.']);
    }
}
