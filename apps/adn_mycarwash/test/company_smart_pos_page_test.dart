import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_smart_pos_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'pos-test-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  testWidgets('Smart POS carga catálogo, carrito y cobro', (tester) async {
    final paths = <String>[];
    final client = MockClient((request) async {
      paths.add(request.url.path);
      if (request.url.path.endsWith('/pos/options')) {
        return http.Response(
          jsonEncode({
            'data': {
              'branches': [
                {'id': 1, 'name': 'Principal'},
              ],
              'methods': [
                {'id': 1, 'name': 'Efectivo', 'channel': 'CASH'},
                {'id': 2, 'name': 'Transferencia', 'channel': 'BANK'},
              ],
              'sessions': [
                {'id': 1, 'branch_id': 1, 'name': 'Caja'},
              ],
              'banks': [
                {'id': 1, 'branch_id': 1, 'alias': 'Banco Demo'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/pos/products')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'sku': 'ARO-01',
                'name': 'Aromatizante',
                'unit': 'unidad',
                'sale_price': '150.00',
                'stock': '5.000',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/pos/sales')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['branch_id'], 1);
        expect((body['lines'] as List).first['quantity'], 1);
        expect((body['payments'] as List).first['amount'], '150.00');
        return http.Response(
          jsonEncode({
            'data': {
              'id': 9,
              'status': 'POSTED',
              'posted_at': '2026-11-16 10:00:00',
              'subtotal': '150.00',
              'discount_amount': '0.00',
              'total': '150.00',
              'lines': [
                {
                  'name_snapshot': 'Aromatizante',
                  'quantity': '1.000',
                  'line_total': '150.00',
                },
              ],
              'payments': [
                {'channel': 'CASH', 'amount': '150.00'},
              ],
            },
          }),
          201,
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
            child: CompanySmartPosPage(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Smart POS'), findsOneWidget);
    expect(find.text('Aromatizante'), findsOneWidget);
    await tester.tap(find.byTooltip('Agregar al carrito'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Subtotal: L 150.00'), findsOneWidget);
    await tester.ensureVisible(find.text('Todo efectivo'));
    await tester.tap(find.text('Todo efectivo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pos_checkout')));
    await tester.tap(find.byKey(const ValueKey('pos_checkout')));
    await tester.pumpAndSettle();
    expect(find.text('Venta #9 confirmada'), findsOneWidget);
    expect(paths.any((p) => p.endsWith('/pos/sales')), isTrue);
  });
}
