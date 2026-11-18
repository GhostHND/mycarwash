<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('service_vehicle_prices', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('service_id');
            $table->string('vehicle_type', 60);
            $table->decimal('price', 12, 2);
            $table->timestamps();
            $table->unique(['service_id', 'vehicle_type'], 'service_vehicle_prices_unique');
            $table->index(['company_id', 'service_id']);
        });
    }
    public function down(): void { Schema::dropIfExists('service_vehicle_prices'); }
};
