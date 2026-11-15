<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // =========================================
        // PERFIL GENERAL DE LA EMPRESA
        // =========================================

        Schema::create('company_profiles', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->unique()
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('commercial_name', 180)->nullable();
            $table->string('business_category', 120)->nullable();
            $table->string('business_type', 100)->nullable();
            $table->string('slogan', 255)->nullable();

            $table->string('public_email', 190)->nullable();
            $table->string('support_email', 190)->nullable();
            $table->string('website_url', 500)->nullable();

            $table->string('legal_representative', 180)->nullable();
            $table->string('registration_number', 100)->nullable();

            $table->date('founded_at')->nullable();

            $table->text('short_description')->nullable();
            $table->longText('description')->nullable();
            $table->longText('history')->nullable();
            $table->longText('mission')->nullable();
            $table->longText('vision')->nullable();
            $table->longText('business_values')->nullable();

            $table->timestamps();

            $table->index('commercial_name');
            $table->index('business_category');
        });

        // =========================================
        // INFORMACION FISCAL
        // =========================================

        Schema::create('company_fiscal_profiles', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->unique()
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('legal_name', 180)->nullable();
            $table->string('tax_id', 60)->nullable();

            $table->string('taxpayer_type', 100)->nullable();
            $table->string('tax_regime', 120)->nullable();
            $table->string('tax_status', 100)->nullable();

            $table->string('commercial_registration', 120)->nullable();

            $table->string('billing_email', 190)->nullable();
            $table->string('billing_phone', 40)->nullable();

            $table->text('fiscal_address')->nullable();
            $table->text('invoice_footer')->nullable();
            $table->text('fiscal_notes')->nullable();

            $table->boolean('is_tax_exempt')->default(false);

            $table->timestamps();

            $table->index('tax_id');
            $table->index('legal_name');
        });

        // =========================================
        // IDENTIDAD VISUAL DEL NEGOCIO
        // =========================================

        Schema::create('company_brandings', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->unique()
                ->constrained('companies')
                ->restrictOnDelete();

            // Archivos del negocio, no logos oficiales ADN.

            $table->string('logo_path', 500)->nullable();
            $table->string('logo_light_path', 500)->nullable();
            $table->string('logo_dark_path', 500)->nullable();
            $table->string('isotype_path', 500)->nullable();
            $table->string('favicon_path', 500)->nullable();
            $table->string('cover_path', 500)->nullable();
            $table->string('background_image_path', 500)->nullable();

            // Colores configurables, almacenados como HEX.

            $table->string('primary_color', 7)->default('#0FA7B4');
            $table->string('secondary_color', 7)->default('#1D1D1B');
            $table->string('accent_color', 7)->default('#ED7E24');

            $table->string('background_color', 7)->default('#FFFFFF');
            $table->string('surface_color', 7)->default('#F5F7F8');
            $table->string('text_color', 7)->default('#1D1D1B');
            $table->string('muted_text_color', 7)->default('#64748B');

            $table->string('sidebar_color', 7)->default('#1D1D1B');
            $table->string('button_color', 7)->default('#0FA7B4');

            $table->string('success_color', 7)->default('#16A34A');
            $table->string('warning_color', 7)->default('#F59E0B');
            $table->string('danger_color', 7)->default('#DC2626');

            $table->string('font_family', 100)->default('Inter');

            $table->string('button_style', 30)->default('rounded');
            $table->string('sidebar_style', 30)->default('expanded');

            $table->unsignedTinyInteger('border_radius')
                ->default(12);

            $table->boolean('compact_mode')->default(false);
            $table->boolean('show_business_name')->default(true);

            $table->timestamps();

            // La identidad oficial ADN NO se modifica
            // desde esta tabla.
        });

        // =========================================
        // CONTACTOS DE LA EMPRESA
        // =========================================

        Schema::create('company_contacts', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('type', 40);
            $table->string('label', 100)->nullable();

            $table->string('value', 255);
            $table->string('normalized_value', 190)->nullable();

            $table->string('contact_person', 180)->nullable();
            $table->string('department', 100)->nullable();

            $table->boolean('is_primary')->default(false);
            $table->boolean('is_public')->default(true);

            $table->unsignedInteger('sort_order')->default(0);

            $table->text('notes')->nullable();

            $table->timestamps();

            $table->index(['company_id', 'type']);
            $table->index(['company_id', 'normalized_value']);
        });

        // =========================================
        // REDES SOCIALES Y ENLACES
        // =========================================

        Schema::create('company_social_links', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('platform', 60);
            $table->string('username', 150)->nullable();
            $table->string('url', 600);

            $table->boolean('is_visible')->default(true);

            $table->unsignedInteger('sort_order')->default(0);

            $table->timestamps();

            $table->index(['company_id', 'platform']);
        });

        // =========================================
        // DIRECCIONES DE LA EMPRESA
        // =========================================

        Schema::create('company_addresses', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('type', 40)->default('principal');

            $table->string('country', 100)->default('Honduras');
            $table->string('department', 120)->nullable();
            $table->string('municipality', 120)->nullable();

            $table->string('neighborhood', 180)->nullable();
            $table->string('street', 255)->nullable();
            $table->string('building_number', 50)->nullable();

            $table->string('postal_code', 30)->nullable();

            $table->text('full_address')->nullable();
            $table->text('reference')->nullable();

            $table->decimal('latitude', 10, 7)->nullable();
            $table->decimal('longitude', 10, 7)->nullable();

            $table->boolean('is_primary')->default(false);

            $table->timestamps();

            $table->index(['company_id', 'municipality']);
            $table->index(['company_id', 'type']);
        });

        // =========================================
        // HORARIOS REGULARES
        // =========================================

        Schema::create('company_business_hours', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            // 1 = lunes, 7 = domingo.

            $table->unsignedTinyInteger('day_of_week');

            $table->time('opens_at')->nullable();
            $table->time('closes_at')->nullable();

            $table->time('break_starts_at')->nullable();
            $table->time('break_ends_at')->nullable();

            $table->boolean('is_closed')->default(false);

            $table->string('notes', 255)->nullable();

            $table->timestamps();

            $table->unique(['company_id', 'day_of_week']);
        });

        // =========================================
        // HORARIOS ESPECIALES
        // =========================================

        Schema::create('company_special_hours', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->date('special_date');

            $table->string('reason', 190)->nullable();

            $table->boolean('is_closed')->default(false);

            $table->time('opens_at')->nullable();
            $table->time('closes_at')->nullable();

            $table->text('notes')->nullable();

            $table->timestamps();

            $table->unique(['company_id', 'special_date']);
        });

        // =========================================
        // PREFERENCIAS GENERALES
        // =========================================

        Schema::create('company_preferences', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->unique()
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('locale', 12)->default('es-HN');
            $table->string('currency_code', 3)->default('HNL');

            $table->string('timezone', 80)
                ->default('America/Tegucigalpa');

            $table->string('date_format', 30)->default('dd/MM/yyyy');
            $table->string('time_format', 15)->default('24h');

            $table->string('default_theme', 12)->default('system');

            $table->string('invoice_paper_size', 30)
                ->default('letter');

            $table->string('country_phone_code', 10)
                ->default('+504');

            $table->unsignedTinyInteger('decimal_places')
                ->default(2);

            $table->boolean('enable_sound_alerts')->default(true);

            $table->text('receipt_footer')->nullable();

            $table->timestamps();
        });

        // =========================================
        // BIBLIOTECA MULTIMEDIA EMPRESARIAL
        // =========================================

        Schema::create('company_media_assets', function (Blueprint $table) {
            $table->engine = 'InnoDB';

            $table->id();

            $table->foreignId('company_id')
                ->constrained('companies')
                ->restrictOnDelete();

            $table->string('category', 60)->default('general');

            $table->string('disk', 50)->default('public');

            $table->string('path', 600);

            $table->string('original_filename', 255)->nullable();
            $table->string('mime_type', 120)->nullable();

            $table->unsignedBigInteger('file_size')->nullable();

            $table->string('alt_text', 255)->nullable();

            $table->boolean('is_public')->default(false);

            $table->unsignedInteger('sort_order')->default(0);

            $table->timestamps();

            $table->index(['company_id', 'category']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('company_media_assets');
        Schema::dropIfExists('company_preferences');
        Schema::dropIfExists('company_special_hours');
        Schema::dropIfExists('company_business_hours');
        Schema::dropIfExists('company_addresses');
        Schema::dropIfExists('company_social_links');
        Schema::dropIfExists('company_contacts');
        Schema::dropIfExists('company_brandings');
        Schema::dropIfExists('company_fiscal_profiles');
        Schema::dropIfExists('company_profiles');
    }
};