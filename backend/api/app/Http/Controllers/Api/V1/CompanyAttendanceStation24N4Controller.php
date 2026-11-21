<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

/** Los supervisores consultan el código actual; nunca lo obtiene un lavador. */
class CompanyAttendanceStation24N4Controller extends Controller
{
    private function guard(Request $request, int $company): void
    {
        $uid = (int)$request->user()->id;
        $owner = DB::table('user_roles as ur')->join('roles as r', 'ur.role_id','=','r.id')
            ->where('ur.company_id',$company)->where('ur.user_id',$uid)->where('r.company_id',$company)
            ->where('r.code','owner')->exists();
        $manager = DB::table('user_roles as ur')->join('role_permission as rp','rp.role_id','=','ur.role_id')
            ->join('permissions as p','p.id','=','rp.permission_id')
            ->where('ur.company_id',$company)->where('ur.user_id',$uid)->where('p.code','company.update')->exists();
        abort_unless(($owner || $manager) && !\App\Support\WasherAccess24N3::isWasher($company,$uid),403);
    }

    public function station(Request $request, int $company): JsonResponse
    {
        $this->guard($request,$company);
        $point = DB::table('washer_attendance_points_24n4')->where('company_id',$company)
            ->where('is_active',true)->orderBy('id')->first();
        if (!$point) {
            $id = DB::table('washer_attendance_points_24n4')->insertGetId([
                'company_id' => $company, 'name' => 'Punto principal',
                'secret_encrypted' => Crypt::encryptString(Str::random(64)),
                'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
            ]);
            $point = DB::table('washer_attendance_points_24n4')->where('id',$id)->first();
        }
        // Firma estática por punto: imprimible. El escaneo sigue requiriendo
        // sesión autenticada de empleado y validaciones del servidor.
        $staticSignature = hash_hmac('sha256', "MCW:ATT:2:$company:{$point->id}", Crypt::decryptString($point->secret_encrypted));
        $qr = "MCW:ATT:2:$company:{$point->id}:".substr($staticSignature,0,40);
        $manual = str_pad((string)(hexdec(substr(hash_hmac('sha256', "MCW:ATT:MANUAL:2:$company:{$point->id}", Crypt::decryptString($point->secret_encrypted)),0,8)) % 100000000),8,'0',STR_PAD_LEFT);
        return response()->json(['point_id' => $point->id, 'name' => $point->name,
            'qr_payload' => $qr, 'manual_code' => $manual,
            'expires_at' => null,
            'refresh_seconds' => 0, 'qr_permanent' => true, 'manual_permanent' => true]);
    }
}
