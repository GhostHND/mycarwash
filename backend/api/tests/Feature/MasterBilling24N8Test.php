<?php
namespace Tests\Feature;

use App\Models\MasterOperator24N8;
use App\Models\User;
use App\Support\MasterBilling24N8;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;
use Carbon\Carbon;

class MasterBilling24N8Test extends TestCase {
    use RefreshDatabase;

    protected function tearDown():void { Carbon::setTestNow();parent::tearDown(); }
    private function company():int {
        return DB::table('companies')->insertGetId(['name'=>'Test Billing','slug'=>'test-billing',
            'public_id'=>'883b5891-09c2-4412-8b70-52b310233000','is_active'=>true,
            'created_at'=>now(),'updated_at'=>now()]);
    }
    public function test_four_grace_days_and_day_five_block_company_even_with_old_token():void {
        Carbon::setTestNow(Carbon::parse('2026-11-25 12:00:00','America/Tegucigalpa'));
        $company=$this->company();
        DB::table('master_subscriptions_24n8')->insert(['company_id'=>$company,'status'=>'active',
            'due_date'=>'2026-11-20','grace_days'=>4,'timezone'=>'America/Tegucigalpa',
            'created_at'=>now(),'updated_at'=>now()]);
        Carbon::setTestNow(Carbon::parse('2026-11-24 10:00:00','America/Tegucigalpa'));
        $this->assertTrue(MasterBilling24N8::allowed($company));
        $this->assertSame('past_due',MasterBilling24N8::state($company)['status']);
        Carbon::setTestNow(Carbon::parse('2026-11-25 00:01:00','America/Tegucigalpa'));
        $this->assertFalse(MasterBilling24N8::allowed($company));
        $this->assertSame('suspended',MasterBilling24N8::state($company)['status']);
        Sanctum::actingAs(User::factory()->create(),['*']);
        $this->getJson("/api/v1/companies/$company/clients")->assertStatus(403);
    }
    public function test_only_master_operator_can_read_global_overview():void {
        Sanctum::actingAs(User::factory()->create(),['*']);
        $this->getJson('/api/v1/master/overview')->assertStatus(403);
    }
    public function test_master_login_uses_separate_credentials():void {
        MasterOperator24N8::create(['name'=>'ADN Owner','email'=>'master@test.local',
            'password'=>Hash::make('Master!Password124'),'is_active'=>true]);
        $this->postJson('/api/v1/master/auth/token',[
            'email'=>'master@test.local','password'=>'Master!Password124',
        ])->assertOk()->assertJsonStructure(['access_token','expires_at']);
        $this->postJson('/api/v1/auth/token',[
            'email'=>'master@test.local','password'=>'Master!Password124','device_name'=>'web',
        ])->assertUnprocessable();
    }
}
