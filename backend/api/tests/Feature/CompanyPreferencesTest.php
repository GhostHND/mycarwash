<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyPreferencesTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::getDefaultConnection() !== 'sqlite' ||
            DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Pruebas solo permitidas en SQLite en memoria.');
        }
        $this->createFixturesSchema();
        $this->createFixturesData();
    }

    private function createFixturesSchema(): void
    {
        foreach ([
            'company_preferences', 'user_roles', 'role_permission', 'permissions',
            'roles', 'company_user', 'companies', 'users',
        ] as $table) {
            Schema::dropIfExists($table);
        }
        Schema::create('users', function (Blueprint $t) {
            $t->id(); $t->string('name'); $t->string('email')->unique();
            $t->string('password'); $t->timestamps();
        });
        Schema::create('companies', function (Blueprint $t) {
            $t->id(); $t->string('name'); $t->string('slug');
            $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('company_user', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('user_id'); $t->string('status')->default('active');
            $t->timestamps();
        });
        Schema::create('roles', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->string('name'); $t->string('code'); $t->timestamps();
        });
        Schema::create('permissions', function (Blueprint $t) {
            $t->id(); $t->string('code'); $t->string('module'); $t->timestamps();
        });
        Schema::create('role_permission', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('role_id');
            $t->unsignedBigInteger('permission_id'); $t->timestamps();
        });
        Schema::create('user_roles', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('user_id'); $t->unsignedBigInteger('role_id');
            $t->timestamps();
        });
        Schema::create('company_preferences', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id');
            $t->string('locale', 12)->default('es-HN');
            $t->string('currency_code', 3)->default('HNL');
            $t->string('timezone', 80)->default('America/Tegucigalpa');
            $t->string('date_format', 30)->default('dd/MM/yyyy');
            $t->string('time_format', 15)->default('24h');
            $t->string('default_theme', 12)->default('system');
            $t->string('invoice_paper_size', 30)->default('letter');
            $t->string('country_phone_code', 10)->default('+504');
            $t->unsignedTinyInteger('decimal_places')->default(2);
            $t->boolean('enable_sound_alerts')->default(true);
            $t->text('receipt_footer')->nullable(); $t->timestamps();
        });
    }

    private function createFixturesData(): void
    {
        DB::table('users')->insert([
            ['id' => 1, 'name' => 'Admin QA', 'email' => 'admin-preferences@example.test', 'password' => 'unused'],
            ['id' => 2, 'name' => 'Visor QA', 'email' => 'viewer-preferences@example.test', 'password' => 'unused'],
            ['id' => 3, 'name' => 'Otro Admin QA', 'email' => 'other-preferences@example.test', 'password' => 'unused'],
        ]);
        DB::table('companies')->insert([
            ['id' => 1, 'name' => 'CarWash Uno', 'slug' => 'carwash-uno', 'is_active' => true],
            ['id' => 2, 'name' => 'CarWash Dos', 'slug' => 'carwash-dos', 'is_active' => true],
        ]);
        DB::table('company_user')->insert([
            ['company_id' => 1, 'user_id' => 1, 'status' => 'active'],
            ['company_id' => 1, 'user_id' => 2, 'status' => 'active'],
            ['company_id' => 2, 'user_id' => 3, 'status' => 'active'],
        ]);
        DB::table('roles')->insert([
            ['id' => 1, 'company_id' => 1, 'name' => 'Admin', 'code' => 'admin'],
            ['id' => 2, 'company_id' => 1, 'name' => 'Viewer', 'code' => 'viewer'],
            ['id' => 3, 'company_id' => 2, 'name' => 'Admin', 'code' => 'admin'],
        ]);
        DB::table('permissions')->insert([
            ['id' => 1, 'code' => 'company.view', 'module' => 'company'],
            ['id' => 2, 'code' => 'company.update', 'module' => 'company'],
        ]);
        DB::table('user_roles')->insert([
            ['company_id' => 1, 'user_id' => 1, 'role_id' => 1],
            ['company_id' => 1, 'user_id' => 2, 'role_id' => 2],
            ['company_id' => 2, 'user_id' => 3, 'role_id' => 3],
        ]);
        DB::table('role_permission')->insert([
            ['role_id' => 1, 'permission_id' => 1],
            ['role_id' => 1, 'permission_id' => 2],
            ['role_id' => 2, 'permission_id' => 1],
            ['role_id' => 3, 'permission_id' => 1],
            ['role_id' => 3, 'permission_id' => 2],
        ]);
    }

    private function login(int $userId = 1): void
    {
        Sanctum::actingAs(User::query()->findOrFail($userId));
    }

    public function test_requires_authentication(): void
    {
        $this->getJson('/api/v1/companies/1/settings/preferences')->assertUnauthorized();
        $this->patchJson('/api/v1/companies/1/settings/preferences', ['time_format' => '12h'])
            ->assertUnauthorized();
    }

    public function test_shows_defaults_without_inserting_record(): void
    {
        $this->login();
        $this->getJson('/api/v1/companies/1/settings/preferences')->assertOk()
            ->assertJsonPath('preferences.locale', 'es-HN')
            ->assertJsonPath('preferences.currency_code', 'HNL')
            ->assertJsonPath('preferences.timezone', 'America/Tegucigalpa')
            ->assertJsonPath('preferences.enable_sound_alerts', true);
        $this->assertSame(0, DB::table('company_preferences')->count());
    }

    public function test_saves_and_partial_update_keeps_previous_values(): void
    {
        $this->login();
        $url = '/api/v1/companies/1/settings/preferences';
        $this->patchJson($url, [
            'time_format' => '12h', 'decimal_places' => 3,
            'receipt_footer' => 'Gracias por su visita', 'enable_sound_alerts' => false,
        ])->assertOk()->assertJsonPath('preferences.time_format', '12h')
            ->assertJsonPath('preferences.decimal_places', 3)
            ->assertJsonPath('preferences.enable_sound_alerts', false);

        $this->patchJson($url, ['currency_code' => 'USD'])
            ->assertOk()->assertJsonPath('preferences.currency_code', 'USD')
            ->assertJsonPath('preferences.receipt_footer', 'Gracias por su visita')
            ->assertJsonPath('preferences.time_format', '12h');
        $this->assertSame(1, DB::table('company_preferences')->count());
    }

    public function test_rejects_invalid_and_unrecognized_fields(): void
    {
        $this->login();
        $url = '/api/v1/companies/1/settings/preferences';
        foreach ([
            ['decimal_places' => 9], ['time_format' => '24hours'],
            ['default_theme' => 'custom-font'], ['timezone' => 'Mars/Space'],
            ['locale' => 'XXXX'], ['currency_code' => 'honduras'],
            ['country_phone_code' => '504'], ['invoice_paper_size' => 'A5'],
            ['date_format' => 'other'], ['enable_sound_alerts' => 'maybe'],
            ['company_id' => 2], ['font_family' => 'Roboto'], [],
        ] as $payload) {
            $this->patchJson($url, $payload)->assertUnprocessable();
        }
        $this->assertSame(0, DB::table('company_preferences')->count());
    }

    public function test_reader_can_view_but_cannot_change_preferences(): void
    {
        $this->login(2);
        $url = '/api/v1/companies/1/settings/preferences';
        $this->getJson($url)->assertOk();
        $this->patchJson($url, ['time_format' => '12h'])->assertForbidden();
        $this->assertSame(0, DB::table('company_preferences')->count());
    }

    public function test_rejects_foreign_company_access(): void
    {
        $this->login();
        $this->getJson('/api/v1/companies/2/settings/preferences')->assertNotFound();
        $this->patchJson('/api/v1/companies/2/settings/preferences', ['time_format' => '12h'])
            ->assertNotFound();
    }

    public function test_company_preferences_are_isolated_per_tenant(): void
    {
        $url1 = '/api/v1/companies/1/settings/preferences';
        $url2 = '/api/v1/companies/2/settings/preferences';
        $this->login(1);
        $this->patchJson($url1, ['receipt_footer' => 'Negocio uno'])->assertOk();
        $this->login(3);
        $this->patchJson($url2, ['receipt_footer' => 'Negocio dos'])->assertOk();
        $this->getJson($url2)->assertJsonPath('preferences.receipt_footer', 'Negocio dos');
        $this->login(1);
        $this->getJson($url1)->assertJsonPath('preferences.receipt_footer', 'Negocio uno');
        $this->assertSame(2, DB::table('company_preferences')->count());
    }
}