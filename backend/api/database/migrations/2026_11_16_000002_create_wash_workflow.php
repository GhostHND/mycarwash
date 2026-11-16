<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('wash_bays', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $table->unsignedBigInteger('branch_id');
            $table->string('name', 120);
            $table->string('code', 40);
            $table->text('notes')->nullable();
            $table->boolean('is_active')->default(true);
            $table->timestamps();
            $table->softDeletes();
            $table->foreign(['branch_id', 'company_id'])->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
            $table->unique(['id', 'company_id']);
            $table->index(['company_id', 'branch_id', 'code']);
        });
        Schema::create('wash_orders', function (Blueprint $table): void {
            $table->id();
            $table->uuid('public_id')->unique();
            $table->string('tracking_code', 48)->unique();
            $table->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $table->unsignedBigInteger('branch_id');
            $table->unsignedBigInteger('vehicle_id');
            $table->unsignedBigInteger('service_id');
            $table->unsignedBigInteger('bay_id')->nullable();
            $table->string('status', 25)->default('EN_ESPERA');
            $table->decimal('quoted_price', 12, 2);
            $table->unsignedSmallInteger('estimated_minutes');
            $table->text('notes')->nullable();
            $table->unsignedInteger('version')->default(1);
            $table->timestamp('started_at')->nullable();
            $table->timestamp('completed_at')->nullable();
            $table->timestamp('delivered_at')->nullable();
            $table->timestamps();
            $table->foreign(['branch_id', 'company_id'])->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
            $table->foreign('vehicle_id')->references('id')->on('vehicles')->restrictOnDelete();
            $table->foreign('service_id')->references('id')->on('wash_services')->restrictOnDelete();
            $table->foreign('bay_id')->references('id')->on('wash_bays')->restrictOnDelete();
            $table->unique(['id', 'company_id']);
            $table->index(['company_id', 'branch_id', 'status', 'created_at']);
        });
        Schema::create('wash_assignments', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $table->unsignedBigInteger('order_id');
            $table->unsignedBigInteger('employee_id');
            $table->string('function', 80)->default('lavado');
            $table->boolean('is_primary')->default(false);
            $table->boolean('is_active')->default(true);
            $table->timestamp('assigned_at');
            $table->timestamp('released_at')->nullable();
            $table->text('notes')->nullable();
            $table->timestamps();
            $table->foreign(['order_id', 'company_id'])->references(['id', 'company_id'])->on('wash_orders')->restrictOnDelete();
            $table->foreign('employee_id')->references('id')->on('employees')->restrictOnDelete();
            $table->index(['company_id', 'order_id', 'is_active']);
            $table->index(['company_id', 'employee_id', 'is_active']);
        });
        // La biblioteca empresarial company_media_assets ya existe desde el
        // Bloque de configuracion. Esta extension solo vincula activos visuales
        // privados con los vehiculos y empleados, sin recrearla ni alterarla.
        Schema::create('company_entity_photos', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $table->string('owner_type', 20);
            $table->unsignedBigInteger('owner_id');
            $table->foreignId('media_asset_id')->constrained('company_media_assets')->restrictOnDelete();
            $table->boolean('show_on_kiosk')->default(false);
            $table->timestamps();
            $table->unique(['company_id', 'owner_type', 'owner_id'], 'company_entity_photos_owner_unique');
            $table->unique('media_asset_id');
        });
        Schema::create('wash_order_events', function (Blueprint $table): void {
            $table->id();
            $table->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $table->unsignedBigInteger('order_id');
            $table->string('from_status', 25)->nullable();
            $table->string('to_status', 25);
            $table->string('reason', 255)->nullable();
            $table->unsignedBigInteger('actor_user_id')->nullable();
            $table->timestamp('occurred_at');
            $table->foreign(['order_id', 'company_id'])->references(['id', 'company_id'])->on('wash_orders')->restrictOnDelete();
            $table->index(['company_id', 'order_id', 'id']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('wash_order_events');
        Schema::dropIfExists('company_entity_photos');
        Schema::dropIfExists('wash_assignments');
        Schema::dropIfExists('wash_orders');
        Schema::dropIfExists('wash_bays');
    }
};
