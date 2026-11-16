<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('inventory_categories', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('name', 140);
            $t->text('description')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'inv_categories_scope_uk');
            $t->index(['company_id', 'name'], 'inv_categories_name_idx');
        });
        Schema::create('inventory_suppliers', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('name', 160);
            $t->string('tax_id', 40)->nullable();
            $t->string('phone', 50)->nullable();
            $t->string('email', 180)->nullable();
            $t->string('address', 500)->nullable();
            $t->text('notes')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'inv_suppliers_scope_uk');
            $t->index(['company_id', 'name'], 'inv_suppliers_name_idx');
        });
        Schema::create('inventory_items', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('category_id')->nullable();
            $t->unsignedBigInteger('supplier_id')->nullable();
            $t->string('sku', 80); $t->string('name', 160);
            $t->string('unit', 24)->default('unidad');
            $t->decimal('min_stock', 14, 3)->default(0);
            $t->decimal('cost_price', 14, 2)->default(0);
            $t->decimal('sale_price', 14, 2)->nullable();
            $t->text('description')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'inv_items_scope_uk');
            $t->foreign(['category_id', 'company_id'], 'inv_item_category_fk')
                ->references(['id','company_id'])->on('inventory_categories')->restrictOnDelete();
            $t->foreign(['supplier_id', 'company_id'], 'inv_item_supplier_fk')
                ->references(['id','company_id'])->on('inventory_suppliers')->restrictOnDelete();
            $t->index(['company_id', 'sku'], 'inv_items_sku_idx');
            $t->index(['company_id', 'category_id'], 'inv_items_category_idx');
            $t->index(['company_id', 'supplier_id'], 'inv_items_supplier_idx');
        });
        Schema::create('inventory_movements', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id');
            $t->unsignedBigInteger('item_id');
            $t->string('movement_type', 3); // IN / OUT
            $t->decimal('quantity', 14, 3);
            $t->string('reference', 100)->nullable();
            $t->text('notes')->nullable();
            $t->unsignedBigInteger('actor_user_id');
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'inv_moves_scope_uk');
            $t->foreign(['branch_id', 'company_id'], 'inv_move_branch_fk')
                ->references(['id','company_id'])->on('branches')->restrictOnDelete();
            $t->foreign(['item_id', 'company_id'], 'inv_move_item_fk')
                ->references(['id','company_id'])->on('inventory_items')->restrictOnDelete();
            $t->index(['company_id', 'branch_id', 'item_id'], 'inv_moves_branch_item_idx');
            $t->index(['company_id', 'created_at'], 'inv_moves_company_date_idx');
        });
        Schema::create('inventory_movement_events', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('movement_id');
            $t->string('action', 20);
            $t->longText('before_json')->nullable();
            $t->longText('after_json')->nullable();
            $t->unsignedBigInteger('actor_user_id');
            $t->timestamp('occurred_at');
            $t->foreign(['movement_id','company_id'], 'inv_move_event_fk')
                ->references(['id','company_id'])->on('inventory_movements')->restrictOnDelete();
            $t->index(['company_id', 'movement_id'], 'inv_move_events_scope_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('inventory_movement_events');
        Schema::dropIfExists('inventory_movements');
        Schema::dropIfExists('inventory_items');
        Schema::dropIfExists('inventory_suppliers');
        Schema::dropIfExists('inventory_categories');
    }
};
