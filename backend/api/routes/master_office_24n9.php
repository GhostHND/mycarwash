<?php

use App\Http\Controllers\Api\V1\MasterOffice24N9Controller as Office;
use App\Http\Middleware\MasterOnly24N8;
use Illuminate\Support\Facades\Route;

Route::prefix('v1/master')->middleware(['auth:sanctum', MasterOnly24N8::class])->group(function () {
    Route::get('workspace-24n9', [Office::class, 'workspace']);
    Route::get('records-24n9/{resource}', [Office::class, 'records']);
    Route::patch('subscriptions-24n9/{company}', [Office::class, 'subscriptionUpdate'])->whereNumber('company');
});
