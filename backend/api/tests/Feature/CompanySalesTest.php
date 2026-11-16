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

class CompanySalesTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Solo SQLite :memory:.');
        }
        // Orden inverso de dependencias: nunca se toca la BD real, solo SQLite :memory:.
        foreach ([
            'cash_movement_events', 'sale_bank_movements', 'cash_movements', 'wash_order_payments',
            'wash_order_discounts', 'sale_payment_methods', 'sale_bank_accounts',
            'booking_events', 'wash_bookings', 'booking_blocks', 'staff_shift_assignments', 'staff_shifts',
            'inventory_movement_events', 'inventory_movements', 'inventory_items',
            'inventory_suppliers', 'inventory_categories', 'cash_sessions',
            'cash_expense_categories', 'cash_registers', 'wash_order_events',
            'company_entity_photos', 'company_media_assets', 'wash_assignments', 'wash_orders', 'wash_bays',
            'wash_services', 'employees', 'vehicles', 'clients', 'branches', 'user_roles', 'role_permission',
            'permissions', 'roles', 'company_user', 'companies', 'users',
        ] as $table) Schema::dropIfExists($table);
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
        (require database_path('migrations/2026_11_16_000005_create_cash_management.php'))->up();
        (require database_path('migrations/2026_11_16_000006_create_wash_sales.php'))->up();
        DB::table('wash_services')->where('id', 1)->update(['price' => '350.00']);
        DB::table('cash_registers')->insert([
            'id'=>1,'company_id'=>1,'branch_id'=>1,'code'=>'CAJA1','name'=>'Caja principal',
            'currency'=>'HNL','is_active'=>true,'created_at'=>now(),'updated_at'=>now(),
        ]);
        DB::table('cash_sessions')->insert([
            'id'=>1,'company_id'=>1,'register_id'=>1,'open_register_id'=>1,'opened_by'=>1,
            'status'=>'OPEN','opening_cash'=>'100.00','opened_at'=>now(),'created_at'=>now(),'updated_at'=>now(),
        ]);
        DB::table('sale_bank_accounts')->insert([
            'id'=>1,'company_id'=>1,'branch_id'=>1,'alias'=>'Cuenta principal','bank_name'=>'Banco Demo',
            'currency'=>'HNL','is_active'=>true,'created_at'=>now(),'updated_at'=>now(),
        ]);
        DB::table('sale_payment_methods')->insert([
            ['id'=>1,'company_id'=>1,'name'=>'Efectivo','channel'=>'CASH','is_active'=>true,'created_at'=>now(),'updated_at'=>now()],
            ['id'=>2,'company_id'=>1,'name'=>'Transferencia','channel'=>'BANK','is_active'=>true,'created_at'=>now(),'updated_at'=>now()],
        ]);
        
    }

    private function login(int $id = 1): void { Sanctum::actingAs(User::query()->findOrFail($id)); }
    private function url(string $resource, ?int $id = null, int $company = 1): string
    { return '/api/v1/companies/'.$company.'/sales/'.$resource.($id === null ? '' : '/'.$id); }
    private function ready(): array
    {
        $order=$this->postJson('/api/v1/companies/1/workflow/orders', [
            'branch_id'=>1,'vehicle_id'=>1,'service_id'=>1,
        ])->assertCreated()->json('data');
        $id=$order['id'];
        $this->postJson('/api/v1/companies/1/workflow/assignments', [
            'order_id'=>$id,'employee_id'=>1,
        ])->assertCreated();
        $this->postJson('/api/v1/companies/1/workflow/orders/'.$id.'/transition', [
            'to_status'=>'EN_PROCESO','expected_version'=>2,
        ])->assertOk();
        $this->postJson('/api/v1/companies/1/workflow/orders/'.$id.'/transition', [
            'to_status'=>'TERMINADO','expected_version'=>3,
        ])->assertOk();
        return ['id'=>$id,'version'=>4];
    }

    public function test_permissions_and_four_crud_catalogs(): void
    {
        foreach (['banks','methods','discounts','payments'] as $resource) {
            $this->getJson($this->url($resource))->assertUnauthorized();
        }
        $this->login(2);
        foreach (['banks','methods','discounts','payments'] as $resource) {
            $this->getJson($this->url($resource))->assertOk();
            $this->postJson($this->url($resource), [])->assertForbidden();
        }
        $this->login();
        $bank=$this->postJson($this->url('banks'), [
            'branch_id'=>1,'alias'=>'Ahorros','bank_name'=>'Banco Dos','account_last4'=>'1234',
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('banks',$bank), ['alias'=>'Cuenta ventas'])->assertOk()
            ->assertJsonPath('data.alias','Cuenta ventas');
        $this->getJson($this->url('banks',$bank))->assertOk();
        $this->deleteJson($this->url('banks',$bank))->assertOk();
        $this->getJson($this->url('banks',$bank))->assertNotFound();
        $method=$this->postJson($this->url('methods'), [
            'name'=>'Depósito','channel'=>'BANK',
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('methods',$method), ['name'=>'Depósito bancario'])->assertOk();
        $this->getJson($this->url('methods',$method))->assertOk();
        $this->deleteJson($this->url('methods',$method))->assertOk();
        $this->getJson($this->url('methods',$method))->assertNotFound();
        $this->getJson($this->url('banks',null,2))->assertNotFound();
    }

    public function test_discount_exact_value_cash_checkout_once(): void
    {
        $this->login(); $o=$this->ready();
        $id=$o['id'];
        $discount=$this->postJson($this->url('discounts'), [
            'order_id'=>$id,'amount'=>'100.00','reason'=>'Descuento amigo',
        ])->assertCreated()->assertJsonPath('data.amount','100.00')->json('data.id');
        $this->patchJson($this->url('discounts',$discount), [
            'reason'=>'Promoción autorizada personalmente',
        ])->assertOk();
        $this->getJson($this->url('quote',$id))->assertOk()->assertJsonPath('data.total','250.00');
        $this->postJson('/api/v1/companies/1/workflow/orders/'.$id.'/transition', [
            'to_status'=>'ENTREGADO','expected_version'=>4,
        ])->assertUnprocessable();
        $this->postJson('/api/v1/companies/1/sales/checkout/'.$id, [
            'expected_version'=>4,'payment_method_id'=>1,'cash_session_id'=>1,
        ])->assertOk()->assertJsonPath('data.status','ENTREGADO')
            ->assertJsonPath('data.total_paid','250.00');
        $this->assertDatabaseHas('wash_order_payments', ['company_id'=>1,'order_id'=>$id,'status'=>'POSTED','amount'=>250]);
        $this->assertDatabaseHas('cash_movements', ['company_id'=>1,'direction'=>'IN','amount'=>250]);
        $this->assertSame(1,DB::table('cash_movements')->where('company_id',1)->whereNotNull('source_sale_payment_id')->count());
        $this->postJson('/api/v1/companies/1/sales/checkout/'.$id, [
            'expected_version'=>4,'payment_method_id'=>1,'cash_session_id'=>1,
        ])->assertStatus(409);
        $this->assertSame(1,DB::table('cash_movements')->where('company_id',1)->whereNotNull('source_sale_payment_id')->count());
        $movement=DB::table('cash_movements')->whereNotNull('source_sale_payment_id')->value('id');
        $this->patchJson('/api/v1/companies/1/cash/movements/'.$movement,['amount'=>'10.00'])->assertUnprocessable();
        $this->deleteJson('/api/v1/companies/1/cash/movements/'.$movement)->assertUnprocessable();
        $this->patchJson($this->url('discounts',$discount),['amount'=>'10.00'])->assertUnprocessable();
    }

    public function test_bank_receipt_does_not_increase_cash_and_can_split(): void
    {
        $this->login(); $o=$this->ready(); $id=$o['id'];
        $p1=$this->postJson($this->url('payments'), [
            'order_id'=>$id,'payment_method_id'=>1,'cash_session_id'=>1,'amount'=>'150.00',
        ])->assertCreated()->json('data.id');
        $p2=$this->postJson($this->url('payments'), [
            'order_id'=>$id,'payment_method_id'=>2,'bank_account_id'=>1,'amount'=>'200.00',
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('payments',$p2), ['reference'=>'TR-2026'])->assertOk();
        $this->postJson('/api/v1/companies/1/sales/checkout/'.$id, ['expected_version'=>4])
            ->assertOk()->assertJsonPath('data.payments_count',2);
        $this->assertDatabaseHas('cash_movements', ['source_sale_payment_id'=>$p1,'amount'=>150]);
        $this->assertDatabaseHas('sale_bank_movements', ['payment_id'=>$p2,'amount'=>200]);
        $this->assertSame(1,DB::table('sale_bank_movements')->where('company_id',1)->count());
        $this->getJson($this->url('banks',1))->assertOk()->assertJsonPath('data.received_total','200.00');
        $this->deleteJson($this->url('payments',$p2))->assertUnprocessable();
    }

    public function test_payment_pending_can_update_and_delete_and_reject_wrong_branch(): void
    {
        $this->login(); $o=$this->ready(); $id=$o['id'];
        $this->postJson($this->url('payments'), [
            'order_id'=>$id,'payment_method_id'=>2,'bank_account_id'=>999,'amount'=>'80.00',
        ])->assertUnprocessable();
        $p=$this->postJson($this->url('payments'), [
            'order_id'=>$id,'payment_method_id'=>1,'cash_session_id'=>1,'amount'=>'150.00',
        ])->assertCreated()->json('data.id');
        $this->patchJson($this->url('payments',$p), ['amount'=>'175.00'])->assertOk();
        $this->getJson($this->url('payments',$p))->assertOk()->assertJsonPath('data.amount','175.00');
        $this->deleteJson($this->url('payments',$p))->assertOk();
        $this->getJson($this->url('payments',$p))->assertNotFound();
        $this->postJson('/api/v1/companies/1/sales/checkout/'.$id,[
            'expected_version'=>4,'discount_amount'=>'400.00','discount_reason'=>'Error',
            'payment_method_id'=>1,'cash_session_id'=>1,
        ])->assertUnprocessable();
        $this->assertDatabaseHas('wash_orders',['id'=>$id,'status'=>'TERMINADO']);
    }

    public function test_partial_checkout_rejected_and_full_courtesy(): void
    {
        $this->login(); $o=$this->ready(); $id=$o['id'];
        $this->postJson($this->url('payments'), [
            'order_id'=>$id,'payment_method_id'=>1,'cash_session_id'=>1,'amount'=>'200.00',
        ])->assertCreated();
        $this->postJson('/api/v1/companies/1/sales/checkout/'.$id,['expected_version'=>4])->assertUnprocessable();
        $this->assertDatabaseHas('wash_orders',['id'=>$id,'status'=>'TERMINADO']);
        $this->deleteJson($this->url('payments',1))->assertOk();
        $this->postJson('/api/v1/companies/1/sales/checkout/'.$id,[
            'expected_version'=>4,'discount_amount'=>'350.00','discount_reason'=>'Cortesía total autorizada',
        ])->assertOk()->assertJsonPath('data.total_paid','0.00');
        $this->assertSame(0,DB::table('cash_movements')->count());
    }
}
