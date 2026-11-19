<?php

namespace Tests\Feature;

use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Illuminate\Support\Str;

/** Prueba aislada de reservas con SQLite en memoria. */
class CompanyReservationIntake24N7Test extends \Tests\TestCase
{
    use \Illuminate\Foundation\Testing\DatabaseTransactions;
    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Las pruebas de agenda solo se ejecutan en SQLite :memory:.');
        }
        foreach (['booking_events','wash_bookings','booking_blocks','staff_shift_assignments','staff_shifts',
            'wash_order_events','company_entity_photos','wash_assignments','wash_orders','wash_bays','wash_services',
            'employees','vehicles','clients','company_business_hours','company_special_hours','branches','user_roles',
            'role_permission','permissions','roles','company_user','companies','users'] as $t) Schema::dropIfExists($t);
        Schema::create('users',function(Blueprint $t):void{$t->id();$t->string('name');$t->string('email');$t->string('password');$t->timestamps();});
        Schema::create('companies',function(Blueprint $t):void{$t->id();$t->string('name');$t->boolean('is_active')->default(true);$t->timestamps();});
        Schema::create('branches',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->string('name');$t->string('timezone')->default('America/Tegucigalpa');$t->boolean('is_active')->default(true);$t->unique(['id','company_id']);});
        Schema::create('company_user',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('user_id');$t->string('status');$t->timestamps();});
        Schema::create('roles',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->string('name');$t->string('code');$t->timestamps();});
        Schema::create('permissions',function(Blueprint $t):void{$t->id();$t->string('code');$t->string('module');$t->timestamps();});
        Schema::create('role_permission',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('role_id');$t->unsignedBigInteger('permission_id');$t->timestamps();});
        Schema::create('user_roles',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('user_id');$t->unsignedBigInteger('role_id');$t->timestamps();});
        Schema::create('company_business_hours',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->unsignedTinyInteger('day_of_week');$t->time('opens_at')->nullable();$t->time('closes_at')->nullable();$t->time('break_starts_at')->nullable();$t->time('break_ends_at')->nullable();$t->boolean('is_closed')->default(false);$t->timestamps();});
        Schema::create('company_special_hours',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->date('special_date');$t->time('opens_at')->nullable();$t->time('closes_at')->nullable();$t->boolean('is_closed')->default(false);$t->timestamps();});
        (require database_path('migrations/2026_11_16_000001_create_operations_catalogs.php'))->up();
        Schema::create('company_media_assets',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->string('path');});
        (require database_path('migrations/2026_11_16_000002_create_wash_workflow.php'))->up();
        (require database_path('migrations/2026_11_16_000003_create_booking_staff_tables.php'))->up();
        DB::table('users')->insert([['id'=>1,'name'=>'Admin','email'=>'a@x.test','password'=>'x'],['id'=>2,'name'=>'Reader','email'=>'b@x.test','password'=>'x']]);
        DB::table('companies')->insert([['id'=>1,'name'=>'A'],['id'=>2,'name'=>'B']]);
        DB::table('branches')->insert([['id'=>1,'company_id'=>1,'name'=>'Centro'],['id'=>2,'company_id'=>2,'name'=>'Otra']]);
        DB::table('company_user')->insert([['company_id'=>1,'user_id'=>1,'status'=>'active'],['company_id'=>1,'user_id'=>2,'status'=>'active']]);
        DB::table('roles')->insert([['id'=>1,'company_id'=>1,'name'=>'Admin','code'=>'admin'],['id'=>2,'company_id'=>1,'name'=>'Lector','code'=>'reader']]);
        DB::table('permissions')->insert([['id'=>1,'code'=>'company.view','module'=>'company'],['id'=>2,'code'=>'company.update','module'=>'company']]);
        DB::table('role_permission')->insert([['role_id'=>1,'permission_id'=>1],['role_id'=>1,'permission_id'=>2],['role_id'=>2,'permission_id'=>1]]);
        DB::table('user_roles')->insert([['company_id'=>1,'user_id'=>1,'role_id'=>1],['company_id'=>1,'user_id'=>2,'role_id'=>2]]);
        DB::table('clients')->insert(['id'=>1,'company_id'=>1,'full_name'=>'Ana','is_active'=>true]);
        DB::table('clients')->insert(['id'=>2,'company_id'=>1,'full_name'=>'Carlos','is_active'=>true]);
        DB::table('vehicles')->insert(['id'=>1,'company_id'=>1,'client_id'=>1,'brand'=>'Honda','model'=>'Civic','plate'=>'P123','is_active'=>true]);
        DB::table('vehicles')->insert(['id'=>2,'company_id'=>1,'client_id'=>2,'brand'=>'Toyota','model'=>'Yaris','plate'=>'P456','is_active'=>true]);
        DB::table('wash_services')->insert(['id'=>1,'company_id'=>1,'name'=>'Completo','duration_minutes'=>45,'price'=>200,'is_active'=>true]);
        DB::table('wash_services')->insert(['id'=>2,'company_id'=>1,'name'=>'Extenso','duration_minutes'=>180,'price'=>400,'is_active'=>true]);
        DB::table('employees')->insert(['id'=>1,'company_id'=>1,'full_name'=>'Lavador 1','position'=>'washer','is_active'=>true]);
        DB::table('employees')->insert(['id'=>2,'company_id'=>1,'full_name'=>'Lavador 2','position'=>'washer','is_active'=>true]);
        DB::table('wash_bays')->insert(['id'=>1,'company_id'=>1,'branch_id'=>1,'name'=>'Puesto A','code'=>'A','is_active'=>true]);
        DB::table('wash_bays')->insert(['id'=>2,'company_id'=>1,'branch_id'=>1,'name'=>'Puesto B','code'=>'B','is_active'=>true]);
        for($d=0;$d<7;$d++) DB::table('company_business_hours')->insert(['company_id'=>1,'day_of_week'=>$d,'opens_at'=>'08:00','closes_at'=>'18:00','is_closed'=>false]);
        Schema::table('roles', function (Blueprint $t): void {
            $t->boolean('is_system')->default(false);
        });
        (require database_path('migrations/2026_11_18_000010_booking_daily_assignments_and_alert_reads.php'))->up();
        (require database_path('migrations/2026_11_19_000006_booking_reception_24n7.php'))->up();
    }


    public function test_received_booking_creates_only_one_new_order_and_preserves_history(): void
    {
        CarbonImmutable::setTestNow(CarbonImmutable::parse('2026-11-19 10:00:00', 'America/Tegucigalpa'));
        try {
            Sanctum::actingAs(User::query()->findOrFail(1));
            $starts = CarbonImmutable::now('America/Tegucigalpa')->addMinutes(8);
            $booking = DB::table('wash_bookings')->insertGetId([
                'public_id' => (string) Str::uuid(), 'booking_code' => 'RSV-ABCD0000111122223333',
                'company_id' => 1, 'branch_id' => 1, 'bay_id' => 1,
                'vehicle_id' => 1, 'service_id' => 1,
                'start_at_utc' => $starts->utc()->format('Y-m-d H:i:s'),
                'end_at_utc' => $starts->addMinutes(45)->utc()->format('Y-m-d H:i:s'),
                'timezone_id' => 'America/Tegucigalpa', 'local_date' => '2026-11-19',
                'status' => 'CONFIRMED', 'quoted_price' => 200, 'estimated_minutes' => 45,
                'version' => 1, 'created_at' => now(), 'updated_at' => now(),
            ]);
            $base = '/api/v1/companies/1/workflow/';
            $this->getJson($base.'reservations-24n7?date=2026-11-19')
                ->assertOk()->assertJsonPath('data.0.received', false);
            $this->getJson($base.'arrival-reminders-24n7')
                ->assertOk()->assertJsonCount(1, 'data');
            $this->postJson($base.'reservations-24n7/'.$booking.'/arrival-read')->assertOk();
            $this->getJson($base.'arrival-reminders-24n7')->assertJsonCount(0, 'data');
            $first = $this->postJson($base.'reservations-24n7/'.$booking.'/receive')
                ->assertOk()->assertJsonPath('data.already_received', false);
            $orderId = $first->json('data.order_id');
            $this->postJson($base.'reservations-24n7/'.$booking.'/receive')
                ->assertOk()->assertJsonPath('data.already_received', true)
                ->assertJsonPath('data.order_id', $orderId);
            $this->assertSame(1, DB::table('wash_orders')->where('company_id', 1)->count());
            $this->assertSame('EN_ESPERA', DB::table('wash_orders')->where('id', $orderId)->value('status'));
            $this->assertSame(1, DB::table('wash_order_events')->where('order_id', $orderId)->count());
            $this->getJson($base.'reservations-24n7?date=2026-11-19')
                ->assertOk()->assertJsonPath('data.0.received', true)
                ->assertJsonPath('data.0.order_id', $orderId);
            $this->patchJson('/api/v1/companies/1/schedule/bookings/'.$booking,
                ['notes' => 'Otra'])->assertUnprocessable();
            $this->deleteJson('/api/v1/companies/1/schedule/bookings/'.$booking)
                ->assertUnprocessable();
            Sanctum::actingAs(User::query()->findOrFail(2));
            $this->postJson($base.'reservations-24n7/'.$booking.'/receive')
                ->assertForbidden();
        } finally {
            CarbonImmutable::setTestNow();
        }
    }
}
