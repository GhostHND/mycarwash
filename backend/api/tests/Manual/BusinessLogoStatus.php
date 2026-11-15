<?php

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

$root = dirname(__DIR__, 2);

require $root . '/vendor/autoload.php';

$app = require $root . '/bootstrap/app.php';

$app->make(Kernel::class)->bootstrap();

if (!$app->environment('local')) {
    throw new RuntimeException('Solo se permite desarrollo local.');
}

$db = DB::connection('mysql');

if ($db->getDatabaseName() !== 'mycarwash_core') {
    throw new RuntimeException('Base de datos incorrecta.');
}

$company = DB::table('companies')
    ->where('slug', 'carwash-pruebas')
    ->first(['id', 'name']);

if (!$company) {
    throw new RuntimeException('Empresa de pruebas no encontrada.');
}

$branding = DB::table('company_brandings')
    ->where('company_id', $company->id)
    ->first();

if (!$branding) {
    throw new RuntimeException('No existe la identidad de la empresa.');
}

echo "\n===== ADN MYCARWASH - IDENTIDAD =====\n";
echo "Empresa: {$company->name}\n";
echo "ID: {$company->id}\n";
echo "Fuente registrada: {$branding->font_family}\n";

$path = $branding->business_logo_path;

if (!$path) {
    echo "Logotipo empresarial: SIN LOGOTIPO\n";
    echo "Estado: CORRECTO si aun no subiste uno o ya lo eliminaste.\n";
    exit(0);
}

$prefix = "mycarwash/companies/{$company->id}/logos/";

if (!str_starts_with($path, $prefix)) {
    throw new RuntimeException('Ruta de logotipo fuera de la empresa.');
}

$disk = Storage::disk('local');

if (!$disk->exists($path)) {
    throw new RuntimeException(
        'MySQL registra el logotipo, pero el archivo no existe.'
    );
}

$mime = $disk->mimeType($path);
$size = $disk->size($path);

echo "Logotipo empresarial: REGISTRADO\n";
echo "Archivo fisico: ENCONTRADO\n";
echo "Tipo MIME: {$mime}\n";
echo "Tamano: {$size} bytes\n";
echo "Ruta privada: {$path}\n";
echo "Estado: ALMACENAMIENTO VERIFICADO\n";