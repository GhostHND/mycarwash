<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Validation\Rule;
use Illuminate\Validation\ValidationException;

/**
 * Catalogos operativos de la empresa: clientes, vehiculos, empleados y lavados.
 * IDs, company_id y deleted_at nunca son aceptados desde el cliente.
 */
class CompanyOperationsController extends Controller
{
    private const RESOURCES = [
        'clients' => [
            'table' => 'clients',
            'search' => ['full_name', 'identity_document', 'phone', 'email'],
            'fields' => ['full_name', 'identity_document', 'phone', 'email', 'address', 'notes', 'is_active'],
        ],
        'vehicles' => [
            'table' => 'vehicles',
            'search' => ['plate', 'brand', 'model', 'color', 'vehicle_type'],
            'fields' => ['client_id', 'plate', 'brand', 'model', 'color', 'year', 'vehicle_type', 'notes', 'is_active'],
        ],
        'employees' => [
            'table' => 'employees',
            'search' => ['full_name', 'identity_document', 'phone', 'email', 'position'],
            'fields' => ['full_name', 'identity_document', 'phone', 'email', 'position', 'hire_date', 'commission_percent', 'notes', 'is_active'],
        ],
        'services' => [
            'table' => 'wash_services',
            'search' => ['name', 'description'],
            'fields' => ['name', 'description', 'price', 'duration_minutes', 'is_active'],
        ],
    ];

    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $userId = $request->user()->id;
        $membership = DB::table('company_user')
            ->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)
            ->where('company_user.user_id', $userId)
            ->where('company_user.status', 'active')
            ->where('companies.is_active', true)
            ->exists();
        if (!$membership) {
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
            ->where('ur.user_id', $userId)
            ->where('p.code', $permission)
            ->exists();
        if (!$allowed) {
            abort(403, 'No tienes permiso para esta operación.');
        }
    }

    private function spec(string $resource): array
    {
        if (!array_key_exists($resource, self::RESOURCES)) {
            abort(404, 'Catálogo no disponible.');
        }
        return self::RESOURCES[$resource];
    }

    private function scoped(string $resource, int $company)
    {
        return DB::table($this->spec($resource)['table'])
            ->where('company_id', $company)
            ->whereNull('deleted_at');
    }

    private function row(string $resource, int $company, int $id): object
    {
        $record = $this->scoped($resource, $company)->where('id', $id)->first();
        if (!$record) {
            abort(404, 'Registro no disponible.');
        }
        return $record;
    }

    private function rules(string $resource, int $company, bool $create, ?int $id): array
    {
        $required = $create ? ['required'] : ['sometimes', 'required'];
        $data = match ($resource) {
            'clients' => [
                'full_name' => [...$required, 'string', 'max:180'],
                'identity_document' => ['sometimes', 'nullable', 'string', 'max:50'],
                'phone' => ['sometimes', 'nullable', 'string', 'max:40'],
                'email' => ['sometimes', 'nullable', 'email', 'max:190'],
                'address' => ['sometimes', 'nullable', 'string', 'max:4000'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:4000'],
                'is_active' => ['sometimes', 'boolean'],
            ],
            'vehicles' => [
                'client_id' => [...$required, 'integer', 'min:1'],
                'plate' => ['sometimes', 'nullable', 'string', 'max:30'],
                'brand' => ['sometimes', 'nullable', 'string', 'max:80'],
                'model' => ['sometimes', 'nullable', 'string', 'max:100'],
                'color' => ['sometimes', 'nullable', 'string', 'max:60'],
                'year' => ['sometimes', 'nullable', 'integer', 'between:1900,'.((int) date('Y') + 1)],
                'vehicle_type' => ['sometimes', 'nullable', 'string', 'max:60'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:4000'],
                'is_active' => ['sometimes', 'boolean'],
            ],
            'employees' => [
                'full_name' => [...$required, 'string', 'max:180'],
                'identity_document' => ['sometimes', 'nullable', 'string', 'max:50'],
                'phone' => ['sometimes', 'nullable', 'string', 'max:40'],
                'email' => ['sometimes', 'nullable', 'email', 'max:190'],
                'position' => ['sometimes', Rule::in(['washer', 'supervisor', 'cashier', 'manager', 'other'])],
                'hire_date' => ['sometimes', 'nullable', 'date_format:Y-m-d'],
                'commission_percent' => ['sometimes', 'numeric', 'between:0,100', 'decimal:0,2'],
                'notes' => ['sometimes', 'nullable', 'string', 'max:4000'],
                'is_active' => ['sometimes', 'boolean'],
            ],
            'services' => [
                'name' => [...$required, 'string', 'max:150'],
                'description' => ['sometimes', 'nullable', 'string', 'max:4000'],
                'price' => [...$required, 'numeric', 'between:0,9999999999.99', 'decimal:0,2'],
                'duration_minutes' => [...$required, 'integer', 'between:1,1440'],
                'is_active' => ['sometimes', 'boolean'],
            ],
        };
        return $data;
    }

    private function validateInput(Request $request, string $resource, int $company, bool $create, ?int $id = null): array
    {
        if ($resource === 'vehicles' && $request->has('plate') && is_string($request->input('plate'))) {
            $request->merge(['plate' => strtoupper(trim($request->input('plate')))]);
        }
        $data = $request->validate($this->rules($resource, $company, $create, $id));
        if (!$data) {
            throw ValidationException::withMessages(['data' => 'Proporciona al menos un campo válido.']);
        }
        if ($resource === 'vehicles' && isset($data['client_id'])) {
            $exists = $this->scoped('clients', $company)
                ->where('id', $data['client_id'])
                ->where('is_active', true)
                ->exists();
            if (!$exists) {
                throw ValidationException::withMessages(['client_id' => 'Selecciona un cliente activo de esta empresa.']);
            }
        }
        if ($resource === 'vehicles' && !empty($data['plate'])) {
            $query = $this->scoped('vehicles', $company)->where('plate', $data['plate']);
            if ($id !== null) $query->where('id', '!=', $id);
            if ($query->exists()) {
                throw ValidationException::withMessages(['plate' => 'Esta placa ya está registrada en la empresa.']);
            }
        }
        if ($resource === 'services' && isset($data['name'])) {
            $query = $this->scoped('services', $company)->where('name', $data['name']);
            if ($id !== null) $query->where('id', '!=', $id);
            if ($query->exists()) {
                throw ValidationException::withMessages(['name' => 'Ya existe un servicio con este nombre.']);
            }
        }
        if ($resource === 'clients' && !empty($data['identity_document'])) {
            $query = $this->scoped('clients', $company)->where('identity_document', $data['identity_document']);
            if ($id !== null) $query->where('id', '!=', $id);
            if ($query->exists()) {
                throw ValidationException::withMessages(['identity_document' => 'El documento ya pertenece a un cliente.']);
            }
        }
        return array_intersect_key($data, array_flip($this->spec($resource)['fields']));
    }

    private function decorate(string $resource, int $company, object $record): array
    {
        $result = (array) $record;
        if ($resource === 'vehicles') {
            $result['client_name'] = $this->scoped('clients', $company)
                ->where('id', $record->client_id)->value('full_name');
        }
        if ($resource === 'services' && \Illuminate\Support\Facades\Schema::hasTable('service_vehicle_prices')) {
            $result['vehicle_prices'] = DB::table('service_vehicle_prices')->where('company_id', $company)
                ->where('service_id', $record->id)->orderBy('vehicle_type')
                ->get(['vehicle_type','price'])->toArray();
        }
        return $result;
    }

    public function index(Request $request, int $company, string $resource): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $spec = $this->spec($resource);
        $input = $request->validate([
            'q' => ['sometimes', 'nullable', 'string', 'max:150'],
            'page' => ['sometimes', 'integer', 'min:1'],
            'per_page' => ['sometimes', 'integer', 'between:1,50'],
        ]);
        $query = $this->scoped($resource, $company);
        $q = trim((string) ($input['q'] ?? ''));
        if ($q !== '') {
            $query->where(function ($builder) use ($q, $spec): void {
                foreach ($spec['search'] as $field) {
                    $builder->orWhere($field, 'like', '%'.$q.'%');
                }
            });
        }
        $paginator = $query->orderByDesc('id')->paginate($input['per_page'] ?? 10);
        $response = $paginator->toArray();
        $response['data'] = array_map(
            fn ($item) => $this->decorate($resource, $company, (object) $item),
            $response['data']
        );
        return response()->json($response);
    }

    public function show(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.view');
        $data = $this->row($resource, $company, $record);
        return response()->json(['data' => $this->decorate($resource, $company, $data)]);
    }

    public function store(Request $request, int $company, string $resource): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $data = $this->validateInput($request, $resource, $company, true);
        $data['company_id'] = $company;
        $data['created_at'] = now();
        $data['updated_at'] = now();
        $id = DB::table($this->spec($resource)['table'])->insertGetId($data);
        return response()->json(['message' => 'Registro creado.', 'data' => $this->decorate($resource, $company, $this->row($resource, $company, $id))], 201);
    }

    public function update(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->row($resource, $company, $record);
        $data = $this->validateInput($request, $resource, $company, false, $record);
        if (($data['is_active'] ?? true) === false) {
            if (in_array($resource, ['vehicles', 'services'], true) &&
                \Illuminate\Support\Facades\Schema::hasTable('wash_bookings')) {
                $field = $resource === 'vehicles' ? 'vehicle_id' : 'service_id';
                if (DB::table('wash_bookings')->where('company_id', $company)->where($field, $record)
                    ->whereNull('deleted_at')->where('status', 'CONFIRMED')->exists()) {
                    return response()->json(['message' => 'No se puede desactivar con reservas confirmadas.'], 409);
                }
            }
            if ($resource === 'employees' &&
                \Illuminate\Support\Facades\Schema::hasTable('staff_shift_assignments') &&
                DB::table('staff_shift_assignments')->where('company_id', $company)->where('employee_id', $record)
                    ->whereNull('deleted_at')->where('is_active', true)->exists()) {
                return response()->json(['message' => 'No se puede desactivar un lavador con turnos asignados.'], 409);
            }
        }
        $data['updated_at'] = now();
        $this->scoped($resource, $company)->where('id', $record)->update($data);
        return response()->json(['message' => 'Registro actualizado.', 'data' => $this->decorate($resource, $company, $this->row($resource, $company, $record))]);
    }

    public function destroy(Request $request, int $company, string $resource, int $record): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'company.update');
        $this->row($resource, $company, $record);
        if (in_array($resource, ['vehicles', 'services'], true) &&
            \Illuminate\Support\Facades\Schema::hasTable('wash_bookings')) {
            $field = $resource === 'vehicles' ? 'vehicle_id' : 'service_id';
            if (DB::table('wash_bookings')->where('company_id', $company)->where($field, $record)
                ->whereNull('deleted_at')->where('status', 'CONFIRMED')->exists()) {
                return response()->json(['message' => 'Registro con reservas futuras o confirmadas. Cancélalas primero.'], 409);
            }
        }
        if ($resource === 'employees' &&
            \Illuminate\Support\Facades\Schema::hasTable('staff_shift_assignments') &&
            DB::table('staff_shift_assignments')->where('company_id', $company)
                ->where('employee_id', $record)->whereNull('deleted_at')->where('is_active', true)->exists()) {
            return response()->json(['message' => 'El empleado tiene turnos asignados. Desasígnalo primero.'], 409);
        }
        if ($resource === 'clients' && $this->scoped('vehicles', $company)->where('client_id', $record)->exists()) {
            return response()->json(['message' => 'Este cliente tiene vehículos. Archívalos primero.'], 409);
        }
        if (in_array($resource, ['vehicles', 'services'], true) &&
            \Illuminate\Support\Facades\Schema::hasTable('wash_orders')) {
            $field = $resource === 'vehicles' ? 'vehicle_id' : 'service_id';
            if (DB::table('wash_orders')->where('company_id', $company)
                ->where($field, $record)
                ->whereIn('status', ['EN_ESPERA', 'ASIGNADO', 'EN_PROCESO'])->exists()) {
                return response()->json(['message' => 'Registro utilizado por una orden activa.'], 409);
            }
        }
        if ($resource === 'employees' &&
            \Illuminate\Support\Facades\Schema::hasTable('wash_assignments') &&
            DB::table('wash_assignments')->where('company_id', $company)
                ->where('employee_id', $record)->where('is_active', true)->exists()) {
            return response()->json(['message' => 'Lavador asignado a una orden. Libera primero su asignación.'], 409);
        }
        $this->scoped($resource, $company)->where('id', $record)
            ->update(['deleted_at' => now(), 'updated_at' => now()]);
        return response()->json(['message' => 'Registro archivado.']);
    }
}
