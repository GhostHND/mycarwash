<?php
namespace App\Http\Controllers\Api\V1;
use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
class CompanyAttendanceReportB25Controller extends Controller {
    public function index(Request $request,int $company): JsonResponse {
        $userId = (int)$request->user()->id;
        $authorized = DB::table('user_roles as ur')->join('roles as r',function($j){$j->on('r.id','=','ur.role_id')->on('r.company_id','=','ur.company_id');})
            ->where('ur.company_id',$company)->where('ur.user_id',$userId)->where('r.code','owner')->exists();
        if (!$authorized) {
            $authorized = DB::table('user_roles as ur')->join('role_permission as rp','rp.role_id','=','ur.role_id')
                ->join('permissions as p','p.id','=','rp.permission_id')->where('ur.company_id',$company)
                ->where('ur.user_id',$userId)->where('p.code','company.update')->exists();
        }
        abort_unless($authorized && !\App\Support\WasherAccess24N3::isWasher($company,$userId),403);
        $v = $request->validate(['from'=>['required','date_format:Y-m-d'],'to'=>['required','date_format:Y-m-d','after_or_equal:from'],
            'employee_id'=>['sometimes','integer','min:1']]);
        $query = DB::table('washer_attendance_24n3 as a')->join('employees as e',function($j){
            $j->on('e.id','=','a.employee_id')->on('e.company_id','=','a.company_id');
        })->where('a.company_id',$company)->whereBetween('a.work_date',[$v['from'],$v['to']]);
        if (isset($v['employee_id'])) $query->where('a.employee_id',$v['employee_id']);
        $rows = $query->orderBy('a.work_date')->orderBy('e.full_name')->limit(2000)
            ->get(['a.id','a.employee_id','e.full_name','a.work_date','a.check_in_at','a.check_out_at']);
        return response()->json(['data'=>$rows,'count'=>$rows->count()]);
    }
}
