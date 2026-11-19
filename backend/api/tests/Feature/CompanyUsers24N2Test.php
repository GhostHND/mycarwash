<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyUsers24N2Test extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::getDefaultConnection() !== 'sqlite' ||
            DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Este test solo admite SQLite en memoria.');
        }
        foreach (['employee_user','employees','user_roles','role_permission','permissions','roles',
            'company_user','companies','personal_access_tokens','users'] as $name) Schema::dropIfExists($name);
        Schema::create('users', function (Blueprint $t) {
            $t->id(); $t->string('name'); $t->string('email')->unique();
            $t->string('password'); $t->timestamps();
        });
        Schema::create('personal_access_tokens', function (Blueprint $t) {
            $t->id(); $t->morphs('tokenable'); $t->string('name');
            $t->string('token', 64)->unique(); $t->text('abilities')->nullable();
            $t->timestamp('last_used_at')->nullable(); $t->timestamp('expires_at')->nullable(); $t->timestamps();
        });
        Schema::create('companies', function (Blueprint $t) {
            $t->id(); $t->string('name'); $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('company_user', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id');
            $t->string('status')->default('active'); $t->boolean('access_all_branches')->default(false); $t->timestamps();
        });
        Schema::create('roles', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
            $t->string('code'); $t->boolean('is_system')->default(false); $t->timestamps();
        });
        Schema::create('user_roles', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id');
            $t->unsignedBigInteger('role_id'); $t->timestamps();
        });
        Schema::create('permissions', function (Blueprint $t) {
            $t->id(); $t->string('code')->unique(); $t->string('module');
            $t->string('description')->nullable(); $t->timestamps();
        });
        Schema::create('role_permission', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('role_id'); $t->unsignedBigInteger('permission_id'); $t->timestamps();
        });
        Schema::create('employees', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('full_name');
            $t->string('email')->nullable(); $t->boolean('is_active')->default(true);
            $t->softDeletes(); $t->timestamps();
        });
        Schema::create('employee_user', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('employee_id');
            $t->unsignedBigInteger('user_id'); $t->timestamps();
        });
        DB::table('users')->insert([
            ['id'=>1, 'name'=>'Dueño QA', 'email'=>'owner@example.test', 'password'=>'x'],
            ['id'=>2, 'name'=>'Otro dueño', 'email'=>'other@example.test', 'password'=>'x'],
        ]);
        DB::table('companies')->insert([
            ['id'=>1, 'name'=>'Empresa Uno', 'is_active'=>true],
            ['id'=>2, 'name'=>'Empresa Dos', 'is_active'=>true],
        ]);
        DB::table('company_user')->insert([
            ['company_id'=>1,'user_id'=>1,'status'=>'active'],
            ['company_id'=>2,'user_id'=>2,'status'=>'active'],
        ]);
        DB::table('roles')->insert([
            ['id'=>1,'company_id'=>1,'name'=>'Propietario','code'=>'owner','is_system'=>true],
            ['id'=>2,'company_id'=>2,'name'=>'Propietario','code'=>'owner','is_system'=>true],
        ]);
        DB::table('user_roles')->insert([
            ['company_id'=>1,'user_id'=>1,'role_id'=>1],
            ['company_id'=>2,'user_id'=>2,'role_id'=>2],
        ]);
        $codes = ['users.view', 'users.manage', 'roles.manage', 'company.view', 'company.update',
            'nav.users.view', 'nav.sales.view', 'nav.washes.view'];
        foreach ($codes as $index=>$code) {
            DB::table('permissions')->insert([
                'id'=>$index+1,'code'=>$code,'module'=>'users', 'description'=>$code,
            ]);
            DB::table('role_permission')->insert([
                'role_id'=>1, 'permission_id'=>$index+1,
            ]);
        }
        DB::table('employees')->insert([
            ['id'=>11,'company_id'=>1,'full_name'=>'Empleado Uno','is_active'=>true],
            ['id'=>22,'company_id'=>2,'full_name'=>'Empleado Otro','is_active'=>true],
        ]);
        Sanctum::actingAs(User::query()->findOrFail(1));
    }

    public function test_propietario_crea_rol_y_cuenta_restringida(): void
    {
        $role = $this->postJson('/api/v1/companies/1/roles', [
            'name' => 'Lavador', 'permissions' => ['nav.washes.view'],
        ])->assertCreated()->json('role_id');
        $this->assertNotNull($role);
        $id = $this->postJson('/api/v1/companies/1/users', [
            'employee_id' => 11, 'email' => 'empleado@example.test',
            'password' => 'UnPasswordSeguro123!', 'role_id' => $role,
        ])->assertCreated()->json('user_id');
        $this->assertTrue(DB::table('employee_user')->where('company_id', 1)
            ->where('employee_id', 11)->where('user_id', $id)->exists());
        $this->assertTrue(DB::table('user_roles')->where('company_id', 1)
            ->where('user_id', $id)->where('role_id', $role)->exists());
        $this->getJson('/api/v1/companies/1/users')->assertOk();
        Sanctum::actingAs(User::query()->findOrFail($id));
        // El empleado no puede consultar datos administrativos de la empresa.
        $this->getJson('/api/v1/companies/1/users')->assertForbidden();
        $this->getJson('/api/v1/companies/2/users')->assertForbidden();
        // La restricción también aplica a los endpoints de bloques anteriores.
        $this->getJson('/api/v1/companies/1/clients')->assertForbidden();
        $this->postJson('/api/v1/companies/1/workflow/orders', [])->assertForbidden();
    }

    public function test_no_permite_enlazar_empleado_de_otra_empresa(): void
    {
        $role = $this->postJson('/api/v1/companies/1/roles', [
            'name' => 'Cajero', 'permissions' => ['nav.sales.view'],
        ])->assertCreated()->json('role_id');
        $this->postJson('/api/v1/companies/1/users', [
            'employee_id'=>22, 'email'=>'ajeno@example.test',
            'password'=>'PasswordSeguro123', 'role_id'=>$role,
        ])->assertUnprocessable();
        $this->assertFalse(DB::table('users')->where('email', 'ajeno@example.test')->exists());
    }

    public function test_no_permite_modificar_propietario_protegido(): void
    {
        $this->patchJson('/api/v1/companies/1/users/1', [
            'status' => 'inactive',
        ])->assertUnprocessable();
        $this->assertEquals('active', DB::table('company_user')
            ->where('company_id', 1)->where('user_id', 1)->value('status'));
    }
}
