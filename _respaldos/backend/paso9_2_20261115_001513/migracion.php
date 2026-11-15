<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // =========================================
        // EMPRESAS
        // =========================================

        Schema::create('companies', function (Blueprint $table) {
            $table->id();

            $table->uuid('public_id')->unique();

            $table->string('name', 180);

            $table->string('slug', 120)->unique();

            $table->string('database_name', 100)
                ->nullable()
                ->unique();

            $table->string('master_instance_id', 120)
                ->nullable()
                ->index();

            $table->boolean('is_active')->default(true);

            $table->timestamps();
        });

        // =========================================
        // SUCURSALES
        // =========================================

        Schema::create('branches', function (Blueprint $table) {
            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('name', 180);

            $table->string('slug', 120);

            $table->string('database_name', 100)
                ->nullable()
                ->unique();

            $table->string('address', 255)->nullable();

            $table->string('phone', 35)->nullable();

            $table->string('timezone', 80)
                ->default('America/Tegucigalpa');

            $table->boolean('is_active')->default(true);

            $table->timestamps();

            $table->unique(['company_id', 'slug']);

            $table->unique(['id', 'company_id']);
        });

        // =========================================
        // USUARIOS POR EMPRESA
        // =========================================

        Schema::create('company_user', function (Blueprint $table) {
            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->foreignId('user_id')
                ->constrained('users')
                ->restrictOnDelete();

            $table->string('status', 25)->default('active');

            $table->boolean('access_all_branches')
                ->default(false);

            $table->timestamps();

            $table->unique(['company_id', 'user_id']);
        });

        // =========================================
        // USUARIOS POR SUCURSAL
        // =========================================

        Schema::create('branch_user', function (Blueprint $table) {
            $table->id();

            $table->unsignedBigInteger('company_id');

            $table->unsignedBigInteger('branch_id');

            $table->unsignedBigInteger('user_id');

            $table->timestamps();

            $table->unique(['branch_id', 'user_id']);

            $table->foreign(['branch_id', 'company_id'])
                ->references(['id', 'company_id'])
                ->on('branches')
                ->restrictOnDelete();

            $table->foreign(['company_id', 'user_id'])
                ->references(['company_id', 'user_id'])
                ->on('company_user')
                ->restrictOnDelete();
        });

        // =========================================
        // ROLES
        // =========================================

        Schema::create('roles', function (Blueprint $table) {
            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('name', 100);

            $table->string('code', 80);

            $table->boolean('is_system')->default(false);

            $table->timestamps();

            $table->unique(['company_id', 'code']);

            $table->unique(['id', 'company_id']);
        });

        // =========================================
        // PERMISOS
        // =========================================

        Schema::create('permissions', function (Blueprint $table) {
            $table->id();

            $table->string('code', 150)->unique();

            $table->string('module', 100);

            $table->string('description', 255)->nullable();

            $table->timestamps();
        });

        // =========================================
        // PERMISOS POR ROL
        // =========================================

        Schema::create('role_permission', function (Blueprint $table) {
            $table->id();

            $table->foreignId('role_id')
                ->constrained('roles')
                ->restrictOnDelete();

            $table->foreignId('permission_id')
                ->constrained('permissions')
                ->restrictOnDelete();

            $table->timestamps();

            $table->unique(['role_id', 'permission_id']);
        });

        // =========================================
        // ROLES ASIGNADOS A USUARIOS
        // =========================================

        Schema::create('user_roles', function (Blueprint $table) {
            $table->id();

            $table->unsignedBigInteger('company_id');

            $table->unsignedBigInteger('user_id');

            $table->unsignedBigInteger('role_id');

            $table->timestamps();

            $table->unique(['user_id', 'role_id']);

            $table->foreign(['company_id', 'user_id'])
                ->references(['company_id', 'user_id'])
                ->on('company_user')
                ->restrictOnDelete();

            $table->foreign(['role_id', 'company_id'])
                ->references(['id', 'company_id'])
                ->on('roles')
                ->restrictOnDelete();
        });

        // =========================================
        // PREFERENCIAS DE USUARIO
        // =========================================

        Schema::create('user_preferences', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->restrictOnDelete();

            $table->string('theme_mode', 12)
                ->default('system');

            $table->string('locale', 12)
                ->default('es-HN');

            $table->timestamps();

            $table->unique('user_id');
        });

        // =========================================
        // GUIA INTERACTIVA DE PRIMER USO
        // =========================================

        Schema::create('onboarding_progress', function (Blueprint $table) {
            $table->id();

            $table->foreignId('user_id')
                ->constrained('users')
                ->restrictOnDelete();

            $table->string('guide_key', 120);

            $table->unsignedInteger('guide_version')
                ->default(1);

            $table->unsignedInteger('last_step')
                ->default(0);

            $table->timestamp('completed_at')->nullable();

            $table->timestamps();

            $table->unique(['user_id', 'guide_key']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('onboarding_progress');

        Schema::dropIfExists('user_preferences');

        Schema::dropIfExists('user_roles');

        Schema::dropIfExists('role_permission');

        Schema::dropIfExists('permissions');

        Schema::dropIfExists('roles');

        Schema::dropIfExists('branch_user');

        Schema::dropIfExists('company_user');

        Schema::dropIfExists('branches');

        Schema::dropIfExists('companies');
    }
};