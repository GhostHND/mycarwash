<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

class CompanyWashWorkflowController extends Controller
{
    private const RESOURCES = [
        'bays' => 'wash_bays',
        'orders' => 'wash_orders',
        'assignments' => 'wash_assignments',
    ];

    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $userId = $request->user()->id;
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        if (!$member) abort(404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')->join('roles as r', function ($join): void {
            $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
        })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $userId)
            ->where('p.code', $permission)->exists();
        if (!$allowed) abort(403, 'No tienes permiso para esta operación.');
    }

    private function table(string $resource): string
    {
        if (!isset(self::RESOURCES[$resource])) abort(404, 'Catálogo no disponible.');
        return self::RESOURCES[$resource];
    }

    private function scoped(string $resource, int $company)
    {
        $builder = DB::table($this->table($resource))->where('company_id', $company);
        if ($resource === 'bays') $builder->whereNull('deleted_at');
        return $builder;
    }

    private function row(string $resource, int $company, int $id): object
    {
        return $this->scoped($resource, $company)->where('id', $id)->first()
            ?? abort(404, 'Registro no encontrado.');
    }

    private function activeBranch(int $company, int $branchId): void
    {
        if (!DB::table('branches')->where('company_id', $company)->where('id', $branchId)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['branch_id' => 'Sucursal inexistente o inactiva.']);
        }
    }

    private function validBay(int $company, int $branch, ?int $bayId): void
    {
        if ($bayId !== null && !$this->scoped('bays', $company)->where('id', $bayId)
            ->where('branch_id', $branch)->where('is_active', true)->exists()) {
            throw ValidationException::withMessages(['bay_id' => 'El puesto no pertenece a la sucursal o está inactivo.']);
        }
    }

    private function validateReferences(int $company, int $vehicle, int $service): array
    {
        $v = DB::table('vehicles as v')->join('clients as c', function ($join): void {
            $join->on('c.id', '=', 'v.client_id')->on('c.company_id', '=', 'v.company_id');
        })->where('v.company_id', $company)->where('v.id', $vehicle)
            ->whereNull('v.deleted_at')->where('v.is_active', true)
            ->whereNull('c.deleted_at')->where('c.is_active', true)->exists();
        if (!$v) throw ValidationException::withMessages(['vehicle_id' => 'Selecciona un vehículo y cliente activos de esta empresa.']);
        $s = DB::table('wash_services')->where('company_id', $company)->where('id', $service)
            ->whereNull('deleted_at')->where('is_active', true)->first();
        if (!$s) throw ValidationException::withMessages(['service_id' => 'Selecciona un servicio activo de esta empresa.']);
        return ['price' => $s->price, 'duration' => $s->duration_minutes];
    }

    private function event(int $company, int $orderId, ?string $from, string $to, ?string $reason, int $actor): void
    {
        DB::table('wash_order_events')->insert([
            'company_id' => $company, 'order_id' => $orderId,
            'from_status' => $from, 'to_status' => $to,
            'reason' => $reason, 'actor_user_id' => $actor, 'occurred_at' => now(),
        ]);
    }

    private function decorated(string $resource, int $company, object $row): array
    {
        $data = (array) $row;
        if ($resource === 'orders') {
            $vehicle = DB::table('vehicles')->where('company_id', $company)->where('id', $row->vehicle_id)->first();
            $service = DB::table('wash_services')->where('company_id', $company)->where('id', $row->service_id)->first();
            $data['vehicle_label'] = $vehicle ? trim(implode(' ', array_filter([$vehicle->brand, $vehicle->model, $vehicle->plate]))) : '';
            $data['service_name'] = $service?->name;
            $data['assignments'] = DB::table('wash_assignments as a')
                ->join('employees as e', 'e.id', '=', 'a.employee_id')
                ->where('a.company_id', $company)->where('a.order_id', $row->id)->where('a.is_active', true)
                ->select('a.id', 'a.employee_id', 'a.function', 'a.is_primary', 'e.full_name')->get()
                ->map(function ($a) use ($company): array {
                    $item = (array) $a;
                    $item['employee_photo_enabled'] = DB::table('company_entity_photos')
                        ->where('company_id', $company)->where('owner_type', 'employees')
                        ->where('owner_id', $a->employee_id)->where('show_on_kiosk', true)->exists();
                    return $item;
                })->toArray();
            $data['vehicle_photo_enabled'] = DB::table('company_entity_photos')->where('company_id', $company)
                ->where('owner_type', 'vehicles')->where('owner_id', $row->vehicle_id)
                ->where('show_on_kiosk', true)->exists();
        }
        if ($resource === 'assignments') {
            $data['employee_name'] = DB::table('employees')->where('company_id', $company)->where('id', $row->employee_id)->value('full_name');
        }
        return $data;
    }

    public function branches(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $branches = DB::table('branches')->where('company_id', $company)->where('is_active', true)
            ->select('id', 'name', 'timezone')->orderBy('name')->get();
        return response()->json(['data' => $branches]);
    }

    public function index(Request $request, int $company, string $resource): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $this->table($resource);
        $input = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:120'],
            'branch_id' => ['sometimes', 'integer', 'min:1'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'between:1,50'],
        ]);
        $query = $this->scoped($resource, $company);
        if ($resource === 'assignments' && isset($input['branch_id'])) {
            $orderIds = DB::table('wash_orders')->where('company_id', $company)->where('branch_id', $input['branch_id'])->select('id');
            $query->whereIn('order_id', $orderIds);
        } elseif (isset($input['branch_id'])) $query->where('branch_id', $input['branch_id']);
        $q = trim((string) ($input['q'] ?? ''));
        if ($q !== '') {
            if ($resource === 'bays') $query->where(fn ($b) => $b->where('name', 'like', '%'.$q.'%')->orWhere('code', 'like', '%'.$q.'%'));
            elseif ($resource === 'orders') $query->where('tracking_code', 'like', '%'.$q.'%');
            else $query->where('function', 'like', '%'.$q.'%');
        }
        $page = $query->orderByDesc('id')->paginate($input['per_page'] ?? 10)->toArray();
        $page['data'] = array_map(fn ($item) => $this->decorated($resource, $company, (object) $item), $page['data']);
        return response()->json($page);
    }

    public function show(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        return response()->json(['data' => $this->decorated($resource, $company, $this->row($resource, $company, $record))]);
    }

    public function store(Request $request, int $company, string $resource): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->table($resource);
        $data = match ($resource) {
            'bays' => $request->validate([
                'branch_id' => ['required', 'integer', 'min:1'],
                'name' => ['required', 'string', 'max:120'],
                'code' => ['required', 'string', 'max:40'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
                'is_active' => ['sometimes', 'boolean'],
            ]),
            'orders' => $request->validate([
                'branch_id' => ['required', 'integer', 'min:1'],
                'vehicle_id' => ['required', 'integer', 'min:1'],
                'service_id' => ['required', 'integer', 'min:1'],
                'bay_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
            ]),
            'assignments' => $request->validate([
                'order_id' => ['required', 'integer', 'min:1'],
                'employee_id' => ['required', 'integer', 'min:1'],
                'function' => ['sometimes', 'string', 'max:80'],
                'is_primary' => ['sometimes', 'boolean'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
            ]),
        };
        $result = DB::transaction(function () use ($request, $company, $resource, $data): array {
            if ($resource === 'bays') {
                $this->activeBranch($company, (int) $data['branch_id']);
                $duplicate = $this->scoped('bays', $company)->where('branch_id', $data['branch_id'])->where('code', $data['code'])->exists();
                if ($duplicate) throw ValidationException::withMessages(['code' => 'El código de puesto ya existe en esta sucursal.']);
            }
            if ($resource === 'orders') {
                $this->activeBranch($company, (int) $data['branch_id']);
                // Bloquear el vehiculo para impedir dos ordenes activas simultaneas.
                DB::table('vehicles')->where('company_id', $company)->where('id', $data['vehicle_id'])->lockForUpdate()->first();
                if ($this->scoped('orders', $company)->where('vehicle_id', $data['vehicle_id'])
                    ->whereIn('status', ['EN_ESPERA', 'ASIGNADO', 'EN_PROCESO', 'TERMINADO'])->exists()) {
                    throw ValidationException::withMessages(['vehicle_id' => 'Este vehículo ya tiene una orden sin entregar o cancelar.']);
                }
                $snapshot = $this->validateReferences($company, (int) $data['vehicle_id'], (int) $data['service_id']);
                $this->validBay($company, (int) $data['branch_id'], isset($data['bay_id']) ? (int) $data['bay_id'] : null);
                $data['quoted_price'] = $snapshot['price'];
                $data['estimated_minutes'] = $snapshot['duration'];
                $data['public_id'] = (string) Str::uuid();
                $data['tracking_code'] = 'MCW-'.strtoupper(bin2hex(random_bytes(10)));
                $data['status'] = 'EN_ESPERA';
            }
            if ($resource === 'assignments') {
                $order = $this->scoped('orders', $company)->where('id', $data['order_id'])->lockForUpdate()->first();
                if (!$order || !in_array($order->status, ['EN_ESPERA', 'ASIGNADO', 'EN_PROCESO'], true)) {
                    throw ValidationException::withMessages(['order_id' => 'La orden no admite asignaciones.']);
                }
                $employee = DB::table('employees')->where('company_id', $company)->where('id', $data['employee_id'])
                    ->whereNull('deleted_at')->where('is_active', true)->whereIn('position', ['washer', 'supervisor'])->exists();
                if (!$employee) throw ValidationException::withMessages(['employee_id' => 'Selecciona un lavador o supervisor activo de esta empresa.']);
                // Una asignacion reserva un turno en la cola personal del lavador.
                // No exige que el trabajador este libre: solo EN_PROCESO ocupa su capacidad.
                // El estado de la orden continua ASIGNADO hasta que pueda comenzar.
                DB::table('employees')->where('company_id', $company)
                    ->where('id', $data['employee_id'])->lockForUpdate()->first();
                if ($order->status === 'EN_PROCESO' && $this->workerIsBusy(
                    $company, (int) $data['employee_id'], (int) $data['order_id']
                )) {
                    throw ValidationException::withMessages([
                        'employee_id' => 'El lavador ya esta atendiendo otra orden; puedes asignarlo a una orden en espera.',
                    ]);
                }
                if ($this->scoped('assignments', $company)->where('order_id', $data['order_id'])
                    ->where('employee_id', $data['employee_id'])->where('is_active', true)->exists()) {
                    throw ValidationException::withMessages(['employee_id' => 'Este lavador ya participa en la orden.']);
                }
                if (!empty($data['is_primary'])) {
                    $this->scoped('assignments', $company)->where('order_id', $data['order_id'])->where('is_active', true)
                        ->update(['is_primary' => false, 'updated_at' => now()]);
                }
                $data['assigned_at'] = now();
                if ($order->status === 'EN_ESPERA') {
                    $this->scoped('orders', $company)->where('id', $order->id)
                        ->update(['status' => 'ASIGNADO', 'version' => $order->version + 1, 'updated_at' => now()]);
                    $this->event($company, (int) $order->id, 'EN_ESPERA', 'ASIGNADO', 'Lavador asignado', (int) $request->user()->id);
                }
            }
            $data['company_id'] = $company;
            $data['created_at'] = now();
            $data['updated_at'] = now();
            $id = DB::table($this->table($resource))->insertGetId($data);
            if ($resource === 'orders') $this->event($company, $id, null, 'EN_ESPERA', null, (int) $request->user()->id);
            return $this->decorated($resource, $company, $this->row($resource, $company, $id));
        });
        return response()->json(['message' => 'Registro creado.', 'data' => $result], 201);
    }

    public function update(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->row($resource, $company, $record);
        $data = match ($resource) {
            'bays' => $request->validate([
                'name' => ['sometimes', 'required', 'string', 'max:120'],
                'code' => ['sometimes', 'required', 'string', 'max:40'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
                'is_active' => ['sometimes', 'boolean'],
            ]),
            'orders' => $request->validate([
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
                'bay_id' => ['sometimes', 'nullable', 'integer', 'min:1'],
            ]),
            'assignments' => $request->validate([
                'function' => ['sometimes', 'required', 'string', 'max:80'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:2000'],
                'is_primary' => ['sometimes', 'boolean'],
            ]),
        };
        if (!$data) throw ValidationException::withMessages(['data' => 'Indica al menos un campo válido.']);
        $result = DB::transaction(function () use ($company, $resource, $record, $data): array {
            $current = $this->scoped($resource, $company)->where('id', $record)->lockForUpdate()->first();
            if (!$current) abort(404);
            if ($resource === 'bays') {
                if (($data['is_active'] ?? true) === false &&
                    \Illuminate\Support\Facades\Schema::hasTable('wash_bookings') &&
                    DB::table('wash_bookings')->where('company_id', $company)->where('bay_id', $record)
                        ->whereNull('deleted_at')->where('status', 'CONFIRMED')->exists()) {
                    return ['conflict' => 'Puesto con reservas confirmadas; cancélalas primero.'];
                }
                if (isset($data['code']) && $this->scoped('bays', $company)->where('branch_id', $current->branch_id)
                    ->where('code', $data['code'])->where('id', '!=', $record)->exists()) {
                    throw ValidationException::withMessages(['code' => 'Código duplicado.']);
                }
                if (($data['is_active'] ?? true) === false && DB::table('wash_orders')->where('company_id', $company)
                    ->where('bay_id', $record)->whereIn('status', ['EN_ESPERA', 'ASIGNADO', 'EN_PROCESO'])->exists()) {
                    return ['conflict' => 'Este puesto tiene órdenes activas.'];
                }
            }
            if ($resource === 'orders') {
                if (!in_array($current->status, ['EN_ESPERA', 'ASIGNADO'], true)) {
                    return ['conflict' => 'Solo pueden editarse órdenes aún no iniciadas.'];
                }
                if (array_key_exists('bay_id', $data)) $this->validBay($company, (int) $current->branch_id, isset($data['bay_id']) ? (int) $data['bay_id'] : null);
            }
            if ($resource === 'assignments') {
                if (!$current->is_active) return ['conflict' => 'Asignación ya liberada.'];
                if (!empty($data['is_primary'])) {
                    $this->scoped('assignments', $company)->where('order_id', $current->order_id)->where('id', '!=', $record)
                        ->where('is_active', true)->update(['is_primary' => false, 'updated_at' => now()]);
                }
            }
            $data['updated_at'] = now();
            $this->scoped($resource, $company)->where('id', $record)->update($data);
            return $this->decorated($resource, $company, $this->row($resource, $company, $record));
        });
        if (isset($result['conflict'])) return response()->json(['message' => $result['conflict']], 409);
        return response()->json(['message' => 'Registro actualizado.', 'data' => $result]);
    }

    public function destroy(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->row($resource, $company, $record);
        $reason = $request->validate(['reason' => ['sometimes', 'nullable', 'string', 'max:255']])['reason'] ?? null;
        $result = DB::transaction(function () use ($request, $company, $resource, $record, $reason): ?string {
            $current = $this->scoped($resource, $company)->where('id', $record)->lockForUpdate()->first();
            if (!$current) abort(404);
            if ($resource === 'bays') {
                if (\Illuminate\Support\Facades\Schema::hasTable('wash_bookings') &&
                    DB::table('wash_bookings')->where('company_id', $company)->where('bay_id', $record)
                        ->whereNull('deleted_at')->where('status', 'CONFIRMED')->exists()) {
                    return 'El puesto tiene reservas confirmadas; cancélalas primero.';
                }
                if (DB::table('wash_orders')->where('company_id', $company)->where('bay_id', $record)
                    ->whereIn('status', ['EN_ESPERA', 'ASIGNADO', 'EN_PROCESO'])->exists()) return 'No puedes archivar un puesto con órdenes activas.';
                $this->scoped('bays', $company)->where('id', $record)->update(['deleted_at' => now(), 'updated_at' => now()]);
            } elseif ($resource === 'orders') {
                if (!in_array($current->status, ['EN_ESPERA', 'ASIGNADO'], true)) return 'No puede cancelarse una orden que ya inició; requiere una incidencia autorizada.';
                $this->scoped('orders', $company)->where('id', $record)->update([
                    'status' => 'CANCELADO', 'version' => $current->version + 1, 'updated_at' => now(),
                ]);
                $this->scoped('assignments', $company)->where('order_id', $record)->where('is_active', true)
                    ->update(['is_active' => false, 'released_at' => now(), 'updated_at' => now()]);
                $this->event($company, $record, $current->status, 'CANCELADO', $reason, (int) $request->user()->id);
            } else {
                if (!$current->is_active) return 'La asignación ya fue liberada.';
                $this->scoped('assignments', $company)->where('id', $record)->update([
                    'is_active' => false, 'released_at' => now(), 'updated_at' => now(),
                ]);
                $remaining = $this->scoped('assignments', $company)->where('order_id', $current->order_id)->where('is_active', true)->exists();
                $order = $this->scoped('orders', $company)->where('id', $current->order_id)->lockForUpdate()->first();
                if (!$remaining && $order && $order->status === 'ASIGNADO') {
                    $this->scoped('orders', $company)->where('id', $order->id)->update([
                        'status' => 'EN_ESPERA', 'version' => $order->version + 1, 'updated_at' => now(),
                    ]);
                    $this->event($company, (int) $order->id, 'ASIGNADO', 'EN_ESPERA', 'Sin lavadores activos', (int) $request->user()->id);
                }
            }
            return null;
        });
        if ($result) return response()->json(['message' => $result], 409);
        return response()->json(['message' => match ($resource) { 'bays' => 'Puesto archivado.', 'orders' => 'Orden cancelada.', default => 'Asignación liberada.' }]);
    }

    /** Trabajos simultaneos: a lo sumo uno EN_PROCESO por lavador. */
    private function workerIsBusy(int $company, int $employeeId, int $exceptOrder = 0): bool
    {
        return DB::table('wash_assignments as a')
            ->join('wash_orders as o', function ($join): void {
                $join->on('o.id', '=', 'a.order_id')->on('o.company_id', '=', 'a.company_id');
            })
            ->where('a.company_id', $company)->where('a.employee_id', $employeeId)
            ->where('a.is_active', true)->where('o.id', '!=', $exceptOrder)
            ->where('o.status', 'EN_PROCESO')->exists();
    }

    private function orderWorkers(int $company, int $orderId): array
    {
        return DB::table('wash_assignments')->where('company_id', $company)
            ->where('order_id', $orderId)->where('is_active', true)
            ->distinct()->orderBy('employee_id')->pluck('employee_id')
            ->map(fn ($id): int => (int) $id)->all();
    }

    /** FIFO por instante de asignacion (desempate por ID), sin mezclar empresas. */
    private function firstQueuedForWorker(int $company, int $employeeId): ?int
    {
        $id = DB::table('wash_assignments as a')
            ->join('wash_orders as o', function ($join): void {
                $join->on('o.id', '=', 'a.order_id')->on('o.company_id', '=', 'a.company_id');
            })
            ->where('a.company_id', $company)->where('a.employee_id', $employeeId)
            ->where('a.is_active', true)->where('o.status', 'ASIGNADO')
            ->orderBy('a.assigned_at')->orderBy('a.id')->value('o.id');
        return $id === null ? null : (int) $id;
    }

    /** Una orden compartida inicia solo si TODOS sus lavadores estan libres y les toca el turno. */
    private function canStartQueued(int $company, object $order): bool
    {
        if ($order->status !== 'ASIGNADO') return false;
        $workers = $this->orderWorkers($company, (int) $order->id);
        if (!$workers) return false;
        foreach ($workers as $worker) {
            if ($this->workerIsBusy($company, $worker, (int) $order->id)) return false;
            if ($this->firstQueuedForWorker($company, $worker) !== (int) $order->id) return false;
        }
        if ($order->bay_id !== null) {
            $occupied = DB::table('wash_orders')->where('company_id', $company)
                ->where('branch_id', $order->branch_id)->where('bay_id', $order->bay_id)
                ->where('status', 'EN_PROCESO')->where('id', '!=', $order->id)->exists();
            if ($occupied) return false;
        }
        return true;
    }

    /** Al terminar un lavado, activa el siguiente turno elegible de cada participante. */
    private function advanceWorkerQueues(int $company, array $workers, int $actor): void
    {
        $candidateIds = [];
        foreach ($workers as $worker) {
            $candidate = $this->firstQueuedForWorker($company, (int) $worker);
            if ($candidate !== null) $candidateIds[$candidate] = $candidate;
        }
        // Orden estable, independiente de cual trabajador se evalua primero.
        sort($candidateIds, SORT_NUMERIC);
        foreach ($candidateIds as $candidateId) {
            $order = $this->scoped('orders', $company)->where('id', $candidateId)
                ->lockForUpdate()->first();
            if (!$order || !$this->canStartQueued($company, $order)) continue;
            $this->scoped('orders', $company)->where('id', $candidateId)->update([
                'status' => 'EN_PROCESO', 'started_at' => now(),
                'version' => $order->version + 1, 'updated_at' => now(),
            ]);
            $this->event($company, $candidateId, 'ASIGNADO', 'EN_PROCESO',
                'Inicio automatico por turno del lavador', $actor);
        }
    }

    public function transition(Request $request, int $company, int $order): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $input = $request->validate([
            'to_status' => ['required', Rule::in(['EN_PROCESO', 'TERMINADO', 'ENTREGADO'])],
            'expected_version' => ['required', 'integer', 'min:1'],
            'reason' => ['sometimes', 'nullable', 'string', 'max:255'],
        ]);
        $result = DB::transaction(function () use ($request, $company, $order, $input): array {
            $current = $this->scoped('orders', $company)->where('id', $order)->lockForUpdate()->first();
            if (!$current) abort(404);
            if ((int) $current->version !== (int) $input['expected_version']) return ['conflict' => 'La orden fue modificada por otra sesión. Actualiza antes de continuar.'];
            $next = $input['to_status'];
            $allowed = ['ASIGNADO' => 'EN_PROCESO', 'EN_PROCESO' => 'TERMINADO', 'TERMINADO' => 'ENTREGADO'];
            if (($allowed[$current->status] ?? '') !== $next) return ['conflict' => 'Transición de estado no permitida.'];
            if ($next === 'ENTREGADO') {
                throw ValidationException::withMessages([
                    'payment' => 'Utiliza Cobrar y entregar para registrar el cobro en caja o banco.',
                ]);
            }
            $workers = $this->orderWorkers($company, $order);
            if ($next === 'EN_PROCESO') {
                if (!$workers) return ['conflict' => 'Asigna al menos un lavador activo.'];
                // Bloquear en orden para reducir carreras entre sesiones.
                DB::table('employees')->where('company_id', $company)
                    ->whereIn('id', $workers)->orderBy('id')->lockForUpdate()->get();
                if (!$this->canStartQueued($company, $current)) {
                    return ['conflict' => 'La orden sigue en cola: algun lavador esta ocupado, tiene un turno anterior o la bahia esta ocupada.'];
                }
            }
            if ($next === 'TERMINADO' && $workers) {
                DB::table('employees')->where('company_id', $company)
                    ->whereIn('id', $workers)->orderBy('id')->lockForUpdate()->get();
            }
            $changes = ['status' => $next, 'version' => $current->version + 1, 'updated_at' => now()];
            if ($next === 'EN_PROCESO') $changes['started_at'] = now();
            if ($next === 'TERMINADO') $changes['completed_at'] = now();
            if ($next === 'ENTREGADO') $changes['delivered_at'] = now();
            $this->scoped('orders', $company)->where('id', $order)->update($changes);
            $this->event($company, $order, $current->status, $next, $input['reason'] ?? null, (int) $request->user()->id);
            if ($next === 'TERMINADO') {
                $this->advanceWorkerQueues($company, $workers, (int) $request->user()->id);
            }
            return ['data' => $this->decorated('orders', $company, $this->row('orders', $company, $order))];
        });
        if (isset($result['conflict'])) return response()->json(['message' => $result['conflict']], 409);
        return response()->json($result);
    }

    public function history(Request $request, int $company, int $order): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $this->row('orders', $company, $order);
        return response()->json(['data' => DB::table('wash_order_events')->where('company_id', $company)
            ->where('order_id', $order)->orderBy('id')->get()]);
    }

    public function queue(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $input = $request->validate(['branch_id' => ['required', 'integer', 'min:1']]);
        $this->activeBranch($company, (int) $input['branch_id']);
        $rows = $this->scoped('orders', $company)->where('branch_id', $input['branch_id'])
            ->whereIn('status', ['EN_ESPERA', 'ASIGNADO', 'EN_PROCESO'])
            ->orderBy('created_at')->limit(50)->get()->map(fn ($r) => $this->decorated('orders', $company, $r));
        return response()->json(['data' => $rows, 'generated_at' => now()->toISOString()]);
    }
}
