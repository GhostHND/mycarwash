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

  http.Client fake() => MockClient(
    (request) async => http.Response(
      jsonEncode({
        'data': {
          'period': 'day',
          'from': '2026-11-18',
          'through': '2026-11-18',
          'cash_closings': {'count': 1, 'difference': '0.00'},
          'totals': {
            'cash_in': '100.00',
            'cash_out': '20.00',
            'bank_in': '50.00',
            'bank_out': '0.00',
          },
          'cash': [
            {
              'id': 1,
              'name': 'Caja central',
              'is_active': true,
              'in': '100.00',
              'out': '20.00',
              'net': '80.00',
              'transfer_in': '50.00',
              'transfer_out': '0.00',
              'session_id': 7,
              'session_status': 'OPEN',
              'opening_cash': '20.00',
              'expected_current': '150.00',
            },
          ],
          'banks': [
            {
              'id': 2,
              'bank_name': 'Banco Uno',
              'alias': 'Cuenta principal',
              'is_active': true,
              'opening_set': true,
              'in': '50.00',
              'out': '0.00',
              'net': '50.00',
              'sales_in': '50.00',
              'other_in': '0.00',
              'transfer_in': '0.00',
              'transfer_out': '50.00',
              'estimated_balance': '100.00',
              'closing': null,
            },
          ],
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    ),
  );

  testWidgets(
    'Caja fisica y bancos muestran tarjetas juntas y traspasos separados',
    (tester) async {
      final client = fake();
      await tester.binding.setSurfaceSize(const Size(1440, 1050));
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
      expect(find.text('Caja central'), findsOneWidget);
      expect(find.text('Banco Uno'), findsOneWidget);
      expect(find.text('Traspasos internos'), findsOneWidget);
      expect(find.text('Retirar banco → caja'), findsOneWidget);
      expect(find.text('Depositar caja → banco'), findsOneWidget);
      client.close();
    },
  );

  testWidgets('Arqueos y conciliaciones no duplican el resumen de caja', (
    tester,
  ) async {
    final client = fake();
    await tester.binding.setSurfaceSize(const Size(1440, 1050));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyFinanceHub24K(
              section: 'reconciliations',
              onNavigate: (_) {},
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Conteo contra caja'), findsOneWidget);
    expect(find.text('Comparar con extracto bancario'), findsOneWidget);
    expect(find.text('Ingresos en efectivo'), findsNothing);
    expect(find.text('Arqueo y cierre'), findsOneWidget);
    client.close();
  });
}
