import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_sales_page.dart';
import 'package:adn_mycarwash/ui/company_sale_checkout_dialog.dart';
import 'package:adn_mycarwash/ui/company_cash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'test-sales-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  for (final module in SalesModule.values) {
    testWidgets('${module.name}: lista y formulario disponibles', (
      tester,
    ) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/sales/options')) {
          return http.Response(
            jsonEncode({
              'data': {
                'branches': [
                  {'id': 1, 'name': 'Principal'},
                ],
                'orders': [
                  {'id': 1, 'tracking_code': 'TST', 'quoted_price': '350.00'},
                ],
                'banks': [
                  {'id': 1, 'alias': 'Cuenta', 'bank_name': 'Banco Demo'},
                ],
                'methods': [
                  {'id': 1, 'name': 'Efectivo', 'channel': 'CASH'},
                ],
                'sessions': [
                  {'id': 1, 'name': 'Caja A', 'branch_id': 1},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'data': [], 'current_page': 1, 'last_page': 1}),
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
      expect(find.byType(CompanySalesPage), findsOneWidget);
      expect(find.text('Sin registros para mostrar.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sales_new')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sales_save')), findsOneWidget);
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
    });
  }

  testWidgets('sesión abierta tiene botón Cerrar caja', (tester) async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': [
            {
              'id': 1,
              'register_name': 'Caja',
              'status': 'OPEN',
              'opening_cash': '100.00',
              'expected_current': '100.00',
            },
          ],
          'current_page': 1,
          'last_page': 1,
        }),
        200,
        headers: {'content-type': 'application/json'},
      ),
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyCashPage(module: CashModule.sessions, client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cerrar caja'), findsOneWidget);
    await tester.tap(find.text('Cerrar caja'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cash_close_counted')), findsOneWidget);
  });

  testWidgets('entrega presenta precio, descuento libre y canal bancario', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/sales/quote/1')) {
        return http.Response(
          jsonEncode({
            'data': {
              'price': '350.00',
              'discount': '0.00',
              'discount_reason': null,
              'payments': [],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({
          'data': {
            'methods': [
              {'id': 1, 'name': 'Efectivo', 'channel': 'CASH'},
              {'id': 2, 'name': 'Transferencia', 'channel': 'BANK'},
            ],
            'sessions': [
              {'id': 1, 'branch_id': 1, 'name': 'Principal'},
            ],
            'banks': [
              {
                'id': 1,
                'branch_id': 1,
                'alias': 'Cuenta',
                'bank_name': 'Banco Demo',
              },
            ],
          },
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => CompanySaleCheckoutDialog(
                  order: {
                    'id': 1,
                    'branch_id': 1,
                    'version': 4,
                    'tracking_code': 'ORD-001',
                    'vehicle_label': 'Toyota',
                  },
                  client: client,
                ),
              ),
              child: const Text('Cobrar'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Cobrar'));
    await tester.pumpAndSettle();
    expect(find.text('Cobrar y entregar vehículo'), findsOneWidget);
    expect(find.textContaining('Precio normal: L 350.00'), findsOneWidget);
    expect(find.text('Precio final acordado (L)'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sales_checkout_confirm')),
      findsOneWidget,
    );
  });
}
