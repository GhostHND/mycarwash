<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/** Bloque 24A.2: analitica agregada, exclusivamente de lectura y aislada por tenant. */
final class CompanyDashboardAnalyticsController extends Controller
{
    private function available(string $table, array $columns): bool
    {
        if (!Schema::hasTable($table)) return false;
        foreach ($columns as $column) if (!Schema::hasColumn($table, $column)) return false;
        return true;
    }

    public function overview(Request $request, int $company): JsonResponse
    {
        $userId = (int) $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $userId)
            ->where('p.code', 'company.view')->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente.');

        $validated = $request->validate([
            'branch_id' => ['sometimes', 'integer', 'min:1'],
            'days' => ['sometimes', 'integer', 'in:7,30'],
        ]);
        $branch = isset($validated['branch_id']) ? (int) $validated['branch_id'] : null;
        $days = (int) ($validated['days'] ?? 7);
        if ($branch !== null && !DB::table('branches')->where('company_id', $company)
            ->where('id', $branch)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal no disponible.']);
        }
        $timezone = (string) config('app.timezone', 'UTC');
        if ($branch !== null && Schema::hasColumn('branches', 'timezone')) {
            $candidate = (string) (DB::table('branches')->where('company_id', $company)->where('id', $branch)->value('timezone') ?? '');
            if (in_array($candidate, timezone_identifiers_list(), true)) $timezone = $candidate;
        }
        $firstDay = now($timezone)->startOfDay()->subDays($days - 1);
        $startUtc = $firstDay->copy()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $endUtc = now($timezone)->addDay()->startOfDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $daily = [];
        for ($i = 0; $i < $days; $i++) {
            $key = $firstDay->copy()->addDays($i)->toDateString();
            $daily[$key] = ['date' => $key, 'amount' => '0.00', 'count' => 0];
        }
        $warnings = [];
        $posAvailable = $this->available('pos_sales', ['company_id','branch_id','status','posted_at','total']);
        if ($posAvailable) {
            // Agrupar en PHP para respetar la zona horaria local, sin SQL especifico de MySQL/SQLite.
            $query = DB::table('pos_sales')->where('company_id', $company)->where('status', 'POSTED')
                ->where('posted_at', '>=', $startUtc)->where('posted_at', '<', $endUtc);
            if ($branch !== null) $query->where('branch_id', $branch);
            if (Schema::hasColumn('pos_sales', 'deleted_at')) $query->whereNull('deleted_at');
            foreach ($query->orderBy('id')->cursor(['id','posted_at','total']) as $sale) {
                $date = \Carbon\Carbon::parse($sale->posted_at, 'UTC')->setTimezone($timezone)->toDateString();
                if (!isset($daily[$date])) continue;
                $daily[$date]['amount'] = number_format((float) $daily[$date]['amount'] + (float) $sale->total, 2, '.', '');
                $daily[$date]['count']++;
            }
        } else $warnings[] = 'Ventas POS: fuente no disponible.';
        $washAvailable = $this->available('wash_orders', ['company_id','branch_id','status']);
        $statuses = [];
        if ($washAvailable) {
            $query = DB::table('wash_orders')->where('company_id', $company);
            if ($branch !== null) $query->where('branch_id', $branch);
            if (Schema::hasColumn('wash_orders', 'deleted_at')) $query->whereNull('deleted_at');
            foreach ($query->select('status', DB::raw('COUNT(*) as total'))->groupBy('status')->orderBy('status')->get() as $row) {
                $statuses[] = ['status' => (string) $row->status, 'count' => (int) $row->total];
            }
        } else $warnings[] = 'Estados de lavado: fuente no disponible.';
        $total = $posAvailable ? array_sum(array_map(fn($d) => (float) $d['amount'], $daily)) : null;
        return response()->json(['data' => [
            'days' => $days, 'timezone' => $timezone,
            'scope' => ['company_id' => $company, 'branch_id' => $branch],
            'pos_available' => $posAvailable, 'wash_available' => $washAvailable,
            'pos_total' => $total === null ? null : number_format($total, 2, '.', ''),
            'pos_daily' => $posAvailable ? array_values($daily) : null,
            'wash_statuses' => $washAvailable ? $statuses : null,
            'wash_note' => 'Estados actuales de todas las órdenes; no son conteos históricos por período.',
            'sales_note' => 'Únicamente ventas Smart POS confirmadas. No incluye cobros de lavados.',
            'warnings' => $warnings,
        ]]);
    }

    /** Órdenes realmente en proceso: paginación circular, cuatro visibles por consulta. */
    public function activeWashes(Request $request, int $company): JsonResponse
    {
        $userId = (int) $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $userId)
            ->where('p.code', 'company.view')->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente.');
        $validated = $request->validate([
            'branch_id' => ['sometimes', 'integer', 'min:1'],
            'offset' => ['sometimes', 'integer', 'min:0'],
        ]);
        $branch = isset($validated['branch_id']) ? (int) $validated['branch_id'] : null;
        if ($branch !== null && !DB::table('branches')->where('company_id', $company)
            ->where('id', $branch)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal no disponible.']);
        }
        if (!$this->available('wash_orders', ['id', 'company_id', 'branch_id', 'status'])) {
            return response()->json(['data' => [
                'available' => false, 'total' => 0, 'offset' => 0, 'items' => [],
            ]]);
        }
        $query = DB::table('wash_orders')->where('company_id', $company)->where('status', 'EN_PROCESO');
        if ($branch !== null) $query->where('branch_id', $branch);
        if (Schema::hasColumn('wash_orders', 'deleted_at')) $query->whereNull('deleted_at');
        $total = (clone $query)->count();
        $offset = $total > 0 ? ((int) ($validated['offset'] ?? 0)) % $total : 0;
        $rows = (clone $query)->orderBy('id')->offset($offset)->limit(4)->get(['id']);
        // La UI nunca presenta cuatro posiciones ficticias: muestra de 0 a 4 órdenes reales.
        return response()->json(['data' => [
            'available' => true, 'total' => $total, 'offset' => $offset,
            'items' => $rows->map(fn($row) => [
                'id' => (int) $row->id,
                'label' => 'Orden #'.(int) $row->id,
            ])->all(),
        ]]);
    }

}
