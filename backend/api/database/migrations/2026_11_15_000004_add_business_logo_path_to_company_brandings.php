<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    protected $connection = 'mysql';

    public function up(): void
    {
        if (!Schema::connection('mysql')->hasColumn(
            'company_brandings',
            'business_logo_path'
        )) {
            Schema::connection('mysql')->table(
                'company_brandings',
                function (Blueprint $table): void {
                    $table->string(
                        'business_logo_path',
                        500
                    )->nullable();
                }
            );
        }
    }

    public function down(): void
    {
        if (Schema::connection('mysql')->hasColumn(
            'company_brandings',
            'business_logo_path'
        )) {
            Schema::connection('mysql')->table(
                'company_brandings',
                function (Blueprint $table): void {
                    $table->dropColumn('business_logo_path');
                }
            );
        }
    }
};