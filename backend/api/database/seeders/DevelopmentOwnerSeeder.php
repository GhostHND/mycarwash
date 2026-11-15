<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use RuntimeException;

class DevelopmentOwnerSeeder extends Seeder
{
    public function run(): void
    {
        if (!app()->environment('local')) {
            throw new RuntimeException(
                'Este seeder solo funciona en desarrollo local.'
            );
        }

        $db = DB::connection('mysql');

        if ($db->getDatabaseName() !== 'mycarwash_core') {
            throw new RuntimeException(
                'La base de datos no es mycarwash_core.'
            );
        }

        $password = getenv('ADN_MYCARWASH_TEST_PASSWORD');

        if (!is_string($password) || $password === '') {
            throw new RuntimeException(
                'Falta la contrasena temporal de desarrollo.'
            );
        }

        $email = 'eduardo@adn.com';
        $slug = 'carwash-pruebas';

        if (
            $db->table('users')->where('email', $email)->exists()
            || $db->table('companies')->where('slug', $slug)->exists()
        ) {
            throw new RuntimeException(
                'El usuario o la empresa de pruebas ya existen. '
                . 'No se modificaran sus datos.'
            );
        }

        $requiredTables = [
            'users',
            'companies',
            'branches',
            'company_user',
            'branch_user',
            'roles',
            'permissions',
            'role_permission',
            'user_roles',
            'user_preferences',
            'company_profiles',
            'company_brandings',
            'company_preferences',
            'personal_access_tokens',
        ];

        foreach ($requiredTables as $table) {
            if (
                !\Illuminate\Support\Facades\Schema::connection('mysql')
                    ->hasTable($table)
            ) {
                throw new RuntimeException(
                    "Falta la tabla {$table}."
                );
            }
        }

        $databases = $db->select(
            "SELECT SCHEMA_NAME AS db_name
             FROM information_schema.SCHEMATA
             WHERE SCHEMA_NAME IN (
                'mycarwash_company_demo',
                'mycarwash_branch_demo'
             )"
        );

        if (count($databases) !== 2) {
            throw new RuntimeException(
                'Faltan bases de datos de desarrollo.'
            );
        }

        $db->transaction(function () use ($db, $email, $slug, $password) {

            $now = now();

            // ======================================
            // USUARIO ADMINISTRADOR
            // ======================================

            $userId = $db->table('users')->insertGetId([
                'name' => 'Eduardo (Pruebas)',
                'email' => $email,
                'password' => Hash::make($password),
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // ======================================
            // EMPRESA DE DESARROLLO
            // ======================================

            $companyId = $db->table('companies')->insertGetId([
                'public_id' => (string) Str::uuid(),
                'name' => 'CarWash de Pruebas',
                'slug' => $slug,
                'database_name' => 'mycarwash_company_demo',
                'master_instance_id' => null,
                'is_active' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // ======================================
            // SUCURSAL DE DESARROLLO
            // ======================================

            $branchId = $db->table('branches')->insertGetId([
                'company_id' => $companyId,
                'name' => 'Sucursal Principal (Pruebas)',
                'slug' => 'principal-pruebas',
                'database_name' => 'mycarwash_branch_demo',
                'timezone' => 'America/Tegucigalpa',
                'is_active' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // ======================================
            // ACCESO A EMPRESA Y SUCURSAL
            // ======================================

            $db->table('company_user')->insert([
                'company_id' => $companyId,
                'user_id' => $userId,
                'status' => 'active',
                'access_all_branches' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            $db->table('branch_user')->insert([
                'company_id' => $companyId,
                'branch_id' => $branchId,
                'user_id' => $userId,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // ======================================
            // ROL PROPIETARIO
            // ======================================

            $roleId = $db->table('roles')->insertGetId([
                'company_id' => $companyId,
                'name' => 'Propietario',
                'code' => 'owner',
                'is_system' => true,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            $db->table('user_roles')->insert([
                'company_id' => $companyId,
                'user_id' => $userId,
                'role_id' => $roleId,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // ======================================
            // CATALOGO INICIAL DE PERMISOS
            // ======================================

            $permissions = [
                ['company.view', 'company', 'Consultar empresa'],
                ['company.update', 'company', 'Modificar empresa'],
                ['company.branding.manage', 'company', 'Administrar identidad visual'],
                ['company.contacts.manage', 'company', 'Administrar contactos'],
                ['company.media.manage', 'company', 'Administrar multimedia'],
                ['company.hours.manage', 'company', 'Administrar horarios'],
                ['company.fiscal.manage', 'company', 'Administrar datos fiscales'],
                ['branches.view', 'branches', 'Consultar sucursales'],
                ['branches.manage', 'branches', 'Administrar sucursales'],
                ['users.view', 'users', 'Consultar usuarios'],
                ['users.manage', 'users', 'Administrar usuarios'],
                ['roles.view', 'roles', 'Consultar roles'],
                ['roles.manage', 'roles', 'Administrar permisos'],
                ['preferences.view', 'preferences', 'Consultar preferencias'],
                ['preferences.update', 'preferences', 'Modificar preferencias'],
            ];

            foreach ($permissions as [$code, $module, $description]) {

                $permissionId = $db->table('permissions')
                    ->where('code', $code)
                    ->value('id');

                if (!$permissionId) {
                    $permissionId = $db->table('permissions')->insertGetId([
                        'code' => $code,
                        'module' => $module,
                        'description' => $description,
                        'created_at' => $now,
                        'updated_at' => $now,
                    ]);
                }

                $db->table('role_permission')->insert([
                    'role_id' => $roleId,
                    'permission_id' => $permissionId,
                    'created_at' => $now,
                    'updated_at' => $now,
                ]);
            }

            // ======================================
            // CONFIGURACION EMPRESARIAL INICIAL
            // ======================================

            $db->table('company_profiles')->insert([
                'company_id' => $companyId,
                'commercial_name' => 'CarWash de Pruebas',
                'business_category' => 'carwash',
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // Los logos del cliente quedan vacios.
            // La identidad ADN es independiente.

            $db->table('company_brandings')->insert([
                'company_id' => $companyId,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            $db->table('company_preferences')->insert([
                'company_id' => $companyId,
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // ======================================
            // PREFERENCIAS DEL ADMINISTRADOR
            // ======================================

            $db->table('user_preferences')->insert([
                'user_id' => $userId,
                'theme_mode' => 'system',
                'locale' => 'es-HN',
                'created_at' => $now,
                'updated_at' => $now,
            ]);

            // Sin registro onboarding_progress:
            // la guia se mostrara en el primer uso.
        });

        $this->command?->info(
            '[OK] Usuario y empresa de pruebas creados.'
        );
    }
}