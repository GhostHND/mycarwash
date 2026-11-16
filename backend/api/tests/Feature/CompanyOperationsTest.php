<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyOperationsTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') ||
            DB::connection()->getDriverName() !== 'sqlite' ||
            DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Solo se permite SQLite :memory: en pruebas.');
        }
        $this->prepareSchema();
        $this->seedOperationalFixtures();
    }

    private function prepareSchema(): void
    {
        foreach ([
            'wash_services', 'employees', 'vehicles', 'clients',
            'user_roles', 'role_permission', 'permissions', 'roles',
            'company_user', 'companies', 'users',
        ] as $table) Schema::dropIfExists($table);

        Schema::create('users', function (Blueprint $t): void {
            $t->id(); $t->string('name'); $t->string('email')->unique();
            $t->string('password'); $t->timestamps();
        });
        Schema::create('companies', function (Blueprint $t): void {
            $t->id(); $t->string('name'); $t->string('slug');
            $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('company_user', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('user_id'); $t->string('status')->default('active');
            $t->timestamps();
        });
        Schema::create('roles', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->string('name'); $t->string('code'); $t->timestamps();
        });
        Schema::create('permissions', function (Blueprint $t): void {
            $t->id(); $t->string('code'); $t->string('module'); $t->timestamps();
        });
        Schema::create('role_permission', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('role_id');
            $t->unsignedBigInteger('permission_id'); $t->timestamps();
        });
        Schema::create('user_roles', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('user_id'); $t->unsignedBigInteger('role_id');
            $t->timestamps();
        });
        $migration = require database_path('migrations/2026_11_16_000001_create_operations_catalogs.php');
        $migration->up();
    }

    private function seedOperationalFixtures(): void
    {
        DB::table('users')->insert([
            ['id' => 1, 'name' => 'Administrador QA', 'email' => 'admin-ops@example.test', 'password' => 'x'],
            ['id' => 2, 'name' => 'Lectura QA', 'email' => 'read-ops@example.test', 'password' => 'x'],
        ]);
        DB::table('companies')->insert([
            ['id' => 1, 'name' => 'Negocio A', 'slug' => 'negocio-a', 'is_active' => true],
            ['id' => 2, 'name' => 'Negocio B', 'slug' => 'negocio-b', 'is_active' => true],
        ]);
        DB::table('company_user')->insert([
            ['company_id' => 1, 'user_id' => 1, 'status' => 'active'],
            ['company_id' => 1, 'user_id' => 2, 'status' => 'active'],
        ]);
        DB::table('roles')->insert([
            ['id' => 1, 'company_id' => 1, 'name' => 'Admin', 'code' => 'admin'],
            ['id' => 2, 'company_id' => 1, 'name' => 'Visor', 'code' => 'view'],
        ]);
        DB::table('permissions')->insert([
            ['id' => 1, 'code' => 'company.view', 'module' => 'company'],
            ['id' => 2, 'code' => 'company.update', 'module' => 'company'],
        ]);
        DB::table('role_permission')->insert([
            ['role_id' => 1, 'permission_id' => 1],
            ['role_id' => 1, 'permission_id' => 2],
            ['role_id' => 2, 'permission_id' => 1],
        ]);
        DB::table('user_roles')->insert([
            ['company_id' => 1, 'user_id' => 1, 'role_id' => 1],
            ['company_id' => 1, 'user_id' => 2, 'role_id' => 2],
        ]);
    }

    private function login(int $id = 1): void
    {
        Sanctum::actingAs(User::query()->findOrFail($id));
    }

    private function url(string $resource, ?int $id = null, int $company = 1): string
    {
        return '/api/v1/companies/'.$company.'/'.$resource.($id === null ? '' : '/'.$id);
    }

    public function test_four_resources_require_authentication(): void
    {
        foreach (['clients', 'vehicles', 'employees', 'services'] as $resource) {
            $this->getJson($this->url($resource))->assertUnauthorized();
            $this->postJson($this->url($resource), [])->assertUnauthorized();
        }
    }

    public function test_clients_full_crud_and_soft_delete(): void
    {
        $this->login();
        $url = $this->url('clients');
        $r = $this->postJson($url, [
            'full_name' => 'María Cliente', 'phone' => '9999-1111',
            'identity_document' => '0801199012345', 'company_id' => 2,
        ])->assertCreated()->assertJsonPath('data.company_id', 1);
        $id = $r->json('data.id');
        $this->getJson($this->url('clients', $id))->assertOk()
            ->assertJsonPath('data.full_name', 'María Cliente');
        $this->getJson($url.'?q=Mar%C3%ADa')->assertOk()->assertJsonCount(1, 'data');
        $this->patchJson($this->url('clients', $id), ['full_name' => 'María Actualizada'])
            ->assertOk()->assertJsonPath('data.full_name', 'María Actualizada');
        $this->deleteJson($this->url('clients', $id))->assertOk();
        $this->getJson($this->url('clients', $id))->assertNotFound();
        $this->getJson($url)->assertJsonCount(0, 'data');
        $this->assertNotNull(DB::table('clients')->where('id', $id)->value('deleted_at'));
    }

    public function test_vehicles_full_crud_and_client_relation(): void
    {
        $this->login();
        $clientId = $this->postJson($this->url('clients'), ['full_name' => 'Cliente con vehículo'])
            ->assertCreated()->json('data.id');
        $r = $this->postJson($this->url('vehicles'), [
            'client_id' => $clientId, 'plate' => ' hba 1234 ',
            'brand' => 'Toyota', 'year' => 2019,
        ])->assertCreated()->assertJsonPath('data.plate', 'HBA 1234')
            ->assertJsonPath('data.client_name', 'Cliente con vehículo');
        $id = $r->json('data.id');
        $this->getJson($this->url('vehicles', $id))->assertOk();
        $this->getJson($this->url('vehicles').'?q=Toyota')->assertJsonCount(1, 'data');
        $this->patchJson($this->url('vehicles', $id), ['color' => 'Gris'])
            ->assertOk()->assertJsonPath('data.color', 'Gris');
        $this->deleteJson($this->url('clients', $clientId))->assertStatus(409);
        $this->deleteJson($this->url('vehicles', $id))->assertOk();
        $this->deleteJson($this->url('clients', $clientId))->assertOk();
    }

    public function test_employees_full_crud(): void
    {
        $this->login();
        $r = $this->postJson($this->url('employees'), [
            'full_name' => 'Lavador QA', 'position' => 'washer', 'hire_date' => '2026-11-16',
        ])->assertCreated();
        $id = $r->json('data.id');
        $this->getJson($this->url('employees', $id))->assertOk();
        $this->getJson($this->url('employees').'?q=Lavador')->assertJsonCount(1, 'data');
        $this->patchJson($this->url('employees', $id), ['position' => 'supervisor'])
            ->assertJsonPath('data.position', 'supervisor');
        $this->deleteJson($this->url('employees', $id))->assertOk();
        $this->getJson($this->url('employees', $id))->assertNotFound();
    }

    public function test_services_full_crud(): void
    {
        $this->login();
        $r = $this->postJson($this->url('services'), [
            'name' => 'Lavado completo', 'price' => 230.50,
            'duration_minutes' => 45, 'is_active' => true,
        ])->assertCreated();
        $id = $r->json('data.id');
        $this->getJson($this->url('services', $id))->assertOk();
        $this->getJson($this->url('services').'?q=completo')->assertJsonCount(1, 'data');
        $this->patchJson($this->url('services', $id), ['price' => 250.00])
            ->assertOk();
        $this->deleteJson($this->url('services', $id))->assertOk();
        $this->getJson($this->url('services', $id))->assertNotFound();
    }


    public function test_patch_required_fields_validates_partial_updates_across_all_catalogs(): void
    {
        $this->login();
        $clientId = $this->postJson($this->url('clients'), [
            'full_name' => 'Cliente parcial',
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('clients', $clientId), [
            'full_name' => 'Cliente editado',
        ])->assertOk()->assertJsonPath('data.full_name', 'Cliente editado');
        $this->patchJson($this->url('clients', $clientId), [
            'full_name' => null,
        ])->assertUnprocessable();

        $vehicleId = $this->postJson($this->url('vehicles'), [
            'client_id' => $clientId, 'plate' => 'HND-150',
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('vehicles', $vehicleId), [
            'client_id' => $clientId,
        ])->assertOk()->assertJsonPath('data.client_id', $clientId);
        $this->patchJson($this->url('vehicles', $vehicleId), [
            'client_id' => null,
        ])->assertUnprocessable();

        $employeeId = $this->postJson($this->url('employees'), [
            'full_name' => 'Lavador parcial',
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('employees', $employeeId), [
            'full_name' => 'Lavador editado',
        ])->assertOk()->assertJsonPath('data.full_name', 'Lavador editado');
        $this->patchJson($this->url('employees', $employeeId), [
            'full_name' => '',
        ])->assertUnprocessable();

        $serviceId = $this->postJson($this->url('services'), [
            'name' => 'Servicio parcial', 'price' => 120, 'duration_minutes' => 30,
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('services', $serviceId), [
            'name' => 'Servicio editado',
        ])->assertOk()->assertJsonPath('data.name', 'Servicio editado');
        $this->patchJson($this->url('services', $serviceId), [
            'price' => 140,
        ])->assertOk();
        $this->patchJson($this->url('services', $serviceId), [
            'duration_minutes' => 35,
        ])->assertOk()->assertJsonPath('data.duration_minutes', 35);
        $this->patchJson($this->url('services', $serviceId), [
            'price' => null,
        ])->assertUnprocessable();
    }

    public function test_cross_company_ids_and_invalid_relations_are_rejected(): void
    {
        $this->login();
        DB::table('clients')->insert([
            'id' => 99, 'company_id' => 2, 'full_name' => 'Cliente de otra empresa',
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $this->getJson($this->url('clients', 99))->assertNotFound();
        $this->patchJson($this->url('clients', 99), ['full_name' => 'Intrusión'])
            ->assertNotFound();
        $this->deleteJson($this->url('clients', 99))->assertNotFound();
        $this->getJson($this->url('clients', null, 2))->assertNotFound();
        $this->postJson($this->url('vehicles'), ['client_id' => 99, 'plate' => 'XYZ'])
            ->assertUnprocessable();
        $this->assertSame('Cliente de otra empresa', DB::table('clients')->where('id', 99)->value('full_name'));
    }

    public function test_reader_cannot_mutate_any_catalog(): void
    {
        $this->login(2);
        foreach (['clients', 'vehicles', 'employees', 'services'] as $resource) {
            $this->getJson($this->url($resource))->assertOk();
            $this->postJson($this->url($resource), [])->assertForbidden();
            $this->patchJson($this->url($resource, 1), [])->assertForbidden();
            $this->deleteJson($this->url($resource, 1))->assertForbidden();
        }
    }

    public function test_input_validation_and_duplicate_protection(): void
    {
        $this->login();
        $this->postJson($this->url('clients'), ['full_name' => ''])->assertUnprocessable();
        $this->postJson($this->url('vehicles'), ['client_id' => 999])->assertUnprocessable();
        $this->postJson($this->url('employees'), [
            'full_name' => 'A', 'position' => 'unknown',
        ])->assertUnprocessable();
        $this->postJson($this->url('services'), [
            'name' => 'X', 'price' => -5, 'duration_minutes' => 0,
        ])->assertUnprocessable();
        $this->postJson($this->url('services'), [
            'name' => 'Lavado exterior', 'price' => 100, 'duration_minutes' => 15,
        ])->assertCreated();
        $this->postJson($this->url('services'), [
            'name' => 'Lavado exterior', 'price' => 120, 'duration_minutes' => 20,
        ])->assertUnprocessable();
        $this->postJson($this->url('clients'), [
            'full_name' => 'Uno', 'identity_document' => 'X-100',
        ])->assertCreated();
        $this->postJson($this->url('clients'), [
            'full_name' => 'Dos', 'identity_document' => 'X-100',
        ])->assertUnprocessable();
    }
}
