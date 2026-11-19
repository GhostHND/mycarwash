import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/company_washer_portal_24n3.dart';
import 'package:adn_mycarwash/core/dashboard_greeting_24n27.dart';

void main() {
  test('24N.3: el lavador dispone de exactamente cuatro categorias', () {
    expect(CompanyWasherPortal24N3.categories.keys.toList(),
      const ['Inicio', 'Mis trabajos', 'Asistencia', 'Perfil']);
  });

  test('Saludo conserva los horarios de la revision anterior', () {
    expect(dashboardGreeting24N27(DateTime(2026, 11, 18, 5), 'A'), 'Buenos días, A');
    expect(dashboardGreeting24N27(DateTime(2026, 11, 18, 18, 1), 'A'), 'Buenas noches, A');
  });
}
