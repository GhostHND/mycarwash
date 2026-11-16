<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('pos_sales', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id');
            $t->string('idempotency_key', 100);
            $t->string('request_hash', 64);
            $t->string('status', 12)->default('POSTED');
            $t->decimal('subtotal', 14, 2);
            $t->decimal('discount_amount', 14, 2)->default(0);
            $t->string('discount_reason', 255)->nullable();
            $t->decimal('total', 14, 2);
            $t->unsignedBigInteger('actor_user_id');
            $t->timestamp('posted_at');
            $t->timestamps();
            $t->unique(['id', 'company_id'], 'pos_sales_scope_uk');
            $t->unique(['company_id', 'idempotency_key'], 'pos_sale_idempotency_uk');
            $t->foreign(['branch_id', 'company_id'], 'pos_sales_branch_fk')
                ->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
            $t->index(['company_id', 'branch_id', 'posted_at'], 'pos_sales_history_idx');
        });
        Schema::create('pos_sale_items', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('sale_id');
            $t->unsignedBigInteger('item_id');
            $t->string('sku_snapshot', 80);
            $t->string('name_snapshot', 160);
            $t->string('unit_snapshot', 24);
            $t->decimal('quantity', 14, 3);
            $t->decimal('unit_price', 14, 2);
            $t->decimal('line_total', 14, 2);
            $t->timestamps();
            $t->unique(['id', 'company_id'], 'pos_sale_items_scope_uk');
            $t->foreign(['sale_id', 'company_id'], 'pos_items_sale_fk')
                ->references(['id', 'company_id'])->on('pos_sales')->restrictOnDelete();
            $t->foreign(['item_id', 'company_id'], 'pos_items_product_fk')
                ->references(['id', 'company_id'])->on('inventory_items')->restrictOnDelete();
            $t->index(['company_id', 'sale_id'], 'pos_items_sale_idx');
        });
        Schema::create('pos_sale_payments', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('sale_id');
            $t->unsignedBigInteger('payment_method_id');
            $t->string('channel', 10);
            $t->unsignedBigInteger('cash_session_id')->nullable();
            $t->unsignedBigInteger('bank_account_id')->nullable();
            $t->decimal('amount', 14, 2);
            $t->string('reference', 120)->nullable();
            $t->timestamp('posted_at');
            $t->timestamps();
            $t->unique(['id', 'company_id'], 'pos_payments_scope_uk');
            $t->foreign(['sale_id', 'company_id'], 'pos_payments_sale_fk')
                ->references(['id', 'company_id'])->on('pos_sales')->restrictOnDelete();
            $t->foreign(['payment_method_id', 'company_id'], 'pos_payments_method_fk')
                ->references(['id', 'company_id'])->on('sale_payment_methods')->restrictOnDelete();
            $t->foreign(['cash_session_id', 'company_id'], 'pos_payments_cash_fk')
                ->references(['id', 'company_id'])->on('cash_sessions')->restrictOnDelete();
            $t->foreign(['bank_account_id', 'company_id'], 'pos_payments_bank_fk')
                ->references(['id', 'company_id'])->on('sale_bank_accounts')->restrictOnDelete();
            $t->index(['company_id', 'bank_account_id'], 'pos_bank_ledger_idx');
        });
        Schema::table('inventory_movements', function (Blueprint $t): void {
            $t->unsignedBigInteger('source_pos_sale_item_id')->nullable();
            $t->unique('source_pos_sale_item_id', 'pos_stock_movement_once_uk');
            $t->foreign(['source_pos_sale_item_id', 'company_id'], 'pos_stock_line_fk')
                ->references(['id', 'company_id'])->on('pos_sale_items')->restrictOnDelete();
        });
        Schema::table('cash_movements', function (Blueprint $t): void {
            $t->unsignedBigInteger('source_pos_payment_id')->nullable();
            $t->unique('source_pos_payment_id', 'pos_cash_movement_once_uk');
            $t->foreign(['source_pos_payment_id', 'company_id'], 'pos_cash_payment_fk')
                ->references(['id', 'company_id'])->on('pos_sale_payments')->restrictOnDelete();
        });
    }
    public function down(): void
    {
        Schema::table('cash_movements', function (Blueprint $t): void {
            $t->dropForeign('pos_cash_payment_fk');
            $t->dropUnique('pos_cash_movement_once_uk');
            $t->dropColumn('source_pos_payment_id');
        });
        Schema::table('inventory_movements', function (Blueprint $t): void {
            $t->dropForeign('pos_stock_line_fk');
            $t->dropUnique('pos_stock_movement_once_uk');
            $t->dropColumn('source_pos_sale_item_id');
        });
        Schema::dropIfExists('pos_sale_payments');
        Schema::dropIfExists('pos_sale_items');
        Schema::dropIfExists('pos_sales');
    }
};
