<?php

namespace Tests\Feature;

use App\Models\User;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Foundation\Testing\DatabaseTransactions;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CompanyScheduleSocialTest extends TestCase
{
    use DatabaseTransactions;

    protected function setUp(): void
    {
        parent::setUp();
        if (!app()->environment('testing') || DB::getDefaultConnection() !== 'sqlite' ||
            DB::connection()->getDatabaseName() !== ':memory:') {
            throw new \RuntimeException('Pruebas solo permitidas en SQLite en memoria.');
        }
        $this->schema();
        $this->seed();
    }

    private function schema(): void
    {
        foreach ([
            'company_social_links', 'company_special_hours', 'company_business_hours',
            'user_roles', 'role_permission', 'permissions', 'roles', 'company_user',
            'companies', 'users',
        ] as $table) Schema::dropIfExists($table);

        Schema::create('users', function (Blueprint $t) {
            $t->id(); $t->string('name'); $t->string('email')->unique();
            $t->string('password'); $t->timestamps();
        });
        Schema::create('companies', function (Blueprint $t) {
            $t->id(); $t->string('name'); $t->string('slug');
            $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('company_user', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id');
            $t->string('status')->default('active'); $t->timestamps();
        });
        Schema::create('roles', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('name');
            $t->string('code'); $t->timestamps();
        });
        Schema::create('permissions', function (Blueprint $t) {
            $t->id(); $t->string('code'); $t->string('module'); $t->timestamps();
        });
        Schema::create('role_permission', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('role_id');
            $t->unsignedBigInteger('permission_id'); $t->timestamps();
        });
        Schema::create('user_roles', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedBigInteger('user_id');
            $t->unsignedBigInteger('role_id'); $t->timestamps();
        });
        Schema::create('company_business_hours', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->unsignedTinyInteger('day_of_week');
            $t->time('opens_at')->nullable(); $t->time('closes_at')->nullable();
            $t->time('break_starts_at')->nullable(); $t->time('break_ends_at')->nullable();
            $t->boolean('is_closed')->default(false); $t->string('notes', 255)->nullable();
            $t->timestamps();
        });
        Schema::create('company_special_hours', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->date('special_date');
            $t->string('reason', 190)->nullable(); $t->boolean('is_closed')->default(false);
            $t->time('opens_at')->nullable(); $t->time('closes_at')->nullable();
            $t->text('notes')->nullable(); $t->timestamps();
        });
        Schema::create('company_social_links', function (Blueprint $t) {
            $t->id(); $t->unsignedBigInteger('company_id'); $t->string('platform', 60);
            $t->string('username', 150)->nullable(); $t->string('url', 600);
            $t->boolean('is_visible')->default(true); $t->unsignedInteger('sort_order')->default(0);
            $t->timestamps();
        });
    }

    private function seed(): void
    {
        DB::table('users')->insert([
            ['id' => 1, 'name' => 'Admin QA', 'email' => 'admin@example.test', 'password' => 'not-used'],
            ['id' => 2, 'name' => 'Lectura QA', 'email' => 'viewer@example.test', 'password' => 'not-used'],
        ]);
        DB::table('companies')->insert([
            ['id' => 1, 'name' => 'CarWash QA', 'slug' => 'carwash-pruebas', 'is_active' => true],
            ['id' => 2, 'name' => 'Otro CarWash', 'slug' => 'otra-empresa', 'is_active' => true],
        ]);
        DB::table('company_user')->insert([
            ['company_id' => 1, 'user_id' => 1, 'status' => 'active'],
            ['company_id' => 1, 'user_id' => 2, 'status' => 'active'],
        ]);
        DB::table('roles')->insert([
            ['id' => 1, 'company_id' => 1, 'name' => 'Admin QA', 'code' => 'admin'],
            ['id' => 2, 'company_id' => 1, 'name' => 'Visor QA', 'code' => 'view'],
        ]);
        DB::table('permissions')->insert([
            ['id' => 1, 'code' => 'company.view', 'module' => 'company'],
            ['id' => 2, 'code' => 'company.update', 'module' => 'company'],
            ['id' => 3, 'code' => 'company.hours.manage', 'module' => 'company'],
        ]);
        DB::table('user_roles')->insert([
            ['company_id' => 1, 'user_id' => 1, 'role_id' => 1],
            ['company_id' => 1, 'user_id' => 2, 'role_id' => 2],
        ]);
        DB::table('role_permission')->insert([
            ['role_id' => 1, 'permission_id' => 1],
            ['role_id' => 1, 'permission_id' => 2],
            ['role_id' => 1, 'permission_id' => 3],
            ['role_id' => 2, 'permission_id' => 1],
        ]);
    }

    private function login(int $user = 1): void
    {
        Sanctum::actingAs(User::query()->findOrFail($user));
    }

    public function test_endpoints_require_authentication(): void
    {
        $this->getJson('/api/v1/companies/1/settings/hours')->assertUnauthorized();
        $this->getJson('/api/v1/companies/1/special-hours')->assertUnauthorized();
        $this->getJson('/api/v1/companies/1/social-links')->assertUnauthorized();
    }

    public function test_weekly_schedule_is_saved_and_partial_update_preserves_other_days(): void
    {
        $this->login();
        $url = '/api/v1/companies/1/settings/hours';
        $this->patchJson($url, ['days' => [
            ['day_of_week' => 0, 'is_closed' => true],
            ['day_of_week' => 1, 'is_closed' => false, 'opens_at' => '08:00',
                'closes_at' => '17:00', 'break_starts_at' => '12:00', 'break_ends_at' => '13:00'],
        ]])->assertOk()->assertJsonCount(2, 'days');

        $this->patchJson($url, ['days' => [
            ['day_of_week' => 1, 'is_closed' => false, 'opens_at' => '07:00', 'closes_at' => '16:00'],
        ]])->assertOk()->assertJsonCount(2, 'days');

        $this->assertSame(2, DB::table('company_business_hours')->where('company_id', 1)->count());
        $this->assertSame('07:00', substr((string) DB::table('company_business_hours')
            ->where('company_id', 1)->where('day_of_week', 1)->value('opens_at'), 0, 5));
        $this->assertSame(1, (int) DB::table('company_business_hours')
            ->where('company_id', 1)->where('day_of_week', 0)->value('is_closed'));
    }

    public function test_weekly_invalid_times_and_duplicate_days_are_rejected(): void
    {
        $this->login();
        $url = '/api/v1/companies/1/settings/hours';
        $this->patchJson($url, ['days' => [
            ['day_of_week' => 1, 'is_closed' => false, 'opens_at' => '17:00', 'closes_at' => '08:00'],
        ]])->assertUnprocessable();
        $this->patchJson($url, ['days' => [
            ['day_of_week' => 1, 'is_closed' => false, 'opens_at' => '08:00',
                'closes_at' => '17:00', 'break_starts_at' => '19:00', 'break_ends_at' => '20:00'],
        ]])->assertUnprocessable();
        $this->patchJson($url, ['days' => [
            ['day_of_week' => 1, 'is_closed' => true],
            ['day_of_week' => 1, 'is_closed' => true],
        ]])->assertUnprocessable();
        $this->assertSame(0, DB::table('company_business_hours')->count());
    }

    public function test_special_hours_crud_and_date_filters(): void
    {
        $this->login();
        $url = '/api/v1/companies/1/special-hours';
        $created = $this->postJson($url, [
            'special_date' => '2027-01-01', 'reason' => 'AÃ±o nuevo', 'is_closed' => true,
        ])->assertCreated()->assertJsonPath('special.is_closed', 1);
        $id = $created->json('special.id');
        $this->getJson($url . '?from=2027-01-01&to=2027-01-01')
            ->assertOk()->assertJsonPath('data.0.id', $id);
        $this->patchJson("$url/$id", [
            'is_closed' => false, 'opens_at' => '09:00', 'closes_at' => '14:00',
        ])->assertOk()->assertJsonPath('special.reason', 'AÃ±o nuevo');
        $this->deleteJson("$url/$id")->assertOk();
        $this->assertDatabaseMissing('company_special_hours', ['id' => $id, 'company_id' => 1]);
    }

    public function test_special_hours_reject_duplicate_and_invalid_schedule(): void
    {
        $this->login();
        $url = '/api/v1/companies/1/special-hours';
        $this->postJson($url, [
            'special_date' => '2027-05-01', 'is_closed' => false,
            'opens_at' => '08:00', 'closes_at' => '15:00',
        ])->assertCreated();
        $this->postJson($url, [
            'special_date' => '2027-05-01', 'is_closed' => true,
        ])->assertUnprocessable();
        $this->postJson($url, [
            'special_date' => '2027-05-02', 'is_closed' => false,
            'opens_at' => '20:00', 'closes_at' => '06:00',
        ])->assertUnprocessable();
        $this->assertSame(1, DB::table('company_special_hours')->count());
    }

    public function test_social_links_crud_search_and_validation(): void
    {
        $this->login();
        $url = '/api/v1/companies/1/social-links';
        $created = $this->postJson($url, [
            'platform' => 'instagram', 'username' => 'pruebas.adn',
            'url' => 'https://instagram.com/pruebas.adn',
        ])->assertCreated();
        $id = $created->json('social.id');
        $this->getJson($url . '?q=pruebas.adn')->assertOk()->assertJsonPath('data.0.id', $id);
        $this->patchJson("$url/$id", ['is_visible' => false, 'sort_order' => 3])
            ->assertOk()->assertJsonPath('social.sort_order', 3);
        $this->postJson($url, ['platform' => 'facebook', 'url' => 'javascript:alert(1)'])
            ->assertUnprocessable();
        $this->deleteJson("$url/$id")->assertOk();
        $this->assertDatabaseMissing('company_social_links', ['id' => $id, 'company_id' => 1]);
    }

    public function test_cannot_access_other_company_records(): void
    {
        $this->login();
        $this->getJson('/api/v1/companies/2/settings/hours')->assertNotFound();
        $this->getJson('/api/v1/companies/2/special-hours')->assertNotFound();
        $this->getJson('/api/v1/companies/2/social-links')->assertNotFound();
        $this->patchJson('/api/v1/companies/2/settings/hours', ['days' => [
            ['day_of_week' => 0, 'is_closed' => true],
        ]])->assertNotFound();

        // No se permite modificar registros de otra empresa usando su ID.
        $foreignSpecial = DB::table('company_special_hours')->insertGetId([
            'company_id' => 2, 'special_date' => '2027-12-25', 'is_closed' => true,
        ]);
        $foreignSocial = DB::table('company_social_links')->insertGetId([
            'company_id' => 2, 'platform' => 'facebook', 'url' => 'https://facebook.com/otro-qa',
        ]);
        $this->patchJson("/api/v1/companies/1/special-hours/$foreignSpecial", [
            'reason' => 'Modificacion indebida',
        ])->assertNotFound();
        $this->deleteJson("/api/v1/companies/1/social-links/$foreignSocial")->assertNotFound();
        $this->assertDatabaseHas('company_special_hours', ['id' => $foreignSpecial, 'company_id' => 2]);
        $this->assertDatabaseHas('company_social_links', ['id' => $foreignSocial, 'company_id' => 2]);
    }

    public function test_view_only_user_cannot_modify_hours_or_socials(): void
    {
        $this->login(2);
        $this->getJson('/api/v1/companies/1/settings/hours')->assertOk();
        $this->patchJson('/api/v1/companies/1/settings/hours', ['days' => [
            ['day_of_week' => 0, 'is_closed' => true],
        ]])->assertForbidden();
        $this->postJson('/api/v1/companies/1/special-hours', [
            'special_date' => '2027-01-01', 'is_closed' => true,
        ])->assertForbidden();
        $this->postJson('/api/v1/companies/1/social-links', [
            'platform' => 'tiktok', 'url' => 'https://tiktok.com/@qa',
        ])->assertForbidden();
    }
}