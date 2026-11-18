<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use DateTimeImmutable;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** Bloque 22A: reportes agregados de Smart POS; estrictamente solo lectura. */
class CompanyPosReportsController extends Controller
{
    private function authorizeCompany(Request $request, int $company): void
    {
        $uid = (int) $request->user()->id;
        if (!DB::table('company_user')
            ->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)
            ->where('company_user.user_id', $uid)
            ->where('company_user.status', 'active')
            ->where('companies.is_active', true)->exists()) {
            abort(404, 'Empresa no disponible.');
        }
        $allowed = DB::table('user_roles as ur')
            ->join('roles as r', function ($join): void {
                $join->on('r.id', '=', 'ur.role_id')
                    ->on('r.company_id', '=', 'ur.company_id');
            })
            ->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)
            ->where('ur.user_id', $uid)
            ->where('p.code', 'company.view')->exists();
        if (!$allowed) {
            abort(403, 'Permiso insuficiente.');
        }
    }

    private function money(mixed $value): string
    {
        return number_format(round((float) ($value ?? 0), 2), 2, '.', '');
    }

    public function summary(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company);
        $today = now()->toDateString();
        $data = $request->validate([
            'from' => ['sometimes', 'date_format:Y-m-d'],
            'to' => ['sometimes', 'date_format:Y-m-d'],
            'branch_id' => ['sometimes', 'integer', 'min:1'],
        ]);
        $from = (string) ($data['from'] ?? now()->subDays(29)->toDateString());
        $to = (string) ($data['to'] ?? $today);
        $start = DateTimeImmutable::createFromFormat('!Y-m-d', $from);
        $end = DateTimeImmutable::createFromFormat('!Y-m-d', $to);
        if (!$start || !$end || $start > $end || $start->diff($end)->days > 365) {
            throw ValidationException::withMessages([
                'from' => 'El período debe estar ordenado y no superar 366 días.',
            ]);
        }
        $toExclusive = $end->modify('+1 day')->format('Y-m-d').' 00:00:00';
        $branch = isset($data['branch_id']) ? (int) $data['branch_id'] : null;
        if ($branch !== null && !DB::table('branches')
            ->where('company_id', $company)->where('id', $branch)
            ->where('is_active', true)->exists()) {
            throw ValidationException::withMessages([
                'branch_id' => 'Sucursal no disponible para esta empresa.',
            ]);
        }

        $saleScope = static function ($query) use ($company, $branch, $from, $toExclusive) {
            $query->where('s.company_id', $company)
                ->where('s.status', 'POSTED')
                ->where('s.posted_at', '>=', $from.' 00:00:00')
                ->where('s.posted_at', '<', $toExclusive);
            if ($branch !== null) {
                $query->where('s.branch_id', $branch);
            }
            return $query;
        };

        // La unidad contable es UNA venta POSTED, no sus líneas ni pagos.
        $totals = $saleScope(DB::table('pos_sales as s'))
            ->selectRaw('COUNT(*) AS sales_count')
            ->selectRaw('COALESCE(SUM(s.subtotal), 0) AS subtotal')
            ->selectRaw('COALESCE(SUM(s.discount_amount), 0) AS discounts')
            ->selectRaw('COALESCE(SUM(s.tax_amount), 0) AS tax')
            ->selectRaw('COALESCE(SUM(s.total), 0) AS total')
            ->first();

        $daily = $saleScope(DB::table('pos_sales as s'))
            ->selectRaw('DATE(s.posted_at) AS day')
            ->selectRaw('COUNT(*) AS sales_count')
            ->selectRaw('COALESCE(SUM(s.total), 0) AS total')
            ->groupByRaw('DATE(s.posted_at)')
            ->orderBy('day')->get()->map(fn ($r) => [
                'day' => $r->day,
                'sales_count' => (int) $r->sales_count,
                'total' => $this->money($r->total),
            ])->values()->all();

        $channels = $saleScope(DB::table('pos_sale_payments as p')
            ->join('pos_sales as s', function ($join): void {
                $join->on('s.id', '=', 'p.sale_id')
                    ->on('s.company_id', '=', 'p.company_id');
            }))
            ->select('p.channel')
            ->selectRaw('COUNT(*) AS payment_count')
            ->selectRaw('COALESCE(SUM(p.amount), 0) AS amount')
            ->groupBy('p.channel')->orderBy('p.channel')->get()
            ->map(fn ($r) => [
                'channel' => $r->channel,
                'payment_count' => (int) $r->payment_count,
                'amount' => $this->money($r->amount),
            ])->values()->all();

        $documents = $saleScope(DB::table('pos_sales as s'))
            ->select('s.document_type')
            ->selectRaw('COUNT(*) AS sales_count')
            ->selectRaw('COALESCE(SUM(s.total), 0) AS total')
            ->groupBy('s.document_type')->orderBy('s.document_type')->get()
            ->map(fn ($r) => [
                'document_type' => $r->document_type,
                'sales_count' => (int) $r->sales_count,
                'total' => $this->money($r->total),
            ])->values()->all();

        $products = $saleScope(DB::table('pos_sale_items as i')
            ->join('pos_sales as s', function ($join): void {
                $join->on('s.id', '=', 'i.sale_id')
                    ->on('s.company_id', '=', 'i.company_id');
            }))
            ->select(['i.item_id', 'i.sku_snapshot', 'i.name_snapshot'])
            ->selectRaw('COALESCE(SUM(i.quantity), 0) AS qty_sold')
            ->selectRaw('COALESCE(SUM(i.line_total), 0) AS gross_line_amount')
            ->groupBy('i.item_id', 'i.sku_snapshot', 'i.name_snapshot')
            ->orderByDesc('qty_sold')->limit(10)->get()
            ->map(fn ($r) => [
                'item_id' => (int) $r->item_id,
                'sku' => $r->sku_snapshot,
                'name' => $r->name_snapshot,
                'quantity' => number_format((float) $r->qty_sold, 3, '.', ''),
                'gross_line_amount' => $this->money($r->gross_line_amount),
            ])->values()->all();

        return response()->json(['data' => [
            'scope' => ['company_id' => $company, 'branch_id' => $branch,
                'from' => $from, 'to' => $to, 'currency' => 'HNL'],
            'kpis' => [
                'sales_count' => (int) ($totals->sales_count ?? 0),
                'subtotal' => $this->money($totals->subtotal ?? 0),
                'discounts' => $this->money($totals->discounts ?? 0),
                'tax' => $this->money($totals->tax ?? 0),
                'total' => $this->money($totals->total ?? 0),
            ],
            'daily' => $daily,
            'payment_channels' => $channels,
            'documents' => $documents,
            'top_products' => $products,
            'disclaimer' => 'Reporte operativo de ventas Smart POS confirmadas. No sustituye contabilidad ni certificación fiscal.',
        ]]);
    }
}
