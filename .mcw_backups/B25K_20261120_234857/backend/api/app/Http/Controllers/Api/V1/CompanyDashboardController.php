<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

/** Dashboard 24A.1: lecturas verificables y aisladas por empresa/sucursal. */
final class CompanyDashboardController extends Controller
{
    private function readable(Request $request, int $company): void
    {
        $user = (int) $request->user()->id;
        if (!DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $user)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists()) {
            abort(404, 'Empresa no disponible.');
        }
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $user)
            ->where('p.code', 'company.view')->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente para Dashboard.');
    }

    private function available(string $table, array $columns): bool
    {
        if (!Schema::hasTable($table)) return false;
        foreach ($columns as $column) if (!Schema::hasColumn($table, $column)) return false;
        return true;
    }

    private function base(string $table, int $company, ?int $branch = null)
    {
        $query = DB::table($table)->where('company_id', $company);
        if ($branch !== null) $query->where('branch_id', $branch);
        if (Schema::hasColumn($table, 'deleted_at')) $query->whereNull('deleted_at');
        return $query;
    }

    private function currency(mixed $amount): string
    {
        return number_format((float) $amount, 2, '.', '');
    }

    public function overview(Request $request, int $company): JsonResponse
    {
        $this->readable($request, $company);
        $validated = $request->validate(['branch_id' => ['sometimes', 'integer', 'min:1']]);
        $branch = isset($validated['branch_id']) ? (int) $validated['branch_id'] : null;
        if ($branch !== null && !DB::table('branches')->where('company_id', $company)
            ->where('id', $branch)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal no disponible.']);
        }
        // Si se elige una sucursal, la fecha se interpreta en su zona horaria.
        $timezone = (string) config('app.timezone', 'UTC');
        if ($branch !== null && Schema::hasColumn('branches', 'timezone')) {
            $candidate = (string) (DB::table('branches')->where('company_id', $company)
                ->where('id', $branch)->value('timezone') ?? '');
            if (in_array($candidate, timezone_identifiers_list(), true)) $timezone = $candidate;
        }
        $date = now($timezone)->toDateString();
        $start = now($timezone)->startOfDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $end = now($timezone)->addDay()->startOfDay()->setTimezone('UTC')->format('Y-m-d H:i:s');
        $warnings = [];
        $moneySales = null;
        if ($this->available('pos_sales', ['company_id','branch_id','status','posted_at','total'])) {
            $moneySales = $this->currency($this->base('pos_sales', $company, $branch)
                ->where('status', 'POSTED')->where('posted_at','>=',$start)
                ->where('posted_at','<',$end)->sum('total'));
        } else $warnings[] = 'Ventas POS: fuente no disponible.';

        $moneyExpenses = null;
        if ($this->available('cash_movements', ['company_id','session_id','direction','amount','created_at'])
            && $this->available('cash_sessions', ['company_id','register_id'])
            && $this->available('cash_registers', ['company_id','branch_id'])) {
            $query = DB::table('cash_movements as m')
                ->join('cash_sessions as s', function ($j): void {
                    $j->on('s.id','=','m.session_id')->on('s.company_id','=','m.company_id');
                })->join('cash_registers as r', function ($j): void {
                    $j->on('r.id','=','s.register_id')->on('r.company_id','=','m.company_id');
                })->where('m.company_id',$company)->where('m.direction','OUT')
                ->where('m.created_at','>=',$start)->where('m.created_at','<',$end);
            if ($branch !== null) $query->where('r.branch_id', $branch);
            if (Schema::hasColumn('cash_movements','deleted_at')) $query->whereNull('m.deleted_at');
            $moneyExpenses = $this->currency($query->sum('m.amount'));
        } else $warnings[] = 'Egresos de caja: fuente no disponible.';

        $washActive = null;
        if ($this->available('wash_orders', ['company_id','branch_id','status'])) {
            $washActive = $this->base('wash_orders', $company, $branch)
                ->where('status','EN_PROCESO')->count();
        } else $warnings[] = 'Lavados activos: fuente no disponible.';

        $bookingsToday = null;
        if ($this->available('wash_bookings', ['company_id','branch_id','local_date','status'])) {
            // Una reserva se cuenta en su fecha de atención, no en la fecha de registro.
            $bookingsToday = $this->base('wash_bookings', $company, $branch)
                ->where('local_date',$date)->where('status','CONFIRMED')->count();
        } else $warnings[] = 'Reservaciones: fuente no disponible.';

        $catalogue = [];
        foreach (['clients'=>'clients','vehicles'=>'vehicles','staff'=>'employees'] as $metric => $table) {
            if ($this->available($table,['company_id'])) {
                $query = $this->base($table, $company); // catálogos compartidos por empresa
                if (Schema::hasColumn($table,'is_active')) $query->where('is_active',true);
                $catalogue[$metric] = $query->count();
            } else {
                $catalogue[$metric] = null;
                $warnings[] = 'Catálogo de '.$metric.': fuente no disponible.';
            }
        }
        $financialB25J = CompanyDashboardFinanceB25J::summary($company, $branch, $timezone);
        $warnings = array_merge($warnings, $financialB25J['warnings']);
        $allBranches = DB::table('branches')->where('company_id', $company)->where('is_active',true)
            ->orderBy('name')->get(['id','name'])->map(fn($row)=>['id'=>(int)$row->id,'name'=>$row->name])->all();
        return response()->json(['data' => [
            'date' => $date, 'timezone' => $timezone,
            'user_name' => trim((string) ($request->user()->name ?? '')),
            'company_name' => (string) (DB::table('companies')->where('id',$company)->value('name') ?? ''),
            'scope' => ['company_id'=>$company,'branch_id'=>$branch],
            'branches' => $allBranches,
            'kpis' => [
                'sales_today' => $moneySales, // Compatibilidad API anterior; POS de artículos.
                'services_today' => $financialB25J['services_today'],
                'commissions_today' => $financialB25J['commissions_today'],
                'expenses_today' => $financialB25J['expenses_today'],
                'balance_today' => $financialB25J['balance_today'],
                'active_washes' => $washActive, 'bookings_today' => $bookingsToday,
                'clients' => $catalogue['clients'], 'vehicles' => $catalogue['vehicles'],
                'staff' => $catalogue['staff'],
            ],
            'balance_note' => 'Servicios cobrados menos comisiones con asistencia validada y gastos de caja categorizados. No incluye ventas de artículos ni equivale a utilidad contable.',
            'warnings' => $warnings,
        ]]);
    }
}
