<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('staff_shifts', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id');
            $t->string('name', 120);
            $t->unsignedTinyInteger('day_of_week'); // 0 domingo a 6 sabado
            $t->time('starts_at');
            $t->time('ends_at');
            $t->boolean('is_active')->default(true);
            $t->string('notes', 500)->nullable();
            $t->timestamps();
            $t->softDeletes();
            $t->foreign(['branch_id', 'company_id'])->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
            $t->unique(['id', 'company_id']);
            $t->index(['company_id', 'branch_id', 'day_of_week']);
        });
        Schema::create('staff_shift_assignments', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('shift_id');
            $t->unsignedBigInteger('employee_id');
            $t->date('effective_from');
            $t->date('effective_to')->nullable();
            $t->boolean('is_active')->default(true);
            $t->string('notes', 500)->nullable();
            $t->timestamps();
            $t->softDeletes();
            $t->foreign(['branch_id', 'company_id'])->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
            $t->foreign(['shift_id', 'company_id'])->references(['id', 'company_id'])->on('staff_shifts')->restrictOnDelete();
            $t->foreign('employee_id')->references('id')->on('employees')->restrictOnDelete();
            $t->index(['company_id','employee_id','effective_from']);
            $t->index(['company_id','branch_id','is_active']);
        });
        Schema::create('booking_blocks', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('bay_id')->nullable(); // null = sucursal completa
            $t->dateTime('start_at_utc');
            $t->dateTime('end_at_utc');
            $t->string('reason', 200);
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->softDeletes();
            $t->foreign(['branch_id','company_id'])->references(['id','company_id'])->on('branches')->restrictOnDelete();
            $t->foreign('bay_id')->references('id')->on('wash_bays')->restrictOnDelete();
            $t->index(['company_id','branch_id','start_at_utc','end_at_utc'], 'blocks_interval_index');
        });
        Schema::create('wash_bookings', function (Blueprint $t): void {
            $t->id();
            $t->uuid('public_id')->unique();
            $t->string('booking_code', 48)->unique();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('bay_id');
            $t->unsignedBigInteger('vehicle_id');
            $t->unsignedBigInteger('service_id');
            $t->dateTime('start_at_utc');
            $t->dateTime('end_at_utc');
            $t->string('timezone_id', 80);
            $t->date('local_date');
            $t->string('status', 24)->default('CONFIRMED');
            $t->decimal('quoted_price', 12, 2);
            $t->unsignedSmallInteger('estimated_minutes');
            $t->string('notes', 1000)->nullable();
            $t->unsignedInteger('version')->default(1);
            $t->timestamps();
            $t->softDeletes();
            $t->foreign(['branch_id','company_id'])->references(['id','company_id'])->on('branches')->restrictOnDelete();
            $t->foreign('bay_id')->references('id')->on('wash_bays')->restrictOnDelete();
            $t->foreign('vehicle_id')->references('id')->on('vehicles')->restrictOnDelete();
            $t->foreign('service_id')->references('id')->on('wash_services')->restrictOnDelete();
            $t->unique(['id','company_id']);
            $t->index(['company_id','branch_id','start_at_utc','end_at_utc'],'bookings_interval_index');
            $t->index(['company_id','status','local_date']);
        });
        Schema::create('booking_events', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('booking_id');
            $t->string('action', 30);
            $t->string('from_status', 24)->nullable();
            $t->string('to_status', 24)->nullable();
            $t->unsignedBigInteger('actor_user_id')->nullable();
            $t->timestamp('occurred_at');
            $t->foreign(['booking_id','company_id'])->references(['id','company_id'])->on('wash_bookings')->restrictOnDelete();
            $t->index(['company_id','booking_id','id']);
        });
    }
    public function down(): void
    {
        Schema::dropIfExists('booking_events');
        Schema::dropIfExists('wash_bookings');
        Schema::dropIfExists('booking_blocks');
        Schema::dropIfExists('staff_shift_assignments');
        Schema::dropIfExists('staff_shifts');
    }
};
