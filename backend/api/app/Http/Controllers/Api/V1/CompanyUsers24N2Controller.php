<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Illuminate\Validation\Rule;

/** CRUD empresarial; nunca administra usuarios de otras empresas. */
class CompanyUsers24N2Controller extends Controller
{
    private function authorizeCompany(Request $request, int $company, string $permission): void
    {
        $member = DB::table('company_user')->join('companies', 'companies.id', '=', 'company_user.company_id')
            ->where('company_user.company_id', $company)->where('company_user.user_id', $request->user()->id)
            ->where('company_user.status', 'active')->where('companies.is_active', true)->exists();
        abort_unless($member, 404, 'Empresa no disponible.');
        $allowed = DB::table('user_roles as ur')
            ->join('roles as r', function ($join): void {
                $join->on('r.id', '=', 'ur.role_id')->on('r.company_id', '=', 'ur.company_id');
            })->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $request->user()->id)
            ->where('p.code', $permission)->exists();
        abort_unless($allowed, 403, 'No tienes permiso para administrar este apartado.');
    }

    private function role(int $company, int $roleId): object
    {
        $role = DB::table('roles')->where('company_id', $company)->where('id', $roleId)->first();
        abort_if($role === null, 422, 'Rol no válido para esta empresa.');
        abort_if((bool) $role->is_system, 422, 'Los roles del sistema no se pueden asignar ni modificar desde aquí.');
        return $role;
    }

    private function rows(int $company): array
    {
        return DB::table('company_user as cu')->join('users as u', 'u.id', '=', 'cu.user_id')
            ->leftJoin('employee_user as eu', function ($join): void {
                $join->on('eu.user_id', '=', 'cu.user_id')->on('eu.company_id', '=', 'cu.company_id');
            })->leftJoin('employees as e', function ($join): void {
                $join->on('e.id', '=', 'eu.employee_id')->on('e.company_id', '=', 'cu.company_id');
            })->where('cu.company_id', $company)
            ->select('u.id', 'u.name', 'u.email', 'cu.status', 'e.id as employee_id', 'e.full_name as employee_name')
            ->orderBy('u.name')->get()->map(function ($user) use ($company) {
                $user->role_ids = DB::table('user_roles')->where('company_id', $company)
                    ->where('user_id', $user->id)->pluck('role_id')->toArray();
                return $user;
            })->toArray();
    }

    public function index(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'users.view');
        $roles = DB::table('roles')->where('company_id', $company)->orderBy('name')->get();
        $permissionRows = DB::table('permissions')->where('code', 'like', 'nav.%')
            ->orderBy('code')->get(['id', 'code', 'description']);
        $rolePermissions = DB::table('role_permission as rp')
            ->join('roles as r', 'r.id', '=', 'rp.role_id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('r.company_id', $company)->where('p.code', 'like', 'nav.%')
            ->get(['rp.role_id', 'p.code'])->groupBy('role_id');
        $available = DB::table('employees as e')->leftJoin('employee_user as eu', function ($join): void {
            $join->on('eu.employee_id', '=', 'e.id')->on('eu.company_id', '=', 'e.company_id');
        })->where('e.company_id', $company)->whereNull('e.deleted_at')
            ->where('e.is_active', true)->whereNull('eu.user_id')
            ->orderBy('e.full_name')->get(['e.id', 'e.full_name', 'e.email']);
        return response()->json([
            'users' => $this->rows($company),
            'roles' => $roles->map(function ($r) use ($rolePermissions) {
                $r->permissions = ($rolePermissions->get($r->id) ?? collect())->pluck('code')->values();
                return $r;
            }),
            'permissions' => $permissionRows,
            'available_employees' => $available,
            'can_manage_users' => $this->hasPermission($request, $company, 'users.manage'),
            'can_manage_roles' => $this->hasPermission($request, $company, 'roles.manage'),
        ]);
    }

    private function hasPermission(Request $request, int $company, string $permission): bool
    {
        return DB::table('user_roles as ur')->join('role_permission as rp', 'rp.role_id', '=', 'ur.role_id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $request->user()->id)
            ->where('p.code', $permission)->exists();
    }

    public function store(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'users.manage');
        $data = $request->validate([
            'employee_id' => ['required', 'integer'],
            'email' => ['required', 'email', 'max:255', Rule::unique('users', 'email')],
            'password' => ['required', 'string', 'min:10', 'max:128'],
            'role_id' => ['required', 'integer'],
        ]);
        $this->role($company, (int) $data['role_id']);
        $employee = DB::table('employees')->where('company_id', $company)
            ->where('id', $data['employee_id'])->where('is_active', true)->whereNull('deleted_at')->first();
        abort_if($employee === null, 422, 'El empleado no pertenece a esta empresa o está inactivo.');
        $created = DB::transaction(function () use ($company, $data, $employee): User {
            abort_if(DB::table('employee_user')->where('company_id', $company)
                ->where('employee_id', $employee->id)->lockForUpdate()->exists(), 422, 'Este empleado ya tiene una cuenta.');
            $user = User::query()->create([
                'name' => $employee->full_name,
                'email' => mb_strtolower($data['email']),
                'password' => Hash::make($data['password']),
            ]);
            $now = now();
            DB::table('company_user')->insert([
                'company_id' => $company, 'user_id' => $user->id, 'status' => 'active',
                'access_all_branches' => false, 'created_at' => $now, 'updated_at' => $now,
            ]);
            DB::table('employee_user')->insert([
                'company_id' => $company, 'employee_id' => $employee->id,
                'user_id' => $user->id, 'created_at' => $now, 'updated_at' => $now,
            ]);
            DB::table('user_roles')->insert([
                'company_id' => $company, 'user_id' => $user->id, 'role_id' => $data['role_id'],
                'created_at' => $now, 'updated_at' => $now,
            ]);
            return $user;
        });
        return response()->json(['message' => 'Cuenta de empleado creada.', 'user_id' => $created->id], 201);
    }

    public function update(Request $request, int $company, int $user): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'users.manage');
        $data = $request->validate([
            'role_id' => ['sometimes', 'integer'],
            'status' => ['sometimes', Rule::in(['active', 'inactive'])],
            'password' => ['sometimes', 'string', 'min:10', 'max:128'],
        ]);
        abort_if($data === [], 422, 'Sin cambios.');
        $membership = DB::table('company_user')->where('company_id', $company)->where('user_id', $user)->first();
        abort_if($membership === null, 404, 'Usuario no pertenece a esta empresa.');
        abort_if($user === (int) $request->user()->id && isset($data['status']) && $data['status'] !== 'active',
            422, 'No puedes desactivar tu propia cuenta.');
        $hasSystemRole = DB::table('user_roles as ur')->join('roles as r', 'r.id', '=', 'ur.role_id')
            ->where('ur.company_id', $company)->where('ur.user_id', $user)->where('r.is_system', true)->exists();
        abort_if($hasSystemRole, 403, 'No puedes modificar una cuenta con rol protegido del sistema.');
        if (isset($data['role_id'])) $this->role($company, (int) $data['role_id']);
        DB::transaction(function () use ($company, $user, $data): void {
            if (isset($data['role_id'])) {
                DB::table('user_roles')->where('company_id', $company)->where('user_id', $user)->delete();
                DB::table('user_roles')->insert([
                    'company_id' => $company, 'user_id' => $user, 'role_id' => $data['role_id'],
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
            if (isset($data['status'])) {
                DB::table('company_user')->where('company_id', $company)->where('user_id', $user)
                    ->update(['status' => $data['status'], 'updated_at' => now()]);
            }
            if (isset($data['password'])) {
                DB::table('users')->where('id', $user)->update([
                    'password' => Hash::make($data['password']), 'updated_at' => now(),
                ]);
            }
            if (isset($data['status']) && $data['status'] === 'inactive' || isset($data['password']) || isset($data['role_id'])) {
                // Invalidar sesiones existentes para que permisos nuevos rijan inmediatamente.
                DB::table('personal_access_tokens')->where('tokenable_type', User::class)
                    ->where('tokenable_id', $user)->delete();
            }
        });
        return response()->json(['message' => 'Acceso actualizado.']);
    }

    public function storeRole(Request $request, int $company): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'roles.manage');
        $data = $request->validate([
            'name' => ['required', 'string', 'min:3', 'max:100'],
            'permissions' => ['required', 'array', 'min:1'],
            'permissions.*' => ['string', 'regex:/^nav\.[a-z_]+\.(view|create|edit|execute)$/'],
        ]);
        $codes = array_values(array_unique($data['permissions']));
        $this->validatePermissions($codes);
        abort_unless(count(array_filter($codes, fn ($code) => str_ends_with($code, '.view'))) > 0, 422, 'El rol necesita al menos un permiso Ver.');
        $id = DB::transaction(function () use ($company, $data, $codes): int {
            $id = DB::table('roles')->insertGetId([
                'company_id' => $company, 'name' => $data['name'],
                'code' => 'custom_'.Str::lower(Str::random(12)),
                'is_system' => false, 'created_at' => now(), 'updated_at' => now(),
            ]);
            $this->assignPermissions($id, $codes);
            return $id;
        });
        return response()->json(['message' => 'Rol creado.', 'role_id' => $id], 201);
    }

    public function updateRole(Request $request, int $company, int $role): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'roles.manage');
        $this->role($company, $role);
        $data = $request->validate([
            'name' => ['required', 'string', 'min:3', 'max:100'],
            'permissions' => ['required', 'array', 'min:1'],
            'permissions.*' => ['string', 'regex:/^nav\.[a-z_]+\.(view|create|edit|execute)$/'],
        ]);
        $codes = array_values(array_unique($data['permissions']));
        $this->validatePermissions($codes);
        abort_unless(count(array_filter($codes, fn ($code) => str_ends_with($code, '.view'))) > 0, 422, 'El rol necesita al menos un permiso Ver.');
        DB::transaction(function () use ($role, $data, $codes, $company): void {
            DB::table('roles')->where('company_id', $company)->where('id', $role)
                ->update(['name' => $data['name'], 'updated_at' => now()]);
            DB::table('role_permission')->where('role_id', $role)->delete();
            $this->assignPermissions($role, $codes);
            $users = DB::table('user_roles')->where('company_id', $company)->where('role_id', $role)->pluck('user_id');
            DB::table('personal_access_tokens')->where('tokenable_type', User::class)
                ->whereIn('tokenable_id', $users)->delete();
        });
        return response()->json(['message' => 'Permisos actualizados y sesiones anteriores invalidadas.']);
    }

    public function deleteRole(Request $request, int $company, int $role): JsonResponse
    {
        $this->authorizeCompany($request, $company, 'roles.manage');
        $this->role($company, $role);
        abort_if(DB::table('user_roles')->where('company_id', $company)->where('role_id', $role)->exists(),
            422, 'Asigna otro rol a los usuarios antes de eliminarlo.');
        DB::transaction(function () use ($company, $role): void {
            DB::table('role_permission')->where('role_id', $role)->delete();
            DB::table('roles')->where('company_id', $company)->where('id', $role)->delete();
        });
        return response()->json(['message' => 'Rol eliminado.']);
    }

    private function validatePermissions(array $codes): void
    {
        $count = DB::table('permissions')->whereIn('code', $codes)->where('code', 'like', 'nav.%')->count();
        abort_unless($count === count($codes), 422, 'La lista contiene permisos desconocidos.');
    }

    private function assignPermissions(int $roleId, array $codes): void
    {
        // La API histórica usa permisos amplios. El middleware 24N.2 aplica el
        // alcance efectivo de nav.* adicionalmente, también sobre endpoints antiguos.
        $legacy = DB::table('permissions')->whereNot('code', 'like', 'nav.%')->pluck('id')->toArray();
        $scoped = DB::table('permissions')->whereIn('code', $codes)->pluck('id')->toArray();
        foreach (array_unique(array_merge($legacy, $scoped)) as $id) {
            DB::table('role_permission')->insert([
                'role_id' => $roleId, 'permission_id' => $id,
                'created_at' => now(), 'updated_at' => now(),
            ]);
        }
    }
}
