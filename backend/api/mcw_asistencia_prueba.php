<?php
require __DIR__ . '/vendor/autoload.php';

$app = require __DIR__ . '/bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;
use Carbon\CarbonImmutable;

$conn = config('database.connections.mysql');

if (
    config('database.default') !== 'mysql' ||
    !in_array($conn['host'], ['127.0.0.1', 'localhost'], true) ||
    DB::connection()->getDatabaseName() !== 'mycarwash_core'
) {
    exit("[ERROR] No es la base de datos local esperada.\n");
}

$hoy = CarbonImmutable::now('America/Tegucigalpa')->toDateString();
$ahora = CarbonImmutable::now('UTC')->format('Y-m-d H:i:s');
$horaLocal = CarbonImmutable::now('America/Tegucigalpa')->format('h:i:s A');

$antonio = DB::table('employees')
    ->where('id', 4)
    ->first();

if (!$antonio || stripos($antonio->full_name, 'Antonio') === false) {
    exit("[ERROR] No se pudo confirmar la identidad de Antonio.\n");
}

$lavadores = DB::table('employees')
    ->where('company_id', $antonio->company_id)
    ->where('is_active', 1)
    ->whereNull('deleted_at')
    ->whereRaw("LOWER(TRIM(position)) IN ('washer','lavador')")
    ->get();

echo "\n========================================\n";
echo " ADN MYCARWASH - ASISTENCIA DE PRUEBA\n";
echo "========================================\n";
echo "Fecha: {$hoy}\n";
echo "Hora Honduras: {$horaLocal}\n";
echo "Empresa ID: {$antonio->company_id}\n";
echo "Lavadores encontrados: " . $lavadores->count() . "\n\n";

$registrados = 0;
$existentes = 0;

DB::transaction(function () use (
    $lavadores,
    $hoy,
    $ahora,
    $horaLocal,
    &$registrados,
    &$existentes
) {
    foreach ($lavadores as $empleado) {

        $existe = DB::table('washer_attendance_24n3')
            ->where('company_id', $empleado->company_id)
            ->where('employee_id', $empleado->id)
            ->where('work_date', $hoy)
            ->exists();

        if ($existe) {
            echo "[YA EXISTE] {$empleado->full_name}\n";
            $existentes++;
            continue;
        }

        DB::table('washer_attendance_24n3')->insert([
            'company_id' => $empleado->company_id,
            'employee_id' => $empleado->id,
            'work_date' => $hoy,
            'check_in_at' => $ahora,
            'check_out_at' => null,
            'created_at' => $ahora,
            'updated_at' => $ahora
        ]);

        echo "[ENTRADA] {$empleado->full_name} - {$horaLocal}\n";
        $registrados++;
    }
});

echo "\n========================================\n";
echo "Nuevas entradas: {$registrados}\n";
echo "Entradas existentes: {$existentes}\n";
echo "[OK] Simulacion finalizada.\n";
echo "========================================\n";

