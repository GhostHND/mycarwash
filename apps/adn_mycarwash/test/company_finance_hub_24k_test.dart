import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_finance_hub_24k.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'test-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Caja y bancos muestran tarjetas e intervalos reales', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/finance/overview')) {
        return http.Response(
          jsonEncode({
            'data': {
              'period': 'day',
              'from': '2026-11-18',
              'through': '2026-11-18',
              'totals': {
                'cash_in': '300.00',
                'cash_out': '20.00',
                'bank_in': '80.00',
                'bank_out': '10.00',
              },
              'cash_closings': {'count': 0, 'difference': '0.00'},
              'cash': [
                {
                  'id': 1,
                  'name': 'Principal',
                  'code': 'CAJA1',
                  'is_active': true,
                  'in': '300.00',
                  'out': '20.00',
                  'net': '280.00',
                  'session_status': 'OPEN',
                  'session_id': 1,
                  'opening_cash': '100.00',
                  'expected_current': '380.00',
                },
              ],
              'banks': [
                {
                  'id': 2,
                  'bank_name': 'Banco de prueba',
                  'alias': 'Principal',
                  'is_active': true,
                  'in': '80.00',
                  'out': '10.00',
                  'net': '70.00',
                  'opening_set': true,
                  'estimated_balance': '180.00',
                },
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        '{}',
        422,
        headers: {'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyFinanceHub24K(
              section: 'cash',
              onNavigate: (_) {},
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Caja física'), findsOneWidget);
    expect(find.text('Banco de prueba'), findsOneWidget);
    expect(find.text('Ingresos bancarios'), findsOneWidget);
    expect(find.textContaining('380.00'), findsWidgets);
    await tester.tap(find.text('Semana'));
    await tester.pumpAndSettle();
    expect(find.text('Banco de prueba'), findsOneWidget);
    client.close();
  });
}
