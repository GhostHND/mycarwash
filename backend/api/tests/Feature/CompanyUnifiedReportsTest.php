<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;

/** Bloque 22B: sólo SQLite :memory: heredado de CompanyPosTest. */
class CompanyUnifiedReportsTest extends CompanyPosTest
{
    private function url22(string $kind, string $tail = ''): string
    {
        return '/api/v1/companies/1/reports/unified?kind='.$kind.'&from='.now()->format('Y-m-d')
            .'&to='.now()->format('Y-m-d').$tail;
    }

    public function test_all_reports_are_read_only_and_have_date_scope(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(1));
        foreach (['overview','pos','washes','bookings','cash','inventory','customers','staff','fiscal','purchases'] as $kind) {
            $response = $this->getJson($this->url22($kind))->assertOk()
                ->assertJsonPath('data.kind', $kind)
                ->assertJsonPath('data.scope.company_id', 1)
                ->assertJsonPath('data.company.name', 'Negocio A');
            $this->assertIsArray($response->json('data.sections'));
            $this->assertIsArray($response->json('data.metrics'));
        }
        $this->assertSame(0, DB::table('pos_sales')->count());
    }

    public function test_pos_split_payments_count_one_sale_and_keep_separate_channels(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(1));
        $payload = [
            'branch_id'=>1, 'idempotency_key'=>'unified-report-pos-22b-one',
            'lines'=>[['item_id'=>1,'quantity'=>2]],
            'discount_amount'=>'50.00','discount_reason'=>'Descuento reporte',
            'payments'=>[
                ['payment_method_id'=>1,'cash_session_id'=>1,'amount'=>'150.00'],
                ['payment_method_id'=>2,'bank_account_id'=>1,'amount'=>'100.00','reference'=>'22B-TEST'],
            ],
        ];
        $this->postJson('/api/v1/companies/1/pos/sales', $payload)->assertCreated();
        $res = $this->getJson($this->url22('pos', '&branch_id=1'))->assertOk();
        $this->assertContains(['label'=>'Ventas POS confirmadas','value'=>'1'], $res->json('data.metrics'));
        $this->assertContains(['label'=>'Ingresos POS','value'=>'L 250.00'], $res->json('data.metrics'));
        $methods = collect($res->json('data.sections.1.rows'))->keyBy('channel');
        $this->assertSame('150.00', $methods->get('CASH')['amount']);
        $this->assertSame('100.00', $methods->get('BANK')['amount']);
        $this->assertSame(1, DB::table('pos_sales')->count());
    }

    public function test_validation_permissions_and_foreign_branch(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(2));
        $this->getJson($this->url22('inventory'))->assertOk();
        $this->getJson($this->url22('pos','&branch_id=2'))->assertUnprocessable();
        $this->getJson($this->url22('unknown'))->assertUnprocessable();
        $this->getJson('/api/v1/companies/2/reports/unified?kind=pos&from=2026-11-01&to=2026-11-17')
            ->assertNotFound();
        $this->getJson('/api/v1/companies/1/reports/unified?kind=pos&from=2026-12-01&to=2026-11-01')
            ->assertUnprocessable();
        $this->getJson('/api/v1/companies/1/reports/unified?kind=pos&from=2020-01-01&to=2026-11-01')
            ->assertUnprocessable();
    }
}
