<?php
namespace App\Support;

use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;
use Illuminate\Validation\ValidationException;

final class ServiceTariff24F {
    public static function resolve(int $company, int $service, int $vehicle, mixed $base): mixed {
        if (!Schema::hasTable('service_vehicle_prices')) return $base;
        $configured = DB::table('service_vehicle_prices')->where('company_id', $company)
            ->where('service_id', $service);
        if (!(clone $configured)->exists()) return $base; // compatibilidad con servicios existentes
        $type = trim((string) DB::table('vehicles')->where('company_id', $company)
            ->where('id', $vehicle)->value('vehicle_type'));
        if ($type === '') throw ValidationException::withMessages([
            'vehicle_id' => 'Configura el tipo del vehículo para calcular la tarifa del lavado.',
        ]);
        $price = (clone $configured)->whereRaw('LOWER(vehicle_type) = ?', [mb_strtolower($type)])->value('price');
        if ($price === null) throw ValidationException::withMessages([
            'service_id' => 'El servicio no tiene tarifa para el tipo de vehículo: '.$type,
        ]);
        return $price;
    }
}
