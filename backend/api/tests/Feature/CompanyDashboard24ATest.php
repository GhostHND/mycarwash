<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;

/** Reutiliza las semillas SQLite del POS. Sin escrituras en GET Dashboard. */
class CompanyDashboard24ATest extends CompanyPosTest
{
    public function test_dashboard_is_read_only_and_scoped_to_authenticated_company(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(1));
        $original = DB::table('pos_sales')->count();
        $this->getJson('/api/v1/companies/1/dashboard/overview')
            ->assertOk()->assertJsonPath('data.scope.company_id',1)
            ->assertJsonPath('data.company_name','Negocio A')
            ->assertJsonPath('data.kpis.sales_today','0.00');
        $this->assertSame($original, DB::table('pos_sales')->count());
    }

    public function test_dashboard_rejects_foreign_company_and_branch(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(2));
        $this->getJson('/api/v1/companies/2/dashboard/overview')->assertNotFound();
        $this->getJson('/api/v1/companies/1/dashboard/overview?branch_id=2')->assertUnprocessable();
    }
}
