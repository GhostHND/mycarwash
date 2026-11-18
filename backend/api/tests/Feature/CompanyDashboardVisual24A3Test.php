<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;

/** Regresión de permisos y consultas de lectura del Dashboard visual. */
class CompanyDashboardVisual24A3Test extends CompanyDashboard24ATest
{
    public function test_visual_endpoint_is_scoped_and_read_only(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(1));
        $before = [DB::table('wash_orders')->count(), DB::table('pos_sales')->count()];
        $this->getJson('/api/v1/companies/1/dashboard/visual-24a3')
            ->assertOk()->assertJsonPath('data.scope.company_id', 1)
            ->assertJsonStructure(['data'=>['production','services','top_item',
                'trend','bookings','active','active_total','warnings']]);
        $this->assertSame($before, [DB::table('wash_orders')->count(), DB::table('pos_sales')->count()]);
    }

    public function test_visual_endpoint_blocks_cross_company_and_foreign_branch(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(2));
        $this->getJson('/api/v1/companies/2/dashboard/visual-24a3')->assertNotFound();
        $this->getJson('/api/v1/companies/1/dashboard/visual-24a3?branch_id=2')
            ->assertUnprocessable();
    }
}
