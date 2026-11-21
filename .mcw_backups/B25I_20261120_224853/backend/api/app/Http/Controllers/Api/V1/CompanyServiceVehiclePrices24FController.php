<?php
namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

class CompanyServiceVehiclePrices24FController extends Controller {
    private function authorizeCompany(Request $request, int $company, string $permission): void {
        $uid = (int) $request->user()->id;
        $member = DB::table('company_user')->join('companies','companies.id','=','company_user.company_id')
            ->where('company_user.company_id',$company)->where('company_user.user_id',$uid)
            ->where('company_user.status','active')->where('companies.is_active',true)->exists();
        if (!$member) abort(404);
        $allowed = DB::table('user_roles as ur')->join('roles as r',function ($j): void {
            $j->on('r.id','=','ur.role_id')->on('r.company_id','=','ur.company_id');
        })->join('role_permission as rp','rp.role_id','=','r.id')
            ->join('permissions as p','p.id','=','rp.permission_id')
            ->where('ur.company_id',$company)->where('ur.user_id',$uid)->where('p.code',$permission)->exists();
        if (!$allowed) abort(403);
    }
    private function service(int $company, int $id): void {
        if (!DB::table('wash_services')->where('company_id',$company)->where('id',$id)
            ->whereNull('deleted_at')->exists()) abort(404);
    }
    /** Catálogo compartido por empresa: Servicios -> Vehículos (alta y edición). */
    public function vehicleTypes(Request $request, int $company): JsonResponse {
        $this->authorizeCompany($request, $company, 'company.view');
        if (!Schema::hasTable('service_vehicle_prices')) {
            abort(503, 'Las tarifas por vehículo aún no están instaladas.');
        }
        // Los tipos base son idénticos a los que presenta el editor de tarifas 24F.2.
        $base = ['Turismo', 'Pickup', 'SUV', 'Camioneta', 'Motocicleta', 'Microbús', 'Camión'];
        $stored = DB::table('service_vehicle_prices')->where('company_id', $company)
            ->distinct()->pluck('vehicle_type');
        foreach ($stored as $type) {
            $value = trim((string)$type);
            if ($value === '') continue;
            $found = false;
            foreach ($base as $existing) {
                if (mb_strtolower($existing) === mb_strtolower($value)) {
                    $found = true;
                    break;
                }
            }
            if (!$found) $base[] = $value;
        }
        return response()->json(['data' => $base]);
    }

    public function index(Request $request, int $company, int $service): JsonResponse {
        $this->authorizeCompany($request,$company,'company.view'); $this->service($company,$service);
        if (!Schema::hasTable('service_vehicle_prices')) abort(503,'La migración de tarifas no está instalada.');
        $rows = DB::table('service_vehicle_prices')->where('company_id',$company)->where('service_id',$service)
            ->orderBy('vehicle_type')->get(['vehicle_type','price']);
        return response()->json(['data'=>$rows]);
    }
    public function replace(Request $request, int $company, int $service): JsonResponse {
        $this->authorizeCompany($request,$company,'company.update'); $this->service($company,$service);
        if (!Schema::hasTable('service_vehicle_prices')) abort(503,'La migración de tarifas no está instalada.');
        $v=$request->validate(['prices'=>['required','array','max:60'],
            'prices.*.vehicle_type'=>['required','string','max:60'],
            'prices.*.price'=>['required','numeric','between:0,9999999999.99','decimal:0,2']]);
        $isOther = mb_strtolower(trim((string) DB::table('wash_services')->where('company_id',$company)
            ->where('id',$service)->value('name'))) === 'otro';
        if ($isOther && count($v['prices']) > 0) {
            throw ValidationException::withMessages(['prices'=>'Otro utiliza un precio base fijo, sin tarifas por vehículo.']);
        }
        $rows=[]; $seen=[];
        foreach ($v['prices'] as $r) {
            $type=trim($r['vehicle_type']); $key=mb_strtolower($type);
            if ($type==='' || isset($seen[$key])) throw ValidationException::withMessages([
                'prices'=>'Tipos de vehículo vacíos o duplicados.']);
            $seen[$key]=true;
            $rows[]=['company_id'=>$company,'service_id'=>$service,'vehicle_type'=>$type,
                'price'=>$r['price'],'created_at'=>now(),'updated_at'=>now()];
        }
        DB::transaction(function () use ($company,$service,$rows): void {
            DB::table('wash_services')->where('company_id',$company)->where('id',$service)->lockForUpdate()->first();
            DB::table('service_vehicle_prices')->where('company_id',$company)->where('service_id',$service)->delete();
            if ($rows) DB::table('service_vehicle_prices')->insert($rows);
        });
        return response()->json(['message'=>'Tarifas guardadas.','data'=>$rows]);
    }
}
