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
      accessToken: 'reports-24m-ui-test',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Reportes: identidad visual y periodos rapidos', (tester) async {
    final kinds = <String>[];
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/pos/options')) {
        return http.Response(
          jsonEncode({
            'data': {'branches': <Object>[]},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/reports/unified')) {
        kinds.add(request.url.queryParameters['kind'] ?? '');
        return http.Response(
          jsonEncode({
            'data': {
              'metrics': [
                {'label': 'Ingresos POS', 'value': 'L 0.00'},
              ],
              'sections': <Object>[],
              'warnings': <Object>[],
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
          body: CompanyUnifiedReportsPage(kind: 'overview', client: client),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reports-hero-24m')), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-filters-24m')), findsOneWidget);
    expect(find.byKey(const ValueKey('reports-quick-Hoy')), findsOneWidget);
    expect(find.text('Resumen general'), findsOneWidget);
    expect(find.text('Exportar PDF del período'), findsOneWidget);
    expect(kinds, contains('overview'));
    expect(tester.takeException(), isNull);
  });
}
