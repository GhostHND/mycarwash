<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration {
    public function up(): void
    {
        if (!Schema::hasTable('booking_order_links_24n7')) {
            Schema::create('booking_order_links_24n7', function (Blueprint $t): void {
                $t->id();
                $t->unsignedBigInteger('company_id');
                $t->unsignedBigInteger('booking_id');
                $t->unsignedBigInteger('order_id');
                $t->unsignedBigInteger('received_by_user_id');
                $t->timestamp('received_at');
                $t->timestamps();
                $t->unique(['company_id', 'booking_id'], 'booking_intake_unique');
                $t->unique(['company_id', 'order_id'], 'booking_order_unique');
                $t->foreign(['booking_id', 'company_id'])->references(['id', 'company_id'])->on('wash_bookings')->restrictOnDelete();
                $t->foreign(['order_id', 'company_id'])->references(['id', 'company_id'])->on('wash_orders')->restrictOnDelete();
            });
        }
        if (!Schema::hasTable('booking_arrival_alert_reads_24n7')) {
            Schema::create('booking_arrival_alert_reads_24n7', function (Blueprint $t): void {
                $t->id();
                $t->unsignedBigInteger('company_id');
                $t->unsignedBigInteger('booking_id');
                $t->unsignedBigInteger('user_id');
                $t->dateTime('booking_start_utc');
                $t->timestamps();
                $t->unique(['company_id', 'booking_id', 'user_id', 'booking_start_utc'], 'booking_arrival_alert_unique');
                $t->foreign(['booking_id', 'company_id'])->references(['id', 'company_id'])->on('wash_bookings')->restrictOnDelete();
                $t->foreign('user_id')->references('id')->on('users')->restrictOnDelete();
            });
        }
    }
    public function down(): void
    {
        Schema::dropIfExists('booking_arrival_alert_reads_24n7');
        Schema::dropIfExists('booking_order_links_24n7');
    }
};
