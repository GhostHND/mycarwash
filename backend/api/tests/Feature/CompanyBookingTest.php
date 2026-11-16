<?php

namespace Tests\Feature;

use App\Models\User;
use Carbon\CarbonImmutable;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyBookingTest extends TestCase
{
    use DatabaseTransactions;

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
    }

    private function login(int $id=1):void{Sanctum::actingAs(User::query()->findOrFail($id));}
    private function url(string $r,?int $id=null,int $company=1):string
    {return '/api/v1/companies/'.$company.'/schedule/'.$r.($id===null?'':'/'.$id);}
    private function day():CarbonImmutable{return CarbonImmutable::now('America/Tegucigalpa')->addDays(3)->startOfDay();}
    private function shift():int
    {
        $d=$this->day();
        return (int)$this->postJson($this->url('shifts'),['branch_id'=>1,'name'=>'Mañana','day_of_week'=>$d->dayOfWeek,
            'starts_at'=>'08:00','ends_at'=>'17:00'])->assertCreated()->json('data.id');
    }
    private function roster(int $shift,int $employee=1):int
    {
        return (int)$this->postJson($this->url('roster'),['shift_id'=>$shift,'employee_id'=>$employee,
            'effective_from'=>$this->day()->subDay()->toDateString()])->assertCreated()->json('data.id');
    }
    private function booking(int $bay=1,int $service=1,string $time='09:00',int $vehicle=1):array
    {return $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>$bay,'vehicle_id'=>$vehicle,
            'service_id'=>$service,'local_date'=>$this->day()->toDateString(),'start_time'=>$time])->assertCreated()->json('data');}

    public function test_security_permissions_and_scoping():void
    {
        foreach(['bookings','blocks','shifts','roster'] as $resource) $this->getJson($this->url($resource))->assertUnauthorized();
        $this->login(2);
        foreach(['bookings','blocks','shifts','roster'] as $r) {
            $this->getJson($this->url($r))->assertOk();
            $this->postJson($this->url($r),[])->assertForbidden();
        }
        $this->login();
        $this->getJson($this->url('bookings',null,2))->assertNotFound();
        $this->postJson($this->url('shifts'),['branch_id'=>2,'name'=>'Invalido','day_of_week'=>1,
            'starts_at'=>'09:00','ends_at'=>'12:00'])->assertUnprocessable();
        $this->getJson($this->url('options'))->assertOk();
    }

    public function test_shift_and_roster_full_crud():void
    {
        $this->login(); $shift=$this->shift();
        $this->getJson($this->url('shifts',$shift))->assertOk()->assertJsonPath('data.name','Mañana');
        $this->patchJson($this->url('shifts',$shift),['name'=>'Turno diurno'])->assertOk()->assertJsonPath('data.name','Turno diurno');
        $roster=$this->roster($shift);
        $this->getJson($this->url('roster',$roster))->assertOk();
        $this->patchJson($this->url('roster',$roster),['notes'=>'Entrada supervisada'])->assertOk();
        $this->postJson($this->url('roster'),['shift_id'=>$shift,'employee_id'=>1,
            'effective_from'=>$this->day()->toDateString()])->assertUnprocessable();
        $this->deleteJson($this->url('shifts',$shift))->assertUnprocessable();
        $this->deleteJson($this->url('roster',$roster))->assertOk();
        $this->getJson($this->url('roster',$roster))->assertNotFound();
        $this->deleteJson($this->url('shifts',$shift))->assertOk();
        $this->getJson($this->url('shifts',$shift))->assertNotFound();
    }

    public function test_booking_crud_capacity_and_history():void
    {
        $this->login();$s=$this->shift();$this->roster($s);
        $row=$this->booking(); $id=$row['id'];
        $this->assertSame('CONFIRMED',$row['status']);
        $this->assertMatchesRegularExpression('/^RSV-[A-F0-9]{20}$/',$row['booking_code']);
        $this->getJson($this->url('bookings',$id))->assertOk()->assertJsonPath('data.vehicle_label','Honda Civic P123');
        $this->getJson($this->url('bookings').'?q='.$row['booking_code'])->assertJsonCount(1,'data');
        $this->deleteJson('/api/v1/companies/1/vehicles/1')->assertStatus(409);
        $this->deleteJson('/api/v1/companies/1/services/1')->assertStatus(409);
        $this->deleteJson('/api/v1/companies/1/workflow/bays/1')->assertStatus(409);
        $this->patchJson('/api/v1/companies/1/vehicles/1',['is_active'=>false])->assertStatus(409);
        $this->patchJson('/api/v1/companies/1/workflow/bays/1',['is_active'=>false])->assertStatus(409);
        $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>1,'vehicle_id'=>1,'service_id'=>1,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'09:20'])->assertUnprocessable();
        $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>2,'vehicle_id'=>1,'service_id'=>1,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'09:20'])->assertUnprocessable();
        DB::table('wash_services')->where('id',1)->update(['price'=>999,'duration_minutes'=>60]);
        $this->patchJson($this->url('bookings',$id),['notes'=>'Sin aromatizante','start_time'=>'10:00'])->assertOk()
            ->assertJsonPath('data.version',2)->assertJsonPath('data.start_time','10:00')
            ->assertJsonPath('data.estimated_minutes',45);
        $this->assertEquals(200,DB::table('wash_bookings')->where('id',$id)->value('quoted_price'));
        $this->getJson('/api/v1/companies/1/schedule/bookings/'.$id.'/history')->assertJsonCount(2,'data');
        $this->deleteJson($this->url('bookings',$id))->assertOk();
        $this->getJson($this->url('bookings',$id))->assertNotFound();
        $this->assertSame('CANCELLED',DB::table('wash_bookings')->where('id',$id)->value('status'));
        $this->getJson('/api/v1/companies/1/schedule/bookings/'.$id.'/history')->assertJsonCount(3,'data');
        $this->assertNotNull(DB::table('wash_bookings')->where('id',$id)->value('deleted_at'));
    }

    public function test_blocks_full_crud_and_protect_reservations():void
    {
        $this->login();$s=$this->shift();$this->roster($s);
        $block=$this->postJson($this->url('blocks'),['branch_id'=>1,'bay_id'=>1,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'09:00','end_time'=>'10:00',
            'reason'=>'Mantenimiento'])->assertCreated()->json('data');
        $this->getJson($this->url('blocks',$block['id']))->assertOk();
        $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>1,'vehicle_id'=>1,'service_id'=>1,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'09:00'])->assertUnprocessable();
        $this->patchJson($this->url('blocks',$block['id']),['reason'=>'Limpieza','start_time'=>'10:00','end_time'=>'11:00'])
            ->assertOk()->assertJsonPath('data.reason','Limpieza');
        $this->deleteJson($this->url('blocks',$block['id']))->assertOk();
        $this->getJson($this->url('blocks',$block['id']))->assertNotFound();
        $b=$this->booking();
        $this->postJson($this->url('blocks'),['branch_id'=>1,'bay_id'=>1,'local_date'=>$this->day()->toDateString(),
            'start_time'=>'09:20','end_time'=>'10:00','reason'=>'No autorizado'])->assertUnprocessable();
        $this->assertNotNull($b['id']);
    }

    public function test_long_service_requires_full_open_window_and_shifts():void
    {
        $this->login();$s=$this->shift();$this->roster($s);
        $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>1,'vehicle_id'=>1,'service_id'=>2,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'16:30'])->assertUnprocessable();
        $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>1,'vehicle_id'=>1,'service_id'=>2,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'14:30'])->assertUnprocessable();
        $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>1,'vehicle_id'=>1,'service_id'=>2,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'13:00'])->assertCreated();
    }

    public function test_two_lavadores_allow_two_simultaneous_bays():void
    {
        $this->login();$s=$this->shift();$this->roster($s);$this->roster($s,2);
        $this->booking(1);
        $this->booking(2,1,'09:00',2);
        $this->getJson($this->url('bookings'))->assertJsonCount(2,'data');
    }

    public function test_invalid_dates_and_tenant_protection():void
    {
        $this->login();
        $this->postJson($this->url('shifts'),['branch_id'=>1,'name'=>'Mal','day_of_week'=>1,
            'starts_at'=>'17:00','ends_at'=>'09:00'])->assertUnprocessable();
        $this->postJson($this->url('bookings'),['branch_id'=>1,'bay_id'=>1,'vehicle_id'=>1,'service_id'=>1,
            'local_date'=>$this->day()->toDateString(),'start_time'=>'09:00'])->assertUnprocessable();
        $this->postJson($this->url('blocks'),['branch_id'=>2,'local_date'=>$this->day()->toDateString(),
            'start_time'=>'09:00','end_time'=>'10:00','reason'=>'Ajeno'])->assertUnprocessable();
    }
}
