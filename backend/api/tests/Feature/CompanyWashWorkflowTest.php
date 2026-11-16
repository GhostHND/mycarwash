<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyWashWorkflowTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Solo SQLite :memory:.');
        }
        foreach (['wash_order_events','company_entity_photos','company_media_assets','wash_assignments','wash_orders','wash_bays',
            'wash_services','employees','vehicles','clients','branches','user_roles','role_permission',
            'permissions','roles','company_user','companies','users'] as $table) Schema::dropIfExists($table);
        Schema::create('users', function (Blueprint $t): void { $t->id(); $t->string('name'); $t->string('email'); $t->string('password'); $t->timestamps(); });
        Schema::create('companies', function (Blueprint $t): void { $t->id(); $t->string('name'); $t->boolean('is_active')->default(true); $t->timestamps(); });
        Schema::create('branches', function (Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name'); $t->boolean('is_active')->default(true); $t->string('timezone')->default('America/Tegucigalpa'); $t->unique(['id','company_id']); });
        Schema::create('company_user', function (Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id'); $t->string('status'); $t->timestamps(); });
        Schema::create('roles', function (Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name'); $t->string('code'); $t->timestamps(); });
        Schema::create('permissions', function (Blueprint $t): void { $t->id(); $t->string('code'); $t->string('module'); $t->timestamps(); });
        Schema::create('role_permission', function (Blueprint $t): void { $t->id(); $t->unsignedBigInteger('role_id'); $t->unsignedBigInteger('permission_id'); $t->timestamps(); });
        Schema::create('user_roles', function (Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id'); $t->unsignedBigInteger('role_id'); $t->timestamps(); });
        (require database_path('migrations/2026_11_16_000001_create_operations_catalogs.php'))->up();
        // Representa la biblioteca existente del Bloque de configuracion.
        // La migracion nueva no debe recrear ni alterar esta tabla.
        Schema::create('company_media_assets', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->string('category', 60)->default('general');
            $t->string('disk', 50)->default('public');
            $t->string('path', 600);
            $t->string('original_filename', 255)->nullable();
            $t->string('mime_type', 120)->nullable();
            $t->unsignedBigInteger('file_size')->nullable();
            $t->string('alt_text', 255)->nullable();
            $t->boolean('is_public')->default(false);
            $t->unsignedInteger('sort_order')->default(0);
            $t->timestamps();
        });
        (require database_path('migrations/2026_11_16_000002_create_wash_workflow.php'))->up();
        DB::table('users')->insert([
            ['id'=>1,'name'=>'Admin','email'=>'w1@test.invalid','password'=>'x'],
            ['id'=>2,'name'=>'Lector','email'=>'w2@test.invalid','password'=>'x'],
        ]);
        DB::table('companies')->insert([['id'=>1,'name'=>'Empresa 1'],['id'=>2,'name'=>'Empresa 2']]);
        DB::table('branches')->insert([['id'=>1,'company_id'=>1,'name'=>'Principal'],['id'=>2,'company_id'=>2,'name'=>'Ajena']]);
        DB::table('company_user')->insert([['company_id'=>1,'user_id'=>1,'status'=>'active'],['company_id'=>1,'user_id'=>2,'status'=>'active']]);
        DB::table('roles')->insert([['id'=>1,'company_id'=>1,'name'=>'Admin','code'=>'admin'],['id'=>2,'company_id'=>1,'name'=>'Visor','code'=>'reader']]);
        DB::table('permissions')->insert([['id'=>1,'code'=>'company.view','module'=>'company'],['id'=>2,'code'=>'company.update','module'=>'company']]);
        DB::table('role_permission')->insert([['role_id'=>1,'permission_id'=>1],['role_id'=>1,'permission_id'=>2],['role_id'=>2,'permission_id'=>1]]);
        DB::table('user_roles')->insert([['company_id'=>1,'user_id'=>1,'role_id'=>1],['company_id'=>1,'user_id'=>2,'role_id'=>2]]);
        DB::table('clients')->insert(['id'=>1,'company_id'=>1,'full_name'=>'Cliente Uno','is_active'=>true]);
        DB::table('vehicles')->insert(['id'=>1,'company_id'=>1,'client_id'=>1,'plate'=>'TST001','brand'=>'Toyota','model'=>'Corolla','is_active'=>true]);
        DB::table('employees')->insert(['id'=>1,'company_id'=>1,'full_name'=>'Lavador Uno','position'=>'washer','is_active'=>true]);
        DB::table('employees')->insert(['id'=>2,'company_id'=>1,'full_name'=>'Lavador Dos','position'=>'washer','is_active'=>true]);
        DB::table('wash_services')->insert(['id'=>1,'company_id'=>1,'name'=>'Completo','price'=>220,'duration_minutes'=>45,'is_active'=>true]);
        Storage::fake('local');
    }

    private function login(int $id=1): void { Sanctum::actingAs(User::query()->findOrFail($id)); }
    private function url(string $resource, ?int $id=null, int $company=1): string
    { return '/api/v1/companies/'.$company.'/workflow/'.$resource.($id === null?'':'/'.$id); }
    private function order(): array
    {
        $r=$this->postJson($this->url('orders'), ['branch_id'=>1,'vehicle_id'=>1,'service_id'=>1])->assertCreated();
        return $r->json('data');
    }

    public function test_authentication_and_read_only_permissions(): void
    {
        foreach (['bays','orders','assignments'] as $resource) $this->getJson($this->url($resource))->assertUnauthorized();
        $this->getJson('/api/v1/companies/1/media/vehicles/1')->assertUnauthorized();
        $this->login(2);
        $this->getJson($this->url('orders'))->assertOk();
        $this->postJson($this->url('orders'), [])->assertForbidden();
        $this->post('/api/v1/companies/1/media/vehicles/1', [])->assertForbidden();
    }

    public function test_bays_full_crud_and_company_scope(): void
    {
        $this->login();
        $r=$this->postJson($this->url('bays'), ['branch_id'=>1,'name'=>'Bahía uno','code'=>'B1'])->assertCreated();
        $id=$r->json('data.id');
        $this->getJson($this->url('bays',$id))->assertOk();
        $this->getJson($this->url('bays').'?q=B1')->assertJsonCount(1,'data');
        $this->patchJson($this->url('bays',$id), ['name'=>'Bahía central'])->assertOk()->assertJsonPath('data.name','Bahía central');
        $this->postJson($this->url('bays'), ['branch_id'=>1,'name'=>'Otro','code'=>'B1'])->assertUnprocessable();
        $this->postJson($this->url('bays'), ['branch_id'=>2,'name'=>'Ajeno','code'=>'A1'])->assertUnprocessable();
        $this->deleteJson($this->url('bays',$id))->assertOk();
        $this->getJson($this->url('bays',$id))->assertNotFound();
    }

    public function test_order_crud_transition_queue_and_immutable_events(): void
    {
        $this->login();
        $data=$this->order(); $id=$data['id'];
        $this->assertSame('EN_ESPERA',$data['status']);
        $this->assertSame(1,$data['version']);
        $this->assertMatchesRegularExpression('/^MCW-[0-9A-F]{20}$/',$data['tracking_code']);
        $this->postJson($this->url('orders'), ['branch_id'=>1, 'vehicle_id'=>1, 'service_id'=>1])->assertUnprocessable();
        $this->getJson($this->url('orders',$id))->assertOk();
        $this->getJson($this->url('orders').'?q='.$data['tracking_code'])->assertJsonCount(1,'data');
        $this->patchJson($this->url('orders',$id),['notes'=>'Lavado con cuidado'])->assertOk();
        $this->getJson('/api/v1/companies/1/workflow/queue?branch_id=1')->assertJsonCount(1,'data');
        $this->postJson($this->url('orders',$id).'/transition',['to_status'=>'EN_PROCESO','expected_version'=>1])->assertStatus(409);
        $this->getJson($this->url('orders',$id).'/history')->assertJsonCount(1,'data');
        $this->deleteJson($this->url('orders',$id))->assertOk();
        $this->getJson($this->url('orders',$id))->assertJsonPath('data.status','CANCELADO');
        $this->getJson($this->url('orders',$id).'/history')->assertJsonCount(2,'data');
        $this->postJson($this->url('orders'),['branch_id'=>2,'vehicle_id'=>1,'service_id'=>1])->assertUnprocessable();
    }

    public function test_assignments_multiwasher_and_state_machine(): void
    {
        $this->login();
        $order=$this->order();$id=$order['id'];
        $a=$this->postJson($this->url('assignments'), ['order_id'=>$id,'employee_id'=>1,'is_primary'=>true])->assertCreated();
        $aid=$a->json('data.id');
        $this->postJson($this->url('assignments'), ['order_id'=>$id,'employee_id'=>2])->assertCreated();
        $this->postJson($this->url('assignments'), ['order_id'=>$id,'employee_id'=>1])->assertUnprocessable();
        $this->getJson($this->url('orders',$id))->assertJsonCount(2,'data.assignments')->assertJsonPath('data.status','ASIGNADO');
        $this->getJson($this->url('assignments',$aid))->assertOk();
        $this->patchJson($this->url('assignments',$aid),['function'=>'Exterior'])->assertOk();
        $this->postJson($this->url('orders',$id).'/transition',['to_status'=>'EN_PROCESO','expected_version'=>1])->assertStatus(409);
        $this->postJson($this->url('orders',$id).'/transition',['to_status'=>'EN_PROCESO','expected_version'=>2])->assertOk()->assertJsonPath('data.status','EN_PROCESO');
        $this->deleteJson('/api/v1/companies/1/vehicles/1')->assertStatus(409);
        $this->deleteJson('/api/v1/companies/1/services/1')->assertStatus(409);
        $this->deleteJson('/api/v1/companies/1/employees/1')->assertStatus(409);
        $this->postJson($this->url('orders',$id).'/transition',['to_status'=>'ENTREGADO','expected_version'=>3])->assertStatus(409);
        $this->postJson($this->url('orders',$id).'/transition',['to_status'=>'TERMINADO','expected_version'=>3])->assertOk();
        $this->postJson($this->url('orders',$id).'/transition',['to_status'=>'ENTREGADO','expected_version'=>4])->assertOk();
        $this->deleteJson($this->url('assignments',$aid))->assertOk();
        $this->assertSame(1,DB::table('wash_orders')->where('id',$id)->count());
        $this->getJson($this->url('orders',$id).'/history')->assertJsonCount(5,'data');
    }

    public function test_media_create_read_update_delete_and_private_storage(): void
    {
        $this->login();
        // El activo general ya existente debe permanecer intacto.
        $untouched = DB::table('company_media_assets')->insertGetId([
            'company_id' => 1, 'category' => 'general', 'disk' => 'public',
            'path' => 'existing/manual.png', 'is_public' => false,
            'created_at' => now(), 'updated_at' => now(),
        ]);
        $uri='/api/v1/companies/1/media/vehicles/1';
        $temp=tempnam(sys_get_temp_dir(),'mcw_photo_');
        $png=base64_decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl9PNcAAAAASUVORK5CYII=');
        file_put_contents($temp,$png);
        try {
            $file=new UploadedFile($temp,'auto.png','image/png',null,true);
            $this->post($uri,['photo'=>$file,'show_on_kiosk'=>'1'],['Accept'=>'application/json'])->assertCreated()->assertJsonPath('data.exists',true);
            $meta=$this->getJson($uri)->assertOk()->assertJsonPath('data.show_on_kiosk',true);
            $this->assertNotNull($meta->json('data.url'));
            $this->assertDatabaseHas('company_media_assets', [
                'company_id' => 1, 'category' => 'vehicle_photo', 'disk' => 'local',
                'is_public' => false,
            ]);
            $this->assertDatabaseHas('company_entity_photos', [
                'company_id' => 1, 'owner_type' => 'vehicles', 'owner_id' => 1,
                'show_on_kiosk' => true,
            ]);
            $this->get($uri.'/file')->assertOk()->assertHeader('Content-Type','image/png');
            $this->patchJson($uri,['show_on_kiosk'=>false])->assertOk()->assertJsonPath('data.show_on_kiosk',false);
            $this->deleteJson($uri)->assertOk();
            $this->get($uri.'/file')->assertNotFound();
            $this->assertDatabaseHas('company_media_assets', [
                'id' => $untouched, 'category' => 'general',
                'path' => 'existing/manual.png',
            ]);
            $this->assertSame(0, DB::table('company_entity_photos')->where('company_id', 1)->count());
        } finally { @unlink($temp); }
    }

    public function test_cross_tenant_references_and_no_mutation(): void
    {
        $this->login();
        $this->getJson($this->url('orders',null,2))->assertNotFound();
        $this->getJson('/api/v1/companies/2/media/vehicles/1')->assertNotFound();
        $this->postJson($this->url('assignments'),['order_id'=>999,'employee_id'=>1])->assertUnprocessable();
        $this->postJson($this->url('orders'),['branch_id'=>1,'vehicle_id'=>999,'service_id'=>1])->assertUnprocessable();
    }
}
