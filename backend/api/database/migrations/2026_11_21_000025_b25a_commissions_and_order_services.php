<?php
use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;
return new class extends Migration {
    public function up(): void {
        if (!Schema::hasColumn('employees','commission_percent')) {
            Schema::table('employees', function(Blueprint $t): void {
                $t->decimal('commission_percent',5,2)->default(40.00);
            });
        }
        if (!Schema::hasTable('wash_order_service_lines_b25')) {
            Schema::create('wash_order_service_lines_b25', function(Blueprint $t): void {
                $t->id();
                $t->unsignedBigInteger('company_id');
                $t->unsignedBigInteger('order_id');
                $t->unsignedBigInteger('service_id')->nullable();
                $t->string('service_name',150);
                $t->decimal('price',12,2);
                $t->decimal('commission_percent',5,2)->default(40);
                $t->unsignedBigInteger('commission_employee_id')->nullable();
                $t->decimal('commission_amount',12,2)->default(0);
                $t->unsignedSmallInteger('line_order')->default(0);
                $t->timestamps();
                $t->foreign(['order_id','company_id'])->references(['id','company_id'])->on('wash_orders')->restrictOnDelete();
                $t->foreign('service_id')->references('id')->on('wash_services')->restrictOnDelete();
                $t->foreign('commission_employee_id')->references('id')->on('employees')->restrictOnDelete();
                $t->unique(['company_id','order_id','line_order'],'b25_lines_company_order_position');
                $t->index(['company_id','commission_employee_id','created_at'],'b25_lines_employee_date');
            });
        }
    }
    public function down(): void {
        // Intencionalmente no elimina datos de producción ni comisiones históricas.
    }
};
