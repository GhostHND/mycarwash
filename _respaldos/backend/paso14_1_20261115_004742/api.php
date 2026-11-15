<?php

use App\Http\Controllers\Api\V1\PreferenceController;
use App\Http\Controllers\Api\V1\SessionController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {

    Route::post(
        '/auth/token',
        [SessionController::class, 'token']
    )->middleware('throttle:5,1');

    Route::middleware('auth:sanctum')->group(function (): void {

        Route::get(
            '/me',
            [SessionController::class, 'me']
        );

        Route::post(
            '/auth/logout',
            [SessionController::class, 'logout']
        );

        Route::get(
            '/preferences',
            [PreferenceController::class, 'show']
        );

        Route::put(
            '/preferences/theme',
            [PreferenceController::class, 'updateTheme']
        );
    });
});