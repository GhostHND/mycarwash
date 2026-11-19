<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\Crypt;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class WasherPortal24N3Test extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Ejecutar exclusivamente con SQLite :memory:.');
        }
        foreach (['washer_attendance_points_24n4','washer_attendance_24n3', 'booking_daily_assignments', 'wash_bookings',
            'wash_assignments','wash_orders','wash_bays','wash_services','vehicles','clients','branches','employee_user',
            'employees','role_permission','permissions','user_roles','roles','company_user',
            'companies','personal_access_tokens','users'] as $table) Schema::dropIfExists($table);

        Schema::create('users', function(Blueprint $t) {
            $t->id(); $t->string('name'); $t->string('email')->unique(); $t->string('password'); $t->timestamps();
        });
        Schema::create('personal_access_tokens', function(Blueprint $t) {
            $t->id(); $t->morphs('tokenable'); $t->string('name'); $t->string('token',64)->unique();
            $t->text('abilities')->nullable(); $t->timestamp('last_used_at')->nullable();
            $t->timestamp('expires_at')->nullable(); $t->timestamps();
        });
        Schema::create('companies', function(Blueprint $t) {
            $t->id(); $t->string('name'); $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('company_user', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id');
            $t->string('status')->default('active'); $t->timestamps();
        });
        Schema::create('roles', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
            $t->string('code'); $t->boolean('is_system')->default(false); $t->timestamps();
        });
        Schema::create('user_roles', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id');
            $t->unsignedBigInteger('role_id'); $t->timestamps();
        });
        Schema::create('employees', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('full_name');
            $t->string('position')->default('washer'); $t->string('phone')->nullable();
            $t->string('identity_document')->nullable(); $t->date('hire_date')->nullable();
            $t->boolean('is_active')->default(true); $t->softDeletes(); $t->timestamps();
        });
        Schema::create('employee_user', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('employee_id');
            $t->unsignedBigInteger('user_id'); $t->timestamps();
        });
        Schema::create('branches', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
            $t->string('timezone')->default('America/Tegucigalpa');
        });
        Schema::create('clients', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('full_name');
        });
        Schema::create('vehicles', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('brand');
            $t->string('model'); $t->string('plate'); $t->unsignedBigInteger('client_id')->nullable();
        });
        Schema::create('wash_bays', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
        });
        Schema::create('wash_services', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
        });
        Schema::create('wash_orders', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('vehicle_id'); $t->unsignedBigInteger('service_id');
            $t->unsignedBigInteger('bay_id')->nullable(); $t->decimal('quoted_price',10,2)->nullable();
            $t->string('tracking_code'); $t->string('status'); $t->integer('version')->default(1);
            $t->integer('estimated_minutes'); $t->timestamp('started_at')->nullable();
            $t->timestamp('completed_at')->nullable(); $t->timestamps();
        });
        Schema::create('wash_assignments', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('order_id');
            $t->unsignedBigInteger('employee_id'); $t->boolean('is_active')->default(true); $t->timestamp('washer_finished_at')->nullable();
        });
        Schema::create('washer_attendance_24n3', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('employee_id');
            $t->date('work_date'); $t->timestamp('check_in_at'); $t->timestamp('check_out_at')->nullable();
            $t->timestamps();
        });
        Schema::create('washer_attendance_points_24n4', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
            $t->text('secret_encrypted'); $t->boolean('is_active')->default(true);
            $t->timestamps();
        });
        Schema::create('wash_bookings', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('vehicle_id'); $t->unsignedBigInteger('service_id');
            $t->dateTime('start_at_utc'); $t->dateTime('end_at_utc');
            $t->string('booking_code'); $t->string('status'); $t->softDeletes();
        });
        Schema::create('booking_daily_assignments', function(Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('booking_id');
            $t->unsignedBigInteger('employee_id'); $t->dateTime('booking_start_utc');
        });

        $pass = Hash::make('PasswordOriginal123!');
        DB::table('users')->insert([
            ['id'=>10,'name'=>'Lavador Uno','email'=>'wash1@example.test','password'=>$pass],
            ['id'=>20,'name'=>'Lavador Dos','email'=>'wash2@example.test','password'=>$pass],
        ]);
        DB::table('companies')->insert(['id'=>1,'name'=>'Carwash QA','is_active'=>true]);
        foreach ([10,20] as $user) {
            DB::table('company_user')->insert(['company_id'=>1,'user_id'=>$user,'status'=>'active']);
            DB::table('roles')->insert(['id'=>$user,'company_id'=>1,'name'=>'Lavador','code'=>'custom_'.$user]);
            DB::table('user_roles')->insert(['company_id'=>1,'user_id'=>$user,'role_id'=>$user]);
            DB::table('employees')->insert(['id'=>$user,'company_id'=>1,'full_name'=>'Empleado '.$user,
                'position'=>'washer','is_active'=>true]);
            DB::table('employee_user')->insert(['company_id'=>1,'employee_id'=>$user,'user_id'=>$user]);
        }
        DB::table('branches')->insert(['id'=>1,'company_id'=>1,'name'=>'Principal']);
        DB::table('wash_bays')->insert(['id'=>1,'company_id'=>1,'name'=>'Bahía A']);
        DB::table('clients')->insert(['id'=>1,'company_id'=>1,'full_name'=>'Cliente Test']);
        DB::table('vehicles')->insert(['id'=>1,'company_id'=>1,'brand'=>'Honda','model'=>'Civic',
            'plate'=>'ABC1','client_id'=>1]);
        DB::table('wash_services')->insert(['id'=>1,'company_id'=>1,'name'=>'Exterior']);
        foreach ([101,102] as $id) {
            DB::table('wash_orders')->insert(['id'=>$id,'company_id'=>1,'branch_id'=>1,
                'vehicle_id'=>1,'service_id'=>1,'bay_id'=>1,'quoted_price'=>500.00,
                'tracking_code'=>'ORD'.$id,
                'status'=>'ASIGNADO','version'=>1,'estimated_minutes'=>30]);
            DB::table('wash_assignments')->insert(['company_id'=>1,'order_id'=>$id,
                'employee_id'=>$id===101?10:20,'is_active'=>true]);
            DB::table('wash_bookings')->insert(['id'=>$id,'company_id'=>1,'branch_id'=>1,
                'vehicle_id'=>1,'service_id'=>1,'booking_code'=>'RES'.$id,
                'start_at_utc'=>'2026-11-19 15:00:00','end_at_utc'=>'2026-11-19 15:30:00',
                'status'=>'CONFIRMED']);
            DB::table('booking_daily_assignments')->insert(['company_id'=>1,'booking_id'=>$id,
                'employee_id'=>$id===101?10:20,'booking_start_utc'=>'2026-11-19 15:00:00']);
        }
        DB::table('washer_attendance_points_24n4')->insert([
            'id'=>1,'company_id'=>1,'name'=>'Punto 1',
            'secret_encrypted'=>Crypt::encryptString('secret-test-washer-qa'),
            'is_active'=>true,
        ]);
        Sanctum::actingAs(User::query()->findOrFail(10));
    }

    public function test_lavador_ve_solamente_sus_trabajos_y_agenda(): void
    {
        $this->getJson('/api/v1/companies/1/washer/orders')->assertOk()
            ->assertJsonCount(1,'data')->assertJsonPath('data.0.id',101)
            ->assertJsonPath('data.0.worker_finished',false)
            ->assertJsonPath('data.0.client_name','Cliente Test')
            ->assertJsonPath('data.0.bay_name','Bahía A');
        $this->getJson('/api/v1/companies/1/washer/agenda?view=week&date=2026-11-19')
            ->assertOk()->assertJsonCount(1,'data')->assertJsonPath('data.0.id',101);
        $this->getJson('/api/v1/companies/1/workflow/orders')->assertForbidden();
        $this->postJson('/api/v1/companies/1/workflow/orders',[])->assertForbidden();
        $this->patchJson('/api/v1/companies/1/workflow/orders/101',[])->assertForbidden();
        $this->postJson('/api/v1/companies/1/washer/orders/102/start', ['expected_version'=>1])
            ->assertForbidden();
        $this->getJson('/api/v1/companies/1/users')->assertForbidden();
    }

    private function qrCode(): string
    {
        $slot = intdiv(time(), 120);
        $hmac = hash_hmac('sha256', "1:1:$slot", 'secret-test-washer-qa');
        return "MCW:ATT:1:1:1:$slot:".substr($hmac,0,40);
    }

    public function test_asistencia_qr_valido_no_permite_marcas_ajenas(): void
    {
        $this->postJson('/api/v1/companies/1/washer/attendance/check-in')->assertForbidden();
        $this->postJson('/api/v1/companies/1/washer/attendance/scan',[
            'code'=>'00000000', 'event'=>'check_in',
        ])->assertStatus(422);
        $this->postJson('/api/v1/companies/1/washer/attendance/scan',[
            'code'=>$this->qrCode(), 'event'=>'check_in','employee_id'=>20,
        ])->assertCreated();
        $this->assertTrue(DB::table('washer_attendance_24n3')->where('employee_id',10)->exists());
        $this->assertFalse(DB::table('washer_attendance_24n3')->where('employee_id',20)->exists());
        $this->postJson('/api/v1/companies/1/washer/attendance/scan',[
            'code'=>$this->qrCode(), 'event'=>'check_in',
        ])->assertStatus(409);
        $this->postJson('/api/v1/companies/1/washer/attendance/scan',[
            'code'=>$this->qrCode(), 'event'=>'check_out',
        ])->assertOk();
        $this->getJson('/api/v1/companies/1/washer/attendance')->assertOk();
    }

    public function test_perfil_personal_y_acceso_fotografias_ajenas(): void
    {
        $this->getJson('/api/v1/companies/1/washer/me')->assertOk()
            ->assertJsonPath('user.employee_id',10);
        $this->get('/api/v1/companies/1/washer/photo/employees/20')->assertForbidden();
        $this->patchJson('/api/v1/companies/1/washer/me',[
            'name'=>'Nuevo Nombre','email'=>'wash1@example.test','phone'=>'99990000',
        ])->assertOk();
        $this->assertSame('99990000',DB::table('employees')->where('id',10)->value('phone'));
        $this->patchJson('/api/v1/companies/1/washer/password',[
            'current_password'=>'incorrecta',
            'password'=>'PasswordNueva123!', 'password_confirmation'=>'PasswordNueva123!',
        ])->assertUnprocessable();
    }

}
