import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_unified_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'test-token-22b',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Reportes muestra rango y exporta documento por categoria', (
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
      if (request.url.path.endsWith('/reports/unified')) {
        return http.Response(
          jsonEncode({
            'data': {
              'title': 'Inventario y productos',
              'kind': 'inventory',
              'scope': {
                'company_id': 1,
                'branch_id': null,
                'from': '2026-11-01',
                'to': '2026-11-17',
                'currency': 'HNL',
              },
              'metrics': [
                {'label': 'Movimientos registrados', 'value': '2'},
              ],
              'sections': [
                {
                  'title': 'Movimientos de inventario',
                  'columns': {'movement_type': 'Tipo', 'quantity': 'Cantidad'},
                  'rows': [
                    {'movement_type': 'IN', 'quantity': '4.000'},
                  ],
                  'note': 'Movimientos del periodo.',
                },
              ],
              'warnings': [],
              'generated_at': '2026-11-17T17:00:00-06:00',
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
        home: Scaffold(
          body: CompanyUnifiedReportsPage(kind: 'inventory', client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inventario y productos'), findsOneWidget);
    expect(find.text('Movimientos registrados'), findsOneWidget);
    expect(find.text('Exportar PDF del período'), findsOneWidget);
    expect(find.text('IN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
