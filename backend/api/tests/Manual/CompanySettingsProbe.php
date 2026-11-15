<?php

declare(strict_types=1);

use App\Models\User;
use Illuminate\Contracts\Http\Kernel;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;

$project = dirname(__DIR__, 2);

require $project . '/vendor/autoload.php';

$app = require $project . '/bootstrap/app.php';

$kernel = $app->make(Kernel::class);
$kernel->bootstrap();

function checkResult(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

function requestApi(
    Kernel $kernel,
    string $method,
    string $uri,
    ?array $body,
    ?string $token
): array {
    app('auth')->forgetGuards();

    $server = [
        'HTTP_ACCEPT' => 'application/json',
        'CONTENT_TYPE' => 'application/json',
    ];

    if ($token !== null) {
        $server['HTTP_AUTHORIZATION'] = 'Bearer ' . $token;
    }

    $request = Request::create(
        $uri,
        $method,
        [],
        [],
        [],
        $server,
        $body === null
            ? null
            : json_encode($body, JSON_THROW_ON_ERROR)
    );

    $response = $kernel->handle($request);

    $result = [
        'status' => $response->getStatusCode(),
        'body' => json_decode(
            (string) $response->getContent(),
            true
        ) ?? [],
    ];

    $kernel->terminate($request, $response);

    return $result;
}

checkResult(
    $app->environment('local'),
    'La prueba solo funciona en entorno local.'
);

$db = DB::connection('mysql');

checkResult(
    $db->getDatabaseName() === 'mycarwash_core',
    'Base de datos incorrecta.'
);

$user = User::where('email', 'eduardo@adn.com')->first();

$company = DB::table('companies')
    ->where('slug', 'carwash-pruebas')
    ->first();

checkResult(
    $user !== null && $company !== null,
    'Falta el administrador o la empresa de pruebas.'
);

$companyId = (int) $company->id;
$base = '/api/v1/companies/' . $companyId;

$previousProfile = $db->table('company_profiles')
    ->where('company_id', $companyId)
    ->first();

$previousBrand = $db->table('company_brandings')
    ->where('company_id', $companyId)
    ->first();

checkResult(
    $previousProfile !== null && $previousBrand !== null,
    'Falta la configuracion inicial de empresa.'
);

$tokenRecord = null;
$contactId = null;

try {
    $anonymous = requestApi(
        $kernel,
        'GET',
        $base . '/settings',
        null,
        null
    );

    checkResult(
        $anonymous['status'] === 401,
        'Mi Empresa permite acceso sin iniciar sesion.'
    );

    echo "[OK] Acceso anonimo bloqueado.\n";

    $issued = $user->createToken(
        'adn-company-probe',
        ['*'],
        now()->addMinutes(15)
    );

    $tokenRecord = $issued->accessToken;
    $token = $issued->plainTextToken;

    $settings = requestApi(
        $kernel,
        'GET',
        $base . '/settings',
        null,
        $token
    );

    checkResult(
        $settings['status'] === 200,
        'No se pudo consultar Mi Empresa.'
    );

    checkResult(
        ($settings['body']['company']['id'] ?? null) === $companyId,
        'La API devolvio una empresa incorrecta.'
    );

    echo "[OK] Datos de empresa consultados.\n";

    $newSlogan = 'Comprobacion temporal API MyCarWash';

    $updatedProfile = requestApi(
        $kernel,
        'PATCH',
        $base . '/settings/profile',
        ['slogan' => $newSlogan],
        $token
    );

    checkResult(
        $updatedProfile['status'] === 200,
        'No se pudo actualizar el perfil.'
    );

    checkResult(
        DB::table('company_profiles')
            ->where('company_id', $companyId)
            ->value('slogan') === $newSlogan,
        'El perfil no se guardo en MySQL.'
    );

    echo "[OK] Perfil guardado en MySQL.\n";

    $newColor = '#1188AA';

    $updatedBrand = requestApi(
        $kernel,
        'PATCH',
        $base . '/settings/branding',
        ['primary_color' => $newColor],
        $token
    );

    checkResult(
        $updatedBrand['status'] === 200,
        'No se pudo actualizar el color.'
    );

    checkResult(
        DB::table('company_brandings')
            ->where('company_id', $companyId)
            ->value('primary_color') === $newColor,
        'El color no se guardo en MySQL.'
    );

    echo "[OK] Color empresarial guardado en MySQL.\n";

    $created = requestApi(
        $kernel,
        'POST',
        $base . '/contacts',
        [
            'type' => 'phone',
            'label' => 'Telefono temporal',
            'value' => '9851-9000',
            'contact_person' => 'Contacto Temporal QA',
            'is_public' => false,
        ],
        $token
    );

    checkResult(
        $created['status'] === 201,
        'No se pudo crear el contacto.'
    );

    $contactId = (int) ($created['body']['contact']['id'] ?? 0);

    checkResult(
        $contactId > 0,
        'La API no devolvio el contacto creado.'
    );

    echo "[OK] Contacto creado.\n";

    $search = requestApi(
        $kernel,
        'GET',
        $base . '/contacts?q=9851',
        null,
        $token
    );

    $results = $search['body']['data'] ?? [];

    checkResult(
        $search['status'] === 200
        && collect($results)->contains('id', $contactId),
        'La busqueda automatica por numero fallo.'
    );

    echo "[OK] Busqueda por telefono correcta.\n";

    $searchName = requestApi(
        $kernel,
        'GET',
        $base . '/contacts?q=Temporal',
        null,
        $token
    );

    checkResult(
        $searchName['status'] === 200
        && collect($searchName['body']['data'] ?? [])
            ->contains('id', $contactId),
        'La busqueda por nombre fallo.'
    );

    echo "[OK] Busqueda por nombre correcta.\n";

    $changed = requestApi(
        $kernel,
        'PATCH',
        $base . '/contacts/' . $contactId,
        ['value' => '9851-9001'],
        $token
    );

    checkResult(
        $changed['status'] === 200,
        'No se pudo editar el contacto.'
    );

    echo "[OK] Contacto actualizado.\n";

    $deleted = requestApi(
        $kernel,
        'DELETE',
        $base . '/contacts/' . $contactId,
        null,
        $token
    );

    checkResult(
        $deleted['status'] === 200,
        'No se pudo eliminar el contacto.'
    );

    $contactId = null;

    echo "[OK] Contacto eliminado.\n";

    $otherCompany = requestApi(
        $kernel,
        'GET',
        '/api/v1/companies/999999999/settings',
        null,
        $token
    );

    checkResult(
        $otherCompany['status'] === 404,
        'La API no protegió el acceso a otras empresas.'
    );

    echo "[OK] Acceso a empresas no autorizadas bloqueado.\n";

    echo "\n[OK] PRUEBAS DE MI EMPRESA SUPERADAS.\n";

} finally {

    // Restaurar los datos iniciales de desarrollo.

    DB::table('company_profiles')
        ->where('company_id', $companyId)
        ->update([
            'slogan' => $previousProfile->slogan,
        ]);

    DB::table('company_brandings')
        ->where('company_id', $companyId)
        ->update([
            'primary_color' => $previousBrand->primary_color,
        ]);

    if ($contactId !== null) {
        DB::table('company_contacts')
            ->where('company_id', $companyId)
            ->where('id', $contactId)
            ->delete();
    }

    $tokenRecord?->delete();

    echo "[OK] Datos temporales restaurados.\n";
}