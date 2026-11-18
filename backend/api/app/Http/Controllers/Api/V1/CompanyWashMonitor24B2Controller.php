<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Carbon\Carbon;

/** Monitor operativo, lectura por empresa/sucursal; sin conceder acceso a dispositivos. */
final class CompanyWashMonitor24B2Controller extends Controller
{
    public function show(Request $request, int $company): JsonResponse
    {
        $uid = (int) $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $uid)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404);
        $permitted = DB::table('user_roles as ur')->join('roles as r', function ($q): void {
            $q->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $uid)
            ->where('p.code', 'company.view')->exists();
        if (!$permitted) abort(403);
        $validated = $request->validate(['branch_id' => ['sometimes', 'integer', 'min:1']]);
        $branch = isset($validated['branch_id']) ? (int) $validated['branch_id'] : null;
        if ($branch !== null && !DB::table('branches')->where('company_id', $company)
            ->where('id', $branch)->where('is_active', true)->exists()) abort(422, 'Sucursal no disponible');
        $tz = (string) config('app.timezone', 'UTC');
        if ($branch !== null && Schema::hasColumn('branches', 'timezone')) {
            $candidate = (string) (DB::table('branches')->where('id', $branch)->where('company_id', $company)->value('timezone') ?? '');
            if (in_array($candidate, timezone_identifiers_list(), true)) $tz = $candidate;
        }
        $base = DB::table('wash_orders as o')
            ->join('vehicles as v', function ($join): void {
                $join->on('v.id', '=', 'o.vehicle_id')->on('v.company_id', '=', 'o.company_id');
            })
            ->join('wash_services as s', function ($join): void {
                $join->on('s.id', '=', 'o.service_id')->on('s.company_id', '=', 'o.company_id');
            })
            ->leftJoin('wash_bays as b', function ($join): void {
                $join->on('b.id', '=', 'o.bay_id')->on('b.company_id', '=', 'o.company_id');
            })
            ->where('o.company_id', $company);
        if ($branch !== null) $base->where('o.branch_id', $branch);
        if (Schema::hasColumn('wash_orders', 'deleted_at')) $base->whereNull('o.deleted_at');
        $columns = ['o.id', 'o.status', 'o.vehicle_id', 'o.branch_id', 'o.started_at',
            'o.estimated_minutes', 'o.created_at', 'v.brand', 'v.model', 'v.plate',
            's.name as service', 'b.name as bay'];
        $activeRows = (clone $base)->where('o.status', 'EN_PROCESO')
            ->orderByRaw('CASE WHEN b.id IS NULL THEN 1 ELSE 0 END')
            ->orderBy('b.id')->orderBy('o.id')->limit(200)->get($columns);
        $waitingRows = (clone $base)->whereIn('o.status', ['EN_ESPERA', 'ASIGNADO'])
            ->orderBy('o.created_at')->orderBy('o.id')->limit(200)->get($columns);
        $ids = $activeRows->concat($waitingRows)->pluck('id')->all();
        $names = [];
        if ($ids) {
            $assigned = DB::table('wash_assignments as a')
                ->join('employees as e', function ($join): void {
                    $join->on('e.id', '=', 'a.employee_id')->on('e.company_id', '=', 'a.company_id');
                })
                ->where('a.company_id', $company)->where('a.is_active', true)
                ->whereIn('a.order_id', $ids)->orderByDesc('a.is_primary')
                ->orderBy('a.id')->get(['a.order_id', 'e.full_name']);
            foreach ($assigned as $row) $names[(int) $row->order_id][] = (string) $row->full_name;
        }
        $vehicleIds = $activeRows->concat($waitingRows)->pluck('vehicle_id')->unique()->all();
        $photos = [];
        if ($vehicleIds && Schema::hasTable('company_entity_photos')) {
            foreach (DB::table('company_entity_photos')->where('company_id', $company)
                ->where('owner_type', 'vehicles')
                ->whereIn('owner_id', $vehicleIds)->get(['owner_id', 'show_on_kiosk']) as $photo) {
                $photos[(int) $photo->owner_id] = (bool) $photo->show_on_kiosk;
            }
        }
        $present = function ($r) use ($names, $photos): array {
            $duration = (int) ($r->estimated_minutes ?? 0);
            $started = $r->started_at === null ? null : Carbon::parse($r->started_at, 'UTC');
            $elapsed = $started ? max(0, now('UTC')->timestamp - $started->timestamp) : null;
            $progress = $duration > 0 && $elapsed !== null
                ? min(100, (int) floor($elapsed * 100 / ($duration * 60))) : null;
            $remain = $duration > 0 && $elapsed !== null ? max(0, $duration * 60 - $elapsed) : null;
            return [
                'id' => (int) $r->id, 'status' => (string) $r->status,
                'vehicle_id' => (int) $r->vehicle_id, 'bay' => $r->bay,
                'brand' => (string) ($r->brand ?? ''), 'model' => (string) ($r->model ?? ''),
                'plate' => (string) ($r->plate ?? ''), 'service' => (string) ($r->service ?? ''),
                'washers' => $names[(int) $r->id] ?? [],
                'photo_enabled' => array_key_exists((int) $r->vehicle_id, $photos),
                'photo_on_kiosk' => (bool) ($photos[(int) $r->vehicle_id] ?? false),
                'estimated_minutes' => $duration > 0 ? $duration : null,
                'started_at' => $started?->toIso8601String(),
                'progress_percent' => $progress, 'remaining_seconds' => $remain,
                'stage' => null, // No presentar etapas supuestas sin configuracion por servicio.
            ];
        };
        $bays = DB::table('wash_bays')->where('company_id', $company)->where('is_active', true)
            ->whereNull('deleted_at');
        if ($branch !== null) $bays->where('branch_id', $branch);
        return response()->json(['data' => [
            'active' => $activeRows->map($present)->values()->all(),
            'active_total' => (clone $base)->where('o.status', 'EN_PROCESO')->count(),
            'waiting_total' => (clone $base)->whereIn('o.status', ['EN_ESPERA', 'ASIGNADO'])->count(),
            'next' => $waitingRows->isEmpty() ? null : $present($waitingRows->first()),
            'bays' => $bays->orderBy('id')->pluck('name')->all(),
            'timezone' => $tz, 'generated_at' => now('UTC')->toIso8601String(),
            'limited' => $activeRows->count() >= 200,
            'stage_note' => 'Etapas estimadas pendientes de reglas configurables por servicio.',
        ]]);
    }
}
