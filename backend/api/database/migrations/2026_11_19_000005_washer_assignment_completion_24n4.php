<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('wash_assignments', function (Blueprint $table): void {
            $table->timestamp('washer_finished_at')->nullable();
        });
    }
    public function down(): void
    {
        Schema::table('wash_assignments', function (Blueprint $table): void {
            $table->dropColumn('washer_finished_at');
        });
    }
};
