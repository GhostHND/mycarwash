<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('washer_attendance_points_24n4', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('name',120);
            $t->text('secret_encrypted');
            $t->boolean('is_active')->default(true);
            $t->timestamps();
            $t->index(['company_id','is_active']);
        });
    }
    public function down(): void { Schema::dropIfExists('washer_attendance_points_24n4'); }
};
