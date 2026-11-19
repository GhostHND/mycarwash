import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/washer_mobile_24n4.dart';

void main() {
  test('24N.4: navegación fija conserva exactamente las cinco pantallas', () {
    expect(WasherMobile24N4.destinations,
      ['Inicio','Órdenes de lavado','Escanear QR','Calendario','Perfil']);
  });
  test('24N.4: diseño base turquesa accesible', () {
    expect(WasherMobileColors.base.toARGB32(), 0xFF0FA7B4);
  });
}
