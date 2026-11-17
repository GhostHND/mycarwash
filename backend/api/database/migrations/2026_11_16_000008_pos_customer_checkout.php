<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

/** 21A.5: metadatos del cliente, copia histórica y entrega de efectivo. Migración aditiva. */
return new class extends Migration {
    public function up(): void
    {
        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->string('customer_type', 12)->default('CONSUMER');
            $table->unsignedBigInteger('customer_id')->nullable();
            $table->string('customer_name_snapshot', 180)->default('Consumidor final');
            $table->string('customer_identity_snapshot', 50)->nullable();
            $table->string('customer_phone_snapshot', 40)->nullable();
            $table->string('customer_email_snapshot', 190)->nullable();
            $table->text('customer_address_snapshot')->nullable();
            $table->decimal('cash_received', 14, 2)->nullable();
            $table->decimal('change_given', 14, 2)->default(0);
            $table->foreign(['customer_id', 'company_id'], 'pos_sales_client_fk')
                ->references(['id', 'company_id'])->on('clients')->restrictOnDelete();
            $table->index(['company_id', 'customer_id'], 'pos_sales_customer_idx');
        });
    }

    public function down(): void
    {
        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->dropForeign('pos_sales_client_fk');
            $table->dropIndex('pos_sales_customer_idx');
            $table->dropColumn([
                'customer_type', 'customer_id', 'customer_name_snapshot', 'customer_identity_snapshot',
                'customer_phone_snapshot', 'customer_email_snapshot', 'customer_address_snapshot',
                'cash_received', 'change_given',
            ]);
        });
    }
};
