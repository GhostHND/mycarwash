<?php

use App\Http\Controllers\Api\V1\PreferenceController;
use App\Http\Controllers\Api\V1\SessionController;
use App\Http\Controllers\Api\V1\CompanySettingsController;
use App\Http\Controllers\Api\V1\CompanyPreferencesController;
use App\Http\Controllers\Api\V1\CompanyScheduleSocialController;
use App\Http\Controllers\Api\V1\CompanyBusinessDetailsController;
use App\Http\Controllers\Api\V1\BusinessLogoController;
use Illuminate\Support\Facades\Route;

// RPI-01C: rutas de dispositivo exclusivamente de lectura (clave limitada al monitor).
Route::prefix('v1/kiosk/rpi01c')->middleware('throttle:120,1')->group(function (): void {
    Route::get('/bootstrap', [\App\Http\Controllers\Api\V1\MonitorDeviceRpi01cController::class, 'bootstrap']);
    Route::get('/monitor', [\App\Http\Controllers\Api\V1\MonitorDeviceRpi01cController::class, 'monitor']);
    Route::get('/photos/{vehicle}', [\App\Http\Controllers\Api\V1\MonitorDeviceRpi01cController::class, 'photo'])->whereNumber('vehicle');
    Route::get('/logo', [\App\Http\Controllers\Api\V1\MonitorDeviceRpi01cController::class, 'logo']);
});
// Vinculación inicial desde cuenta propietaria autenticada.
Route::prefix('v1/companies/{company}/monitor-devices-rpi01c')
    ->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])
    ->group(function (): void {
        Route::get('/', [\App\Http\Controllers\Api\V1\MonitorDeviceRpi01cController::class, 'index']);
        Route::post('/', [\App\Http\Controllers\Api\V1\MonitorDeviceRpi01cController::class, 'issue']);
        Route::delete('/{device}', [\App\Http\Controllers\Api\V1\MonitorDeviceRpi01cController::class, 'revoke'])->whereNumber('device');
    });

Route::prefix('v1')->group(function (): void {

    Route::post(
        '/auth/token',
        [SessionController::class, 'token']
    )->middleware('throttle:5,1');

    Route::middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {

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

        // BLOQUE 24N.3: endpoints exclusivos y acotados del lavador.
        Route::get('/companies/{company}/washer/branding', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'branding'])->whereNumber('company');
        Route::get('/companies/{company}/washer/summary', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'summary'])->whereNumber('company');
        Route::get('/companies/{company}/washer/orders', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'orders'])->whereNumber('company');
        Route::get('/companies/{company}/washer/photo/{kind}/{record}', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'photo'])->whereNumber('company')->where('kind','vehicles|employees')->whereNumber('record');
        Route::post('/companies/{company}/washer/attendance/scan', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'scanAttendance'])->whereNumber('company');
        Route::get('/companies/{company}/attendance-points/station', [\App\Http\Controllers\Api\V1\CompanyAttendanceStation24N4Controller::class, 'station'])->whereNumber('company');
        Route::get('/companies/{company}/attendance/report-b25', [\App\Http\Controllers\Api\V1\CompanyAttendanceReportB25Controller::class, 'index'])->whereNumber('company');
        Route::get('/companies/{company}/commissions/report-b25l', [\App\Http\Controllers\Api\V1\CompanyCommissionReportB25LController::class, 'index'])->whereNumber('company');
        Route::get('/companies/{company}/washer/agenda', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'agenda'])->whereNumber('company');
        Route::get('/companies/{company}/washer/me', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'me'])->whereNumber('company');
        Route::patch('/companies/{company}/washer/me', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'updateMe'])->whereNumber('company');
        Route::patch('/companies/{company}/washer/password', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'password'])->whereNumber('company');
        Route::post('/companies/{company}/washer/orders/{order}/start', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'start'])->whereNumber('company')->whereNumber('order')->name('washer.order.start');
        Route::post('/companies/{company}/washer/orders/{order}/finish', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'finish'])->whereNumber('company')->whereNumber('order')->name('washer.order.finish');

        Route::get('/companies/{company}/washer/attendance', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'attendance'])->whereNumber('company');
        Route::post('/companies/{company}/washer/attendance/check-in', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'checkIn'])->whereNumber('company');
        Route::post('/companies/{company}/washer/attendance/check-out', [\App\Http\Controllers\Api\V1\CompanyWasherPortal24N3Controller::class, 'checkOut'])->whereNumber('company');

        // BLOQUE 24N.2: cuentas de empleados y roles por empresa
        Route::get('/companies/{company}/users', [\App\Http\Controllers\Api\V1\CompanyUsers24N2Controller::class, 'index'])->whereNumber('company');
        Route::post('/companies/{company}/users', [\App\Http\Controllers\Api\V1\CompanyUsers24N2Controller::class, 'store'])->whereNumber('company');
        Route::patch('/companies/{company}/users/{user}', [\App\Http\Controllers\Api\V1\CompanyUsers24N2Controller::class, 'update'])->whereNumber('company')->whereNumber('user');
        Route::post('/companies/{company}/roles', [\App\Http\Controllers\Api\V1\CompanyUsers24N2Controller::class, 'storeRole'])->whereNumber('company');
        Route::patch('/companies/{company}/roles/{role}', [\App\Http\Controllers\Api\V1\CompanyUsers24N2Controller::class, 'updateRole'])->whereNumber('company')->whereNumber('role');
        Route::delete('/companies/{company}/roles/{role}', [\App\Http\Controllers\Api\V1\CompanyUsers24N2Controller::class, 'deleteRole'])->whereNumber('company')->whereNumber('role');

        // MI EMPRESA

        Route::get('/companies/{company}/monitor-theme-24b', [\App\Http\Controllers\Api\V1\CompanyMonitorTheme24BController::class, 'show'])->whereNumber('company');
        Route::patch('/companies/{company}/monitor-theme-24b', [\App\Http\Controllers\Api\V1\CompanyMonitorTheme24BController::class, 'update'])->whereNumber('company');

        Route::get('/companies/{company}/dashboard/monitor-24b2', [\App\Http\Controllers\Api\V1\CompanyWashMonitor24B2Controller::class, 'show'])->whereNumber('company');

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
        Route::get('/companies/{company}/settings/preferences', [CompanyPreferencesController::class, 'show'])->whereNumber('company');
        Route::patch('/companies/{company}/settings/preferences', [CompanyPreferencesController::class, 'update'])->whereNumber('company');

    });
});

// BLOQUE 15 - CATALOGOS OPERATIVOS (4 CRUD)
Route::middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->prefix('v1')->group(function (): void {
    Route::get('/companies/{company}/services/vehicle-types', [\App\Http\Controllers\Api\V1\CompanyServiceVehiclePrices24FController::class, 'vehicleTypes'])->whereNumber('company');
    Route::get('/companies/{company}/services/{service}/vehicle-prices', [\App\Http\Controllers\Api\V1\CompanyServiceVehiclePrices24FController::class, 'index'])->whereNumber('company')->whereNumber('service');
    Route::patch('/companies/{company}/services/{service}/vehicle-prices', [\App\Http\Controllers\Api\V1\CompanyServiceVehiclePrices24FController::class, 'replace'])->whereNumber('company')->whereNumber('service');
    Route::get('/companies/{company}/{resource}', [\App\Http\Controllers\Api\V1\CompanyOperationsController::class, 'index'])
        ->whereNumber('company')->where('resource', 'clients|vehicles|employees|services');
    Route::get('/companies/{company}/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyOperationsController::class, 'show'])
        ->whereNumber('company')->whereNumber('record')->where('resource', 'clients|vehicles|employees|services');
    Route::post('/companies/{company}/{resource}', [\App\Http\Controllers\Api\V1\CompanyOperationsController::class, 'store'])
        ->whereNumber('company')->where('resource', 'clients|vehicles|employees|services');
    Route::patch('/companies/{company}/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyOperationsController::class, 'update'])
        ->whereNumber('company')->whereNumber('record')->where('resource', 'clients|vehicles|employees|services');
    Route::delete('/companies/{company}/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyOperationsController::class, 'destroy'])
        ->whereNumber('company')->whereNumber('record')->where('resource', 'clients|vehicles|employees|services');
});

// BLOQUE 16 - puestos, ordenes, asignaciones y fotos de vehiculos/lavadores.
Route::middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->prefix('v1')->group(function (): void {
    Route::get('/companies/{company}/workflow/branches', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'branches'])->whereNumber('company');
    Route::get('/companies/{company}/workflow/queue', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'queue'])->whereNumber('company');
    // 24N.7: reservas visibles, recepción idempotente y avisos de llegada.
    Route::get('/companies/{company}/workflow/reservations-24n7', [\App\Http\Controllers\Api\V1\CompanyReservationIntake24N7Controller::class, 'index'])->whereNumber('company');
    Route::get('/companies/{company}/workflow/arrival-reminders-24n7', [\App\Http\Controllers\Api\V1\CompanyReservationIntake24N7Controller::class, 'reminders'])->whereNumber('company');
    Route::post('/companies/{company}/workflow/reservations-24n7/{booking}/arrival-read', [\App\Http\Controllers\Api\V1\CompanyReservationIntake24N7Controller::class, 'acknowledge'])->whereNumber('company')->whereNumber('booking');
    Route::post('/companies/{company}/workflow/reservations-24n7/{booking}/receive', [\App\Http\Controllers\Api\V1\CompanyReservationIntake24N7Controller::class, 'receive'])->whereNumber('company')->whereNumber('booking');
    Route::get('/companies/{company}/workflow/orders-board-24e', [\App\Http\Controllers\Api\V1\CompanyWashOrdersBoard24EController::class, 'index'])->whereNumber('company');
    Route::post('/companies/{company}/workflow/orders/{order}/transition', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'transition'])->whereNumber('company')->whereNumber('order');
    Route::get('/companies/{company}/workflow/orders/{order}/history', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'history'])->whereNumber('company')->whereNumber('order');
    Route::get('/companies/{company}/workflow/{resource}', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'index'])->whereNumber('company')->where('resource', 'bays|orders|assignments');
    Route::post('/companies/{company}/workflow/{resource}', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'store'])->whereNumber('company')->where('resource', 'bays|orders|assignments');
    Route::get('/companies/{company}/workflow/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'show'])->whereNumber('company')->where('resource', 'bays|orders|assignments')->whereNumber('record');
    Route::patch('/companies/{company}/workflow/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'update'])->whereNumber('company')->where('resource', 'bays|orders|assignments')->whereNumber('record');
    Route::delete('/companies/{company}/workflow/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyWashWorkflowController::class, 'destroy'])->whereNumber('company')->where('resource', 'bays|orders|assignments')->whereNumber('record');
    Route::get('/companies/{company}/media/{kind}/{record}', [\App\Http\Controllers\Api\V1\CompanyMediaController::class, 'show'])->whereNumber('company')->where('kind', 'vehicles|employees|items')->whereNumber('record');
    Route::get('/companies/{company}/media/{kind}/{record}/file', [\App\Http\Controllers\Api\V1\CompanyMediaController::class, 'file'])->whereNumber('company')->where('kind', 'vehicles|employees|items')->whereNumber('record');
    Route::post('/companies/{company}/media/{kind}/{record}', [\App\Http\Controllers\Api\V1\CompanyMediaController::class, 'store'])->whereNumber('company')->where('kind', 'vehicles|employees|items')->whereNumber('record');
    Route::patch('/companies/{company}/media/{kind}/{record}', [\App\Http\Controllers\Api\V1\CompanyMediaController::class, 'update'])->whereNumber('company')->where('kind', 'vehicles|employees|items')->whereNumber('record');
    Route::delete('/companies/{company}/media/{kind}/{record}', [\App\Http\Controllers\Api\V1\CompanyMediaController::class, 'destroy'])->whereNumber('company')->where('kind', 'vehicles|employees|items')->whereNumber('record');
});

// BLOQUE 17 - Agenda administrativa: reservas, bloqueos, turnos y plantilla de personal.
Route::prefix('v1')->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {
    Route::get('/companies/{company}/schedule/agenda-24d', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'agenda24D'])->whereNumber('company');
    Route::get('/companies/{company}/schedule/availability-24d', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'availability24D'])->whereNumber('company');
    // Bloque 24D.2: avisos diarios y asignacion previa, sin iniciar lavados.
    Route::get('/companies/{company}/schedule/daily-24d2', [\App\Http\Controllers\Api\V1\CompanyBookingDaily24D2Controller::class, 'overview'])->whereNumber('company');
    Route::post('/companies/{company}/schedule/daily-24d2/reminder-read', [\App\Http\Controllers\Api\V1\CompanyBookingDaily24D2Controller::class, 'acknowledgeTomorrow'])->whereNumber('company');
    Route::post('/companies/{company}/schedule/daily-24d2/{booking}/assign', [\App\Http\Controllers\Api\V1\CompanyBookingDaily24D2Controller::class, 'assign'])->whereNumber('company')->whereNumber('booking');
    Route::post('/companies/{company}/schedule/roster-bulk-b25d', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'bulkRosterB25D'])->whereNumber('company');
    Route::get('/companies/{company}/schedule/options', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'options'])->whereNumber('company');
    Route::get('/companies/{company}/schedule/bookings/{booking}/history', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'history'])->whereNumber('company')->whereNumber('booking');
    Route::get('/companies/{company}/schedule/{resource}', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'index'])->whereNumber('company')->where('resource','bookings|blocks|shifts|roster');
    Route::post('/companies/{company}/schedule/{resource}', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'store'])->whereNumber('company')->where('resource','bookings|blocks|shifts|roster');
    Route::get('/companies/{company}/schedule/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'show'])->whereNumber('company')->where('resource','bookings|blocks|shifts|roster')->whereNumber('record');
    Route::patch('/companies/{company}/schedule/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'update'])->whereNumber('company')->where('resource','bookings|blocks|shifts|roster')->whereNumber('record');
    Route::delete('/companies/{company}/schedule/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyBookingController::class, 'destroy'])->whereNumber('company')->where('resource','bookings|blocks|shifts|roster')->whereNumber('record');
});

// BLOQUE 18 - Inventario por empresa/sucursal: categorias, proveedores, productos, movimientos.
Route::prefix('v1')->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {
    Route::get('/companies/{company}/inventory/options', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'options'])->whereNumber('company');
    Route::get('/companies/{company}/inventory/stock', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'stock'])->whereNumber('company');
    Route::get('/companies/{company}/inventory/movements/{movement}/history', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'history'])->whereNumber('company')->whereNumber('movement');
    Route::get('/companies/{company}/inventory/{resource}', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'index'])->whereNumber('company')->where('resource', 'categories|suppliers|items|movements');
    Route::post('/companies/{company}/inventory/{resource}', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'store'])->whereNumber('company')->where('resource', 'categories|suppliers|items|movements');
    Route::get('/companies/{company}/inventory/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'show'])->whereNumber('company')->where('resource', 'categories|suppliers|items|movements')->whereNumber('record');
    Route::patch('/companies/{company}/inventory/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'update'])->whereNumber('company')->where('resource', 'categories|suppliers|items|movements')->whereNumber('record');
    Route::delete('/companies/{company}/inventory/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyInventoryController::class, 'destroy'])->whereNumber('company')->where('resource', 'categories|suppliers|items|movements')->whereNumber('record');
});

// BLOQUE 19 - Caja manual: cajas, sesiones, categorias de egresos y movimientos.
Route::prefix('v1')->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {
    // 24K - tarjetas, movimientos auditados y conciliaciones bancarias.
        Route::post('/companies/{company}/finance/transfers', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'internalTransfer'])->whereNumber('company');
    Route::get('/companies/{company}/finance/transfers', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'internalTransfers'])->whereNumber('company');
    Route::get('/companies/{company}/finance/overview', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'overview'])->whereNumber('company');
    Route::post('/companies/{company}/finance/banks/{bank}/initialize', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'initializeBank'])->whereNumber('company')->whereNumber('bank');
    Route::get('/companies/{company}/finance/banks/{bank}/entries', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'entries'])->whereNumber('company')->whereNumber('bank');
    Route::post('/companies/{company}/finance/banks/{bank}/entries', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'bankEntry'])->whereNumber('company')->whereNumber('bank');
    Route::post('/companies/{company}/finance/banks/{bank}/closings/open', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'openClosing'])->whereNumber('company')->whereNumber('bank');
    Route::post('/companies/{company}/finance/banks/{bank}/closings/{closing}/close', [\App\Http\Controllers\Api\V1\CompanyFinance24KController::class, 'closeClosing'])->whereNumber('company')->whereNumber('bank')->whereNumber('closing');
    Route::get('/companies/{company}/cash/options', [\App\Http\Controllers\Api\V1\CompanyCashController::class, 'options'])->whereNumber('company');
    Route::get('/companies/{company}/cash/movements/{movement}/history', [\App\Http\Controllers\Api\V1\CompanyCashController::class, 'history'])->whereNumber('company')->whereNumber('movement');
    Route::get('/companies/{company}/cash/{resource}', [\App\Http\Controllers\Api\V1\CompanyCashController::class, 'index'])->whereNumber('company')->where('resource', 'registers|sessions|categories|movements');
    Route::post('/companies/{company}/cash/{resource}', [\App\Http\Controllers\Api\V1\CompanyCashController::class, 'store'])->whereNumber('company')->where('resource', 'registers|sessions|categories|movements');
    Route::get('/companies/{company}/cash/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyCashController::class, 'show'])->whereNumber('company')->where('resource', 'registers|sessions|categories|movements')->whereNumber('record');
    Route::patch('/companies/{company}/cash/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyCashController::class, 'update'])->whereNumber('company')->where('resource', 'registers|sessions|categories|movements')->whereNumber('record');
    Route::delete('/companies/{company}/cash/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanyCashController::class, 'destroy'])->whereNumber('company')->where('resource', 'registers|sessions|categories|movements')->whereNumber('record');
});

// BLOQUE 20 - Venta y cobro al entregar: cuentas, medios, descuentos y cobros.
Route::prefix('v1')->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {
    Route::get('/companies/{company}/sales/options', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'options'])->whereNumber('company');
    Route::get('/companies/{company}/sales/quote/{order}', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'quote'])->whereNumber('company')->whereNumber('order');
    Route::post('/companies/{company}/sales/checkout/{order}', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'checkout'])->whereNumber('company')->whereNumber('order');
    Route::get('/companies/{company}/sales/{resource}', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'index'])->whereNumber('company')->where('resource','banks|methods|discounts|payments');
    Route::post('/companies/{company}/sales/{resource}', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'store'])->whereNumber('company')->where('resource','banks|methods|discounts|payments');
    Route::get('/companies/{company}/sales/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'show'])->whereNumber('company')->where('resource','banks|methods|discounts|payments')->whereNumber('record');
    Route::patch('/companies/{company}/sales/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'update'])->whereNumber('company')->where('resource','banks|methods|discounts|payments')->whereNumber('record');
    Route::delete('/companies/{company}/sales/{resource}/{record}', [\App\Http\Controllers\Api\V1\CompanySalesController::class, 'destroy'])->whereNumber('company')->where('resource','banks|methods|discounts|payments')->whereNumber('record');
});

// BLOQUE 21A - Smart POS artículos y accesorios (comprobante no fiscal).
Route::prefix('v1')->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {
    Route::get('/companies/{company}/pos/options', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'options'])->whereNumber('company');
    Route::get('/companies/{company}/pos/document-designs', [\App\Http\Controllers\Api\V1\CompanyPosDocumentTemplateController::class, 'show'])->whereNumber('company');
    Route::post('/companies/{company}/pos/document-designs', [\App\Http\Controllers\Api\V1\CompanyPosDocumentTemplateController::class, 'save'])->whereNumber('company');
    Route::get('/companies/{company}/pos/fiscal-settings', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'fiscalSettings'])->whereNumber('company');
    Route::post('/companies/{company}/pos/fiscal-settings', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'saveFiscalSettings'])->whereNumber('company');
    Route::get('/companies/{company}/pos/wash/{order}', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'washForCheckout'])->whereNumber('company')->whereNumber('order');
    Route::get('/companies/{company}/pos/products', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'products'])->whereNumber('company');
    Route::get('/companies/{company}/pos/customers', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'customers'])->whereNumber('company');
    Route::get('/companies/{company}/pos/reports/summary', [\App\Http\Controllers\Api\V1\CompanyPosReportsController::class, 'summary'])->whereNumber('company');
    Route::get('/companies/{company}/reports/unified', [\App\Http\Controllers\Api\V1\CompanyUnifiedReportsController::class, 'show'])->whereNumber('company');
    Route::get('/companies/{company}/pos/sales', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'index'])->whereNumber('company');
    Route::post('/companies/{company}/pos/sales', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'checkout'])->whereNumber('company');
    Route::get('/companies/{company}/pos/sales/{sale}', [\App\Http\Controllers\Api\V1\CompanyPosController::class, 'show'])->whereNumber('company')->whereNumber('sale');
});

// BLOQUE 23A - Compras reales y recepciones parciales auditadas.
Route::prefix('v1')->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {
    Route::get('/companies/{company}/purchasing/options', [\App\Http\Controllers\Api\V1\CompanyPurchasingController::class, 'options'])->whereNumber('company');
    Route::get('/companies/{company}/purchasing/orders', [\App\Http\Controllers\Api\V1\CompanyPurchasingController::class, 'index'])->whereNumber('company');
    Route::post('/companies/{company}/purchasing/orders', [\App\Http\Controllers\Api\V1\CompanyPurchasingController::class, 'store'])->whereNumber('company');
    Route::get('/companies/{company}/purchasing/orders/{order}', [\App\Http\Controllers\Api\V1\CompanyPurchasingController::class, 'show'])->whereNumber('company')->whereNumber('order');
    Route::post('/companies/{company}/purchasing/orders/{order}/receive', [\App\Http\Controllers\Api\V1\CompanyPurchasingController::class, 'receive'])->whereNumber('company')->whereNumber('order');
    Route::post('/companies/{company}/purchasing/orders/{order}/cancel', [\App\Http\Controllers\Api\V1\CompanyPurchasingController::class, 'cancel'])->whereNumber('company')->whereNumber('order');
});
// BLOQUE 24A.1 - Dashboard ejecutivo: lectura autenticada, sin migraciones.
Route::prefix('v1')->middleware(['auth:sanctum', \App\Http\Middleware\CompanyModuleAccess24N2::class])->group(function (): void {
    Route::get('/companies/{company}/dashboard/overview', [\App\Http\Controllers\Api\V1\CompanyDashboardController::class, 'overview'])->whereNumber('company');
    Route::get('/companies/{company}/dashboard/visual-24a3', [\App\Http\Controllers\Api\V1\CompanyDashboardVisual24A3Controller::class, 'show'])->whereNumber('company');
    Route::get('/companies/{company}/dashboard/search-24a3', [\App\Http\Controllers\Api\V1\CompanyDashboardVisual24A3Controller::class, 'search'])->whereNumber('company');
    Route::get('/companies/{company}/dashboard/analytics', [\App\Http\Controllers\Api\V1\CompanyDashboardAnalyticsController::class, 'overview'])->whereNumber('company');
    Route::get('/companies/{company}/dashboard/active-washes', [\App\Http\Controllers\Api\V1\CompanyDashboardAnalyticsController::class, 'activeWashes'])->whereNumber('company');
});

// 24N.8 - Administracion propia de MyCarWash
require __DIR__.'/master_24n8.php';

// BLOQUE 24N.9.1 - Panel maestro con dashboard y suscripciones.
require __DIR__.'/master_office_24n9.php';
