<?php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/** B25L: reporte de comisiones devengadas, no pago de nómina; solo lectura. */
final class CompanyCommissionReportB25LController extends Controller
{
    private const TZ = 'America/Tegucigalpa';

    public function index(Request $request, int $company): JsonResponse
    {
        $uid = (int) $request->user()->id;
        $member = DB::table('company_user')->where('company_id', $company)
            ->where('user_id', $uid)->where('status', 'active')->exists();
        abort_unless($member, 403);
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($j): void {
            $j->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->where('ur.company_id', $company)->where('ur.user_id', $uid)
          ->where('r.code', 'owner')->exists();
        if (!$allowed) {
            $allowed = DB::table('user_roles as ur')->join('role_permission as rp', 'rp.role_id', '=', 'ur.role_id')
                ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
                ->where('ur.company_id', $company)->where('ur.user_id', $uid)
                ->whereIn('p.code', ['company.view', 'company.update'])->exists();
        }
        abort_unless($allowed && !\App\Support\WasherAccess24N3::isWasher($company, $uid), 403);
        $v = $request->validate([
            'from' => ['required','date_format:Y-m-d'],
            'to' => ['required','date_format:Y-m-d','after_or_equal:from'],
            'employee_id' => ['sometimes','integer','min:1'],
            'branch_id' => ['sometimes','integer','min:1'],
        ]);
        $startLocal = CarbonImmutable::createFromFormat('!Y-m-d', $v['from'], self::TZ);
        $endLocal = CarbonImmutable::createFromFormat('!Y-m-d', $v['to'], self::TZ);
        if (!$startLocal || !$endLocal || $startLocal->diffInDays($endLocal) > 366) {
            throw ValidationException::withMessages(['from' => 'Período máximo de 367 días.']);
        }
        $first = $startLocal->startOfDay()->utc()->format('Y-m-d H:i:s');
        $until = $endLocal->addDay()->startOfDay()->utc()->format('Y-m-d H:i:s');
        $branch = isset($v['branch_id']) ? (int)$v['branch_id'] : null;
        if ($branch !== null) {
            abort_unless(DB::table('branches')->where('company_id',$company)->where('id',$branch)->exists(), 422);
        }
        if (isset($v['employee_id'])) {
            abort_unless(DB::table('employees')->where('company_id',$company)->where('id',$v['employee_id'])->exists(),422);
        }
        foreach (['wash_orders','wash_order_service_lines_b25','employees','vehicles','washer_attendance_24n3'] as $table) {
            if (!Schema::hasTable($table)) {
                return response()->json(['message'=>'Falta la estructura de comisiones: '.$table], 409);
            }
        }
        $query=DB::table('wash_orders as o')->where('o.company_id',$company)
            ->whereIn('o.status',['TERMINADO','ENTREGADO'])
            ->whereRaw('COALESCE(o.completed_at,o.delivered_at) >= ?',[$first])
            ->whereRaw('COALESCE(o.completed_at,o.delivered_at) < ?',[$until]);
        if ($branch!==null) $query->where('o.branch_id',$branch);
        // Límite explícito: no aparentar que el reporte abarca todos si excede el máximo.
        $orders=$query->orderBy('o.id')->limit(2001)->get(['o.id','o.branch_id','o.vehicle_id','o.tracking_code','o.completed_at','o.delivered_at']);
        if ($orders->count()>2000) {
            return response()->json(['message'=>'Demasiadas órdenes. Selecciona un período más corto.'],422);
        }
        if ($orders->isEmpty()) return response()->json(['data'=>[
            'from'=>$v['from'],'to'=>$v['to'],'rows'=>[],'employees'=>[],
            'total_recognized'=>'0.00','total_pending'=>'0.00','total_services'=>0,
            'note'=>'Comisiones reconocidas (gasto devengado), no pagos de caja.',
        ]]);
        $ids=$orders->pluck('id')->all();
        $lines=DB::table('wash_order_service_lines_b25')->where('company_id',$company)
            ->whereIn('order_id',$ids)->orderBy('order_id')->orderBy('line_order')->orderBy('id')
            ->get(['id','order_id','service_name','price','commission_percent','commission_employee_id']);
        if ($lines->count()>5000) return response()->json(['message'=>'Demasiados servicios. Reduce el período.'],422);
        $byOrder=$orders->keyBy('id');
        $principal=[];
        foreach (DB::table('wash_assignments')->where('company_id',$company)->whereIn('order_id',$ids)
            ->orderBy('order_id')->orderBy('assigned_at')->orderBy('id')
            ->get(['order_id','employee_id']) as $assignment) {
            $principal[(int)$assignment->order_id] ??= (int)$assignment->employee_id;
        }
        $employees=DB::table('employees')->where('company_id',$company)->get(['id','full_name'])->keyBy('id');
        $vehicles=DB::table('vehicles')->where('company_id',$company)->whereIn('id',$orders->pluck('vehicle_id')->all())
            ->get(['id','plate','brand','model'])->keyBy('id');
        $empIds=[];
        foreach ($lines as $line) {
            $emp=$principal[(int)$line->order_id]??$line->commission_employee_id;
            if ($emp) $empIds[(int)$emp]=true;
        }
        $attendance=[];
        if ($empIds) {
            foreach (DB::table('washer_attendance_24n3')->where('company_id',$company)
                ->whereIn('employee_id',array_keys($empIds))
                ->where('check_in_at','>=',CarbonImmutable::parse($first,'UTC')->subHours(16)->format('Y-m-d H:i:s'))
                ->where('check_in_at','<',$until)->get(['employee_id','check_in_at','check_out_at']) as $mark) {
                $attendance[(int)$mark->employee_id][]=$mark;
            }
        }
        $items=[];$summary=[];$total=0;$pending=0;
        foreach ($lines as $line) {
            $order=$byOrder[$line->order_id]??null;
            if (!$order) continue;
            $employee=(int)($principal[(int)$line->order_id]??$line->commission_employee_id??0);
            if ($employee<=0 || !isset($employees[$employee])) continue;
            if (isset($v['employee_id']) && $employee!==(int)$v['employee_id']) continue;
            $raw=$order->completed_at??$order->delivered_at;
            if (!$raw) continue;
            $at=CarbonImmutable::parse($raw,'UTC');
            $valid=false;
            foreach ($attendance[$employee]??[] as $mark) {
                $in=CarbonImmutable::parse($mark->check_in_at,'UTC');
                $out=$mark->check_out_at?CarbonImmutable::parse($mark->check_out_at,'UTC'):null;
                $minutes=$in->diffInMinutes($at,false);
                if ($minutes>=0 && $minutes<=960 && ($out===null||$out->greaterThanOrEqualTo($at))) {
                    $valid=true;break;
                }
            }
            $price=(float)$line->price;$percent=(float)$line->commission_percent;
            if ($price<0 || $percent<0 || $percent>100) continue;
            $cents=(int)round($price*$percent); // Precio * porcentaje /100 -> céntimos
            $vehicle=$vehicles[$order->vehicle_id]??null;
            $local=$at->setTimezone(self::TZ);
            $items[]=[
                'employee_id'=>$employee,'employee_name'=>(string)$employees[$employee]->full_name,
                'order_id'=>(int)$order->id,'order_code'=>$order->tracking_code,
                'vehicle'=>trim(implode(' ',array_filter([$vehicle->brand??'', $vehicle->model??'']))),
                'plate'=>$vehicle->plate??'', 'service_name'=>(string)$line->service_name,
                'date'=>$local->format('Y-m-d'),'time'=>$local->format('g:i a'),
                'price'=>number_format($price,2,'.',''), 'percent'=>number_format($percent,2,'.',''),
                'commission'=>number_format($cents/100,2,'.',''),
                'recognized'=>$valid,'reason'=>$valid?'':'Sin asistencia válida en la hora de finalización',
            ];
            $summary[$employee]??=['employee_id'=>$employee,'name'=>(string)$employees[$employee]->full_name,
                'services'=>0,'recognized_services'=>0,'recognized_cents'=>0,'pending_cents'=>0];
            $summary[$employee]['services']++;
            if ($valid) {
                $total+=$cents;$summary[$employee]['recognized_cents']+=$cents;
                $summary[$employee]['recognized_services']++;
            } else {
                $pending+=$cents;$summary[$employee]['pending_cents']+=$cents;
            }
        }
        foreach ($summary as &$r) {
            $r['recognized']=number_format($r['recognized_cents']/100,2,'.','');
            $r['pending']=number_format($r['pending_cents']/100,2,'.','');
            unset($r['recognized_cents'],$r['pending_cents']);
        }unset($r);
        usort($items, static fn($a,$b)=>strcmp($a['date'].' '.$a['time'],$b['date'].' '.$b['time']));
        return response()->json(['data'=>[
            'from'=>$v['from'],'to'=>$v['to'],'rows'=>$items,'employees'=>array_values($summary),
            'total_recognized'=>number_format($total/100,2,'.',''),
            'total_pending'=>number_format($pending/100,2,'.',''),
            'total_services'=>count($items),
            'note'=>'Comisiones reconocidas: gasto devengado, no necesariamente pagado. No registrar doble egreso en caja.',
        ]]);
    }
}
