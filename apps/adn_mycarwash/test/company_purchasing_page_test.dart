import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_purchasing_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'purchase-test',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Compras muestra proveedores, articulos y ordenes sin overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/purchasing/options')) {
        return http.Response(
          jsonEncode({
            'data': {
              'branches': [
                {'id': 1, 'name': 'Principal'},
              ],
              'suppliers': [
                {'id': 3, 'name': 'Proveedor Uno'},
              ],
              'items': [
                {
                  'id': 7,
                  'sku': 'FIL-01',
                  'name': 'Filtro',
                  'unit': 'unidad',
                  'cost_price': '35.00',
                },
              ],
            },
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/purchasing/orders')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 8,
                'number': 'OC-0000008',
                'status': 'ORDERED',
                'total': '70.00',
                'created_at': '2026-11-17 08:00:00',
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path.endsWith('/purchasing/orders/8')) {
        return http.Response(
          jsonEncode({
            'data': {
              'order': {'id': 8, 'number': 'OC-0000008', 'status': 'ORDERED'},
              'lines': [
                {
                  'id': 13,
                  'name_snapshot': 'Filtro',
                  'ordered_quantity': '2.000',
                  'received_quantity': '0.000',
                  'line_total': '70.00',
                },
              ],
              'receipts': [],
            },
          }),
          200,
        );
      }
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompanyPurchasingPage(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Compras y recepciones'), findsOneWidget);
    expect(find.text('Agregar artículo'), findsOneWidget);
    expect(find.text('OC-0000008 · L 70.00'), findsOneWidget);
    // Previene la regresión ListTile dentro de una tarjeta decorada.
    // Su Material transparente debe estar por encima de la decoración.
    final tiles = find.byType(ListTile);
    expect(tiles, findsOneWidget);
    final tileMaterials = find.ancestor(
      of: tiles,
      matching: find.byType(Material),
    );
    expect(
      tester
          .widgetList<Material>(tileMaterials)
          .any((material) => material.type == MaterialType.transparency),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(390, 820);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
