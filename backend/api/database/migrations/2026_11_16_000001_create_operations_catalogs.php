<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('clients', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('full_name', 180);
            $t->string('identity_document', 50)->nullable();
            $t->string('phone', 40)->nullable();
            $t->string('email', 190)->nullable();
            $t->text('address')->nullable();
            $t->text('notes')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();
            $t->index(['company_id', 'full_name']);
            $t->index(['company_id', 'identity_document']);
            $t->unique(['id', 'company_id']);
        });

        Schema::create('vehicles', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('client_id');
            $t->string('plate', 30)->nullable();
            $t->string('brand', 80)->nullable();
            $t->string('model', 100)->nullable();
            $t->string('color', 60)->nullable();
            $t->unsignedSmallInteger('year')->nullable();
            $t->string('vehicle_type', 60)->nullable();
            $t->text('notes')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();
            $t->foreign(['client_id', 'company_id'])
                ->references(['id', 'company_id'])->on('clients')->restrictOnDelete();
            $t->index(['company_id', 'plate']);
            $t->index(['company_id', 'client_id']);
        });

        Schema::create('employees', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('full_name', 180);
            $t->string('identity_document', 50)->nullable();
            $t->string('phone', 40)->nullable();
            $t->string('email', 190)->nullable();
            $t->string('position', 60)->default('washer');
            $t->date('hire_date')->nullable();
            $t->text('notes')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();
            $t->index(['company_id', 'full_name']);
            $t->index(['company_id', 'position']);
        });

        Schema::create('wash_services', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('name', 150);
            $t->text('description')->nullable();
            $t->decimal('price', 12, 2);
            $t->unsignedSmallInteger('duration_minutes');
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();
            $t->index(['company_id', 'name']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('wash_services');
        Schema::dropIfExists('employees');
        Schema::dropIfExists('vehicles');
        Schema::dropIfExists('clients');
    }
};
