<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;

/** Reutiliza la base SQLite :memory: del POS: ninguna operación sobre MySQL real. */
class CompanyPosReportsTest extends CompanyPosTest
{
    private function url22(string $suffix = ''): string
    {
        return '/api/v1/companies/1/pos'.$suffix;
    }

    private function exampleSale(): array
    {
        return [
            'branch_id'=>1, 'idempotency_key'=>'pos-reports-22a-one-sale',
            'lines'=>[['item_id'=>1,'quantity'=>2]],
            'discount_amount'=>'50.00', 'discount_reason'=>'Descuento de prueba',
            'payments'=>[
                ['payment_method_id'=>1,'cash_session_id'=>1,'amount'=>'150.00'],
                ['payment_method_id'=>2,'bank_account_id'=>1,'amount'=>'100.00','reference'=>'TEST-22A'],
            ],
        ];
    }

    public function test_reports_count_a_split_sale_once_and_keep_payment_channels_separate(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(1));
        $sale = $this->exampleSale();
        $this->postJson($this->url22('/sales'), $sale)->assertCreated();
        $this->postJson($this->url22('/sales'), $sale)->assertOk()->assertJsonPath('replayed', true);
        $result = $this->getJson($this->url22('/reports/summary?branch_id=1'))
            ->assertOk()
            ->assertJsonPath('data.kpis.sales_count',1)
            ->assertJsonPath('data.kpis.subtotal','300.00')
            ->assertJsonPath('data.kpis.discounts','50.00')
            ->assertJsonPath('data.kpis.tax','0.00')
            ->assertJsonPath('data.kpis.total','250.00');
        $channels = collect($result->json('data.payment_channels'))->keyBy('channel');
        $this->assertSame('150.00', $channels->get('CASH')['amount']);
        $this->assertSame('100.00', $channels->get('BANK')['amount']);
        $this->assertSame('2.000', $result->json('data.top_products.0.quantity'));
        $this->assertCount(1, $result->json('data.daily'));
        $this->assertCount(1, $result->json('data.documents'));
        $this->assertSame(1, DB::table('pos_sales')->count());
    }

    public function test_reports_validate_tenant_branch_range_and_reader_access(): void
    {
        Sanctum::actingAs(User::query()->findOrFail(2));
        $this->getJson($this->url22('/reports/summary'))->assertOk()
            ->assertJsonPath('data.kpis.sales_count', 0);
        $this->getJson('/api/v1/companies/2/pos/reports/summary')->assertNotFound();
        $this->getJson($this->url22('/reports/summary?branch_id=2'))->assertUnprocessable();
        $this->getJson($this->url22('/reports/summary?from=2026-12-01&to=2026-11-01'))
            ->assertUnprocessable();
        $this->getJson($this->url22('/reports/summary?from=2025-01-01&to=2026-11-01'))
            ->assertUnprocessable();
        $this->getJson($this->url22('/reports/summary?from=not-a-date'))->assertUnprocessable();
    }
}
