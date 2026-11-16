<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\ValidationException;

/** Bloque 21A: ventas físicas POS, inventario y pago atómicos, sin facturación fiscal. */
class CompanyPosController extends Controller
{
    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $uid = (int) $request->user()->id;
        if (!DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $uid)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists()) {
            abort(404, 'Empresa no disponible.');
        }
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $uid)
            ->where('p.code', $permission)->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente.');
    }

    private function cents(mixed $value, string $field = 'amount', bool $allowZero = true): int
    {
        $txt = (string) $value;
        if (!preg_match('/^(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,2})?$/D', $txt)) {
            throw ValidationException::withMessages([$field => 'Importe inválido; máximo dos decimales.']);
        }
        $parts = explode('.', $txt, 2);
        $num = (int) $parts[0] * 100 + (int) str_pad($parts[1] ?? '', 2, '0');
        if (!$allowZero && $num === 0) throw ValidationException::withMessages([$field => 'Importe mayor a cero obligatorio.']);
        return $num;
    }
    private function money(int $cents): string
    {
        return intdiv($cents, 100).'.'.str_pad((string) ($cents % 100), 2, '0', STR_PAD_LEFT);
    }
    private function branch(int $company, int $id): void
    {
        if (!DB::table('branches')->where('company_id', $company)->where('id', $id)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal no disponible.']);
        }
    }
    private function scopeStock(int $company, int $branch, int $item): int
    {
        $quantity = DB::table('inventory_movements')->where('company_id', $company)
            ->where('branch_id', $branch)->where('item_id', $item)->whereNull('deleted_at')
            ->selectRaw("COALESCE(SUM(CASE WHEN movement_type='IN' THEN quantity ELSE -quantity END), 0) AS balance")
            ->first();
        $txt = (string) ($quantity->balance ?? '0');
        if (!preg_match('/^(-?)([0-9]+)(?:\.([0-9]{1,3}))?$/D', $txt, $parts)) {
            abort(500, 'Saldo de inventario no representable.');
        }
        $milli = (int) $parts[2] * 1000 + (int) str_pad($parts[3] ?? '', 3, '0');
        return $parts[1] === '-' ? -$milli : $milli;
    }
    private function stockLabel(int $milli): string
    {
        return intdiv($milli, 1000).'.'.str_pad((string) ($milli % 1000), 3, '0', STR_PAD_LEFT);
    }

    public function options(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        return response()->json(['data' => [
            'branches' => DB::table('branches')->where('company_id', $company)->where('is_active', true)
                ->orderBy('name')->get(['id', 'name']),
            'methods' => DB::table('sale_payment_methods')->where('company_id', $company)
                ->where('is_active', true)->whereNull('deleted_at')->get(['id', 'name', 'channel']),
            'banks' => DB::table('sale_bank_accounts')->where('company_id', $company)
                ->where('is_active', true)->whereNull('deleted_at')->get(['id', 'alias', 'branch_id']),
            'sessions' => DB::table('cash_sessions as s')->join('cash_registers as r', 'r.id', '=', 's.register_id')
                ->where('s.company_id', $company)->where('r.company_id', $company)
                ->where('s.status', 'OPEN')->whereNull('s.deleted_at')->whereNull('r.deleted_at')
                ->get(['s.id', 'r.name', 'r.branch_id']),
        ]]);
    }

    public function products(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $data = $request->validate([
            'branch_id' => ['required', 'integer', 'min:1'],
            'q' => ['sometimes', 'nullable', 'string', 'max:120'],
        ]);
        $branch = (int) $data['branch_id'];
        $this->branch($company, $branch);
        $stock = DB::table('inventory_movements')->where('company_id', $company)->where('branch_id', $branch)
            ->whereNull('deleted_at')->groupBy('item_id')
            ->select('item_id')->selectRaw("SUM(CASE WHEN movement_type='IN' THEN quantity ELSE -quantity END) AS stock");
        $query = DB::table('inventory_items as i')->leftJoinSub($stock, 'b', 'b.item_id', '=', 'i.id')
            ->where('i.company_id', $company)->where('i.is_active', true)->whereNull('i.deleted_at')
            ->whereNotNull('i.sale_price')->where('i.sale_price', '>', 0);
        if (trim((string) ($data['q'] ?? '')) !== '') {
            $q = trim($data['q']);
            $query->where(fn ($builder) => $builder->where('i.name', 'like', '%'.$q.'%')
                ->orWhere('i.sku', 'like', '%'.$q.'%'));
        }
        $result = $query->orderBy('i.name')->limit(50)
            ->get(['i.id', 'i.sku', 'i.name', 'i.unit', 'i.sale_price', DB::raw('COALESCE(b.stock,0) AS stock')])
            ->map(fn ($r) => [
                'id' => $r->id, 'sku' => $r->sku, 'name' => $r->name, 'unit' => $r->unit,
                'sale_price' => $this->money($this->cents($r->sale_price, 'sale_price')),
                'stock' => $this->stockLabel($this->scopeStock($company, $branch, (int) $r->id)),
            ]);
        return response()->json(['data' => $result]);
    }

    private function receipt(int $company, int $saleId): array
    {
        $sale = DB::table('pos_sales')->where('company_id', $company)->where('id', $saleId)->first();
        if (!$sale) abort(404, 'Venta no encontrada.');
        $lines = DB::table('pos_sale_items')->where('company_id', $company)->where('sale_id', $saleId)
            ->orderBy('id')->get(['id', 'item_id', 'sku_snapshot', 'name_snapshot', 'unit_snapshot', 'quantity', 'unit_price', 'line_total'])
            ->map(function ($r): array {
                $v = (array) $r;
                $v['unit_price'] = $this->money($this->cents($r->unit_price));
                $v['line_total'] = $this->money($this->cents($r->line_total));
                $v['quantity'] = $this->stockLabel((int) round((float) $r->quantity * 1000));
                return $v;
            });
        $payments = DB::table('pos_sale_payments')->where('company_id', $company)->where('sale_id', $saleId)
            ->orderBy('id')->get(['id', 'channel', 'amount', 'reference', 'cash_session_id', 'bank_account_id'])
            ->map(function ($r): array {
                $v = (array) $r;
                $v['amount'] = $this->money($this->cents($r->amount));
                return $v;
            });
        return ['id' => $sale->id, 'branch_id' => $sale->branch_id, 'status' => $sale->status,
            'subtotal' => $this->money($this->cents($sale->subtotal)),
            'discount_amount' => $this->money($this->cents($sale->discount_amount)),
            'discount_reason' => $sale->discount_reason,
            'total' => $this->money($this->cents($sale->total)),
            'posted_at' => $sale->posted_at, 'receipt_type' => 'NON_FISCAL',
            'lines' => $lines, 'payments' => $payments];
    }
    public function show(Request $request, int $company, int $sale): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        return response()->json(['data' => $this->receipt($company, $sale)]);
    }
    public function index(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $data = $request->validate([
            'branch_id' => ['sometimes', 'integer', 'min:1'],
            'page' => ['sometimes', 'integer', 'min:1'],
        ]);
        $query = DB::table('pos_sales')->where('company_id', $company);
        if (isset($data['branch_id'])) {
            $this->branch($company, (int) $data['branch_id']);
            $query->where('branch_id', $data['branch_id']);
        }
        return response()->json($query->orderByDesc('id')->paginate(15));
    }

    public function checkout(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $data = $request->validate([
            'branch_id' => ['required', 'integer', 'min:1'],
            'idempotency_key' => ['required', 'string', 'min:12', 'max:100', 'regex:/^[A-Za-z0-9._-]+$/'],
            'lines' => ['required', 'array', 'min:1', 'max:40'],
            'lines.*.item_id' => ['required', 'integer', 'min:1', 'distinct'],
            'lines.*.quantity' => ['required', 'integer', 'between:1,999'],
            'discount_amount' => ['required', 'regex:/^(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,2})?$/D'],
            'discount_reason' => ['sometimes', 'nullable', 'string', 'max:255'],
            'payments' => ['required', 'array', 'min:1', 'max:2'],
            'payments.*.payment_method_id' => ['required', 'integer', 'min:1'],
            'payments.*.cash_session_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
            'payments.*.bank_account_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
            'payments.*.amount' => ['required', 'regex:/^(?:0|[1-9][0-9]{0,8})(?:\.[0-9]{1,2})?$/D'],
            'payments.*.reference' => ['sometimes', 'nullable', 'string', 'max:120'],
        ]);
        $hash = hash('sha256', json_encode($data, JSON_THROW_ON_ERROR));
        $result = DB::transaction(function () use ($request, $company, $data, $hash): array {
            // Serializa confirmaciones de la empresa, incluso reintentos simultáneos del mismo ticket.
            DB::table('companies')->where('id', $company)->lockForUpdate()->first();
            $previous = DB::table('pos_sales')->where('company_id', $company)
                ->where('idempotency_key', $data['idempotency_key'])->first();
            if ($previous) {
                if ($previous->request_hash !== $hash) return ['conflict' => 'Clave repetida con datos diferentes.'];
                return ['data' => $this->receipt($company, (int) $previous->id), 'replayed' => true];
            }
            $branch = (int) $data['branch_id'];
            $this->branch($company, $branch);
            $actor = (int) $request->user()->id;
            $lineRows = []; $subtotal = 0;
            foreach ($data['lines'] as $line) {
                $item = DB::table('inventory_items')->where('company_id', $company)
                    ->where('id', $line['item_id'])->where('is_active', true)
                    ->whereNull('deleted_at')->lockForUpdate()->first();
                if (!$item || $item->sale_price === null) {
                    throw ValidationException::withMessages(['lines' => 'Artículo inactivo o sin precio de venta.']);
                }
                $quantity = (int) $line['quantity'];
                $price = $this->cents($item->sale_price, 'sale_price', false);
                if ($this->scopeStock($company, $branch, (int) $item->id) < $quantity * 1000) {
                    throw ValidationException::withMessages(['lines' => 'Inventario insuficiente para '.$item->name.'.']);
                }
                $value = $quantity * $price;
                if ($value > 99999999999 || $subtotal + $value > 99999999999) {
                    throw ValidationException::withMessages(['lines' => 'Límite de importe superado.']);
                }
                $subtotal += $value;
                $lineRows[] = ['item' => $item, 'quantity' => $quantity,
                    'unit_price' => $this->money($price), 'total' => $this->money($value)];
            }
            $discount = $this->cents($data['discount_amount'], 'discount_amount');
            if ($discount >= $subtotal) {
                throw ValidationException::withMessages(['discount_amount' => 'El descuento debe ser menor que el subtotal.']);
            }
            $reason = trim((string) ($data['discount_reason'] ?? ''));
            if ($discount > 0 && mb_strlen($reason) < 3) {
                throw ValidationException::withMessages(['discount_reason' => 'Explica el descuento aplicado.']);
            }
            $net = $subtotal - $discount;
            $sum = 0; $paymentRows = []; $used = [];
            foreach ($data['payments'] as $payment) {
                $method = DB::table('sale_payment_methods')->where('company_id', $company)
                    ->where('id', $payment['payment_method_id'])->where('is_active', true)->whereNull('deleted_at')->first();
                if (!$method || !in_array($method->channel, ['CASH', 'BANK'], true)) {
                    throw ValidationException::withMessages(['payments' => 'Medio de pago no disponible.']);
                }
                if (isset($used[$method->channel])) {
                    throw ValidationException::withMessages(['payments' => 'Solo se admite una línea por canal de pago.']);
                }
                $used[$method->channel] = true;
                $amount = $this->cents($payment['amount'], 'payments.amount', false);
                $cash = $payment['cash_session_id'] ?? null;
                $bank = $payment['bank_account_id'] ?? null;
                if ($method->channel === 'CASH') {
                    if ($cash === null || $bank !== null) {
                        throw ValidationException::withMessages(['cash_session_id' => 'Selecciona solo la sesión de caja.']);
                    }
                    $session = DB::table('cash_sessions as s')->join('cash_registers as r', 'r.id', '=', 's.register_id')
                        ->where('s.company_id', $company)->where('r.company_id', $company)
                        ->where('s.id', $cash)->where('s.status', 'OPEN')->whereNull('s.deleted_at')
                        ->whereNull('r.deleted_at')->where('r.branch_id', $branch)->first(['s.id']);
                    if (!$session) throw ValidationException::withMessages(['cash_session_id' => 'Caja cerrada o de otra sucursal.']);
                } else {
                    if ($bank === null || $cash !== null) {
                        throw ValidationException::withMessages(['bank_account_id' => 'Selecciona solo cuenta bancaria.']);
                    }
                    $account = DB::table('sale_bank_accounts')->where('company_id', $company)
                        ->where('branch_id', $branch)->where('id', $bank)->where('is_active', true)
                        ->whereNull('deleted_at')->first();
                    if (!$account) throw ValidationException::withMessages(['bank_account_id' => 'Cuenta no disponible en la sucursal.']);
                }
                $sum += $amount;
                $paymentRows[] = ['channel' => $method->channel, 'method_id' => $method->id,
                    'cash' => $cash, 'bank' => $bank, 'amount' => $amount,
                    'reference' => trim((string) ($payment['reference'] ?? '')) ?: null];
            }
            if ($sum !== $net) throw ValidationException::withMessages([
                'payments' => 'La suma de pagos debe coincidir exactamente con el total después del descuento.',
            ]);
            $now = now();
            $saleId = DB::table('pos_sales')->insertGetId([
                'company_id' => $company, 'branch_id' => $branch,
                'idempotency_key' => $data['idempotency_key'], 'request_hash' => $hash,
                'status' => 'POSTED', 'subtotal' => $this->money($subtotal),
                'discount_amount' => $this->money($discount), 'discount_reason' => $discount ? $reason : null,
                'total' => $this->money($net), 'actor_user_id' => $actor, 'posted_at' => $now,
                'created_at' => $now, 'updated_at' => $now,
            ]);
            foreach ($lineRows as $line) {
                $item = $line['item'];
                $lineId = DB::table('pos_sale_items')->insertGetId([
                    'company_id' => $company, 'sale_id' => $saleId, 'item_id' => $item->id,
                    'sku_snapshot' => $item->sku, 'name_snapshot' => $item->name,
                    'unit_snapshot' => $item->unit,
                    'quantity' => $this->stockLabel($line['quantity'] * 1000),
                    'unit_price' => $line['unit_price'], 'line_total' => $line['total'],
                    'created_at' => $now, 'updated_at' => $now,
                ]);
                $movementId = DB::table('inventory_movements')->insertGetId([
                    'company_id' => $company, 'branch_id' => $branch, 'item_id' => $item->id,
                    'movement_type' => 'OUT', 'quantity' => $this->stockLabel($line['quantity'] * 1000),
                    'reference' => 'POS-'.$saleId,
                    'notes' => 'Venta POS confirmada. Línea '.$lineId,
                    'actor_user_id' => $actor, 'source_pos_sale_item_id' => $lineId,
                    'created_at' => $now, 'updated_at' => $now,
                ]);
                DB::table('inventory_movement_events')->insert([
                    'company_id' => $company, 'movement_id' => $movementId,
                    'action' => 'CREATE', 'before_json' => null,
                    'after_json' => json_encode(['source_pos_sale_item_id' => $lineId,
                        'direction' => 'OUT', 'quantity' => $line['quantity']], JSON_THROW_ON_ERROR),
                    'actor_user_id' => $actor, 'occurred_at' => $now,
                ]);
            }
            foreach ($paymentRows as $p) {
                $paymentId = DB::table('pos_sale_payments')->insertGetId([
                    'company_id' => $company, 'sale_id' => $saleId,
                    'payment_method_id' => $p['method_id'], 'channel' => $p['channel'],
                    'cash_session_id' => $p['cash'], 'bank_account_id' => $p['bank'],
                    'amount' => $this->money($p['amount']), 'reference' => $p['reference'],
                    'posted_at' => $now, 'created_at' => $now, 'updated_at' => $now,
                ]);
                if ($p['channel'] === 'CASH') {
                    $session = DB::table('cash_sessions')->where('company_id', $company)
                        ->where('id', $p['cash'])->where('status', 'OPEN')->lockForUpdate()->first();
                    if (!$session) throw ValidationException::withMessages(['cash_session_id' => 'Caja cerrada durante la venta.']);
                    $movementId = DB::table('cash_movements')->insertGetId([
                        'company_id' => $company, 'session_id' => $p['cash'],
                        'expense_category_id' => null, 'direction' => 'IN',
                        'amount' => $this->money($p['amount']), 'reference' => 'POS-'.$saleId,
                        'notes' => 'Cobro de artículos en Smart POS', 'actor_user_id' => $actor,
                        'source_pos_payment_id' => $paymentId,
                        'created_at' => $now, 'updated_at' => $now,
                    ]);
                    DB::table('cash_movement_events')->insert([
                        'company_id' => $company, 'movement_id' => $movementId,
                        'action' => 'CREATE', 'before_json' => null,
                        'after_json' => json_encode(['source_pos_payment_id' => $paymentId,
                            'direction' => 'IN', 'amount' => $this->money($p['amount'])], JSON_THROW_ON_ERROR),
                        'actor_user_id' => $actor, 'occurred_at' => $now,
                    ]);
                }
            }
            return ['data' => $this->receipt($company, $saleId), 'replayed' => false];
        });
        if (isset($result['conflict'])) return response()->json(['message' => $result['conflict']], 409);
        return response()->json($result, empty($result['replayed']) ? 201 : 200);
    }
}
