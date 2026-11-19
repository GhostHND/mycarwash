<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void {
        Schema::create('master_operators_24n8', function (Blueprint $t) {
            $t->id(); $t->string('name',180); $t->string('email',255)->unique();
            $t->string('password'); $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('master_customers_24n8', function (Blueprint $t) {
            $t->id(); $t->string('name',180); $t->string('email',255)->nullable();
            $t->string('phone',40)->nullable(); $t->string('tax_id',80)->nullable();
            $t->text('notes')->nullable(); $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('master_plans_24n8', function (Blueprint $t) {
            $t->id(); $t->string('name',100)->unique(); $t->decimal('monthly_price',12,2)->nullable();
            $t->char('currency',3)->default('HNL'); $t->json('features')->nullable();
            $t->boolean('is_active')->default(true); $t->timestamps();
        });
        Schema::create('master_subscriptions_24n8', function (Blueprint $t) {
            $t->id(); $t->foreignId('company_id')->unique()->constrained('companies')->restrictOnDelete();
            $t->foreignId('master_customer_id')->nullable()->constrained('master_customers_24n8')->nullOnDelete();
            $t->foreignId('master_plan_id')->nullable()->constrained('master_plans_24n8')->restrictOnDelete();
            $t->string('status',24)->default('pending');
            $t->date('due_date')->nullable(); $t->unsignedTinyInteger('grace_days')->default(4);
            $t->string('timezone',80)->default('America/Tegucigalpa');
            $t->text('notes')->nullable(); $t->timestamps();
        });
        Schema::create('master_invoices_24n8', function (Blueprint $t) {
            $t->id(); $t->foreignId('company_id')->constrained('companies')->restrictOnDelete();
            $t->foreignId('master_plan_id')->nullable()->constrained('master_plans_24n8')->restrictOnDelete();
            $t->string('reference',90)->unique(); $t->decimal('amount',12,2);
            $t->char('currency',3)->default('HNL'); $t->date('due_date');
            $t->date('coverage_until')->nullable(); $t->string('status',24)->default('pending');
            $t->timestamp('paid_at')->nullable(); $t->text('notes')->nullable(); $t->timestamps();
            $t->index(['company_id','due_date']);
        });
        Schema::create('master_payments_24n8', function (Blueprint $t) {
            $t->id(); $t->foreignId('master_invoice_id')->constrained('master_invoices_24n8')->restrictOnDelete();
            $t->decimal('amount',12,2); $t->string('method',45); $t->string('reference',130)->nullable();
            $t->string('status',22)->default('pending'); $t->timestamp('paid_at')->nullable();
            $t->foreignId('confirmed_by')->nullable()->constrained('master_operators_24n8')->nullOnDelete();
            $t->text('notes')->nullable(); $t->timestamps();
        });
        Schema::create('master_notices_24n8', function (Blueprint $t) {
            $t->id(); $t->foreignId('company_id')->nullable()->constrained('companies')->restrictOnDelete();
            $t->string('title',160); $t->text('body'); $t->string('severity',15)->default('info');
            $t->boolean('is_active')->default(true); $t->timestamp('starts_at')->nullable();
            $t->timestamp('expires_at')->nullable(); $t->timestamps();
        });
        Schema::create('master_notice_reads_24n8', function (Blueprint $t) {
            $t->id(); $t->foreignId('notice_id')->constrained('master_notices_24n8')->cascadeOnDelete();
            $t->foreignId('user_id')->constrained('users')->cascadeOnDelete();
            $t->timestamp('read_at'); $t->unique(['notice_id','user_id']);
        });
        Schema::create('master_audit_24n8', function (Blueprint $t) {
            $t->id(); $t->foreignId('master_operator_id')->constrained('master_operators_24n8')->restrictOnDelete();
            $t->string('action',90); $t->string('target',100); $t->json('details')->nullable();
            $t->timestamp('created_at')->useCurrent();
        });
        // Las empresas anteriores siguen operativas hasta que se configure su suscripción.
        foreach (DB::table('companies')->select('id')->orderBy('id')->cursor() as $company) {
            DB::table('master_subscriptions_24n8')->insert([
                'company_id'=>$company->id, 'status'=>'active', 'due_date'=>null,
                'grace_days'=>4, 'timezone'=>'America/Tegucigalpa',
                'created_at'=>now(), 'updated_at'=>now(),
            ]);
        }
        foreach (['Económico','Básico','Premium','Pro'] as $name) {
            DB::table('master_plans_24n8')->insert([
                'name'=>$name, 'monthly_price'=>null, 'currency'=>'HNL',
                'features'=>json_encode(['operations'=>true,'monitor'=>in_array($name,['Básico','Premium','Pro']),
                    'marketing_site'=>in_array($name,['Premium','Pro']), 'editor'=> $name==='Pro']),
                'is_active'=>true, 'created_at'=>now(), 'updated_at'=>now(),
            ]);
        }
    }
    public function down(): void {
        foreach (['master_audit_24n8','master_notice_reads_24n8','master_notices_24n8','master_payments_24n8',
            'master_invoices_24n8','master_subscriptions_24n8','master_plans_24n8',
            'master_customers_24n8','master_operators_24n8'] as $table) Schema::dropIfExists($table);
    }
};
