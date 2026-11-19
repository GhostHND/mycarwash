import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_order_detail_24n6.dart';

void main() {
  setUp(() => MyCarWashSession.begin(
        accessToken: 'test-token',
        companyId: 1,
        apiBaseUrl: 'http://localhost:8000/api/v1',
      ));
  tearDown(MyCarWashSession.clear);

  testWidgets('24N.6: detalle real, historial y acciones sin desbordamiento',
      (tester) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/workflow/orders/10/history')) {
        return http.Response(jsonEncode({
          'data': [
            {'from_status': null, 'to_status': 'EN_ESPERA', 'occurred_at': '2026-11-19 08:00:00'},
            {'from_status': 'EN_ESPERA', 'to_status': 'EN_PROCESO', 'occurred_at': '2026-11-19 08:15:00'},
          ],
        }), 200);
      }
      if (request.url.path.endsWith('/workflow/orders/10')) {
        return http.Response(jsonEncode({
          'data': {
            'id': 10,
            'tracking_code': 'MCW-TEST-10',
            'vehicle_id': 4,
            'vehicle_name': 'Toyota Corolla',
            'plate': 'HAA-1234',
            'vehicle_photo_exists': false,
            'client_name': 'Cliente QA',
            'service_name': 'Lavado general',
            'bay_name': 'Puesto 2',
            'status': 'EN_PROCESO',
            'started_at': '2026-11-19 08:15:00',
            'estimated_minutes': 45,
            'quoted_price': '350.00',
            'assignments': [
              {'full_name': 'Lavador QA', 'is_primary': true},
            ],
          },
        }), 200);
      }
      return http.Response('{"message":"No encontrado"}', 404);
    });
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (context) => TextButton(
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => CompanyOrderDetail24N6(
            orderId: 10,
            client: client,
            onEdit: (order) async {},
            onAdvance: (order) async {},
          ),
        ),
        child: const Text('Abrir orden'),
      ),
    ))));
    await tester.tap(find.text('Abrir orden'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle de orden'), findsOneWidget);
    expect(find.text('MCW-TEST-10'), findsOneWidget);
    expect(find.text('Toyota Corolla'), findsOneWidget);
    expect(find.text('HAA-1234'), findsOneWidget);
    expect(find.text('Cliente QA'), findsOneWidget);
    expect(find.textContaining('Lavador QA'), findsOneWidget);
    expect(find.text('Historial de la orden'), findsOneWidget);
    expect(find.byKey(const ValueKey('order_detail_edit_24n6')), findsOneWidget);
    expect(find.byKey(const ValueKey('order_detail_status_24n6')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Cerrar'));
    await tester.pumpAndSettle();
    expect(find.text('Detalle de orden'), findsNothing);
  });
}
