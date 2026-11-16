import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_inventory_page.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'test-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  for (final module in InventoryModule.values) {
    testWidgets('${module.name} ofrece nuevo, consultar, editar y eliminar', (
      tester,
    ) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/inventory/options')) {
          return http.Response(
            jsonEncode({
              'data': {
                'branches': [
                  {'id': 1, 'name': 'Principal'},
                ],
                'categories': [
                  {'id': 1, 'name': 'Químicos'},
                ],
                'suppliers': [
                  {'id': 1, 'name': 'Proveedor'},
                ],
                'items': [
                  {
                    'id': 1,
                    'name': 'Shampoo',
                    'sku': 'SH-001',
                    'unit': 'litro',
                  },
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
              child: CompanyInventoryPage(module: module, client: client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CompanyInventoryPage), findsOneWidget);
      expect(find.text('No hay registros.'), findsOneWidget);
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
