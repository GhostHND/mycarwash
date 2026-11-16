<?php

use App\Http\Controllers\Api\V1\PreferenceController;
use App\Http\Controllers\Api\V1\SessionController;
use App\Http\Controllers\Api\V1\CompanySettingsController;
use App\Http\Controllers\Api\V1\CompanyScheduleSocialController;
use App\Http\Controllers\Api\V1\CompanyBusinessDetailsController;
use App\Http\Controllers\Api\V1\BusinessLogoController;
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

        // LOGOTIPO PARTICULAR DEL NEGOCIO

        Route::get(
            '/companies/{company}/settings/logo',
            [BusinessLogoController::class, 'show']
        )->whereNumber('company');

        Route::post(
            '/companies/{company}/settings/logo',
            [BusinessLogoController::class, 'upload']
        )->whereNumber('company');

        Route::delete(
            '/companies/{company}/settings/logo',
            [BusinessLogoController::class, 'remove']
        )->whereNumber('company');

        // DATOS FISCALES EMPRESARIALES

        Route::get(
            '/companies/{company}/settings/fiscal',
            [CompanyBusinessDetailsController::class, 'fiscal']
        )->whereNumber('company');

        Route::patch(
            '/companies/{company}/settings/fiscal',
            [CompanyBusinessDetailsController::class, 'saveFiscal']
        )->whereNumber('company');

        // DIRECCIONES EMPRESARIALES

        Route::get(
            '/companies/{company}/addresses',
            [CompanyBusinessDetailsController::class, 'addresses']
        )->whereNumber('company');

        Route::post(
            '/companies/{company}/addresses',
            [CompanyBusinessDetailsController::class, 'storeAddress']
        )->whereNumber('company');

        Route::patch(
            '/companies/{company}/addresses/{address}',
            [CompanyBusinessDetailsController::class, 'updateAddress']
        )->whereNumber('company')->whereNumber('address');

        Route::delete(
            '/companies/{company}/addresses/{address}',
            [CompanyBusinessDetailsController::class, 'deleteAddress']
        )->whereNumber('company')->whereNumber('address');

        // HORARIOS SEMANALES
        Route::get('/companies/{company}/settings/hours', [CompanyScheduleSocialController::class, 'weekly'])->whereNumber('company');
        Route::patch('/companies/{company}/settings/hours', [CompanyScheduleSocialController::class, 'saveWeekly'])->whereNumber('company');

        // HORARIOS ESPECIALES
        Route::get('/companies/{company}/special-hours', [CompanyScheduleSocialController::class, 'special'])->whereNumber('company');
        Route::post('/companies/{company}/special-hours', [CompanyScheduleSocialController::class, 'storeSpecial'])->whereNumber('company');
        Route::patch('/companies/{company}/special-hours/{special}', [CompanyScheduleSocialController::class, 'updateSpecial'])->whereNumber('company')->whereNumber('special');
        Route::delete('/companies/{company}/special-hours/{special}', [CompanyScheduleSocialController::class, 'deleteSpecial'])->whereNumber('company')->whereNumber('special');

        // REDES SOCIALES
        Route::get('/companies/{company}/social-links', [CompanyScheduleSocialController::class, 'socials'])->whereNumber('company');
        Route::post('/companies/{company}/social-links', [CompanyScheduleSocialController::class, 'storeSocial'])->whereNumber('company');
        Route::patch('/companies/{company}/social-links/{social}', [CompanyScheduleSocialController::class, 'updateSocial'])->whereNumber('company')->whereNumber('social');
        Route::delete('/companies/{company}/social-links/{social}', [CompanyScheduleSocialController::class, 'deleteSocial'])->whereNumber('company')->whereNumber('social');
    });
});