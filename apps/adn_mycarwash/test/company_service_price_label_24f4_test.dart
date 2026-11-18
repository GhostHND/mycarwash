import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/company_service_price_label_24f4.dart';

void main() {
  final vehicles = <Map<String, dynamic>>[
    {'id': 2, 'vehicle_type': 'Turismo'},
    {'id': 3, 'vehicle_type': 'Pickup'},
    {'id': 4, 'vehicle_type': 'Camioneta'},
  ];
  final service = <String, dynamic>{
    'name': 'Lavado Básico',
    'price': '350.00',
    'vehicle_prices': [
      {'vehicle_type': 'Turismo', 'price': '200.00'},
      {'vehicle_type': 'Pickup', 'price': '350.00'},
    ],
  };
  test('Turismo muestra la tarifa especifica y no el precio base', () {
    expect(
      servicePriceLabel24F4(service, 2, vehicles),
      'Lavado Básico · L 200.00 (Turismo)',
    );
  });
  test('Pickup muestra su tarifa', () {
    expect(
      servicePriceLabel24F4(service, 3, vehicles),
      'Lavado Básico · L 350.00 (Pickup)',
    );
  });
  test('No inventa precio para categoria no configurada', () {
    expect(
      servicePriceLabel24F4(service, 4, vehicles),
      'Lavado Básico · Sin tarifa para Camioneta',
    );
  });
  test('Servicio antiguo sin tarifas muestra su precio base', () {
    final legacy = <String, dynamic>{
      'name': 'Lavado Antiguo',
      'price': '500.00',
    };
    expect(
      servicePriceLabel24F4(legacy, 2, vehicles),
      'Lavado Antiguo · L 500.00 (precio base)',
    );
  });
  test('No muestra precio sin vehiculo seleccionado', () {
    expect(
      servicePriceLabel24F4(service, null, vehicles),
      'Lavado Básico · Selecciona primero el vehículo',
    );
  });
}
