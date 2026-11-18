import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_booking_page.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'test-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  for (final module in BookingModule.values) {
    testWidgets('${module.name} muestra CRUD y formulario de alta', (
      tester,
    ) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/schedule/options')) {
          return http.Response(
            jsonEncode({
              'data': {
                'branches': [
                  {
                    'id': 1,
                    'name': 'Principal',
                    'timezone': 'America/Tegucigalpa',
                  },
                ],
                'bays': [
                  {'id': 1, 'branch_id': 1, 'name': 'Puesto A', 'code': 'A'},
                ],
                'vehicles': [
                  {
                    'id': 1,
                    'brand': 'Toyota',
                    'model': 'Corolla',
                    'plate': 'P01',
                  },
                ],
                'services': [
                  {
                    'id': 1,
                    'name': 'Lavado',
                    'price': 200,
                    'duration_minutes': 45,
                  },
                ],
                'employees': [
                  {'id': 1, 'full_name': 'Lavador'},
                ],
                'shifts': [
                  {'id': 1, 'branch_id': 1, 'name': 'Mañana', 'day_of_week': 1},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': <Map<String, dynamic>>[],
              'current_page': 1,
              'last_page': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'message': 'Sin datos de prueba'}),
          422,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanyBookingPage(module: module, client: client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CompanyBookingPage), findsOneWidget);
      if (module == BookingModule.bookings) {
        expect(find.text('No hay próximas reservas'), findsOneWidget);
      } else {
        expect(find.text('No hay registros.'), findsOneWidget);
      }
      final create = find.byIcon(Icons.add);
      expect(create, findsOneWidget);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(find.textContaining('Guardar'), findsWidgets);
      // No crear registros de prueba sobre el backend.
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      client.close();
    });
  }
}
