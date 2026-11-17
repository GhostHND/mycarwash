<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        Schema::create('pos_document_template_revisions', function (Blueprint $table): void {
            $table->id();
            $table->unsignedBigInteger('company_id');
            $table->unsignedBigInteger('branch_id');
            $table->string('document_type', 24);
            $table->unsignedInteger('revision');
            $table->mediumText('design_json');
            $table->unsignedBigInteger('author_user_id');
            $table->timestamps();
            $table->unique(['company_id', 'branch_id', 'document_type', 'revision'], 'pos_template_revision_unique');
            $table->index(['company_id', 'branch_id', 'document_type', 'id'], 'pos_template_current_idx');
            $table->foreign(['branch_id', 'company_id'], 'pos_template_branch_fk')
                ->references(['id', 'company_id'])->on('branches')->restrictOnDelete();
        });
        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->unsignedBigInteger('document_template_revision_id')->nullable()->index('pos_sale_template_revision_idx');
        });
    }

    public function down(): void
    {
        Schema::table('pos_sales', function (Blueprint $table): void {
            $table->dropIndex('pos_sale_template_revision_idx');
            $table->dropColumn('document_template_revision_id');
        });
        Schema::dropIfExists('pos_document_template_revisions');
    }
};
