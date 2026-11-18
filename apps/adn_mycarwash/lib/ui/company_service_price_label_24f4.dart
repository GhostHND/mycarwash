// Bloque 24F.4: mostrar la tarifa de Servicios que corresponde al vehículo.
// La autoridad de cobro sigue siendo Laravel (ServiceTariff24F).
String servicePriceLabel24F4(
  Map<String, dynamic> service,
  int? vehicleId,
  List<Map<String, dynamic>> vehicles,
) {
  final name = '${service['name'] ?? 'Servicio'}';
  if (vehicleId == null) {
    return '$name · Selecciona primero el vehículo';
  }
  Map<String, dynamic>? selectedVehicle;
  for (final vehicle in vehicles) {
    if (int.tryParse('${vehicle['id']}') == vehicleId) {
      selectedVehicle = vehicle;
      break;
    }
  }
  if (selectedVehicle == null) {
    return '$name · Vehículo no disponible';
  }
  final type = '${selectedVehicle['vehicle_type'] ?? ''}'.trim();
  final prices = service['vehicle_prices'];
  if (prices is List && prices.isNotEmpty) {
    if (type.isEmpty) {
      return '$name · Configura el tipo del vehículo';
    }
    for (final item in prices) {
      if (item is Map &&
          '${item['vehicle_type'] ?? ''}'.trim().toLowerCase() ==
              type.toLowerCase()) {
        final price = num.tryParse('${item['price']}');
        if (price != null) {
          return '$name · L ${price.toStringAsFixed(2)} ($type)';
        }
      }
    }
    return '$name · Sin tarifa para $type';
  }
  final base = num.tryParse('${service['price']}');
  if (base == null) {
    return '$name · Precio no disponible';
  }
  return '$name · L ${base.toStringAsFixed(2)} (precio base)';
}
