<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('cash_registers', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id');
            $t->string('code', 40); $t->string('name', 140);
            $t->string('currency', 3)->default('HNL');
            $t->text('notes')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'cash_register_scope_uk');
            $t->foreign(['branch_id','company_id'], 'cash_register_branch_fk')
                ->references(['id','company_id'])->on('branches')->restrictOnDelete();
            $t->index(['company_id','branch_id'], 'cash_register_branch_idx');
        });
        Schema::create('cash_expense_categories', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('name', 140); $t->text('description')->nullable();
            $t->boolean('is_active')->default(true);
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id','company_id'], 'cash_category_scope_uk');
            $t->index(['company_id','name'], 'cash_category_name_idx');
        });
        Schema::create('cash_sessions', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('register_id');
            $t->unsignedBigInteger('opened_by');
            $t->unsignedBigInteger('closed_by')->nullable();
            $t->unsignedBigInteger('open_register_id')->nullable();
            $t->string('status', 12)->default('OPEN');
            $t->decimal('opening_cash', 14, 2);
            $t->decimal('counted_cash', 14, 2)->nullable();
            $t->decimal('expected_cash', 14, 2)->nullable();
            $t->decimal('difference_cash', 14, 2)->nullable();
            $t->text('notes')->nullable();
            $t->timestamp('opened_at'); $t->timestamp('closed_at')->nullable();
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id','company_id'], 'cash_session_scope_uk');
            $t->unique(['company_id','open_register_id'], 'cash_one_open_register_uk');
            $t->foreign(['register_id','company_id'], 'cash_session_register_fk')
                ->references(['id','company_id'])->on('cash_registers')->restrictOnDelete();
            $t->index(['company_id','status'], 'cash_session_status_idx');
        });
        Schema::create('cash_movements', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('session_id');
            $t->unsignedBigInteger('expense_category_id')->nullable();
            $t->string('direction', 3); // IN / OUT
            $t->decimal('amount', 14, 2);
            $t->string('reference', 100)->nullable();
            $t->text('notes')->nullable();
            $t->unsignedBigInteger('actor_user_id');
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id','company_id'], 'cash_movement_scope_uk');
            $t->foreign(['session_id','company_id'], 'cash_movement_session_fk')
                ->references(['id','company_id'])->on('cash_sessions')->restrictOnDelete();
            $t->foreign(['expense_category_id','company_id'], 'cash_movement_category_fk')
                ->references(['id','company_id'])->on('cash_expense_categories')->restrictOnDelete();
            $t->index(['company_id','session_id'], 'cash_movement_session_idx');
        });
        Schema::create('cash_movement_events', function (Blueprint $t): void {
            $t->id();
            $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('movement_id');
            $t->string('action', 16);
            $t->longText('before_json')->nullable();
            $t->longText('after_json')->nullable();
            $t->unsignedBigInteger('actor_user_id');
            $t->timestamp('occurred_at');
            $t->foreign(['movement_id','company_id'], 'cash_event_movement_fk')
                ->references(['id','company_id'])->on('cash_movements')->restrictOnDelete();
            $t->index(['company_id','movement_id'], 'cash_event_movement_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('cash_movement_events');
        Schema::dropIfExists('cash_movements');
        Schema::dropIfExists('cash_sessions');
        Schema::dropIfExists('cash_expense_categories');
        Schema::dropIfExists('cash_registers');
    }
};
