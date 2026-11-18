<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->unsignedBigInteger('wash_order_id')->nullable();
            $table->string('wash_service_snapshot', 180)->nullable();
            $table->decimal('wash_price_snapshot', 12, 2)->nullable();
            $table->unique(['company_id', 'wash_order_id'], 'pos_sale_wash_unique_24g');
        });
    }

    public function down(): void
    {
        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->dropUnique('pos_sale_wash_unique_24g');
            $table->dropColumn(['wash_order_id', 'wash_service_snapshot', 'wash_price_snapshot']);
        });
    }
};
