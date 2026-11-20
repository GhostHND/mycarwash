<?php

namespace Tests\Feature;

use App\Models\MasterOperator24N8;
use App\Models\User;
use App\Support\MasterBilling24N8;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MasterOffice24N9Test extends TestCase
{
    use RefreshDatabase;

    private function loginMaster(): void
    {
        $operator = MasterOperator24N8::create([
            'name' => 'ADN Master', 'email' => 'office@test.local',
            'password' => Hash::make('VerySecureMaster!123'), 'is_active' => true,
        ]);
        Sanctum::actingAs($operator, ['master:all']);
    }

    private function company(): int
    {
        $id = DB::table('companies')->insertGetId([
            'name' => 'Empresa de Prueba 24N9',
            'slug' => 'empresa-24n9-'.Str::random(5),
            'public_id' => (string) Str::uuid(),
            'is_active' => true, 'created_at' => now(), 'updated_at' => now(),
        ]);
        DB::table('master_subscriptions_24n8')->insert([
            'company_id' => $id, 'status' => 'active',
            'due_date' => null, 'grace_days' => 4,
            'timezone' => 'America/Tegucigalpa',
            'created_at' => now(), 'updated_at' => now(),
        ]);
        return $id;
    }

    public function test_workspace_is_only_for_master_accounts(): void
    {
        Sanctum::actingAs(User::factory()->create(), ['*']);
        $this->getJson('/api/v1/master/workspace-24n9')->assertForbidden();
        $this->getJson('/api/v1/master/records-24n9/companies')->assertForbidden();
    }

    public function test_dashboard_returns_actual_totals_and_paginated_companies(): void
    {
        $company = $this->company();
        $this->loginMaster();
        $this->getJson('/api/v1/master/workspace-24n9')
            ->assertOk()->assertJsonPath('summary.companies_total', 1)
            ->assertJsonPath('summary.companies_active', 1)
            ->assertJsonStructure(['subscriptions', 'income_months', 'due_soon', 'activity']);
        $this->getJson('/api/v1/master/records-24n9/companies?page=1&per_page=10')
            ->assertOk()->assertJsonPath('total', 1)
            ->assertJsonPath('data.0.id', $company);
    }

    public function test_subscription_activation_needs_plan_and_due_date(): void
    {
        $company = $this->company();
        DB::table('companies')->where('id', $company)->update(['is_active' => false]);
        DB::table('master_subscriptions_24n8')->where('company_id', $company)
            ->update(['status' => 'suspended']);
        $this->loginMaster();
        $this->patchJson('/api/v1/master/subscriptions-24n9/'.$company,
            ['status' => 'active'])->assertUnprocessable();
        $plan = DB::table('master_plans_24n8')->where('name', 'Básico')->first();
        DB::table('master_plans_24n8')->where('id', $plan->id)->update([
            'monthly_price' => 250, 'is_active' => true,
        ]);
        $this->patchJson('/api/v1/master/subscriptions-24n9/'.$company, [
            'status' => 'active', 'plan_id' => $plan->id, 'due_date' => '2027-01-01',
        ])->assertOk()->assertJsonPath('billing.allowed', true);
        $this->assertTrue(MasterBilling24N8::allowed($company));
        $this->assertDatabaseHas('master_subscriptions_24n8', [
            'company_id' => $company, 'grace_days' => 4,
        ]);
        $this->assertDatabaseHas('master_audit_24n8', [
            'action' => 'subscription.updated', 'target' => 'company:'.$company,
        ]);
    }

    public function test_suspend_keeps_data_and_denies_company_access(): void
    {
        $company = $this->company();
        $this->loginMaster();
        $this->patchJson('/api/v1/master/subscriptions-24n9/'.$company,
            ['status' => 'suspended'])->assertOk()->assertJsonPath('billing.allowed', false);
        $this->assertFalse(MasterBilling24N8::allowed($company));
        $this->assertDatabaseHas('companies', ['id' => $company, 'is_active' => false]);
        $this->assertDatabaseHas('master_subscriptions_24n8', [
            'company_id' => $company, 'status' => 'suspended',
        ]);
    }
}
