<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyFinance24KTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Finanzas 24K: pruebas solamente en SQLite :memory:.');
        }
        foreach (['finance_bank_closings_24k','finance_bank_entries_24k','finance_bank_openings_24k',
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

    public function test_permission_scope_and_opening_is_immutable(): void
    {
        $this->getJson($this->url('/overview'))->assertUnauthorized();
        $this->login(2);
        $this->getJson($this->url('/overview'))->assertOk();
        $this->postJson($this->url('/banks/10/initialize'),[])->assertForbidden();
        $this->login();
        $date=now('America/Tegucigalpa')->subDay()->format('Y-m-d');
        $this->postJson($this->url('/banks/20/initialize'),['opening_balance'=>'100.00','effective_date'=>$date])->assertNotFound();
        $this->postJson($this->url('/banks/10/initialize'),['opening_balance'=>'100.00','effective_date'=>$date])->assertCreated();
        $this->postJson($this->url('/banks/10/initialize'),['opening_balance'=>'300.00','effective_date'=>$date])->assertUnprocessable();
    }

    public function test_bank_daily_close_balances_and_idempotency(): void
    {
        $this->login();
        $date=now('America/Tegucigalpa')->subDay()->format('Y-m-d');
        $this->postJson($this->url('/banks/10/initialize'),['opening_balance'=>'100.00','effective_date'=>$date])->assertCreated();
        $entry=['direction'=>'IN','amount'=>'25.00','posted_date'=>$date,
            'reference'=>'T-1','notes'=>'Ajuste verificado','idempotency_key'=>'finance-test-idempotency-00001'];
        $this->postJson($this->url('/banks/10/entries'),$entry)->assertCreated();
        $this->postJson($this->url('/banks/10/entries'),$entry)->assertCreated();
        $this->assertSame(1,DB::table('finance_bank_entries_24k')->count());
        $this->postJson($this->url('/banks/10/entries'),[...$entry,'direction'=>'OUT','amount'=>'10.00',
            'notes'=>'Gasto verificado','idempotency_key'=>'finance-test-idempotency-00002'])->assertCreated();
        $this->getJson($this->url('/overview?period=day&date='.$date))->assertOk()
            ->assertJsonPath('data.banks.0.in','25.00')
            ->assertJsonPath('data.banks.0.out','10.00')
            ->assertJsonPath('data.banks.0.estimated_balance','115.00');
        $id=$this->postJson($this->url('/banks/10/closings/open'),['period'=>'day','date'=>$date])
            ->assertCreated()->json('data.id');
        $this->postJson($this->url('/banks/10/closings/'.$id.'/close'),['counted_balance'=>'114.00'])
            ->assertOk()->assertJsonPath('data.difference','-1.00');
        $this->postJson($this->url('/banks/10/closings/'.$id.'/close'),['counted_balance'=>'114.00'])->assertUnprocessable();
        $this->postJson($this->url('/banks/10/entries'),[...$entry,'idempotency_key'=>'finance-test-idempotency-00003'])
            ->assertUnprocessable();
    }
}
