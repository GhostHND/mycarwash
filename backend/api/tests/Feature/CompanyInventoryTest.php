<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyInventoryTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Las pruebas de agenda solo se ejecutan en SQLite :memory:.');
        }
        foreach (['inventory_movement_events','inventory_movements','inventory_items','inventory_suppliers','inventory_categories','booking_events','wash_bookings','booking_blocks','staff_shift_assignments','staff_shifts',
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
        (require database_path('migrations/2026_11_16_000004_create_inventory_catalogs.php'))->up();
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

    private function login(int $userId = 1): void
    {
        Sanctum::actingAs(User::query()->findOrFail($userId));
    }

    private function url(string $resource, ?int $id = null, int $company = 1): string
    {
        return '/api/v1/companies/'.$company.'/inventory/'.$resource.($id === null ? '' : '/'.$id);
    }

    private function category(string $name='Químicos'): int
    {
        return (int)$this->postJson($this->url('categories'),['name'=>$name,'description'=>'Categoría base'])
            ->assertCreated()->json('data.id');
    }

    private function supplier(string $name='Proveedor Uno'): int
    {
        return (int)$this->postJson($this->url('suppliers'),['name'=>$name,'phone'=>'12345678'])
            ->assertCreated()->json('data.id');
    }

    private function item(?int $category = null, ?int $supplier = null, string $sku='SH-001'): int
    {
        return (int)$this->postJson($this->url('items'),['name'=>'Shampoo', 'sku'=>$sku,
            'unit'=>'litro','category_id'=>$category,'supplier_id'=>$supplier,
            'min_stock'=>'3.000','cost_price'=>'85.50','sale_price'=>'120.00'])->assertCreated()->json('data.id');
    }

    private function movement(int $item, string $kind='IN', string $quantity='10.000'): int
    {
        return (int)$this->postJson($this->url('movements'),['branch_id'=>1,'item_id'=>$item,
            'movement_type'=>$kind,'quantity'=>$quantity,'reference'=>'PRUEBA'])->assertCreated()->json('data.id');
    }

    public function test_authentication_read_only_and_tenant_scope(): void
    {
        foreach(['categories','suppliers','items','movements'] as $r) {
            $this->getJson($this->url($r))->assertUnauthorized();
        }
        $this->login(2);
        foreach(['categories','suppliers','items','movements'] as $r) {
            $this->getJson($this->url($r))->assertOk();
            $this->postJson($this->url($r),[])->assertForbidden();
        }
        $this->login();
        $this->getJson($this->url('items',null,2))->assertNotFound();
        $this->getJson($this->url('options'))->assertOk();
    }

    public function test_categories_crud_and_linked_product_protection(): void
    {
        $this->login();
        $category=$this->category();
        $this->getJson($this->url('categories',$category))->assertOk()->assertJsonPath('data.name','Químicos');
        $this->patchJson($this->url('categories',$category),['name'=>'Químicos Premium'])->assertOk()
            ->assertJsonPath('data.name','Químicos Premium');
        $this->postJson($this->url('categories'),['name'=>'Químicos Premium'])->assertUnprocessable();
        $item=$this->item($category);
        $this->deleteJson($this->url('categories',$category))->assertUnprocessable();
        $this->patchJson($this->url('categories',$category),['is_active'=>false])->assertUnprocessable();
        $this->patchJson($this->url('items',$item),['category_id'=>null])->assertOk();
        $this->deleteJson($this->url('categories',$category))->assertOk();
        $this->getJson($this->url('categories',$category))->assertNotFound();
    }

    public function test_suppliers_crud_validation_and_relationships(): void
    {
        $this->login();
        $supplier=$this->supplier();
        $this->getJson($this->url('suppliers',$supplier))->assertOk();
        $this->patchJson($this->url('suppliers',$supplier),['email'=>'compras@empresa.hn'])->assertOk()
            ->assertJsonPath('data.email','compras@empresa.hn');
        $this->postJson($this->url('suppliers'),['name'=>'Falso','email'=>'correo-malo'])->assertUnprocessable();
        $this->postJson($this->url('suppliers'),['name'=>'Proveedor Uno'])->assertUnprocessable();
        $item=$this->item(null,$supplier);
        $this->deleteJson($this->url('suppliers',$supplier))->assertUnprocessable();
        $this->patchJson($this->url('items',$item),['supplier_id'=>null])->assertOk();
        $this->deleteJson($this->url('suppliers',$supplier))->assertOk();
        $this->getJson($this->url('suppliers',$supplier))->assertNotFound();
    }

    public function test_items_crud_unique_sku_scoped_and_stock_total(): void
    {
        $this->login();
        $category=$this->category(); $supplier=$this->supplier();
        $id=$this->item($category,$supplier);
        $this->getJson($this->url('items',$id))->assertOk()->assertJsonPath('data.category_name','Químicos');
        $this->postJson($this->url('items'),['sku'=>'sh-001','name'=>'Otro','unit'=>'unidad'])->assertUnprocessable();
        $this->postJson($this->url('items'),['sku'=>'OTRO','name'=>'Otro','unit'=>'unidad','supplier_id'=>999])->assertUnprocessable();
        $this->postJson($this->url('items'),['sku'=>'OTRO','name'=>'Otro','unit'=>'unidad','category_id'=>999])->assertUnprocessable();
        $this->patchJson($this->url('items',$id),['name'=>'Shampoo premium','min_stock'=>'5.000'])->assertOk()
            ->assertJsonPath('data.name','Shampoo premium');
        $this->movement($id,'IN','7.000');
        $this->getJson($this->url('items',$id))->assertOk()->assertJsonPath('data.stock_total',7);
        $this->deleteJson($this->url('items',$id))->assertUnprocessable();
        $this->patchJson($this->url('items',$id),['is_active'=>false])->assertUnprocessable();
        $this->movement($id,'OUT','7.000');
        $this->deleteJson($this->url('items',$id))->assertOk();
        $this->getJson($this->url('items',$id))->assertNotFound();
    }

    public function test_movements_full_crud_audit_and_balance(): void
    {
        $this->login(); $item=$this->item();
        $first=$this->movement($item,'IN','10.500');
        $second=$this->movement($item,'OUT','3.250');
        $this->getJson($this->url('stock').'?branch_id=1&item_id='.$item)->assertOk()
            ->assertJsonPath('data.quantity','7.250');
        $this->patchJson($this->url('movements',$second),['quantity'=>'4.125','notes'=>'Corrección'])->assertOk()
            ->assertJsonPath('data.notes','Corrección');
        $this->getJson($this->url('stock').'?branch_id=1&item_id='.$item)->assertJsonPath('data.quantity','6.375');
        $this->getJson($this->url('movements',$second))->assertOk();
        $this->getJson($this->url('movements',$second).'/history')->assertOk()->assertJsonCount(2,'data');
        $this->deleteJson($this->url('movements',$first))->assertUnprocessable();
        $this->deleteJson($this->url('movements',$second))->assertOk();
        $this->getJson($this->url('movements',$second))->assertNotFound();
        $this->getJson($this->url('movements',$second).'/history')->assertJsonCount(3,'data');
        $this->getJson($this->url('stock').'?branch_id=1&item_id='.$item)->assertJsonPath('data.quantity','10.500');
        $this->deleteJson($this->url('movements',$first))->assertOk();
        $this->getJson($this->url('stock').'?branch_id=1&item_id='.$item)->assertJsonPath('data.quantity','0.000');
    }

    public function test_out_of_stock_and_cross_company_references_are_rejected(): void
    {
        $this->login();$item=$this->item();
        $this->postJson($this->url('movements'),['branch_id'=>1,'item_id'=>$item,'movement_type'=>'OUT','quantity'=>'1.000'])
            ->assertUnprocessable();
        $this->postJson($this->url('movements'),['branch_id'=>2,'item_id'=>$item,'movement_type'=>'IN','quantity'=>'1.000'])
            ->assertUnprocessable();
        $this->postJson($this->url('movements'),['branch_id'=>1,'item_id'=>888,'movement_type'=>'IN','quantity'=>'1.000'])
            ->assertUnprocessable();
        $this->postJson($this->url('movements'),['branch_id'=>1,'item_id'=>$item,'movement_type'=>'IN','quantity'=>'1.0001'])
            ->assertUnprocessable();
        $this->movement($item,'IN','2.000');
        $this->postJson($this->url('movements'),['branch_id'=>1,'item_id'=>$item,'movement_type'=>'OUT','quantity'=>'2.001'])
            ->assertUnprocessable();
    }

    public function test_reference_items_cannot_change_on_existing_stock_entry(): void
    {
        $this->login();$item=$this->item();$other=$this->item(null,null,'SH-002');
        $id=$this->movement($item,'IN','5.000');
        $this->patchJson($this->url('movements',$id),['item_id'=>$other])->assertUnprocessable();
        $this->patchJson($this->url('movements',$id),['branch_id'=>2])->assertUnprocessable();
        $this->patchJson($this->url('movements',$id),['quantity'=>'0.001'])->assertOk();
        $this->getJson($this->url('stock').'?branch_id=1&item_id='.$item)->assertJsonPath('data.quantity','0.001');
    }
}
