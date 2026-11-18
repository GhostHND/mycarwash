<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyFinanceTransfers24K2Test extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Finanzas 24K: pruebas solamente en SQLite :memory:.');
        }
        foreach (['finance_internal_transfers_24k2','finance_bank_closings_24k','finance_bank_entries_24k','finance_bank_openings_24k',
            'sale_bank_movements','pos_sale_payments','pos_sales','cash_movements','cash_sessions',
            'cash_registers','sale_bank_accounts','user_roles','role_permission','permissions',
            'roles','company_user','companies','users'] as $table) Schema::dropIfExists($table);
        Schema::create('users', function(Blueprint $t):void{$t->id();$t->string('name');$t->string('email');$t->string('password');$t->timestamps();});
        Schema::create('companies', function(Blueprint $t):void{$t->id();$t->boolean('is_active')->default(true);});
        Schema::create('company_user', function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('user_id');$t->string('status');});
        Schema::create('roles', function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');});
        Schema::create('permissions', function(Blueprint $t):void{$t->id();$t->string('code');});
        Schema::create('role_permission', function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('role_id');$t->unsignedBigInteger('permission_id');});
        Schema::create('user_roles', function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('user_id');$t->unsignedBigInteger('role_id');});
        Schema::create('sale_bank_accounts', function(Blueprint $t):void{
            $t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('branch_id');
            $t->string('alias');$t->string('bank_name');$t->string('account_last4')->nullable();
            $t->boolean('is_active')->default(true);$t->softDeletes();
        });
        Schema::create('sale_bank_movements',function(Blueprint $t):void{
            $t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('bank_account_id');
            $t->decimal('amount',14,2);$t->timestamp('posted_at');
        });
        Schema::create('pos_sales',function(Blueprint $t):void{
            $t->id();$t->unsignedBigInteger('company_id');$t->string('status');
        });
        Schema::create('pos_sale_payments',function(Blueprint $t):void{
            $t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('sale_id');
            $t->unsignedBigInteger('bank_account_id')->nullable();$t->decimal('amount',14,2);
            $t->timestamp('posted_at');
        });
        Schema::create('cash_registers',function(Blueprint $t):void{
            $t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('branch_id');
            $t->string('code');$t->string('name');$t->boolean('is_active');$t->softDeletes();
        });
        Schema::create('cash_sessions',function(Blueprint $t):void{
            $t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('register_id');
            $t->string('status');$t->decimal('opening_cash',14,2);
            $t->decimal('expected_cash',14,2)->nullable();$t->decimal('counted_cash',14,2)->nullable();
            $t->decimal('difference_cash',14,2)->nullable();$t->timestamp('closed_at')->nullable();$t->softDeletes();
        });
        Schema::create('cash_movements',function(Blueprint $t):void{
            $t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('session_id');
            $t->string('direction');$t->decimal('amount',14,2);$t->timestamps();$t->softDeletes();
        });
        (require database_path('migrations/2026_11_18_235959_create_finance_bank_controls_24k.php'))->up();
        (require database_path('migrations/2026_11_19_000001_create_finance_internal_transfers_24k2.php'))->up();
        DB::table('users')->insert([['id'=>1,'name'=>'Admin','email'=>'a@example.test','password'=>'x'],
            ['id'=>2,'name'=>'Reader','email'=>'b@example.test','password'=>'x']]);
        DB::table('companies')->insert([['id'=>1,'is_active'=>true],['id'=>2,'is_active'=>true]]);
        DB::table('company_user')->insert([['company_id'=>1,'user_id'=>1,'status'=>'active'],
            ['company_id'=>1,'user_id'=>2,'status'=>'active']]);
        DB::table('roles')->insert([['id'=>1,'company_id'=>1],['id'=>2,'company_id'=>1]]);
        DB::table('permissions')->insert([['id'=>1,'code'=>'company.view'],['id'=>2,'code'=>'company.update']]);
        DB::table('role_permission')->insert([['role_id'=>1,'permission_id'=>1],['role_id'=>1,'permission_id'=>2],
            ['role_id'=>2,'permission_id'=>1]]);
        DB::table('user_roles')->insert([['user_id'=>1,'company_id'=>1,'role_id'=>1],
            ['user_id'=>2,'company_id'=>1,'role_id'=>2]]);
        DB::table('sale_bank_accounts')->insert([
            ['id'=>10,'company_id'=>1,'branch_id'=>1,'alias'=>'Cuenta principal','bank_name'=>'BAC','is_active'=>true],
            ['id'=>20,'company_id'=>2,'branch_id'=>2,'alias'=>'Ajena','bank_name'=>'Banco B','is_active'=>true],
        ]);
    }

    private function login(int $id=1): void {Sanctum::actingAs(User::query()->findOrFail($id));}
    private function url(string $path): string {return '/api/v1/companies/1/finance'.$path;}

    public function test_transfers_affect_balances_but_never_sales_or_expenses(): void
    {
        $this->login();
        $today=now('America/Tegucigalpa')->format('Y-m-d');
        $yesterday=now('America/Tegucigalpa')->subDay()->format('Y-m-d');
        DB::table('cash_registers')->insert([
            'id'=>7,'company_id'=>1,'branch_id'=>1,'code'=>'CX1','name'=>'Caja principal','is_active'=>true,
        ]);
        DB::table('cash_sessions')->insert([
            'id'=>30,'company_id'=>1,'register_id'=>7,'status'=>'OPEN','opening_cash'=>'300.00',
        ]);
        $this->postJson($this->url('/banks/10/initialize'),[
            'opening_balance'=>'1000.00','effective_date'=>$yesterday,
        ])->assertCreated();
        $first=['direction'=>'BANK_TO_CASH','bank_account_id'=>10,'cash_session_id'=>30,
            'amount'=>'200.00','reference'=>'RET1','notes'=>'Dinero para caja',
            'idempotency_key'=>'tr24k2-first-test-unique-00001'];
        $this->postJson($this->url('/transfers'),$first)->assertCreated()
            ->assertJsonPath('data.replayed',false);
        $this->postJson($this->url('/transfers'),$first)->assertOk()
            ->assertJsonPath('data.replayed',true);
        $this->assertSame(1,DB::table('finance_internal_transfers_24k2')->count());
        $this->assertSame(0,DB::table('cash_movements')->count());
        $this->assertSame(0,DB::table('finance_bank_entries_24k')->count());
        $this->getJson($this->url('/overview?period=day&date='.$today))->assertOk()
            ->assertJsonPath('data.totals.cash_in','0.00')
            ->assertJsonPath('data.totals.cash_out','0.00')
            ->assertJsonPath('data.totals.bank_in','0.00')
            ->assertJsonPath('data.totals.bank_out','0.00')
            ->assertJsonPath('data.cash.0.expected_current','500.00')
            ->assertJsonPath('data.cash.0.transfer_in','200.00')
            ->assertJsonPath('data.banks.0.estimated_balance','800.00')
            ->assertJsonPath('data.banks.0.transfer_out','200.00');
        $second=[...$first,'direction'=>'CASH_TO_BANK','amount'=>'100.00',
            'idempotency_key'=>'tr24k2-second-test-unique-0002'];
        $this->postJson($this->url('/transfers'),$second)->assertCreated();
        $this->getJson($this->url('/overview?period=day&date='.$today))->assertOk()
            ->assertJsonPath('data.cash.0.expected_current','400.00')
            ->assertJsonPath('data.cash.0.transfer_out','100.00')
            ->assertJsonPath('data.banks.0.estimated_balance','900.00')
            ->assertJsonPath('data.banks.0.transfer_in','100.00');
        $this->getJson($this->url('/transfers'))->assertOk()->assertJsonCount(2,'data');
        $this->postJson($this->url('/transfers'),[...$first,'amount'=>'99999.00',
            'idempotency_key'=>'tr24k2-insufficient-00000003'])->assertUnprocessable();
        $this->assertSame(2,DB::table('finance_internal_transfers_24k2')->count());
    }

    public function test_transfers_reject_other_company_closed_cash_and_reader_permission(): void
    {
        $this->login(2);
        $this->postJson($this->url('/transfers'),[])->assertForbidden();
        $this->login();
        $day=now('America/Tegucigalpa')->format('Y-m-d');
        DB::table('cash_registers')->insert([
            'id'=>7,'company_id'=>1,'branch_id'=>1,'code'=>'CX1','name'=>'Caja principal','is_active'=>true,
        ]);
        DB::table('cash_sessions')->insert([
            'id'=>30,'company_id'=>1,'register_id'=>7,'status'=>'CLOSED','opening_cash'=>'300.00',
        ]);
        $this->postJson($this->url('/banks/10/initialize'),[
            'opening_balance'=>'1000.00','effective_date'=>$day,
        ])->assertCreated();
        $data=['direction'=>'BANK_TO_CASH','bank_account_id'=>10,'cash_session_id'=>30,
            'amount'=>'50.00','idempotency_key'=>'tr24k2-closed-test-unique-00004'];
        $this->postJson($this->url('/transfers'),$data)->assertUnprocessable();
        DB::table('cash_sessions')->where('id',30)->update(['status'=>'OPEN']);
        $this->postJson($this->url('/transfers'),[...$data,'bank_account_id'=>20])->assertNotFound();
        $this->assertSame(0,DB::table('finance_internal_transfers_24k2')->count());
    }
}
