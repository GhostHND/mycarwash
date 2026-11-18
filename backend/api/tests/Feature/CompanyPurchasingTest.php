<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

final class CompanyPurchasingTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Las pruebas de compras solo pueden ejecutarse en SQLite :memory:.');
        }
        Schema::disableForeignKeyConstraints();
        foreach (['purchase_receipt_lines','purchase_receipts','purchase_order_lines','purchase_orders',
            'inventory_movement_events','inventory_movements','inventory_items','inventory_suppliers',
            'inventory_categories','user_roles','role_permission','permissions','roles',
            'company_user','branches','companies','users'] as $table) Schema::dropIfExists($table);
        Schema::enableForeignKeyConstraints();
        Schema::create('users', function(Blueprint $t): void { $t->id(); $t->string('name'); $t->string('email'); $t->string('password'); $t->timestamps(); });
        Schema::create('companies', function(Blueprint $t): void { $t->id(); $t->string('name'); $t->boolean('is_active')->default(true); $t->timestamps(); });
        Schema::create('branches',function(Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name'); $t->boolean('is_active')->default(true); $t->unique(['id','company_id']); });
        Schema::create('company_user',function(Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id'); $t->string('status'); $t->timestamps(); });
        Schema::create('roles',function(Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name'); $t->string('code'); $t->timestamps(); });
        Schema::create('permissions',function(Blueprint $t): void { $t->id(); $t->string('code'); $t->string('module'); $t->timestamps(); });
        Schema::create('role_permission',function(Blueprint $t): void { $t->id(); $t->unsignedBigInteger('role_id'); $t->unsignedBigInteger('permission_id'); $t->timestamps(); });
        Schema::create('user_roles',function(Blueprint $t): void { $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id'); $t->unsignedBigInteger('role_id'); $t->timestamps(); });
        (require database_path('migrations/2026_11_16_000004_create_inventory_catalogs.php'))->up();
        (require database_path('migrations/2026_11_18_000001_create_purchase_orders_and_receipts.php'))->up();
        DB::table('users')->insert([
            ['id'=>1,'name'=>'Admin','email'=>'admin@test.com','password'=>'x'],
            ['id'=>2,'name'=>'Reader','email'=>'reader@test.com','password'=>'x'],
        ]);
        DB::table('companies')->insert([['id'=>1,'name'=>'A'],['id'=>2,'name'=>'B']]);
        DB::table('branches')->insert([['id'=>1,'company_id'=>1,'name'=>'Principal'],['id'=>2,'company_id'=>2,'name'=>'Extranjera']]);
        DB::table('company_user')->insert([['company_id'=>1,'user_id'=>1,'status'=>'active'],['company_id'=>1,'user_id'=>2,'status'=>'active']]);
        DB::table('roles')->insert([['id'=>1,'company_id'=>1,'name'=>'Admin','code'=>'admin'],['id'=>2,'company_id'=>1,'name'=>'Lector','code'=>'reader']]);
        DB::table('permissions')->insert([['id'=>1,'code'=>'company.view','module'=>'company'],['id'=>2,'code'=>'company.update','module'=>'company']]);
        DB::table('role_permission')->insert([['role_id'=>1,'permission_id'=>1],['role_id'=>1,'permission_id'=>2],['role_id'=>2,'permission_id'=>1]]);
        DB::table('user_roles')->insert([['company_id'=>1,'user_id'=>1,'role_id'=>1],['company_id'=>1,'user_id'=>2,'role_id'=>2]]);
        DB::table('inventory_suppliers')->insert([
            ['id'=>10,'company_id'=>1,'name'=>'Proveedor Uno','is_active'=>true],
            ['id'=>20,'company_id'=>2,'name'=>'Proveedor Extranjero','is_active'=>true],
        ]);
        DB::table('inventory_items')->insert([
            ['id'=>7,'company_id'=>1,'sku'=>'FIL-01','name'=>'Filtro','unit'=>'unidad','is_active'=>true,'cost_price'=>'35.00'],
            ['id'=>8,'company_id'=>1,'sku'=>'ARO-01','name'=>'Aromatizante','unit'=>'unidad','is_active'=>true,'cost_price'=>'50.00'],
            ['id'=>9,'company_id'=>2,'sku'=>'OTRO','name'=>'Ajeno','unit'=>'unidad','is_active'=>true,'cost_price'=>'5.00'],
        ]);
    }
    private function login(int $id=1): void { Sanctum::actingAs(User::query()->findOrFail($id)); }
    private function path(string $part=''): string { return '/api/v1/companies/1/purchasing/'.$part; }
    private function create(): int
    {
        return (int)$this->postJson($this->path('orders'),[
            'branch_id'=>1,'supplier_id'=>10,
            'lines'=>[['item_id'=>7,'quantity'=>'5.000','unit_cost'=>'35.00'],
                ['item_id'=>8,'quantity'=>'2.000','unit_cost'=>'50.00']],
        ])->assertCreated()->assertJsonPath('data.order.total','275.00')
            ->assertJsonPath('data.order.status','ORDERED')->json('data.order.id');
    }
    public function test_authorization_supplier_branch_and_item_isolation(): void
    {
        $this->getJson($this->path('orders'))->assertUnauthorized();
        $this->login(2);
        $this->getJson($this->path('orders'))->assertOk();
        $this->postJson($this->path('orders'),[])->assertForbidden();
        $this->login(1);
        $this->getJson('/api/v1/companies/2/purchasing/orders')->assertNotFound();
        foreach([['branch_id'=>2,'supplier_id'=>10,'item_id'=>7],
            ['branch_id'=>1,'supplier_id'=>20,'item_id'=>7],
            ['branch_id'=>1,'supplier_id'=>10,'item_id'=>9]] as $case) {
            $this->postJson($this->path('orders'),['branch_id'=>$case['branch_id'],
                'supplier_id'=>$case['supplier_id'],
                'lines'=>[['item_id'=>$case['item_id'],'quantity'=>'2.000','unit_cost'=>'5.00']]])
                ->assertUnprocessable();
        }
    }
    public function test_partial_receipts_inventory_events_and_idempotency(): void
    {
        $this->login();
        $id=$this->create();
        // El API debe serializar decimales de manera estable con SQLite y MySQL.
        $this->getJson($this->path('orders'))->assertOk()
            ->assertJsonPath('data.0.total','275.00');
        $this->getJson($this->path('orders/'.$id))->assertOk()
            ->assertJsonPath('data.order.total','275.00')
            ->assertJsonPath('data.lines.0.ordered_quantity','5.000')
            ->assertJsonPath('data.lines.0.received_quantity','0.000')
            ->assertJsonPath('data.lines.0.unit_cost','35.00')
            ->assertJsonPath('data.lines.0.line_total','175.00');
        $this->assertDatabaseCount('inventory_movements',0);
        $line=(int)DB::table('purchase_order_lines')->where('order_id',$id)->where('item_id',7)->value('id');
        $other=(int)DB::table('purchase_order_lines')->where('order_id',$id)->where('item_id',8)->value('id');
        $body=['idempotency_key'=>'test-receipt-idem-0000001','lines'=>[['order_line_id'=>$line,'quantity'=>'2.500']]];
        $first=$this->postJson($this->path('orders/'.$id.'/receive'),$body)->assertOk()
            ->assertJsonPath('data.order.order.status','PARTIAL')
            ->assertJsonPath('data.order.lines.0.received_quantity','2.500')
            ->json('data.receipt_id');
        $this->postJson($this->path('orders/'.$id.'/receive'),$body)->assertOk()
            ->assertJsonPath('data.receipt_id',$first);
        $this->assertDatabaseCount('inventory_movements',1);
        $this->assertDatabaseCount('inventory_movement_events',1);
        $this->assertEquals(2.5,(float) DB::table('inventory_movements')
            ->where('company_id',1)->where('branch_id',1)->where('item_id',7)
            ->where('movement_type','IN')->value('quantity'));
        $this->postJson($this->path('orders/'.$id.'/receive'),['idempotency_key'=>'test-receipt-idem-0000002',
            'lines'=>[['order_line_id'=>$line,'quantity'=>'3.000']]])->assertUnprocessable();
        $this->postJson($this->path('orders/'.$id.'/receive'),['idempotency_key'=>'test-receipt-idem-0000003',
            'lines'=>[['order_line_id'=>$line,'quantity'=>'2.500'],['order_line_id'=>$other,'quantity'=>'2.000']]])
            ->assertOk()->assertJsonPath('data.order.order.status','RECEIVED');
        $this->assertDatabaseCount('inventory_movements',3);
        $this->assertDatabaseCount('purchase_receipts',2);
        $this->postJson($this->path('orders/'.$id.'/receive'),['idempotency_key'=>'test-receipt-idem-0000004',
            'lines'=>[['order_line_id'=>$line,'quantity'=>'0.500']]])->assertStatus(409);
    }
    public function test_cancellation_is_safe_and_receipts_cannot_be_deleted(): void
    {
        $this->login();
        $id=$this->create();
        $this->postJson($this->path('orders/'.$id.'/cancel'))->assertOk()
            ->assertJsonPath('data.order.status','CANCELLED');
        $line=(int)DB::table('purchase_order_lines')->where('order_id',$id)->value('id');
        $this->postJson($this->path('orders/'.$id.'/receive'),[
            'idempotency_key'=>'test-receipt-idem-0000005',
            'lines'=>[['order_line_id'=>$line,'quantity'=>'1.000']]])->assertStatus(409);
        $this->assertDatabaseCount('inventory_movements',0);
    }
}
