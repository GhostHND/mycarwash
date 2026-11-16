<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyBusinessDetailsTest extends TestCase
{
    use DatabaseTransactions;

    private int $companyId;

    protected function setUp(): void
    {
        parent::setUp();

        if (DB::connection()->getDatabaseName() !== 'mycarwash_core') {
            throw new \RuntimeException(
                'Las pruebas requieren la base mycarwash_core.'
            );
        }
    }

    private function authenticateManager(): void
    {
        $membership = DB::table('company_user as cu')
            ->join('companies as c', 'c.id', '=', 'cu.company_id')
            ->join('user_roles as ur', function ($join) {
                $join->on('ur.company_id', '=', 'cu.company_id')
                    ->on('ur.user_id', '=', 'cu.user_id');
            })
            ->join('roles as r', function ($join) {
                $join->on('r.id', '=', 'ur.role_id')
                    ->on('r.company_id', '=', 'ur.company_id');
            })
            ->join('role_permission as rp', 'rp.role_id', '=', 'r.id')
            ->join('permissions as p', 'p.id', '=', 'rp.permission_id')
            ->where('c.slug', 'carwash-pruebas')
            ->where('c.is_active', true)
            ->where('cu.status', 'active')
            ->whereIn('p.code', [
                'company.view',
                'company.update',
                'company.fiscal.manage',
            ])
            ->groupBy('cu.company_id', 'cu.user_id')
            ->havingRaw('COUNT(DISTINCT p.code) = 3')
            ->first([
                'cu.company_id',
                'cu.user_id',
            ]);

        if (!$membership) {
            throw new \RuntimeException(
                'No existe un usuario demo con los permisos requeridos.'
            );
        }

        $this->companyId = (int) $membership->company_id;

        Sanctum::actingAs(
            User::query()->findOrFail($membership->user_id)
        );
    }

    public function test_fiscal_requires_authentication(): void
    {
        $this->getJson(
            '/api/v1/companies/1/settings/fiscal'
        )->assertUnauthorized();
    }

    public function test_addresses_require_authentication(): void
    {
        $this->getJson(
            '/api/v1/companies/1/addresses'
        )->assertUnauthorized();
    }

    public function test_fiscal_can_be_saved_and_read(): void
    {
        $this->authenticateManager();

        $url = "/api/v1/companies/{$this->companyId}/settings/fiscal";

        $this->patchJson($url, [
            'legal_name' => 'Autolavado QA Fiscal',
            'tax_id' => '08011999123456',
            'billing_email' => 'facturacion@example.com',
            'is_tax_exempt' => false,
        ])
            ->assertOk()
            ->assertJsonPath(
                'fiscal.legal_name',
                'Autolavado QA Fiscal'
            );

        $this->getJson($url)
            ->assertOk()
            ->assertJsonPath(
                'fiscal.tax_id',
                '08011999123456'
            );

        $this->patchJson($url, [
            'billing_email' => 'correo-no-valido',
        ])->assertUnprocessable();
    }

    public function test_addresses_crud_and_search(): void
    {
        $this->authenticateManager();

        $url = "/api/v1/companies/{$this->companyId}/addresses";

        $first = $this->postJson($url, [
            'type' => 'principal',
            'country' => 'Honduras',
            'department' => 'El Paraíso',
            'municipality' => 'Danlí',
            'full_address' => 'Dirección QA14B-A',
            'is_primary' => true,
        ])->assertCreated();

        $firstId = (int) $first->json('address.id');

        $second = $this->postJson($url, [
            'type' => 'comercial',
            'country' => 'Honduras',
            'municipality' => 'Danlí',
            'full_address' => 'Dirección QA14B-B',
            'is_primary' => true,
        ])->assertCreated();

        $secondId = (int) $second->json('address.id');

        $primaryCount = DB::table('company_addresses')
            ->where('company_id', $this->companyId)
            ->where('is_primary', true)
            ->count();

        $this->assertSame(1, $primaryCount);

        $this->getJson($url . '?q=QA14B-B')
            ->assertOk()
            ->assertJsonPath('data.0.id', $secondId);

        $this->patchJson("$url/$firstId", [
            'full_address' => 'Dirección QA14B-EDITADA',
            'is_primary' => true,
        ])
            ->assertOk()
            ->assertJsonPath(
                'address.full_address',
                'Dirección QA14B-EDITADA'
            );

        $this->deleteJson("$url/$firstId")->assertOk();

        $this->assertDatabaseMissing('company_addresses', [
            'id' => $firstId,
            'company_id' => $this->companyId,
        ]);

        // La dirección restante se convierte en principal.
        $this->assertSame(
            1,
            (int) DB::table('company_addresses')
                ->where('company_id', $this->companyId)
                ->where('id', $secondId)
                ->value('is_primary')
        );
    }

    public function test_invalid_addresses_and_foreign_company_are_rejected(): void
    {
        $this->authenticateManager();

        $url = "/api/v1/companies/{$this->companyId}/addresses";

        $this->postJson($url, [
            'full_address' => 'Dirección inválida',
            'latitude' => 200,
        ])->assertUnprocessable();

        $this->postJson($url, [
            'type' => 'principal',
        ])->assertUnprocessable();

        $this->getJson(
            '/api/v1/companies/999999999/addresses'
        )->assertNotFound();
    }
}