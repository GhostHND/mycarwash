<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('booking_daily_assignments')) {
            Schema::create('booking_daily_assignments', function (Blueprint $t): void {
                $t->id();
                $t->unsignedBigInteger('company_id');
                $t->unsignedBigInteger('branch_id');
                $t->unsignedBigInteger('booking_id');
                $t->unsignedBigInteger('employee_id');
                $t->dateTime('booking_start_utc');
                $t->unsignedBigInteger('assigned_by');
                $t->timestamps();
                $t->unique(['company_id','booking_id'], 'booking_daily_one_assignment');
                $t->index(['company_id','branch_id','booking_start_utc'], 'booking_daily_branch_index');
                $t->index(['company_id','employee_id','booking_start_utc'], 'booking_daily_employee_index');
                $t->foreign(['booking_id','company_id'])->references(['id','company_id'])->on('wash_bookings')->restrictOnDelete();
                $t->foreign('employee_id')->references('id')->on('employees')->restrictOnDelete();
                $t->foreign('assigned_by')->references('id')->on('users')->restrictOnDelete();
            });
        }
        if (!Schema::hasTable('booking_reminder_reads')) {
            Schema::create('booking_reminder_reads', function (Blueprint $t): void {
                $t->id();
                $t->unsignedBigInteger('company_id');
                $t->unsignedBigInteger('branch_id');
                $t->unsignedBigInteger('user_id');
                $t->unsignedBigInteger('booking_id');
                $t->date('target_date');
                $t->timestamps();
                $t->unique(['company_id','user_id','booking_id','target_date'], 'booking_reminder_once_per_booking');
                $t->foreign('user_id')->references('id')->on('users')->restrictOnDelete();
                $t->foreign(['booking_id','company_id'])->references(['id','company_id'])->on('wash_bookings')->restrictOnDelete();
            });
        }
    }
    public function down(): void
    {
        Schema::dropIfExists('booking_reminder_reads');
        Schema::dropIfExists('booking_daily_assignments');
    }
};
