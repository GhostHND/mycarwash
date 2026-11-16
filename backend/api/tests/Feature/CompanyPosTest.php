<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyPosTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('POS tests: únicamente SQLite :memory:.');
        }
        foreach ([
            'pos_sale_payments', 'pos_sale_items', 'pos_sales', 'cash_movement_events',
            'sale_bank_movements', 'cash_movements', 'wash_order_payments', 'wash_order_discounts',
            'sale_payment_methods', 'sale_bank_accounts', 'inventory_movement_events',
            'inventory_movements', 'inventory_items', 'inventory_categories', 'inventory_suppliers',
            'cash_sessions', 'cash_expense_categories', 'cash_registers', 'wash_order_events',
            'company_entity_photos', 'company_media_assets', 'wash_assignments', 'wash_orders',
            'wash_bays', 'wash_services', 'employees', 'vehicles', 'clients', 'branches',
            'user_roles', 'role_permission', 'permissions', 'roles', 'company_user', 'companies', 'users',
        ] as $table) Schema::dropIfExists($table);
        Schema::create('users', fn (Blueprint $t) => [ $t->id(), $t->string('name'), $t->string('email'), $t->string('password'), $t->timestamps() ]);
        Schema::create('companies', fn (Blueprint $t) => [ $t->id(), $t->string('name'), $t->boolean('is_active')->default(true), $t->timestamps() ]);
        Schema::create('branches', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name'); $t->boolean('is_active')->default(true);
            $t->string('timezone')->default('America/Tegucigalpa'); $t->unique(['id', 'company_id']);
        });
        Schema::create('company_user', fn (Blueprint $t) => [ $t->id(), $t->unsignedBigInteger('company_id'), $t->unsignedBigInteger('user_id'), $t->string('status'), $t->timestamps() ]);
        Schema::create('roles', fn (Blueprint $t) => [ $t->id(), $t->unsignedBigInteger('company_id'), $t->string('name'), $t->string('code'), $t->timestamps() ]);
        Schema::create('permissions', fn (Blueprint $t) => [ $t->id(), $t->string('code'), $t->string('module'), $t->timestamps() ]);
        Schema::create('role_permission', fn (Blueprint $t) => [ $t->id(), $t->unsignedBigInteger('role_id'), $t->unsignedBigInteger('permission_id'), $t->timestamps() ]);
        Schema::create('user_roles', fn (Blueprint $t) => [ $t->id(), $t->unsignedBigInteger('company_id'), $t->unsignedBigInteger('user_id'), $t->unsignedBigInteger('role_id'), $t->timestamps() ]);
        (require database_path('migrations/2026_11_16_000001_create_operations_catalogs.php'))->up();
        Schema::create('company_media_assets', function (Blueprint $t): void {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('path', 600);
        });
        (require database_path('migrations/2026_11_16_000002_create_wash_workflow.php'))->up();
        (require database_path('migrations/2026_11_16_000004_create_inventory_catalogs.php'))->up();
        (require database_path('migrations/2026_11_16_000005_create_cash_management.php'))->up();
        (require database_path('migrations/2026_11_16_000006_create_wash_sales.php'))->up();
        (require database_path('migrations/2026_11_16_000007_create_pos_sales.php'))->up();
        DB::table('users')->insert([['id'=>1,'name'=>'Administrador','email'=>'adm@test.invalid','password'=>'x'],
            ['id'=>2,'name'=>'Lector','email'=>'ver@test.invalid','password'=>'x']]);
        DB::table('companies')->insert([['id'=>1,'name'=>'Negocio A'], ['id'=>2,'name'=>'Negocio B']]);
        DB::table('branches')->insert([['id'=>1,'company_id'=>1,'name'=>'Principal'], ['id'=>2,'company_id'=>2,'name'=>'Ajena']]);
        DB::table('company_user')->insert([['company_id'=>1,'user_id'=>1,'status'=>'active'], ['company_id'=>1,'user_id'=>2,'status'=>'active']]);
        DB::table('roles')->insert([['id'=>1,'company_id'=>1,'name'=>'Admin','code'=>'admin'], ['id'=>2,'company_id'=>1,'name'=>'Lector','code'=>'reader']]);
        DB::table('permissions')->insert([['id'=>1,'code'=>'company.view','module'=>'company'], ['id'=>2,'code'=>'company.update','module'=>'company']]);
        DB::table('role_permission')->insert([['role_id'=>1,'permission_id'=>1], ['role_id'=>1,'permission_id'=>2], ['role_id'=>2,'permission_id'=>1]]);
        DB::table('user_roles')->insert([['company_id'=>1,'user_id'=>1,'role_id'=>1], ['company_id'=>1,'user_id'=>2,'role_id'=>2]]);
        DB::table('cash_registers')->insert(['id'=>1,'company_id'=>1,'branch_id'=>1,'code'=>'C1','name'=>'Caja', 'is_active'=>true, 'created_at'=>now(),'updated_at'=>now()]);
        DB::table('cash_sessions')->insert(['id'=>1,'company_id'=>1,'register_id'=>1,'open_register_id'=>1,
            'status'=>'OPEN','opening_cash'=>'100.00','opened_by'=>1,'opened_at'=>now(),'created_at'=>now(),'updated_at'=>now()]);
        DB::table('sale_bank_accounts')->insert(['id'=>1,'company_id'=>1,'branch_id'=>1,'alias'=>'Banco','bank_name'=>'Demo',
            'currency'=>'HNL','is_active'=>true,'created_at'=>now(),'updated_at'=>now()]);
        DB::table('sale_payment_methods')->insert([
            ['id'=>1,'company_id'=>1,'name'=>'Efectivo','channel'=>'CASH','is_active'=>true,'created_at'=>now(),'updated_at'=>now()],
            ['id'=>2,'company_id'=>1,'name'=>'Transferencia','channel'=>'BANK','is_active'=>true,'created_at'=>now(),'updated_at'=>now()],
        ]);
        DB::table('inventory_items')->insert([
            'id'=>1,'company_id'=>1,'name'=>'Aromatizante','sku'=>'ARO-01','unit'=>'unidad',
            'sale_price'=>'150.00','cost_price'=>'50.00','is_active'=>true,
            'created_at'=>now(),'updated_at'=>now(),
        ]);
        DB::table('inventory_movements')->insert([
            'company_id'=>1,'branch_id'=>1,'item_id'=>1,'movement_type'=>'IN','quantity'=>'5.000',
            'reference'=>'TEST-IN','actor_user_id'=>1,'created_at'=>now(),'updated_at'=>now(),
        ]);
    }

    private function login(int $userId = 1): void { Sanctum::actingAs(User::query()->findOrFail($userId)); }
    private function url(string $path = ''): string { return '/api/v1/companies/1/pos'.$path; }
    private function sale(string $key = 'pos-unique-test-20261116', int $quantity = 2): array
    {
        return [
            'branch_id' => 1, 'idempotency_key' => $key,
            'lines' => [['item_id'=>1,'quantity'=>$quantity]],
            'discount_amount' => '50.00', 'discount_reason' => 'Cliente frecuente',
            'payments' => [['payment_method_id'=>1,'cash_session_id'=>1,'amount'=>'150.00'],
                ['payment_method_id'=>2,'bank_account_id'=>1,'amount'=>'100.00','reference'=>'TR-001']],
        ];
    }

    public function test_auth_permissions_and_catalog(): void
    {
        $this->getJson($this->url('/options'))->assertUnauthorized();
        $this->login(2);
        $this->getJson($this->url('/options'))->assertOk();
        $this->getJson($this->url('/products?branch_id=1&q=ARO'))->assertOk()
            ->assertJsonPath('data.0.stock', '5.000');
        $this->postJson($this->url('/sales'), $this->sale())->assertForbidden();
        $this->login();
        $this->getJson('/api/v1/companies/2/pos/options')->assertNotFound();
        $this->getJson($this->url('/products?branch_id=2'))->assertUnprocessable();
    }

    public function test_sale_split_discount_stock_and_cash_immutable(): void
    {
        $this->login();
        $response = $this->postJson($this->url('/sales'), $this->sale())->assertCreated()
            ->assertJsonPath('data.total', '250.00')->assertJsonPath('data.discount_amount','50.00');
        $id = $response->json('data.id');
        $this->getJson($this->url('/sales/'.$id))->assertOk()->assertJsonCount(2,'data.payments');
        $this->assertDatabaseHas('pos_sales', ['id'=>$id,'company_id'=>1,'status'=>'POSTED','total'=>250]);
        $this->assertDatabaseHas('pos_sale_payments', ['sale_id'=>$id,'channel'=>'BANK','amount'=>100]);
        $this->assertDatabaseHas('cash_movements', ['direction'=>'IN','amount'=>150]);
        $this->assertDatabaseHas('inventory_movements', ['reference'=>'POS-'.$id,'movement_type'=>'OUT','quantity'=>2]);
        $this->getJson($this->url('/products?branch_id=1'))->assertJsonPath('data.0.stock','3.000');
        $cashMovement = DB::table('cash_movements')->whereNotNull('source_pos_payment_id')->value('id');
        $stockMovement = DB::table('inventory_movements')->whereNotNull('source_pos_sale_item_id')->value('id');
        $this->patchJson('/api/v1/companies/1/cash/movements/'.$cashMovement, ['amount'=>'1.00'])->assertUnprocessable();
        $this->deleteJson('/api/v1/companies/1/inventory/movements/'.$stockMovement)->assertUnprocessable();
        $this->getJson('/api/v1/companies/1/sales/banks/1')->assertJsonPath('data.received_total','100.00');
    }

    public function test_idempotency_stock_and_payment_validation(): void
    {
        $this->login();
        $data = $this->sale();
        $this->postJson($this->url('/sales'), $data)->assertCreated();
        $this->postJson($this->url('/sales'), $data)->assertOk()->assertJsonPath('replayed',true);
        $this->assertSame(1, DB::table('pos_sales')->count());
        $this->assertSame(1, DB::table('cash_movements')->count());
        $different = $data;
        $different['discount_reason'] = 'Cambiado';
        $this->postJson($this->url('/sales'), $different)->assertStatus(409);
        $this->postJson($this->url('/sales'), $this->sale('pos-another-test-20261116', 4))->assertUnprocessable();
        $this->assertSame(1, DB::table('pos_sales')->count());
        $this->assertSame(1, DB::table('cash_movements')->count());
        $wrong = $this->sale('pos-third-test-20261116');
        $wrong['payments'][1]['bank_account_id'] = 999;
        $this->postJson($this->url('/sales'), $wrong)->assertUnprocessable();
        $this->assertSame(1, DB::table('pos_sales')->count());
    }
}
