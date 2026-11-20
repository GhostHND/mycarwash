<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Support\MasterBilling24N8;
use Carbon\CarbonImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** Vista comercial 24N.9: solo el operador maestro, sin datos operativos entre empresas. */
final class MasterOffice24N9Controller extends Controller
{
    public function workspace(): JsonResponse
    {
        $base = app(MasterControl24N8Controller::class)->overview()->getData(true);
        $today = CarbonImmutable::now('America/Tegucigalpa');
        $companies = collect($base['companies'] ?? []);
        $subscriptions = $companies->map(function (array $row) {
            $billing = $row['billing'] ?? MasterBilling24N8::state((int) $row['id']);
            if (!(bool) ($row['is_active'] ?? false)) {
                $billing['allowed'] = false;
                $billing['status'] = $billing['status'] === 'active' ? 'suspended' : $billing['status'];
            }
            return [
                'id' => (int) $row['id'],
                'company_id' => (int) $row['id'],
                'company_name' => $row['name'],
                'customer_name' => $row['customer_name'] ?? null,
                'plan_name' => $row['plan_name'] ?? null,
                'master_customer_id' => $row['master_customer_id'] ?? null,
                'master_plan_id' => $row['master_plan_id'] ?? null,
                'status' => $row['stored_status'] ?? 'pending',
                'due_date' => $row['due_date'] ?? null,
                'grace_days' => $row['grace_days'] ?? 4,
                'billing' => $billing,
                'allowed' => $billing['allowed'] ?? false,
            ];
        })->values();
        $monthStart = $today->startOfMonth()->startOfDay()->utc();
        $nextMonthStart = $today->addMonthNoOverflow()->startOfMonth()->startOfDay()->utc();
        $incomeThisMonth = DB::table('master_payments_24n8')
            ->where('status', 'confirmed')->where('paid_at', '>=', $monthStart)
            ->where('paid_at', '<', $nextMonthStart)->sum('amount');
        $invoiceOpen = DB::table('master_invoices_24n8')
            ->where('status', 'pending')->sum('amount');
        $pendingPayments = DB::table('master_payments_24n8')
            ->where('status', 'pending')->count();
        $dueSoon = $subscriptions->filter(function (array $item) {
            $days = $item['billing']['days_until_due'] ?? null;
            return $days !== null && $days >= 0 && $days <= 7;
        })->sortBy('due_date')->values()->all();
        $atRisk = $subscriptions->filter(function (array $item) {
            return in_array($item['billing']['status'] ?? '', ['past_due', 'suspended'], true);
        })->values()->all();
        $months = [];
        for ($i = 5; $i >= 0; $i--) {
            $start = $today->subMonthsNoOverflow($i)->startOfMonth()->startOfDay();
            $end = $start->addMonth();
            $value = DB::table('master_payments_24n8')->where('status', 'confirmed')
                ->where('paid_at', '>=', $start->utc())->where('paid_at', '<', $end->utc())
                ->sum('amount');
            $months[] = ['month' => $start->format('Y-m'), 'amount' => (float) $value];
        }
        $activity = DB::table('master_audit_24n8 as a')
            ->leftJoin('master_operators_24n8 as o', 'o.id', '=', 'a.master_operator_id')
            ->select('a.id', 'a.action', 'a.target', 'a.created_at', 'o.name as operator_name')
            ->orderByDesc('a.id')->limit(100)->get();
        return response()->json(array_merge($base, [
            'subscriptions' => $subscriptions,
            'activity' => $activity,
            'due_soon' => $dueSoon,
            'at_risk' => $atRisk,
            'income_months' => $months,
            'summary' => [
                'companies_total' => $companies->count(),
                'companies_active' => $companies->filter(fn ($r) => ($r['billing']['allowed'] ?? false) === true)->count(),
                'companies_suspended' => $companies->filter(fn ($r) => ($r['billing']['allowed'] ?? false) !== true)->count(),
                'in_grace' => $companies->filter(fn ($r) => ($r['billing']['status'] ?? '') === 'past_due')->count(),
                'due_soon' => count($dueSoon),
                'customers' => collect($base['customers'] ?? [])->where('is_active', true)->count(),
                'income_month' => round((float) $incomeThisMonth, 2),
                'open_invoices_amount' => round((float) $invoiceOpen, 2),
                'payments_to_review' => (int) $pendingPayments,
            ],
            'generated_at' => $today->toIso8601String(),
        ]));
    }

    /** Paginación en servidor: los CRUD no se limitan a los últimos 300 registros. */
    public function records(Request $request, string $resource): JsonResponse
    {
        $resources = [
            'companies' => ['companies as c', 'c.name', 'c.id'],
            'customers' => ['master_customers_24n8 as c', 'c.name', 'c.id'],
            'plans' => ['master_plans_24n8 as c', 'c.name', 'c.id'],
            'subscriptions' => ['master_subscriptions_24n8 as s', 'c.name', 's.company_id'],
            'invoices' => ['master_invoices_24n8 as c', 'c.reference', 'c.id'],
            'payments' => ['master_payments_24n8 as c', 'c.reference', 'c.id'],
            'notices' => ['master_notices_24n8 as c', 'c.title', 'c.id'],
            'activity' => ['master_audit_24n8 as c', 'c.action', 'c.id'],
        ];
        abort_unless(isset($resources[$resource]), 404);
        $d = $request->validate([
            'page' => 'sometimes|integer|min:1|max:100000',
            'per_page' => 'sometimes|integer|min:1|max:50',
            'search' => 'nullable|string|max:100',
        ]);
        $query = DB::table($resources[$resource][0]);
        if ($resource === 'companies') {
            $query->leftJoin('master_subscriptions_24n8 as s', 's.company_id', '=', 'c.id')
                ->leftJoin('master_plans_24n8 as p', 'p.id', '=', 's.master_plan_id')
                ->leftJoin('master_customers_24n8 as m', 'm.id', '=', 's.master_customer_id')
                ->select('c.id', 'c.name', 'c.slug', 'c.is_active', 's.status as stored_status',
                    's.due_date', 's.grace_days', 's.master_plan_id', 's.master_customer_id',
                    'p.name as plan_name', 'm.name as customer_name');
        } elseif ($resource === 'subscriptions') {
            $query->join('companies as c', 'c.id', '=', 's.company_id')
                ->leftJoin('master_plans_24n8 as p', 'p.id', '=', 's.master_plan_id')
                ->leftJoin('master_customers_24n8 as m', 'm.id', '=', 's.master_customer_id')
                ->select('s.*', 'c.name as company_name', 'p.name as plan_name',
                    'm.name as customer_name');
        } elseif ($resource === 'payments') {
            $query->join('master_invoices_24n8 as i', 'i.id', '=', 'c.master_invoice_id')
                ->leftJoin('companies as company', 'company.id', '=', 'i.company_id')
                ->select('c.*', 'i.reference as invoice_reference',
                    'i.company_id', 'company.name as company_name');
        } elseif ($resource === 'invoices') {
            $query->leftJoin('companies as company', 'company.id', '=', 'c.company_id')
                ->select('c.*', 'company.name as company_name');
        } elseif ($resource === 'notices') {
            $query->leftJoin('companies as company', 'company.id', '=', 'c.company_id')
                ->select('c.*', 'company.name as company_name');
        } elseif ($resource === 'activity') {
            $query->leftJoin('master_operators_24n8 as operator', 'operator.id', '=', 'c.master_operator_id')
                ->select('c.*', 'operator.name as operator_name');
        } else {
            $query->select('c.*');
        }
        if (!empty($d['search'])) {
            $search = str_replace(['%', '_'], ['\%', '\_'], trim($d['search']));
            $query->where($resources[$resource][1], 'like', '%'.$search.'%');
        }
        $paginator = $query->orderByDesc($resources[$resource][2])->paginate(
            (int) ($d['per_page'] ?? 18), ['*'], 'page', (int) ($d['page'] ?? 1)
        );
        $rows = collect($paginator->items())->map(function ($row) use ($resource) {
            $item = (array) $row;
            if (in_array($resource, ['companies', 'subscriptions'], true)) {
                $id = (int) ($item['company_id'] ?? $item['id']);
                $item['billing'] = MasterBilling24N8::state($id);
                if ($resource === 'companies' && !(bool) ($item['is_active'] ?? false)) {
                    $item['billing']['allowed'] = false;
                    if ($item['billing']['status'] === 'active') $item['billing']['status'] = 'suspended';
                }
            }
            return $item;
        })->all();
        return response()->json([
            'data' => $rows, 'page' => $paginator->currentPage(),
            'last_page' => $paginator->lastPage(), 'total' => $paginator->total(),
        ]);
    }

    /** Suscripción única por empresa, sin borrado físico ni cambios de gracia. */
    public function subscriptionUpdate(Request $request, int $company): JsonResponse
    {
        abort_unless(DB::table('companies')->where('id', $company)->exists(), 404);
        $input = $request->validate([
            'customer_id' => 'sometimes|nullable|integer|exists:master_customers_24n8,id',
            'plan_id' => 'sometimes|nullable|integer|exists:master_plans_24n8,id',
            'due_date' => 'sometimes|nullable|date_format:Y-m-d',
            'status' => 'sometimes|in:pending,active,suspended,canceled',
            'notes' => 'sometimes|nullable|string|max:2000',
        ]);
        $result = DB::transaction(function () use ($request, $company, $input) {
            $sub = DB::table('master_subscriptions_24n8')->where('company_id', $company)->lockForUpdate()->first();
            abort_unless($sub, 409, 'La empresa no tiene suscripción inicial.');
            $planId = array_key_exists('plan_id', $input) ? $input['plan_id'] : $sub->master_plan_id;
            $date = array_key_exists('due_date', $input) ? $input['due_date'] : $sub->due_date;
            $newStatus = $input['status'] ?? $sub->status;
            if ($newStatus === 'active' && ($input['status'] ?? '') === 'active') {
                $plan = $planId ? DB::table('master_plans_24n8')->where('id', $planId)->first() : null;
                if (!$plan || !$plan->is_active || $plan->monthly_price === null || !$date) {
                    throw ValidationException::withMessages([
                        'status' => ['Para activar: selecciona un plan vigente con precio y fecha de vencimiento.'],
                    ]);
                }
            }
            $updates = ['grace_days' => 4, 'timezone' => 'America/Tegucigalpa', 'updated_at' => now()];
            foreach (['customer_id' => 'master_customer_id', 'plan_id' => 'master_plan_id',
                'due_date' => 'due_date', 'status' => 'status', 'notes' => 'notes'] as $from => $to) {
                if (array_key_exists($from, $input)) $updates[$to] = $input[$from];
            }
            DB::table('master_subscriptions_24n8')->where('company_id', $company)->update($updates);
            if (isset($input['status'])) {
                DB::table('companies')->where('id', $company)->update([
                    'is_active' => $input['status'] === 'active', 'updated_at' => now(),
                ]);
            }
            DB::table('master_audit_24n8')->insert([
                'master_operator_id' => $request->user()->id,
                'action' => 'subscription.updated', 'target' => 'company:'.$company,
                'details' => json_encode(array_diff_key($input, ['notes' => true]), JSON_UNESCAPED_UNICODE),
                'created_at' => now(),
            ]);
            return MasterBilling24N8::state($company);
        }, 3);
        return response()->json(['ok' => true, 'billing' => $result]);
    }
}
