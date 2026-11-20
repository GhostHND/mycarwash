<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Symfony\Component\HttpFoundation\Response;

/** RPI-01C: dispositivos pantalla exclusivos, sin credenciales de propietario. */
final class MonitorDeviceRpi01cController extends Controller
{
    private function ready(): void
    {
        abort_unless(Schema::hasTable('monitor_devices_rpi01c'), 503, 'Pendiente migración RPI-01C.');
    }

    private function owner(Request $request, int $company): void
    {
        $user = $request->user();
        abort_unless($user, 401);
        $active = DB::table('company_user as cu')
            ->join('companies as c', 'c.id', '=', 'cu.company_id')
            ->where('cu.company_id', $company)->where('cu.user_id', $user->id)
            ->where('cu.status', 'active')->where('c.is_active', true)->exists();
        abort_unless($active, 404, 'Empresa no disponible.');
        $isOwner = DB::table('user_roles as ur')
            ->join('roles as r', function ($q): void {
                $q->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
            })->where('ur.company_id', $company)->where('ur.user_id', $user->id)
            ->where('r.code', 'owner')->where('r.is_system', true)->exists();
        abort_unless($isOwner, 403, 'Solo el propietario puede vincular pantallas.');
    }

    public function index(Request $request, int $company): JsonResponse
    {
        $this->ready(); $this->owner($request, $company);
        return response()->json(['data' => DB::table('monitor_devices_rpi01c')
            ->where('company_id', $company)->orderByDesc('id')
            ->get(['id','branch_id','name','is_active','last_seen_at','created_at'])]);
    }

    public function issue(Request $request, int $company): JsonResponse
    {
        $this->ready(); $this->owner($request, $company);
        $data = $request->validate([
            'branch_id' => ['required','integer','min:1'],
            'name' => ['required','string','min:2','max:90'],
        ]);
        $branch = (int) $data['branch_id'];
        abort_unless(DB::table('branches')->where('id', $branch)->where('company_id', $company)
            ->where('is_active', true)->exists(), 422, 'La sucursal no pertenece a la empresa o está inactiva.');
        $key = bin2hex(random_bytes(32));
        $id = DB::table('monitor_devices_rpi01c')->insertGetId([
            'company_id' => $company, 'branch_id' => $branch,
            'name' => trim($data['name']), 'key_hash' => hash('sha256', $key),
            'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
        ]);
        return response()->json(['id' => $id, 'device_key' => $key,
            'message' => 'La clave se entrega una sola vez. Conservar exclusivamente en la Raspberry.'], 201)
            ->header('Cache-Control', 'no-store');
    }

    public function revoke(Request $request, int $company, int $device): JsonResponse
    {
        $this->ready(); $this->owner($request, $company);
        $count = DB::table('monitor_devices_rpi01c')->where('company_id', $company)
            ->where('id', $device)->update(['is_active' => false, 'updated_at' => now()]);
        abort_unless($count === 1, 404);
        return response()->json(['revoked' => true]);
    }

    /** La clave no autentica un usuario; sólo permite las rutas GET rpi01c expuestas abajo. */
    private function device(Request $request): object
    {
        $this->ready();
        $key = (string) $request->header('X-MCW-Kiosk-Key', '');
        abort_unless((bool) preg_match('/\A[a-f0-9]{64}\z/D', $key), 401, 'Dispositivo no vinculado.');
        $d = DB::table('monitor_devices_rpi01c as d')
            ->join('companies as c', 'c.id', '=', 'd.company_id')
            ->join('branches as b', function ($j): void {
                $j->on('b.id', '=', 'd.branch_id')->on('b.company_id', '=', 'd.company_id');
            })->where('d.key_hash', hash('sha256', $key))
            ->where('d.is_active', true)->where('c.is_active', true)->where('b.is_active', true)
            ->first(['d.id','d.company_id','d.branch_id','c.name as company_name','b.name as branch_name']);
        abort_unless($d, 401, 'Dispositivo revocado o empresa/sucursal inactiva.');
        // Actualizar presencia con un máximo de una escritura por minuto.
        DB::table('monitor_devices_rpi01c')->where('id', $d->id)
            ->where(function ($q): void { $q->whereNull('last_seen_at')->orWhere('last_seen_at', '<', now()->subMinute()); })
            ->update(['last_seen_at' => now()]);
        return $d;
    }

    /** Reusa el controlador existente, fijando empresa, sucursal y usuario propietario sólo en memoria. */
    private function monitorRequest(Request $request, object $d): Request
    {
        $uid = DB::table('company_user as cu')
            ->join('user_roles as ur', function ($j): void {
                $j->on('ur.user_id', '=', 'cu.user_id')->on('ur.company_id', '=', 'cu.company_id');
            })->join('roles as r', function ($j): void {
                $j->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
            })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('cu.company_id', $d->company_id)->where('cu.status', 'active')
            ->where('r.code', 'owner')->where('r.is_system', true)
            ->where('p.code', 'company.view')->value('cu.user_id');
        abort_unless($uid, 503, 'La empresa no dispone de un propietario activo para el monitor.');
        $owner = User::find($uid);
        abort_unless($owner, 503);
        $request->setUserResolver(static fn () => $owner);
        // La sucursal proviene exclusivamente de la vinculación, nunca de la URL.
        $request->query->replace(['branch_id' => (int) $d->branch_id]);
        return $request;
    }

    public function bootstrap(Request $request): JsonResponse
    {
        $d = $this->device($request);
        $profile = Schema::hasTable('company_profiles')
            ? DB::table('company_profiles')->where('company_id', $d->company_id)->first()
            : null;
        $colorJson = Schema::hasTable('company_monitor_themes')
            ? DB::table('company_monitor_themes')->where('company_id', $d->company_id)->value('colors') : null;
        return response()->json(['company_id' => (int) $d->company_id,
            'branch_id' => (int) $d->branch_id,
            'company_name' => (string) (($profile->commercial_name ?? null) ?: $d->company_name),
            'branch_name' => $d->branch_name,
            'colors' => $colorJson ? json_decode((string) $colorJson, true) : (object) [],
        ])->header('Cache-Control', 'no-store');
    }

    public function monitor(Request $request): JsonResponse
    {
        $d = $this->device($request);
        $inner = $this->monitorRequest($request, $d);
        $res = app(CompanyWashMonitor24B2Controller::class)->show($inner, (int) $d->company_id);
        $payload = $res->getData(true);
        // En el kiosco nunca anunciar fotografías que no estén marcadas como públicas para TV.
        if (isset($payload['data']['active']) && is_array($payload['data']['active'])) {
            foreach ($payload['data']['active'] as &$row) {
                $row['photo_enabled'] = !empty($row['photo_on_kiosk']);
            } unset($row);
        }
        if (isset($payload['data']['completion_events']) && is_array($payload['data']['completion_events'])) {
            foreach ($payload['data']['completion_events'] as &$row) {
                $row['photo_enabled'] = !empty($row['photo_on_kiosk']);
            } unset($row);
        }
        if (isset($payload['data']['next']) && is_array($payload['data']['next'])) {
            $payload['data']['next']['photo_enabled'] = !empty($payload['data']['next']['photo_on_kiosk']);
        }
        return response()->json($payload)->header('Cache-Control','no-store');
    }

    public function photo(Request $request, int $vehicle): Response
    {
        $d = $this->device($request);
        $allowed = DB::table('company_entity_photos')->where('company_id', $d->company_id)
            ->where('owner_type', 'vehicles')->where('owner_id', $vehicle)
            ->where('show_on_kiosk', true)->exists();
        abort_unless($allowed, 404);
        $this->monitorRequest($request, $d);
        return app(CompanyMediaController::class)->file($request, (int) $d->company_id, 'vehicles', $vehicle);
    }
    public function logo(Request $request): Response
    {
        $d = $this->device($request);
        $this->monitorRequest($request, $d);
        return app(BusinessLogoController::class)->show($request, (int) $d->company_id);
    }

}
