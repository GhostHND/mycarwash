<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('purchase_orders', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('supplier_id');
            $t->string('number', 48);
            $t->string('status', 16)->default('ORDERED');
            $t->decimal('total', 16, 2)->default(0);
            $t->string('supplier_reference', 100)->nullable();
            $t->text('notes')->nullable();
            $t->unsignedBigInteger('created_by');
            $t->timestamps();
            $t->unique(['company_id', 'number'], 'purchase_number_company_unique');
            $t->index(['company_id', 'branch_id', 'created_at'], 'purchase_order_scope_date_idx');
        });
        Schema::create('purchase_order_lines', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('order_id');
            $t->unsignedBigInteger('item_id');
            $t->string('sku_snapshot', 80);
            $t->string('name_snapshot', 160);
            $t->string('unit_snapshot', 24);
            $t->decimal('ordered_quantity', 14, 3);
            $t->decimal('received_quantity', 14, 3)->default(0);
            $t->decimal('unit_cost', 14, 2);
            $t->decimal('line_total', 16, 2);
            $t->timestamps();
            $t->index(['company_id','order_id'], 'purchase_lines_scope_idx');
        });
        Schema::create('purchase_receipts', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('order_id');
            $t->unsignedBigInteger('branch_id');
            $t->string('idempotency_key', 80);
            $t->string('supplier_document', 100)->nullable();
            $t->unsignedBigInteger('received_by');
            $t->timestamp('received_at');
            $t->timestamps();
            $t->unique(['company_id','idempotency_key'], 'purchase_receipt_idempotency_unique');
            $t->index(['company_id','branch_id','received_at'], 'purchase_receipt_scope_date_idx');
        });
        Schema::create('purchase_receipt_lines', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('receipt_id');
            $t->unsignedBigInteger('order_line_id');
            $t->unsignedBigInteger('item_id');
            $t->unsignedBigInteger('inventory_movement_id');
            $t->decimal('quantity', 14, 3);
            $t->decimal('unit_cost', 14, 2);
            $t->timestamps();
            $t->index(['company_id','receipt_id'], 'purchase_receipt_lines_scope_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('purchase_receipt_lines');
        Schema::dropIfExists('purchase_receipts');
        Schema::dropIfExists('purchase_order_lines');
        Schema::dropIfExists('purchase_orders');
    }
};
