<?php

return [
    'paths' => ['api/*', 'sanctum/csrf-cookie'],

    'allowed_methods' => ['*'],

    'allowed_origins' => [],

    // Solo desarrollo Flutter Web en la computadora local.
    'allowed_origins_patterns' => [
        '~^http://(?:localhost|127\.0\.0\.1):[0-9]+$~',
    ],

    'allowed_headers' => [
        'Accept',
        'Authorization',
        'Content-Type',
        'Origin',
    ],

    'exposed_headers' => [],

    'max_age' => 600,

    'supports_credentials' => false,
];