import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_sales_page.dart';
import 'package:adn_mycarwash/ui/company_smart_pos_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'test-sales-cards-24l',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  for (final module in [
    SalesModule.methods,
    SalesModule.discounts,
    SalesModule.payments,
  ]) {
    testWidgets('${module.name}: muestra tarjeta compacta con datos reales', (
      tester,
    ) async {
      final fixtures = <SalesModule, Map<String, dynamic>>{
        SalesModule.methods: {
          'id': 11,
          'name': 'Transferencia bancaria',
          'channel': 'BANK',
          'is_active': true,
        },
        SalesModule.discounts: {
          'id': 12,
          'tracking_code': 'LAV-120',
          'order_id': 120,
          'amount': '45.00',
          'reason': 'Promoción autorizada',
        },
        SalesModule.payments: {
          'id': 13,
          'tracking_code': 'LAV-121',
          'order_id': 121,
          'amount': '240.00',
          'method_name': 'Efectivo',
          'status': 'POSTED',
        },
      };
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'data': [fixtures[module]],
            'current_page': 1,
            'last_page': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanySalesPage(module: module, client: client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(
          ValueKey('sales_card_24l_${module.name}_${fixtures[module]!['id']}'),
        ),
        findsOneWidget,
      );
      expect(find.byTooltip('Consultar'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Historial presenta tarjeta y boton de comprobante', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/pos/options')) {
        return http.Response(
          jsonEncode({
            'data': {
              'branches': [
                {'id': 1, 'name': 'Principal'},
              ],
              'methods': [],
              'sessions': [],
              'banks': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/pos/sales')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 91,
                'total': '195.00',
                'document_type': 'RECEIPT',
                'customer_name_snapshot': 'Cliente de prueba',
                'status': 'POSTED',
                'posted_at': '2026-11-18 13:15:00',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanySmartPosPage(client: client, initialHistory: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('pos_history_card_24l_91')),
      findsOneWidget,
    );
    expect(find.text('Cliente de prueba'), findsOneWidget);
    expect(find.text('Consultar comprobante'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
