<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

/**
 * 24N.2.6: Solo cambia los DEFAULT SQL de company_brandings.
 * Ninguna fila existente se sobrescribe; cada empresa conserva sus preferencias.
 */
return new class extends Migration
{
    private const COLORS = [
            'primary_color' => '#00DCE5',
            'secondary_color' => '#0B292F',
            'accent_color' => '#00DCE5',
            'background_color' => '#050C0F',
            'surface_color' => '#071B20',
            'card_color' => '#071F23',
            'border_color' => '#17434B',
            'field_color' => '#16343D',
            'text_color' => '#F4F7F8',
            'muted_text_color' => '#A5B6BB',
            'sidebar_color' => '#061115',
            'button_color' => '#00DCE5',
            'icon_color' => '#00DCE5',
            'heading_color' => '#F4F7F8',
            'hover_color' => '#10383F',
            'selected_color' => '#10454D',
            'success_color' => '#00D99A',
            'warning_color' => '#F59E0B',
            'danger_color' => '#EC488A',
        ];
    private const PREVIOUS = [
            'primary_color' => '#0FA7B4',
            'secondary_color' => '#1D1D1B',
            'accent_color' => '#ED7E24',
            'background_color' => '#FFFFFF',
            'surface_color' => '#F5F7F8',
            'card_color' => '#102027',
            'border_color' => '#21333B',
            'field_color' => '#15262D',
            'text_color' => '#1D1D1B',
            'muted_text_color' => '#64748B',
            'sidebar_color' => '#1D1D1B',
            'button_color' => '#0FA7B4',
            'icon_color' => '#0FA7B4',
            'heading_color' => '#F5FAFC',
            'hover_color' => '#16343C',
            'selected_color' => '#17454D',
            'success_color' => '#16A34A',
            'warning_color' => '#F59E0B',
            'danger_color' => '#DC2626',
        ];

    private function changeDefaults(array $colors, int $version): void
    {
        if (!Schema::hasTable('company_brandings')) {
            throw new RuntimeException('Falta company_brandings; instale primero Bloque 24N.2.4.');
        }
        foreach (array_keys($colors) as $field) {
            if (!Schema::hasColumn('company_brandings', $field)) {
                throw new RuntimeException("Falta la columna $field de Bloque 24N.2.4.");
            }
        }
        if (!Schema::hasColumn('company_brandings', 'visual_theme_version')) {
            throw new RuntimeException('Falta visual_theme_version de Bloque 24N.2.4.');
        }
        $driver = DB::connection()->getDriverName();
        if (in_array($driver, ['mysql', 'mariadb'], true)) {
            // Un único ALTER: evita una migración parcialmente ejecutada.
            $clauses = [];
            foreach ($colors as $key => $hex) {
                $clauses[] = "MODIFY COLUMN `$key` VARCHAR(7) NOT NULL DEFAULT '$hex'";
            }
            $clauses[] = "MODIFY COLUMN `visual_theme_version` TINYINT UNSIGNED NOT NULL DEFAULT $version";
            DB::statement('ALTER TABLE `company_brandings` ' . implode(', ', $clauses));
        } elseif ($driver === 'pgsql') {
            foreach ($colors as $key => $hex) {
                DB::statement("ALTER TABLE company_brandings ALTER COLUMN \"$key\" SET DEFAULT '$hex'");
            }
            DB::statement('ALTER TABLE company_brandings ALTER COLUMN visual_theme_version SET DEFAULT ' . $version);
        } elseif ($driver === 'sqlite') {
            Schema::table('company_brandings', function (Blueprint $table) use ($colors, $version): void {
                foreach ($colors as $key => $hex) {
                    $table->string($key, 7)->default($hex)->change();
                }
                $table->unsignedTinyInteger('visual_theme_version')->default($version)->change();
            });
        } else {
            throw new RuntimeException('Motor no soportado para modificar defaults de paleta: ' . $driver);
        }
    }

    public function up(): void
    {
        $this->changeDefaults(self::COLORS, 3);
    }

    public function down(): void
    {
        // No modifica los registros ya existentes, solo los defaults futuros.
        $this->changeDefaults(self::PREVIOUS, 0);
    }
};
