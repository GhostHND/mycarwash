<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('finance_bank_openings_24k', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('bank_account_id');
            $t->date('effective_date');
            $t->decimal('opening_balance', 14, 2);
            $t->unsignedBigInteger('actor_user_id');
            $t->timestamps();
            $t->unique(['company_id', 'bank_account_id'], 'finance24k_one_opening');
            $t->foreign('bank_account_id', 'finance24k_opening_bank_fk')
                ->references('id')->on('sale_bank_accounts')->restrictOnDelete();
            $t->index(['company_id', 'bank_account_id'], 'finance24k_opening_lookup');
        });
        Schema::create('finance_bank_entries_24k', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('bank_account_id');
            $t->date('posted_date');
            $t->string('direction', 3);
            $t->decimal('amount', 14, 2);
            $t->string('reference', 120)->nullable();
            $t->text('notes')->nullable();
            $t->string('idempotency_key', 120);
            $t->string('request_hash', 64);
            $t->unsignedBigInteger('actor_user_id');
            $t->timestamps();
            $t->unique(['company_id','idempotency_key'], 'finance24k_entry_idempotency');
            $t->foreign('bank_account_id', 'finance24k_entry_bank_fk')
                ->references('id')->on('sale_bank_accounts')->restrictOnDelete();
            $t->index(['company_id','bank_account_id','posted_date'], 'finance24k_entry_period');
        });
        Schema::create('finance_bank_closings_24k', function (Blueprint $t): void {
            $t->id();
            $t->unsignedBigInteger('company_id');
            $t->unsignedBigInteger('bank_account_id');
            $t->string('period_kind', 8);
            $t->date('period_start');
            $t->date('period_end');
            $t->string('status', 8)->default('OPEN');
            $t->decimal('expected_balance', 14, 2)->nullable();
            $t->decimal('counted_balance', 14, 2)->nullable();
            $t->decimal('difference_balance', 14, 2)->nullable();
            $t->unsignedBigInteger('opened_by');
            $t->timestamp('opened_at');
            $t->unsignedBigInteger('closed_by')->nullable();
            $t->timestamp('closed_at')->nullable();
            $t->text('notes')->nullable();
            $t->timestamps();
            $t->unique(['company_id','bank_account_id','period_kind','period_start'], 'finance24k_one_closing_period');
            $t->foreign('bank_account_id', 'finance24k_closing_bank_fk')
                ->references('id')->on('sale_bank_accounts')->restrictOnDelete();
            $t->index(['company_id','bank_account_id','period_end'], 'finance24k_closing_lookup');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('finance_bank_closings_24k');
        Schema::dropIfExists('finance_bank_entries_24k');
        Schema::dropIfExists('finance_bank_openings_24k');
    }
};
