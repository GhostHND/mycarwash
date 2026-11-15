<?php

declare(strict_types=1);

use Illuminate\Contracts\Http\Kernel;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

$project = dirname(__DIR__, 2);

require $project . '/vendor/autoload.php';

$app = require $project . '/bootstrap/app.php';

/** @var Kernel $kernel */
$kernel = $app->make(Kernel::class);
$kernel->bootstrap();

function ensure(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

function apiRequest(
    Kernel $kernel,
    string $method,
    string $uri,
    ?array $payload = null,
    ?string $token = null
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
        $payload === null
            ? null
            : json_encode($payload, JSON_THROW_ON_ERROR)
    );

    $response = $kernel->handle($request);

    $result = [
        'status' => $response->getStatusCode(),
        'data' => json_decode(
            (string) $response->getContent(),
            true
        ) ?? [],
    ];

    $kernel->terminate($request, $response);

    return $result;
}

ensure(
    app()->environment('local'),
    'La prueba solo se permite en entorno local.'
);

$db = DB::connection('mysql');

ensure(
    $db->getDatabaseName() === 'mycarwash_core',
    'Base de datos incorrecta.'
);

$password = getenv('ADN_MYCARWASH_TEST_PASSWORD');

ensure(
    is_string($password) && $password !== '',
    'No se recibio la clave de desarrollo.'
);

$email = 'eduardo@adn.com';

$user = DB::table('users')
    ->where('email', $email)
    ->first();

ensure(
    $user !== null,
    'No existe el administrador de pruebas.'
);

ensure(
    Hash::check($password, $user->password),
    'La contrasena no coincide con su hash.'
);

echo "[OK] Usuario almacenado y contrasena cifrada.\n";

$anonymous = apiRequest(
    $kernel,
    'GET',
    '/api/v1/me'
);

ensure(
    $anonymous['status'] === 401,
    'El perfil permite acceso sin autenticacion.'
);

echo "[OK] Acceso anonimo bloqueado.\n";

$login = apiRequest(
    $kernel,
    'POST',
    '/api/v1/auth/token',
    [
        'email' => $email,
        'password' => $password,
        'device_name' => 'adn-development-probe',
    ]
);

ensure(
    $login['status'] === 200,
    'Inicio de sesion fallido. HTTP ' . $login['status']
);

$token = $login['data']['access_token'] ?? null;

ensure(
    is_string($token) && $token !== '',
    'No se recibio el token de acceso.'
);

echo "[OK] Inicio de sesion real correcto.\n";

try {

    $me = apiRequest(
        $kernel,
        'GET',
        '/api/v1/me',
        null,
        $token
    );

    ensure(
        $me['status'] === 200,
        'No se pudo consultar el usuario autenticado.'
    );

    ensure(
        ($me['data']['user']['email'] ?? null) === $email,
        'El usuario autenticado no coincide.'
    );

    $companies = $me['data']['companies'] ?? [];

    ensure(
        is_array($companies)
        && count($companies) === 1
        && ($companies[0]['slug'] ?? null) === 'carwash-pruebas',
        'La empresa autorizada no coincide.'
    );

    echo "[OK] Acceso a la empresa correcta.\n";

    $initial = apiRequest(
        $kernel,
        'GET',
        '/api/v1/preferences',
        null,
        $token
    );

    ensure(
        $initial['status'] === 200
        && ($initial['data']['theme_mode'] ?? null) === 'system',
        'No se recuperaron las preferencias iniciales.'
    );

    echo "[OK] Preferencias iniciales recuperadas.\n";

    foreach (['dark', 'light', 'system'] as $mode) {

        $update = apiRequest(
            $kernel,
            'PUT',
            '/api/v1/preferences/theme',
            ['theme_mode' => $mode],
            $token
        );

        ensure(
            $update['status'] === 200
            && ($update['data']['theme_mode'] ?? null) === $mode,
            "No se pudo guardar el modo {$mode}."
        );

        $read = apiRequest(
            $kernel,
            'GET',
            '/api/v1/preferences',
            null,
            $token
        );

        ensure(
            $read['status'] === 200
            && ($read['data']['theme_mode'] ?? null) === $mode,
            "No se pudo recuperar el modo {$mode}."
        );

        $storedMode = DB::table('user_preferences')
            ->where('user_id', $user->id)
            ->value('theme_mode');

        ensure(
            $storedMode === $mode,
            "MySQL no almaceno el modo {$mode}."
        );

        echo "[OK] Modo {$mode} guardado y leido desde MySQL.\n";
    }

    $logout = apiRequest(
        $kernel,
        'POST',
        '/api/v1/auth/logout',
        null,
        $token
    );

    ensure(
        $logout['status'] === 200,
        'No se pudo cerrar la sesion.'
    );

    $revoked = apiRequest(
        $kernel,
        'GET',
        '/api/v1/me',
        null,
        $token
    );

    ensure(
        $revoked['status'] === 401,
        'El token revocado conserva acceso.'
    );

    echo "[OK] Cierre de sesion y revocacion verificados.\n";

} finally {

    // Evitar dejar sesiones de prueba activas
    // si alguna comprobacion falla.

    DB::table('personal_access_tokens')
        ->where('tokenable_type', 'App\\Models\\User')
        ->where('tokenable_id', $user->id)
        ->where('name', 'adn-development-probe')
        ->delete();
}

echo "\n[OK] TODAS LAS PRUEBAS DE API SUPERADAS.\n";