<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        Schema::create('finance_internal_transfers_24k2', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('bank_account_id');
            $table->unsignedBigInteger('cash_session_id');
            $table->string('direction', 16);
            $table->decimal('amount', 14, 2);
            $table->string('reference', 120)->nullable();
            $table->text('notes')->nullable();
            $table->string('idempotency_key', 120);
            $table->string('request_hash', 64);
            $table->unsignedBigInteger('actor_user_id');
            $table->timestamp('transferred_at');
            $table->timestamps();
            $table->unique(['company_id','idempotency_key'], 'finance24k2_idempotency');
            $table->foreign('bank_account_id', 'finance24k2_bank_fk')
                ->references('id')->on('sale_bank_accounts')->restrictOnDelete();
            $table->foreign('cash_session_id', 'finance24k2_cash_fk')
                ->references('id')->on('cash_sessions')->restrictOnDelete();
            $table->index(['company_id','bank_account_id','transferred_at'], 'finance24k2_bank_idx');
            $table->index(['company_id','cash_session_id','transferred_at'], 'finance24k2_cash_idx');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('finance_internal_transfers_24k2');
    }
};
