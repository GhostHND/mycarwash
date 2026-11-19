<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('washer_attendance_24n3')) {
            Schema::create('washer_attendance_24n3', function (Blueprint $t): void {
                $t->id();
                $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
                $t->unsignedBigInteger('employee_id');
                $t->date('work_date'); // Fecha local al registrar la entrada.
                $t->timestamp('check_in_at'); // Marca absoluta del servidor UTC.
                $t->timestamp('check_out_at')->nullable();
                $t->timestamps();
                $t->foreign('employee_id')->references('id')->on('employees')->restrictOnDelete();
                $t->unique(['company_id','employee_id','work_date'], 'washer_attendance_unique_day');
                $t->index(['company_id','employee_id','check_in_at'], 'washer_attendance_employee_index');
            });
        }
    }

    public function down(): void
    {
        Schema::dropIfExists('washer_attendance_24n3');
    }
};
