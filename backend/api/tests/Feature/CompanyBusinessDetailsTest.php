<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Database\Schema\Blueprint;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyBusinessDetailsTest extends TestCase
{
    use DatabaseTransactions;

    private int $companyId;

    protected function setUp(): void
    {
        parent::setUp();

        // Protección obligatoria antes de crear datos.
        if (
            !app()->environment('testing') ||
            DB::getDefaultConnection() !== 'sqlite' ||
            DB::connection()->getDatabaseName() !== ':memory:'
        ) {
            throw new \RuntimeException(
                'Estas pruebas solo pueden ejecutarse en SQLite en memoria.'
            );
        }

        $this->prepareIsolatedSchema();
        $this->seedIsolatedCompany();
    }

    private function prepareIsolatedSchema(): void
    {
        // Todas las operaciones siguientes se ejecutan exclusivamente
        // en la base SQLite temporal, nunca en MySQL.

        foreach ([
            'user_roles',
            'role_permission',
            'permissions',
            'roles',
            'company_user',
            'company_addresses',
            'company_fiscal_profiles',
            'companies',
            'users',
        ] as $table) {
            Schema::dropIfExists($table);
        }

        Schema::create('users', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('email')->unique();
            $table->string('password');
            $table->timestamps();
        });

        Schema::create('companies', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->string('slug')->unique();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
        });

        Schema::create('company_user', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('user_id');
            $table->string('status')->default('active');
            $table->timestamps();
        });

        Schema::create('roles', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->string('name');
            $table->string('code');
            $table->timestamps();
        });

        Schema::create('permissions', function (Blueprint $table) {
            $table->id();
            $table->string('code')->unique();
            $table->string('module');
            $table->timestamps();
        });

        Schema::create('role_permission', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('role_id');
            $table->unsignedBigInteger('permission_id');
            $table->timestamps();
        });

        Schema::create('user_roles', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('user_id');
            $table->unsignedBigInteger('role_id');
            $table->timestamps();
        });

        Schema::create('company_fiscal_profiles', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('company_id')->unique();

            $table->string('legal_name', 180)->nullable();
            $table->string('tax_id', 60)->nullable();
            $table->string('taxpayer_type', 100)->nullable();
            $table->string('tax_regime', 120)->nullable();
            $table->string('tax_status', 100)->nullable();
            $table->string('commercial_registration', 120)->nullable();
            $table->string('billing_email', 190)->nullable();
            $table->string('billing_phone', 40)->nullable();

            $table->text('fiscal_address')->nullable();
            $table->text('invoice_footer')->nullable();
            $table->text('fiscal_notes')->nullable();

            $table->boolean('is_tax_exempt')->default(false);
            $table->timestamps();
        });

        Schema::create('company_addresses', function (Blueprint $table) {
            $table->id();
            $table->unsignedBigInteger('company_id');

            $table->string('type', 40)->default('principal');
            $table->string('country', 100)->default('Honduras');
            $table->string('department', 120)->nullable();
            $table->string('municipality', 120)->nullable();
            $table->string('neighborhood', 180)->nullable();
            $table->string('street', 255)->nullable();
            $table->string('building_number', 50)->nullable();
            $table->string('postal_code', 30)->nullable();

            $table->text('full_address')->nullable();
            $table->text('reference')->nullable();

            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();

            $table->boolean('is_primary')->default(false);
            $table->timestamps();
        });
    }

    private function seedIsolatedCompany(): void
    {
        DB::table('users')->insert([
            'id' => 1,
            'name' => 'Administrador de pruebas',
            'email' => 'qa@example.test',
            'password' => 'not-used',
        ]);

        DB::table('companies')->insert([
            [
                'id' => 1,
                'name' => 'Autolavado QA',
                'slug' => 'carwash-pruebas',
                'is_active' => true,
            ],
            [
                'id' => 2,
                'name' => 'Otra Empresa QA',
                'slug' => 'otra-empresa-qa',
                'is_active' => true,
            ],
        ]);

        DB::table('company_user')->insert([
            'company_id' => 1,
            'user_id' => 1,
            'status' => 'active',
        ]);

        DB::table('roles')->insert([
            'id' => 1,
            'company_id' => 1,
            'name' => 'Administrador QA',
            'code' => 'admin',
        ]);

        DB::table('permissions')->insert([
            [
                'id' => 1,
                'code' => 'company.view',
                'module' => 'company',
            ],
            [
                'id' => 2,
                'code' => 'company.update',
                'module' => 'company',
            ],
            [
                'id' => 3,
                'code' => 'company.fiscal.manage',
                'module' => 'company',
            ],
        ]);

        DB::table('user_roles')->insert([
            'company_id' => 1,
            'user_id' => 1,
            'role_id' => 1,
        ]);

        DB::table('role_permission')->insert([
            ['role_id' => 1, 'permission_id' => 1],
            ['role_id' => 1, 'permission_id' => 2],
            ['role_id' => 1, 'permission_id' => 3],
        ]);
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