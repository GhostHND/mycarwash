import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_pos_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'report-test-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Bloque 22A muestra ventas sin duplicar pagos mixtos', (
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
      if (request.url.path.endsWith('/pos/reports/summary')) {
        return http.Response(
          jsonEncode({
            'data': {
              'scope': {
                'company_id': 1,
                'branch_id': null,
                'from': '2026-11-01',
                'to': '2026-11-17',
                'currency': 'HNL',
              },
              'kpis': {
                'sales_count': 1,
                'total': '250.00',
                'discounts': '50.00',
                'tax': '0.00',
                'subtotal': '300.00',
              },
              'daily': [
                {'day': '2026-11-17', 'sales_count': 1, 'total': '250.00'},
              ],
              'payment_channels': [
                {'channel': 'CASH', 'payment_count': 1, 'amount': '150.00'},
                {'channel': 'BANK', 'payment_count': 1, 'amount': '100.00'},
              ],
              'documents': [
                {
                  'document_type': 'RECEIPT',
                  'sales_count': 1,
                  'total': '250.00',
                },
              ],
              'top_products': [
                {
                  'item_id': 1,
                  'sku': 'ARO-01',
                  'name': 'Aromatizante',
                  'quantity': '2.000',
                  'gross_line_amount': '300.00',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CompanyPosReportsPage(client: client)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Reportes Smart POS'), findsOneWidget);
    expect(find.text('L 250.00'), findsWidgets);
    expect(find.text('Aromatizante'), findsOneWidget);
    expect(find.text('Copiar CSV diario'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
