<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/** Bloque 20. Ventas cobradas al entregar, sin documento fiscal ni impuestos inventados. */
class CompanySalesController extends Controller
{
    private const TABLES = [
        'banks' => 'sale_bank_accounts',
        'methods' => 'sale_payment_methods',
        'discounts' => 'wash_order_discounts',
        'payments' => 'wash_order_payments',
    ];

    private function check(Request $request, int $company, string $permission): void
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
            ->where('ur.company_id', $company)->where('ur.user_id', $uid)->where('p.code', $permission)->exists();
        if (!$allowed) abort(403, 'Permiso insuficiente.');
    }

    private function table(string $resource): string
    {
        return self::TABLES[$resource] ?? abort(404, 'Recurso no disponible.');
    }

    private function scoped(string $resource, int $company)
    {
        return DB::table($this->table($resource))->where('company_id', $company)->whereNull('deleted_at');
    }

    private function record(string $resource, int $company, int $id): object
    {
        return $this->scoped($resource, $company)->where('id', $id)->first()
            ?? abort(404, 'Registro inexistente.');
    }

    private function cents(mixed $value, string $field = 'amount', bool $zero = true): int
    {
        $str = (string) $value;
        if (!preg_match('/^(?:0|[1-9][0-9]{0,9})(?:\.[0-9]{1,2})?$/D', $str)) {
            throw ValidationException::withMessages([$field => 'Importe inválido; usa máximo dos decimales.']);
        }
        $split = explode('.', $str, 2);
        $result = ((int) $split[0] * 100) + (int) str_pad($split[1] ?? '', 2, '0');
        if (!$zero && $result <= 0) {
            throw ValidationException::withMessages([$field => 'El monto debe ser mayor a cero.']);
        }
        return $result;
    }

    private function fmt(int $cents): string
    {
        $sign = $cents < 0 ? '-' : '';
        $abs = abs($cents);
        return $sign.intdiv($abs, 100).'.'.str_pad((string) ($abs % 100), 2, '0', STR_PAD_LEFT);
    }

    private function branch(int $company, int $branch): void
    {
        if (!DB::table('branches')->where('company_id', $company)->where('id', $branch)
            ->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal inválida.']);
        }
    }

    private function order(int $company, int $id, bool $locked = false): object
    {
        $query = DB::table('wash_orders')->where('company_id', $company)->where('id', $id);
        if ($locked) $query->lockForUpdate();
        return $query->first() ?? abort(404, 'Orden inexistente.');
    }

    private function editableOrder(int $company, int $id, bool $locked = false): object
    {
        $order = $this->order($company, $id, $locked);
        if ($order->status !== 'TERMINADO') {
            throw ValidationException::withMessages(['order_id' => 'Solo se prepara el cobro de un lavado terminado, aún no entregado.']);
        }
        return $order;
    }

    private function method(int $company, int $id): object
    {
        $method = $this->scoped('methods', $company)->where('id', $id)->where('is_active', true)->first();
        if (!$method) throw ValidationException::withMessages(['payment_method_id' => 'Medio de pago no disponible.']);
        return $method;
    }

    private function destination(int $company, object $order, object $method, array $values): array
    {
        $cash = isset($values['cash_session_id']) ? (int) $values['cash_session_id'] : null;
        $bank = isset($values['bank_account_id']) ? (int) $values['bank_account_id'] : null;
        if ($method->channel === 'CASH') {
            if ($cash === null || $bank !== null) {
                throw ValidationException::withMessages(['cash_session_id' => 'Selecciona únicamente una sesión de caja abierta.']);
            }
            $session = DB::table('cash_sessions as s')->join('cash_registers as r', 'r.id', '=', 's.register_id')
                ->where('s.company_id', $company)->where('s.id', $cash)->where('s.status', 'OPEN')
                ->whereNull('s.deleted_at')->whereNull('r.deleted_at')
                ->where('r.company_id', $company)->where('r.branch_id', $order->branch_id)->first(['s.id']);
            if (!$session) throw ValidationException::withMessages(['cash_session_id' => 'La caja debe estar abierta en la sucursal de la orden.']);
        } elseif ($method->channel === 'BANK') {
            if ($bank === null || $cash !== null) {
                throw ValidationException::withMessages(['bank_account_id' => 'Selecciona únicamente una cuenta bancaria activa.']);
            }
            $account = $this->scoped('banks', $company)->where('id', $bank)
                ->where('branch_id', $order->branch_id)->where('is_active', true)->first();
            if (!$account) throw ValidationException::withMessages(['bank_account_id' => 'Cuenta inactiva o de otra sucursal.']);
        } else {
            throw ValidationException::withMessages(['payment_method_id' => 'Canal no admitido.']);
        }
        return ['cash_session_id' => $cash, 'bank_account_id' => $bank];
    }

    private function discount(int $company, int $orderId): int
    {
        $row = $this->scoped('discounts', $company)->where('order_id', $orderId)->first();
        return $row ? $this->cents($row->amount) : 0;
    }

    private function discountUpdate(int $company, object $order, string $amount, ?string $reason, int $actor): void
    {
        $price = $this->cents($order->quoted_price);
        $discount = $this->cents($amount, 'discount_amount');
        if ($discount > $price) {
            throw ValidationException::withMessages(['discount_amount' => 'No puedes descontar más del precio del servicio.']);
        }
        if ($discount > 0 && mb_strlen(trim((string) $reason)) < 3) {
            throw ValidationException::withMessages(['discount_reason' => 'Indica el motivo del descuento personalizado.']);
        }
        // La unicidad por orden evita dos descuentos sobre la misma operación.
        $exists = DB::table('wash_order_discounts')->where('company_id', $company)->where('order_id', $order->id)->first();
        if ($discount === 0) {
            if ($exists) DB::table('wash_order_discounts')->where('id', $exists->id)->update(['deleted_at' => now(), 'updated_at' => now()]);
            return;
        }
        $payload = [
            'amount' => $this->fmt($discount), 'reason' => trim((string) $reason),
            'authorized_by' => $actor, 'deleted_at' => null, 'updated_at' => now(),
        ];
        if ($exists) DB::table('wash_order_discounts')->where('id', $exists->id)->update($payload);
        else DB::table('wash_order_discounts')->insert([
            ...$payload, 'company_id' => $company, 'order_id' => $order->id, 'created_at' => now(),
        ]);
    }

    private function paymentInfo(int $company, object $payment): array
    {
        $row = (array) $payment;
        $row['amount'] = $this->fmt($this->cents($payment->amount));
        $row['method_name'] = DB::table('sale_payment_methods')->where('company_id', $company)
            ->where('id', $payment->payment_method_id)->value('name');
        return $row;
    }

    private function decorate(int $company, string $resource, object $record): array
    {
        $data = (array) $record;
        if ($resource === 'discounts' || $resource === 'payments') {
            $order = $this->order($company, (int) $record->order_id);
            $data['tracking_code'] = $order->tracking_code;
            $data['order_status'] = $order->status;
            $data['order_price'] = $this->fmt($this->cents($order->quoted_price));
            if ($resource === 'discounts') $data['amount'] = $this->fmt($this->cents($record->amount));
            else return array_merge($data, $this->paymentInfo($company, $record));
        }
        if ($resource === 'banks') {
            $data['received_total'] = $this->fmt($this->cents((string) DB::table('sale_bank_movements')
                ->where('company_id', $company)->where('bank_account_id', $record->id)->sum('amount')));
        }
        return $data;
    }

    public function options(Request $request, int $company): JsonResponse
    {
        $this->check($request, $company, 'company.view');
        return response()->json(['data' => [
            'branches' => DB::table('branches')->where('company_id', $company)->where('is_active', true)->get(['id', 'name']),
            'orders' => DB::table('wash_orders')->where('company_id', $company)->where('status', 'TERMINADO')
                ->orderByDesc('id')->limit(100)->get(['id', 'tracking_code', 'branch_id', 'quoted_price', 'status']),
            'banks' => $this->scoped('banks', $company)->where('is_active', true)->get(['id', 'alias', 'branch_id', 'bank_name']),
            'methods' => $this->scoped('methods', $company)->where('is_active', true)->get(['id', 'name', 'channel']),
            'sessions' => DB::table('cash_sessions as s')->join('cash_registers as r', 'r.id', '=', 's.register_id')
                ->where('s.company_id', $company)->where('s.status', 'OPEN')->whereNull('s.deleted_at')
                ->where('r.company_id', $company)->get(['s.id', 's.register_id', 'r.name', 'r.branch_id']),
        ]]);
    }

    public function quote(Request $request, int $company, int $order): JsonResponse
    {
        $this->check($request, $company, 'company.view');
        $row = $this->order($company, $order);
        $price = $this->cents($row->quoted_price);
        $discount = $this->discount($company, $order);
        return response()->json(['data' => [
            'order_id' => $order, 'tracking_code' => $row->tracking_code,
            'status' => $row->status, 'branch_id' => $row->branch_id,
            'price' => $this->fmt($price), 'discount' => $this->fmt($discount),
            'discount_reason' => $this->scoped('discounts', $company)->where('order_id', $order)->value('reason'),
            'total' => $this->fmt($price - $discount),
            'payments' => $this->scoped('payments', $company)->where('order_id', $order)->get()
                ->map(fn ($p) => $this->paymentInfo($company, $p)),
        ]]);
    }

    public function index(Request $request, int $company, string $resource): JsonResponse
    {
        $this->check($request, $company, 'company.view');
        $this->table($resource);
        $input = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:120'],
            'page' => ['sometimes', 'integer', 'min:1'], 'per_page' => ['sometimes', 'integer', 'between:1,50'],
        ]);
        $query = $this->scoped($resource, $company);
        if (!empty($input['q'])) {
            $search = trim($input['q']);
            $columns = match ($resource) {
                'banks' => ['alias', 'bank_name'], 'methods' => ['name', 'channel'],
                'discounts' => ['reason'], 'payments' => ['reference', 'notes'],
            };
            $query->where(function ($q) use ($columns, $search): void {
                foreach ($columns as $column) $q->orWhere($column, 'like', '%'.$search.'%');
            });
        }
        $page = $query->orderByDesc('id')->paginate($input['per_page'] ?? 10)->toArray();
        $page['data'] = array_map(fn ($r) => $this->decorate($company, $resource, (object) $r), $page['data']);
        return response()->json($page);
    }

    public function show(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->check($request, $company, 'company.view');
        return response()->json(['data' => $this->decorate($company, $resource, $this->record($resource, $company, $record))]);
    }

    private function rules(string $resource, bool $create): array
    {
        $required = $create ? ['required'] : ['sometimes', 'required'];
        $money = ['regex:/^(?:0|[1-9][0-9]{0,9})(?:\.[0-9]{1,2})?$/D'];
        return match ($resource) {
            'banks' => [
                'branch_id' => [...$required, 'integer', 'min:1'],
                'alias' => [...$required, 'string', 'max:120'],
                'bank_name' => [...$required, 'string', 'max:160'],
                'account_last4' => ['sometimes', 'nullable', 'digits:4'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
                'is_active' => ['sometimes', 'boolean'],
            ],
            'methods' => [
                'name' => [...$required, 'string', 'max:120'],
                'channel' => [...$required, Rule::in(['CASH', 'BANK'])],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
                'is_active' => ['sometimes', 'boolean'],
            ],
            'discounts' => [
                'order_id' => [...$required, 'integer', 'min:1'],
                'amount' => [...$required, ...$money],
                'reason' => [...$required, 'string', 'min:3', 'max:255'],
            ],
            'payments' => [
                'order_id' => [...$required, 'integer', 'min:1'],
                'payment_method_id' => [...$required, 'integer', 'min:1'],
                'cash_session_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
                'bank_account_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
                'amount' => [...$required, ...$money],
                'reference' => ['sometimes', 'nullable', 'string', 'max:120'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
            ],
            default => abort(404),
        };
    }

    public function store(Request $request, int $company, string $resource): JsonResponse
    {
        $this->check($request, $company, 'company.update');
        $this->table($resource);
        $data = $request->validate($this->rules($resource, true));
        $result = DB::transaction(function () use ($request, $company, $resource, $data): object {
            if ($resource === 'banks') {
                $this->branch($company, (int) $data['branch_id']);
                $data['alias'] = trim($data['alias']); $data['bank_name'] = trim($data['bank_name']);
            }
            if ($resource === 'methods') {
                $data['name'] = trim($data['name']);
                if ($this->scoped('methods', $company)->where('name', $data['name'])->exists()) {
                    throw ValidationException::withMessages(['name' => 'Nombre de método duplicado.']);
                }
            }
            if ($resource === 'discounts') {
                $order = $this->editableOrder($company, (int) $data['order_id'], true);
                if ($this->scoped('discounts', $company)->where('order_id', $order->id)->exists()) {
                    throw ValidationException::withMessages(['order_id' => 'La orden ya tiene descuento: edítalo.']);
                }
                $this->cents($data['amount'], 'amount', false);
                $this->discountUpdate($company, $order, (string) $data['amount'], $data['reason'], (int) $request->user()->id);
                return $this->scoped('discounts', $company)->where('order_id', $order->id)->first();
            }
            if ($resource === 'payments') {
                $order = $this->editableOrder($company, (int) $data['order_id'], true);
                $method = $this->method($company, (int) $data['payment_method_id']);
                $this->cents($data['amount'], 'amount', false);
                $data = array_merge($data, $this->destination($company, $order, $method, $data));
                $already = $this->scoped('payments', $company)->where('order_id', $order->id)->get();
                $sum = $already->sum(fn ($p) => $this->cents($p->amount)) + $this->cents($data['amount']);
                if ($sum > $this->cents($order->quoted_price) - $this->discount($company, $order->id)) {
                    throw ValidationException::withMessages(['amount' => 'Cobros pendientes superan el total del lavado.']);
                }
                $data += ['status' => 'PENDING', 'registered_by' => $request->user()->id];
            }
            $id = DB::table($this->table($resource))->insertGetId([
                ...$data, 'company_id' => $company, 'created_at' => now(), 'updated_at' => now(),
            ]);
            return $this->record($resource, $company, $id);
        });
        return response()->json(['data' => $this->decorate($company, $resource, $result)], 201);
    }

    public function update(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->check($request, $company, 'company.update');
        $data = $request->validate($this->rules($resource, false));
        if (!$data) throw ValidationException::withMessages(['data' => 'Indica un campo para actualizar.']);
        $result = DB::transaction(function () use ($request, $company, $resource, $record, $data): object {
            $old = $this->record($resource, $company, $record);
            if ($resource === 'banks') {
                if (isset($data['branch_id']) && (int) $data['branch_id'] !== (int) $old->branch_id) {
                    throw ValidationException::withMessages(['branch_id' => 'No puedes cambiar una cuenta bancaria de sucursal.']);
                }
                unset($data['branch_id']);
                if (($data['is_active'] ?? true) === false && $this->scoped('payments', $company)
                    ->where('bank_account_id', $record)->where('status', 'PENDING')->exists()) {
                    throw ValidationException::withMessages(['is_active' => 'Cuenta vinculada a pagos pendientes.']);
                }
            }
            if ($resource === 'methods') {
                if (isset($data['channel']) && $data['channel'] !== $old->channel &&
                    DB::table('wash_order_payments')->where('company_id', $company)->where('payment_method_id', $record)->exists()) {
                    throw ValidationException::withMessages(['channel' => 'No cambies el canal de un método con cobros registrados.']);
                }
                if (isset($data['name']) && $this->scoped('methods', $company)->where('name', trim($data['name']))
                    ->where('id', '!=', $record)->exists()) {
                    throw ValidationException::withMessages(['name' => 'Nombre de método duplicado.']);
                }
                if (isset($data['name'])) $data['name'] = trim($data['name']);
            }
            if ($resource === 'discounts') {
                $order = $this->editableOrder($company, (int) $old->order_id, true);
                if (isset($data['order_id']) && (int) $data['order_id'] !== (int) $old->order_id) {
                    throw ValidationException::withMessages(['order_id' => 'No se puede mover el descuento a otra orden.']);
                }
                $amount = (string) ($data['amount'] ?? $old->amount);
                $reason = (string) ($data['reason'] ?? $old->reason);
                $pending = $this->scoped('payments', $company)->where('order_id', $order->id)->get();
                if ($pending->sum(fn ($p) => $this->cents($p->amount)) > $this->cents($order->quoted_price) - $this->cents($amount)) {
                    throw ValidationException::withMessages(['amount' => 'El descuento supera el saldo tras pagos ya preparados.']);
                }
                $this->cents($amount, 'amount', false);
                $this->discountUpdate($company, $order, $amount, $reason, (int) $request->user()->id);
                return $this->record('discounts', $company, $record);
            }
            if ($resource === 'payments') {
                $order = $this->editableOrder($company, (int) $old->order_id, true);
                if ($old->status !== 'PENDING') throw ValidationException::withMessages(['status' => 'Cobro confirmado inmutable.']);
                if (isset($data['order_id']) && (int) $data['order_id'] !== (int) $old->order_id) {
                    throw ValidationException::withMessages(['order_id' => 'La orden no puede cambiarse.']);
                }
                unset($data['order_id']);
                $method = $this->method($company, (int) ($data['payment_method_id'] ?? $old->payment_method_id));
                $combined = [...(array) $old, ...$data];
                $data = [...$data, ...$this->destination($company, $order, $method, $combined)];
                if (isset($data['amount'])) $this->cents($data['amount'], 'amount', false);
                $others = $this->scoped('payments', $company)->where('order_id', $order->id)->where('id', '!=', $record)->get();
                if ($others->sum(fn ($p) => $this->cents($p->amount)) + $this->cents($data['amount'] ?? $old->amount) >
                    $this->cents($order->quoted_price) - $this->discount($company, $order->id)) {
                    throw ValidationException::withMessages(['amount' => 'El total de los cobros supera el precio final.']);
                }
            }
            $data['updated_at'] = now();
            DB::table($this->table($resource))->where('company_id', $company)->where('id', $record)->update($data);
            return $this->record($resource, $company, $record);
        });
        return response()->json(['data' => $this->decorate($company, $resource, $result)]);
    }

    public function destroy(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->check($request, $company, 'company.update');
        DB::transaction(function () use ($request, $company, $resource, $record): void {
            $old = $this->record($resource, $company, $record);
            if ($resource === 'banks' && DB::table('wash_order_payments')->where('company_id', $company)
                ->where('bank_account_id', $record)->exists()) {
                throw ValidationException::withMessages(['id' => 'Cuenta con historial: desactívala.']);
            }
            if ($resource === 'methods' && DB::table('wash_order_payments')->where('company_id', $company)
                ->where('payment_method_id', $record)->exists()) {
                throw ValidationException::withMessages(['id' => 'Método utilizado: desactívalo.']);
            }
            if ($resource === 'discounts') $this->editableOrder($company, (int) $old->order_id, true);
            if ($resource === 'payments') {
                $this->editableOrder($company, (int) $old->order_id, true);
                if ($old->status !== 'PENDING') throw ValidationException::withMessages(['status' => 'Cobro confirmado no se elimina.']);
            }
            DB::table($this->table($resource))->where('company_id', $company)->where('id', $record)
                ->update(['deleted_at' => now(), 'updated_at' => now()]);
        });
        return response()->json(['message' => 'Registro archivado.']);
    }

    public function checkout(Request $request, int $company, int $order): JsonResponse
    {
        $this->check($request, $company, 'company.update');
        $data = $request->validate([
            'expected_version' => ['required', 'integer', 'min:1'],
            'discount_amount' => ['sometimes', 'required', 'regex:/^(?:0|[1-9][0-9]{0,9})(?:\.[0-9]{1,2})?$/D'],
            'discount_reason' => ['sometimes', 'nullable', 'string', 'max:255'],
            'payment_method_id' => ['sometimes', 'integer', 'min:1'],
            'cash_session_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
            'bank_account_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
            'reference' => ['sometimes', 'nullable', 'string', 'max:120'],
            'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
        ]);
        $result = DB::transaction(function () use ($request, $company, $order, $data): array {
            $row = $this->order($company, $order, true);
            if ($row->status === 'ENTREGADO') return ['conflict' => 'La orden ya fue entregada y cobrada.'];
            if ($row->status !== 'TERMINADO') return ['conflict' => 'Primero termina el lavado antes de entregarlo.'];
            if ((int) $row->version !== (int) $data['expected_version']) {
                return ['conflict' => 'La orden cambió en otra sesión; actualiza para continuar.'];
            }
            if (array_key_exists('discount_amount', $data)) {
                $this->discountUpdate($company, $row, $data['discount_amount'], $data['discount_reason'] ?? null,
                    (int) $request->user()->id);
            }
            $net = $this->cents($row->quoted_price) - $this->discount($company, $order);
            $pending = $this->scoped('payments', $company)->where('order_id', $order)->lockForUpdate()->get();
            if (array_key_exists('payment_method_id', $data)) {
                if ($net === 0) throw ValidationException::withMessages(['payment_method_id' => 'Una cortesía total no genera movimiento de cobro.']);
                if ($pending->isNotEmpty()) return ['conflict' => 'Ya existen cobros preparados. Revísalos antes de entregar.'];
                $method = $this->method($company, (int) $data['payment_method_id']);
                $destination = $this->destination($company, $row, $method, $data);
                $id = DB::table('wash_order_payments')->insertGetId([
                    'company_id' => $company, 'order_id' => $order,
                    'payment_method_id' => $method->id, ...$destination,
                    'amount' => $this->fmt($net), 'status' => 'PENDING',
                    'reference' => $data['reference'] ?? null, 'notes' => $data['notes'] ?? null,
                    'registered_by' => $request->user()->id,
                    'created_at' => now(), 'updated_at' => now(),
                ]);
                $pending = $this->scoped('payments', $company)->where('id', $id)->get();
            }
            $sum = $pending->sum(fn ($payment) => $this->cents($payment->amount));
            if (($net > 0 && $pending->isEmpty()) || $sum !== $net) {
                throw ValidationException::withMessages([
                    'payments' => 'El total cobrado debe coincidir exactamente con el precio después del descuento.',
                ]);
            }
            foreach ($pending as $payment) {
                if ($payment->status !== 'PENDING') return ['conflict' => 'La orden contiene un cobro que ya fue registrado.'];
                $method = $this->method($company, (int) $payment->payment_method_id);
                $this->destination($company, $row, $method, (array) $payment);
                if ($method->channel === 'CASH') {
                    $this->postCash($company, $payment, (int) $request->user()->id);
                } else {
                    DB::table('sale_bank_movements')->insert([
                        'company_id' => $company, 'bank_account_id' => $payment->bank_account_id,
                        'payment_id' => $payment->id, 'amount' => $this->fmt($this->cents($payment->amount)),
                        'posted_at' => now(),
                    ]);
                }
                DB::table('wash_order_payments')->where('id', $payment->id)->where('company_id', $company)
                    ->update(['status' => 'POSTED', 'posted_at' => now(), 'updated_at' => now()]);
            }
            DB::table('wash_orders')->where('company_id', $company)->where('id', $order)->update([
                'status' => 'ENTREGADO', 'delivered_at' => now(), 'version' => $row->version + 1, 'updated_at' => now(),
            ]);
            DB::table('wash_order_events')->insert([
                'company_id' => $company, 'order_id' => $order, 'from_status' => 'TERMINADO',
                'to_status' => 'ENTREGADO', 'reason' => 'Cobro confirmado y vehículo entregado',
                'actor_user_id' => $request->user()->id, 'occurred_at' => now(),
            ]);
            return ['data' => [
                'order_id' => $order, 'status' => 'ENTREGADO', 'quoted_price' => $this->fmt($this->cents($row->quoted_price)),
                'discount' => $this->fmt($this->discount($company, $order)),
                'total_paid' => $this->fmt($sum), 'payments_count' => $pending->count(),
            ]];
        });
        if (isset($result['conflict'])) return response()->json(['message' => $result['conflict']], 409);
        return response()->json($result);
    }

    private function postCash(int $company, object $payment, int $actor): void
    {
        $session = DB::table('cash_sessions')->where('company_id', $company)
            ->where('id', $payment->cash_session_id)->where('status', 'OPEN')->lockForUpdate()->first();
        if (!$session) throw ValidationException::withMessages(['cash_session_id' => 'La caja se cerró antes de confirmar el cobro.']);
        $movement = DB::table('cash_movements')->insertGetId([
            'company_id' => $company, 'session_id' => $session->id,
            'expense_category_id' => null, 'direction' => 'IN',
            'amount' => $this->fmt($this->cents($payment->amount)),
            'reference' => 'LAVADO-'.$payment->order_id,
            'notes' => 'Cobro automático al entregar vehículo', 'actor_user_id' => $actor,
            'source_sale_payment_id' => $payment->id,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        DB::table('cash_movement_events')->insert([
            'company_id' => $company, 'movement_id' => $movement, 'action' => 'CREATE',
            'before_json' => null, 'after_json' => json_encode([
                'source_sale_payment_id' => $payment->id, 'amount' => $this->fmt($this->cents($payment->amount)),
                'direction' => 'IN',
            ], JSON_THROW_ON_ERROR), 'actor_user_id' => $actor, 'occurred_at' => now(),
        ]);
    }
}
