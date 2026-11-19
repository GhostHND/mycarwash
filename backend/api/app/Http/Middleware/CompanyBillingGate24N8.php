<?php
namespace App\Http\Middleware;

use App\Support\MasterBilling24N8;
use Illuminate\Support\Facades\DB;
use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/** Impide utilizar rutas de cualquier módulo, incluso con un bearer token previo. */
class CompanyBillingGate24N8 {
    public function handle(Request $request,Closure $next):Response {
        // El maestro administra incluso empresas suspendidas sin heredar su bloqueo.
        if (str_starts_with($request->path(),'api/v1/master/')) return $next($request);
        $company=$request->route('company');
        if ($company !== null && ctype_digit((string)$company) && $request->user('sanctum') && !MasterBilling24N8::allowed((int)$company)) {
            return response()->json(['code'=>'COMPANY_SUSPENDED',
                'message'=>'Acceso temporalmente suspendido por vencimiento o inactivación. Los datos se conservan.',
                'billing'=>MasterBilling24N8::state((int)$company)],403);
        }
        // Control de prestaciones disponibles según el plan contratado.
        if ($company !== null && ctype_digit((string)$company) && $request->user('sanctum')) {
            $sub = DB::table('master_subscriptions_24n8')->where('company_id',(int)$company)->first();
            if ($sub && $sub->master_plan_id) {
                $plan = DB::table('master_plans_24n8')->where('id',$sub->master_plan_id)->first();
                if ($plan) {
                    $features = json_decode((string)$plan->features,true) ?: [];
                    $path = $request->path();
                    $needed = null;
                    if (str_contains($path,'/monitor-theme-24b') || str_contains($path,'/dashboard/monitor-24b2')) {
                        $needed = 'monitor';
                    } elseif (str_contains($path,'/website/editor') || str_contains($path,'/site/editor')) {
                        $needed = 'editor';
                    } elseif (str_contains($path,'/website') || str_contains($path,'/site/marketing')) {
                        $needed = 'marketing_site';
                    }
                    if ($needed && empty($features[$needed])) return response()->json([
                        'code'=>'PLAN_FEATURE_DISABLED',
                        'message'=>'Esta función no está habilitada en el plan de la empresa.',
                    ],403);
                }
            }
        }
        return $next($request);
    }
}
