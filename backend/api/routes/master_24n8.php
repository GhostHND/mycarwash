<?php
/** Control maestro independiente, compatible con el API v1 existente. */
use App\Http\Controllers\Api\V1\MasterControl24N8Controller as Master;
use App\Http\Middleware\MasterOnly24N8;
use App\Http\Middleware\CompanyModuleAccess24N2;
use Illuminate\Support\Facades\Route;

Route::prefix('v1/master')->group(function () {
    Route::post('auth/token',[Master::class,'login'])->middleware('throttle:5,1');
    Route::middleware(['auth:sanctum',MasterOnly24N8::class])->group(function () {
        Route::post('auth/logout',[Master::class,'logout']);
        Route::get('overview',[Master::class,'overview']);
        Route::post('customers',[Master::class,'customerCreate']);
        Route::patch('customers/{customer}',[Master::class,'customerUpdate'])->whereNumber('customer');
        Route::delete('customers/{customer}',[Master::class,'customerDelete'])->whereNumber('customer');
        Route::post('plans',[Master::class,'planCreate']);
        Route::patch('plans/{plan}',[Master::class,'planUpdate'])->whereNumber('plan');
        Route::delete('plans/{plan}',[Master::class,'planDelete'])->whereNumber('plan');
        Route::post('companies',[Master::class,'companyCreate']);
        Route::patch('companies/{company}',[Master::class,'companyUpdate'])->whereNumber('company');
        Route::delete('companies/{company}',[Master::class,'companyDelete'])->whereNumber('company');
        Route::post('invoices',[Master::class,'invoiceCreate']);
        Route::patch('invoices/{invoice}',[Master::class,'invoiceUpdate'])->whereNumber('invoice');
        Route::delete('invoices/{invoice}',[Master::class,'invoiceDelete'])->whereNumber('invoice');
        Route::post('payments',[Master::class,'paymentCreate']);
        Route::patch('payments/{payment}',[Master::class,'paymentUpdate'])->whereNumber('payment');
        Route::post('payments/{payment}/confirm',[Master::class,'paymentConfirm'])->whereNumber('payment');
        Route::delete('payments/{payment}',[Master::class,'paymentDelete'])->whereNumber('payment');
        Route::post('notices',[Master::class,'noticeCreate']);
        Route::patch('notices/{notice}',[Master::class,'noticeUpdate'])->whereNumber('notice');
        Route::delete('notices/{notice}',[Master::class,'noticeDelete'])->whereNumber('notice');
    });
});
Route::prefix('v1')->middleware(['auth:sanctum',CompanyModuleAccess24N2::class])->group(function () {
    Route::get('companies/{company}/master-alerts-24n8',[Master::class,'companyAlerts'])->whereNumber('company');
    Route::post('companies/{company}/master-alerts-24n8/{notice}/read',[Master::class,'noticeRead'])->whereNumber('company')->whereNumber('notice');
});
