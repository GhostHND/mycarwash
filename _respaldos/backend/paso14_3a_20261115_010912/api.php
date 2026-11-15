<?php

use App\Http\Controllers\Api\V1\PreferenceController;
use App\Http\Controllers\Api\V1\SessionController;
use App\Http\Controllers\Api\V1\CompanySettingsController;
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

        // MI EMPRESA

        Route::get(
            '/companies/{company}/settings',
            [CompanySettingsController::class, 'show']
        )->whereNumber('company');

        Route::patch(
            '/companies/{company}/settings/profile',
            [CompanySettingsController::class, 'updateProfile']
        )->whereNumber('company');

        Route::patch(
            '/companies/{company}/settings/branding',
            [CompanySettingsController::class, 'updateBranding']
        )->whereNumber('company');

        Route::get(
            '/companies/{company}/contacts',
            [CompanySettingsController::class, 'contacts']
        )->whereNumber('company');

        Route::post(
            '/companies/{company}/contacts',
            [CompanySettingsController::class, 'storeContact']
        )->whereNumber('company');

        Route::patch(
            '/companies/{company}/contacts/{contact}',
            [CompanySettingsController::class, 'updateContact']
        )->whereNumber('company')->whereNumber('contact');

        Route::delete(
            '/companies/{company}/contacts/{contact}',
            [CompanySettingsController::class, 'deleteContact']
        )->whereNumber('company')->whereNumber('contact');
    });
});