<?php
namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use RuntimeException;

/** Catalogo de permisos operativos (separado de los nav.* de empleados). */
final class OwnerOperationalPermissionsH049
{
    public const CODES = ['company.branding.manage', 'company.contacts.manage', 'company.fiscal.manage', 'company.hours.manage', 'company.update', 'company.view', 'roles.manage', 'users.manage', 'users.view'];

    /** Debe llamarse dentro de la transaccion que crea la empresa. */
    public static function syncForOwner(int $company, int $roleId): void
    {
        $role = DB::table('roles')->where('id', $roleId)
            ->where('company_id', $company)->where('code', 'owner')
            ->where('is_system', true)->first();
        if (!$role) { throw new RuntimeException('Rol owner del sistema no valido.'); }
        foreach (self::CODES as $code) {
            $module = explode('.', $code, 2)[0];
            $existing = DB::table('permissions')->where('code', $code)->first();
            if ($existing) {
                if ($existing->module !== $module) { throw new RuntimeException('Modulo de permiso incompatible: '.$code); }
                $id = (int) $existing->id;
            } else {
                $id = DB::table('permissions')->insertGetId([
                    'code' => $code, 'module' => $module,
                    'description' => 'Permiso operativo '.$code,
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
            if (!DB::table('role_permission')->where('role_id', $roleId)->where('permission_id', $id)->exists()) {
                DB::table('role_permission')->insert([
                    'role_id' => $roleId, 'permission_id' => $id,
                    'created_at' => now(), 'updated_at' => now(),
                ]);
            }
        }
    }
}