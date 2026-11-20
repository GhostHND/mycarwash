<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('monitor_devices_rpi01c', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('branch_id');
            $table->string('name', 90);
            $table->char('key_hash', 64)->unique();
            $table->boolean('is_active')->default(true);
            $table->timestamp('last_seen_at')->nullable();
            $table->timestamps();
            $table->index(['company_id', 'branch_id', 'is_active'], 'rpi01c_company_branch_active');
        });
    }
    public function down(): void { Schema::dropIfExists('monitor_devices_rpi01c'); }
};
