<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('sale_bank_accounts', function (Blueprint $t): void {
            $t->id(); $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('branch_id'); $t->string('alias', 120);
            $t->string('bank_name', 160); $t->string('account_last4', 4)->nullable();
            $t->string('currency', 3)->default('HNL'); $t->boolean('is_active')->default(true);
            $t->text('notes')->nullable(); $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'sale_bank_company_uk');
            $t->foreign(['branch_id', 'company_id'], 'sale_bank_branch_fk')
                ->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
            $t->index(['company_id', 'branch_id'], 'sale_bank_branch_idx');
        });
        Schema::create('sale_payment_methods', function (Blueprint $t): void {
            $t->id(); $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->string('name', 120); $t->string('channel', 10); // CASH o BANK
            $t->boolean('is_active')->default(true); $t->text('notes')->nullable();
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'sale_method_company_uk');
            $t->index(['company_id', 'channel'], 'sale_method_channel_idx');
        });
        Schema::create('wash_order_discounts', function (Blueprint $t): void {
            $t->id(); $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('order_id'); $t->decimal('amount', 12, 2);
            $t->string('reason', 255); $t->unsignedBigInteger('authorized_by');
            $t->timestamps(); $t->softDeletes();
            $t->unique(['order_id', 'company_id'], 'sale_one_discount_order_uk');
            $t->foreign(['order_id', 'company_id'], 'sale_discount_order_fk')
                ->references(['id', 'company_id'])->on('wash_orders')->restrictOnDelete();
        });
        Schema::create('wash_order_payments', function (Blueprint $t): void {
            $t->id(); $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('order_id'); $t->unsignedBigInteger('payment_method_id');
            $t->unsignedBigInteger('cash_session_id')->nullable();
            $t->unsignedBigInteger('bank_account_id')->nullable();
            $t->decimal('amount', 12, 2); $t->string('status', 12)->default('PENDING');
            $t->string('reference', 120)->nullable(); $t->text('notes')->nullable();
            $t->unsignedBigInteger('registered_by'); $t->timestamp('posted_at')->nullable();
            $t->timestamps(); $t->softDeletes();
            $t->unique(['id', 'company_id'], 'sale_payment_company_uk');
            $t->foreign(['order_id', 'company_id'], 'sale_payment_order_fk')
                ->references(['id', 'company_id'])->on('wash_orders')->restrictOnDelete();
            $t->foreign(['payment_method_id', 'company_id'], 'sale_payment_method_fk')
                ->references(['id', 'company_id'])->on('sale_payment_methods')->restrictOnDelete();
            $t->foreign(['cash_session_id', 'company_id'], 'sale_payment_session_fk')
                ->references(['id', 'company_id'])->on('cash_sessions')->restrictOnDelete();
            $t->foreign(['bank_account_id', 'company_id'], 'sale_payment_bank_fk')
                ->references(['id', 'company_id'])->on('sale_bank_accounts')->restrictOnDelete();
            $t->index(['company_id', 'order_id', 'status'], 'sale_payment_order_idx');
        });
        Schema::create('sale_bank_movements', function (Blueprint $t): void {
            $t->id(); $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->unsignedBigInteger('bank_account_id'); $t->unsignedBigInteger('payment_id');
            $t->decimal('amount', 12, 2); $t->timestamp('posted_at');
            $t->foreign(['bank_account_id', 'company_id'], 'sale_ledger_bank_fk')
                ->references(['id', 'company_id'])->on('sale_bank_accounts')->restrictOnDelete();
            $t->foreign(['payment_id', 'company_id'], 'sale_ledger_payment_fk')
                ->references(['id', 'company_id'])->on('wash_order_payments')->restrictOnDelete();
            $t->unique('payment_id', 'sale_ledger_once_uk');
            $t->index(['company_id', 'bank_account_id'], 'sale_ledger_bank_idx');
        });
        Schema::table('cash_movements', function (Blueprint $t): void {
            $t->unsignedBigInteger('source_sale_payment_id')->nullable();
            $t->unique('source_sale_payment_id', 'cash_sale_payment_once_uk');
            $t->foreign(['source_sale_payment_id', 'company_id'], 'cash_sale_payment_fk')
                ->references(['id', 'company_id'])->on('wash_order_payments')->restrictOnDelete();
        });
    }

    public function down(): void
    {
        Schema::table('cash_movements', function (Blueprint $t): void {
            $t->dropForeign('cash_sale_payment_fk');
            $t->dropUnique('cash_sale_payment_once_uk');
            $t->dropColumn('source_sale_payment_id');
        });
        Schema::dropIfExists('sale_bank_movements');
        Schema::dropIfExists('wash_order_payments');
        Schema::dropIfExists('wash_order_discounts');
        Schema::dropIfExists('sale_payment_methods');
        Schema::dropIfExists('sale_bank_accounts');
    }
};
