<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyCashTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::connection()->getDriverName() !== 'sqlite'
            || DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Pruebas monetarias solo autorizadas en SQLite :memory:.');
        }
        foreach (['cash_movement_events','cash_movements','cash_sessions','cash_expense_categories','cash_registers',
            'branches','user_roles','role_permission','permissions','roles','company_user','companies','users'] as $table) {
            Schema::dropIfExists($table);
        }
        Schema::create('users',function(Blueprint $t):void{$t->id();$t->string('name');$t->string('email');$t->string('password');$t->timestamps();});
        Schema::create('companies',function(Blueprint $t):void{$t->id();$t->string('name');$t->boolean('is_active')->default(true);$t->timestamps();});
        Schema::create('branches',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->string('name');$t->boolean('is_active')->default(true);$t->unique(['id','company_id']);});
        Schema::create('company_user',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('user_id');$t->string('status');$t->timestamps();});
        Schema::create('roles',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->string('name');$t->string('code');$t->timestamps();});
        Schema::create('permissions',function(Blueprint $t):void{$t->id();$t->string('code');$t->string('module');$t->timestamps();});
        Schema::create('role_permission',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('role_id');$t->unsignedBigInteger('permission_id');$t->timestamps();});
        Schema::create('user_roles',function(Blueprint $t):void{$t->id();$t->unsignedBigInteger('company_id');$t->unsignedBigInteger('user_id');$t->unsignedBigInteger('role_id');$t->timestamps();});
        (require database_path('migrations/2026_11_16_000005_create_cash_management.php'))->up();
        DB::table('users')->insert([['id'=>1,'name'=>'Admin','email'=>'a@x.test','password'=>'x'],['id'=>2,'name'=>'Lector','email'=>'b@x.test','password'=>'x']]);
        DB::table('companies')->insert([['id'=>1,'name'=>'A'],['id'=>2,'name'=>'B']]);
        DB::table('branches')->insert([['id'=>1,'company_id'=>1,'name'=>'Principal'],['id'=>2,'company_id'=>2,'name'=>'Ajena']]);
        DB::table('company_user')->insert([['company_id'=>1,'user_id'=>1,'status'=>'active'],['company_id'=>1,'user_id'=>2,'status'=>'active']]);
        DB::table('roles')->insert([['id'=>1,'company_id'=>1,'name'=>'Admin','code'=>'admin'],['id'=>2,'company_id'=>1,'name'=>'Lector','code'=>'reader']]);
        DB::table('permissions')->insert([['id'=>1,'code'=>'company.view','module'=>'company'],['id'=>2,'code'=>'company.update','module'=>'company']]);
        DB::table('role_permission')->insert([['role_id'=>1,'permission_id'=>1],['role_id'=>1,'permission_id'=>2],['role_id'=>2,'permission_id'=>1]]);
        DB::table('user_roles')->insert([['company_id'=>1,'user_id'=>1,'role_id'=>1],['company_id'=>1,'user_id'=>2,'role_id'=>2]]);
    }

    private function login(int $id = 1): void { Sanctum::actingAs(User::query()->findOrFail($id)); }
    private function url(string $resource, ?int $id = null, int $company = 1): string
    { return '/api/v1/companies/'.$company.'/cash/'.$resource.($id === null ? '' : '/'.$id); }

    private function register(string $code = 'CAJA1'): int
    {
        return (int)$this->postJson($this->url('registers'), ['branch_id'=>1,'code'=>$code,'name'=>'Caja principal'])
            ->assertCreated()->json('data.id');
    }
    private function category(string $name = 'Agua'): int
    {
        return (int)$this->postJson($this->url('categories'),['name'=>$name])->assertCreated()->json('data.id');
    }
    private function openCashTestSession(int $register, string $opening='100.00'): int
    {
        return (int)$this->postJson($this->url('sessions'),[
            'register_id'=>$register,'opening_cash'=>$opening,'notes'=>'Turno de pruebas',
        ])->assertCreated()->json('data.id');
    }
    private function movement(int $session, string $direction='IN', string $amount='20.00', ?int $category=null): int
    {
        return (int)$this->postJson($this->url('movements'),[
            'session_id'=>$session,'direction'=>$direction,'amount'=>$amount,
            'expense_category_id'=>$category,'reference'=>'TEST',
        ])->assertCreated()->json('data.id');
    }

    public function test_authentication_permissions_company_scope_and_options(): void
    {
        foreach (['registers','sessions','categories','movements'] as $resource) {
            $this->getJson($this->url($resource))->assertUnauthorized();
        }
        $this->login(2);
        foreach (['registers','sessions','categories','movements'] as $resource) {
            $this->getJson($this->url($resource))->assertOk();
            $this->postJson($this->url($resource),[])->assertForbidden();
        }
        $this->getJson($this->url('options'))->assertOk();
        $this->login();
        $this->getJson($this->url('registers',null,2))->assertNotFound();
        $this->postJson($this->url('registers'),['branch_id'=>2,'code'=>'A','name'=>'Ajena'])->assertUnprocessable();
    }

    public function test_register_crud_and_branch_protection(): void
    {
        $this->login(); $id=$this->register();
        $this->getJson($this->url('registers',$id))->assertOk()->assertJsonPath('data.branch_name','Principal');
        $this->patchJson($this->url('registers',$id),['name'=>'Caja actualizada','code'=>'NUEVA'])->assertOk()
            ->assertJsonPath('data.code','NUEVA');
        $this->postJson($this->url('registers'),['branch_id'=>1,'code'=>'nueva','name'=>'Duplicada'])->assertUnprocessable();
        $this->patchJson($this->url('registers',$id),['branch_id'=>2])->assertUnprocessable();
        $this->deleteJson($this->url('registers',$id))->assertOk();
        $this->getJson($this->url('registers',$id))->assertNotFound();
    }

    public function test_expense_categories_crud_and_linked_protection(): void
    {
        $this->login(); $id=$this->category();
        $this->getJson($this->url('categories',$id))->assertOk();
        $this->patchJson($this->url('categories',$id),['name'=>'Servicios básicos'])->assertOk()
            ->assertJsonPath('data.name','Servicios básicos');
        $this->postJson($this->url('categories'),['name'=>'Servicios básicos'])->assertUnprocessable();
        $this->deleteJson($this->url('categories',$id))->assertOk();
        $this->getJson($this->url('categories',$id))->assertNotFound();
    }

    public function test_session_lifecycle_single_open_and_final_inmutable(): void
    {
        $this->login(); $register=$this->register(); $session=$this->openCashTestSession($register,'125.50');
        $this->postJson($this->url('sessions'),['register_id'=>$register,'opening_cash'=>'0.00'])->assertUnprocessable();
        $this->patchJson($this->url('sessions',$session),['opening_cash'=>'150.00','notes'=>'Ajustado'])->assertOk()
            ->assertJsonPath('data.expected_current','150.00');
        $this->patchJson($this->url('sessions',$session),['status'=>'CLOSED','counted_cash'=>'147.00','notes'=>'Faltante revisado'])
            ->assertOk()->assertJsonPath('data.difference_cash','-3.00')->assertJsonPath('data.status','CLOSED');
        $this->patchJson($this->url('sessions',$session),['notes'=>'Alterar cierre'])->assertUnprocessable();
        $this->deleteJson($this->url('sessions',$session))->assertUnprocessable();
        $this->openCashTestSession($register,'20.00');
        $this->deleteJson($this->url('registers',$register))->assertUnprocessable();
    }

    public function test_movement_create_edit_archive_audit_and_accurate_money(): void
    {
        $this->login(); $register=$this->register(); $session=$this->openCashTestSession($register,'100.00');
        $expense=$this->category();
        $in=$this->movement($session,'IN','25.35');
        $out=$this->movement($session,'OUT','7.15',$expense);
        $this->getJson($this->url('sessions',$session))->assertJsonPath('data.expected_current','118.20');
        $this->patchJson($this->url('movements',$out),['amount'=>'9.10','notes'=>'Corregido'])->assertOk()
            ->assertJsonPath('data.notes','Corregido');
        $this->getJson($this->url('sessions',$session))->assertJsonPath('data.expected_current','116.25');
        $this->getJson($this->url('movements',$out).'/history')->assertOk()->assertJsonCount(2,'data');
        $this->deleteJson($this->url('movements',$out))->assertOk();
        $this->getJson($this->url('movements',$out))->assertNotFound();
        $this->getJson($this->url('movements',$out).'/history')->assertJsonCount(3,'data');
        $this->getJson($this->url('sessions',$session))->assertJsonPath('data.expected_current','125.35');
        $this->deleteJson($this->url('movements',$in))->assertOk();
        $this->getJson($this->url('sessions',$session))->assertJsonPath('data.expected_current','100.00');
    }

    public function test_prevent_negative_cash_balance_and_invalid_money(): void
    {
        $this->login(); $register=$this->register(); $session=$this->openCashTestSession($register,'20.00');
        $category=$this->category();
        $this->postJson($this->url('movements'),['session_id'=>$session,'direction'=>'OUT',
            'amount'=>'20.01','expense_category_id'=>$category])->assertUnprocessable();
        $this->postJson($this->url('movements'),['session_id'=>$session,'direction'=>'OUT',
            'amount'=>'1.00'])->assertUnprocessable();
        $this->postJson($this->url('movements'),['session_id'=>$session,'direction'=>'IN',
            'amount'=>'0.00'])->assertUnprocessable();
        $this->postJson($this->url('movements'),['session_id'=>$session,'direction'=>'IN',
            'amount'=>'1.001'])->assertUnprocessable();
        $income=$this->movement($session,'IN','5.00');
        $expense=$this->movement($session,'OUT','23.00',$category);
        $this->deleteJson($this->url('movements',$income))->assertUnprocessable();
        $this->patchJson($this->url('movements',$income),['amount'=>'1.00'])->assertUnprocessable();
        $this->getJson($this->url('sessions',$session))->assertJsonPath('data.expected_current','2.00');
        $this->deleteJson($this->url('categories',$category))->assertUnprocessable();
        $this->deleteJson($this->url('movements',$expense))->assertOk();
    }

    public function test_movement_correction_prevents_negative_intermediate_balance(): void
    {
        $this->login(); $register=$this->register(); $session=$this->openCashTestSession($register,'0.00');
        $category=$this->category();
        $in=$this->movement($session,'IN','100.00');
        $this->movement($session,'OUT','70.00',$category);
        $this->movement($session,'IN','100.00');
        $this->getJson($this->url('sessions',$session))->assertJsonPath('data.expected_current','130.00');
        $this->deleteJson($this->url('movements',$in))->assertUnprocessable();
        $this->patchJson($this->url('movements',$in),['amount'=>'50.00'])->assertUnprocessable();
        $this->patchJson($this->url('sessions',$session),['notes'=>'Turno regular'])->assertOk();
        $this->getJson($this->url('sessions',$session))->assertJsonPath('data.expected_current','130.00');
    }

    public function test_closed_sessions_reject_all_money_mutations(): void
    {
        $this->login();$register=$this->register();$session=$this->openCashTestSession($register);
        $movement=$this->movement($session,'IN','10.00');
        $this->patchJson($this->url('sessions',$session),['status'=>'CLOSED','counted_cash'=>'110.00'])
            ->assertOk()->assertJsonPath('data.expected_cash','110.00');
        $this->patchJson($this->url('movements',$movement),['amount'=>'50.00'])->assertUnprocessable();
        $this->deleteJson($this->url('movements',$movement))->assertUnprocessable();
        $this->postJson($this->url('movements'),['session_id'=>$session,'direction'=>'IN','amount'=>'1.00'])->assertUnprocessable();
        $this->deleteJson($this->url('registers',$register))->assertUnprocessable();
        $this->patchJson($this->url('registers',$register),['branch_id'=>2])->assertUnprocessable();
    }

    public function test_archive_empty_open_session_and_reopen_register(): void
    {
        $this->login();$register=$this->register();$session=$this->openCashTestSession($register);
        $this->deleteJson($this->url('sessions',$session))->assertOk();
        $this->getJson($this->url('sessions',$session))->assertNotFound();
        $next=$this->openCashTestSession($register);$this->assertGreaterThan($session,$next);
    }

    public function test_cash_values_are_decimal_strings_across_sqlite_and_mysql(): void
    {
        $this->login();
        $register = $this->register();
        $session = $this->openCashTestSession($register, '100.50');
        $this->getJson($this->url('sessions', $session))->assertOk()
            ->assertJsonPath('data.opening_cash', '100.50')
            ->assertJsonPath('data.expected_current', '100.50');
        $movement = $this->movement($session, 'IN', '3.20');
        $this->getJson($this->url('movements', $movement))->assertOk()
            ->assertJsonPath('data.amount', '3.20');
        $this->patchJson($this->url('sessions', $session), [
            'status' => 'CLOSED', 'counted_cash' => '103.70',
        ])->assertOk()
            ->assertJsonPath('data.opening_cash', '100.50')
            ->assertJsonPath('data.counted_cash', '103.70')
            ->assertJsonPath('data.expected_cash', '103.70')
            ->assertJsonPath('data.difference_cash', '0.00');
        $this->getJson($this->url('sessions', $session))->assertOk()
            ->assertJsonPath('data.expected_cash', '103.70');
    }

    public function test_foreign_records_and_stale_references_rejected(): void
    {
        $this->login();$register=$this->register();$session=$this->openCashTestSession($register);
        $category=$this->category();
        $this->postJson($this->url('movements'),['session_id'=>999,'direction'=>'IN','amount'=>'1.00'])->assertUnprocessable();
        $this->postJson($this->url('movements'),['session_id'=>$session,'direction'=>'OUT','amount'=>'1.00',
            'expense_category_id'=>888])->assertUnprocessable();
        $this->patchJson($this->url('sessions',$session),['register_id'=>999])->assertUnprocessable();
        $this->getJson($this->url('registers',$register,2))->assertNotFound();
        $this->getJson($this->url('movements',null,2))->assertNotFound();
        $this->deleteJson($this->url('categories',$category,2))->assertNotFound();
    }
}
