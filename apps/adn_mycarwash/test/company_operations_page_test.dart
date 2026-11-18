import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_operations_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> page(List<Map<String, dynamic>> data) => {
  'data': data,
  'current_page': 1,
  'last_page': 1,
  'total': data.length,
};

Widget wrapper(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'catalog-test-token',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Clientes consulta y crea con autenticación', (tester) async {
    final rows = <Map<String, dynamic>>[];
    var created = false;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer catalog-test-token');
      expect(request.url.path, '/api/v1/companies/1/clients');
      if (request.method == 'GET') {
        return http.Response(jsonEncode(page(rows)), 200);
      }
      expect(request.method, 'POST');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['full_name'], 'Cliente QA');
      rows.add({...body, 'id': 10});
      created = true;
      return http.Response(jsonEncode({'data': rows.first}), 201);
    });
    await tester.pumpWidget(
      wrapper(
        CompanyOperationsPage(
          catalog: OperationsCatalog.clients,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operations_new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('operations_full_name')),
      'Cliente QA',
    );
    final button = find.byKey(const ValueKey('operations_save'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(created, isTrue);
    expect(find.text('Cliente QA'), findsOneWidget);
    client.close();
  });

  testWidgets('Vehículos obliga seleccionar un cliente existente', (
    tester,
  ) async {
    var created = false;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer catalog-test-token');
      if (request.url.path.endsWith('/services/vehicle-types')) {
        expect(request.method, 'GET');
        return http.Response(
          jsonEncode({
            'data': ['Turismo', 'Pickup'],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/clients')) {
        return http.Response(
          jsonEncode(
            page([
              {'id': 4, 'full_name': 'Cliente dueño', 'is_active': true},
            ]),
          ),
          200,
        );
      }
      expect(request.url.path, '/api/v1/companies/1/vehicles');
      if (request.method == 'GET') {
        return http.Response(jsonEncode(page([])), 200);
      }
      final payload = jsonDecode(request.body) as Map<String, dynamic>;
      expect(payload['client_id'], 4);
      expect(payload['plate'], 'HBA-1000');
      expect(payload['vehicle_type'], 'Pickup');
      created = true;
      return http.Response(
        jsonEncode({
          'data': {...payload, 'id': 5},
        }),
        201,
      );
    });
    await tester.pumpWidget(
      wrapper(
        CompanyOperationsPage(
          catalog: OperationsCatalog.vehicles,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operations_new')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operations_choose_client')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente dueño'));
    await tester.pumpAndSettle();
    // Seleccionar una categoria recibida del API y comprobar que se envia.
    await tester.ensureVisible(
      find.byKey(const ValueKey('operations_vehicle_type')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operations_vehicle_type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pickup').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('operations_plate')),
      'HBA-1000',
    );
    final button = find.byKey(const ValueKey('operations_save'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(created, isTrue);
    client.close();
  });

  testWidgets('Empleados registra un lavador', (tester) async {
    var created = false;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/companies/1/employees');
      if (request.method == 'GET') {
        return http.Response(jsonEncode(page([])), 200);
      }
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      expect(data['position'], 'washer');
      expect(data['full_name'], 'Lavador QA');
      created = true;
      return http.Response(
        jsonEncode({
          'data': {...data, 'id': 1},
        }),
        201,
      );
    });
    await tester.pumpWidget(
      wrapper(
        CompanyOperationsPage(
          catalog: OperationsCatalog.employees,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operations_new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('operations_full_name')),
      'Lavador QA',
    );
    final button = find.byKey(const ValueKey('operations_save'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(created, isTrue);
    client.close();
  });

  testWidgets('Servicios valida precio y duración antes de guardar', (
    tester,
  ) async {
    var created = false;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/companies/1/services');
      if (request.method == 'GET') {
        return http.Response(jsonEncode(page([])), 200);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['price'], 250.5);
      expect(body['duration_minutes'], 45);
      created = true;
      return http.Response(
        jsonEncode({
          'data': {...body, 'id': 7},
        }),
        201,
      );
    });
    await tester.pumpWidget(
      wrapper(
        CompanyOperationsPage(
          catalog: OperationsCatalog.services,
          client: client,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('operations_new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('operations_name')),
      'Lavado premium',
    );
    await tester.enterText(
      find.byKey(const ValueKey('operations_price')),
      '250.50',
    );
    await tester.enterText(
      find.byKey(const ValueKey('operations_duration_minutes')),
      '45',
    );
    final button = find.byKey(const ValueKey('operations_save'));
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(created, isTrue);
    client.close();
  });
}
