<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pos_fiscal_authorizations', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('branch_id');
            $table->string('legal_name', 180);
            $table->string('rtn', 20);
            $table->string('cai', 50);
            $table->string('establishment_code', 3);
            $table->string('point_code', 3);
            $table->string('document_code', 2)->default('01');
            $table->unsignedInteger('start_sequence');
            $table->unsignedInteger('end_sequence');
            $table->unsignedInteger('next_sequence');
            $table->date('expires_on');
            $table->boolean('is_active')->default(true);
            $table->unsignedBigInteger('confirmed_by_user_id');
            $table->timestamps();
            $table->index(['company_id', 'branch_id', 'is_active'], 'pos_auth_tenant_branch_idx');
            $table->foreign(['branch_id', 'company_id'], 'pos_auth_branch_fk')
                ->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
        });

        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->string('document_type', 24)->default('RECEIPT');
            $table->decimal('tax_amount', 14, 2)->default(0);
            $table->unsignedSmallInteger('tax_rate_bps')->default(0);
            $table->unsignedBigInteger('fiscal_authorization_id')->nullable();
            $table->string('fiscal_number', 32)->nullable();
            $table->string('fiscal_cai', 50)->nullable();
            $table->string('fiscal_rtn', 20)->nullable();
            $table->string('fiscal_legal_name', 180)->nullable();
            $table->string('fiscal_range_start', 32)->nullable();
            $table->string('fiscal_range_end', 32)->nullable();
            $table->date('fiscal_expires_on')->nullable();
            $table->unique(['company_id', 'fiscal_number'], 'pos_sales_fiscal_number_unique');
        });
    }

    public function down(): void
    {
        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->dropUnique('pos_sales_fiscal_number_unique');
            $table->dropColumn(['document_type','tax_amount','tax_rate_bps',
                'fiscal_authorization_id','fiscal_number','fiscal_cai','fiscal_rtn',
                'fiscal_legal_name','fiscal_range_start','fiscal_range_end','fiscal_expires_on']);
        });
        Schema::dropIfExists('pos_fiscal_authorizations');
    }
};
