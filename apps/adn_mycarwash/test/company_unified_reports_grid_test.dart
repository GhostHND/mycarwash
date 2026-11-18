import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_unified_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client reportClient() => MockClient((request) async {
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
          'kind': 'overview',
          'title': 'Resumen general',
          'scope': {
            'company_id': 1,
            'branch_id': null,
            'from': '2026-11-01',
            'to': '2026-11-17',
            'currency': 'HNL',
          },
          'metrics': [
            {'label': 'Ventas POS confirmadas', 'value': '7'},
            {'label': 'Ingresos POS', 'value': 'L 2,880.00'},
            {'label': 'Descuentos POS', 'value': 'L 100.00'},
            {'label': 'ISV registrado POS', 'value': 'L 180.00'},
            {'label': 'Órdenes de lavado creadas', 'value': '1'},
            {'label': 'Cobros de lavados registrados', 'value': 'L 350.00'},
          ],
          'sections': [
            {
              'title': 'Ventas POS por día',
              'columns': {'date': 'Fecha', 'total': 'Total HNL'},
              'rows': [
                {'date': '2026-11-17', 'total': '2880.00'},
              ],
              'note': 'Una venta se cuenta una vez.',
            },
            {
              'title': 'Cobros POS por canal',
              'columns': {'channel': 'Canal', 'amount': 'Importe HNL'},
              'rows': [
                {'channel': 'BANK', 'amount': '1170.00'},
                {'channel': 'CASH', 'amount': '1710.00'},
              ],
              'note': 'No sumar de nuevo para calcular ingresos.',
            },
            {
              'title': 'Lavados por estado',
              'columns': {'state': 'Estado', 'count': 'Órdenes'},
              'rows': [
                {'state': 'ENTREGADO', 'count': '1'},
              ],
              'note': '',
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

int columns(WidgetTester tester, String key) {
  final grid = tester.widget<GridView>(find.byKey(ValueKey(key)));
  final delegate =
      grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
  return delegate.crossAxisCount;
}

Future<void> verifyGrid(
  WidgetTester tester,
  Size size,
  int expectedMetrics,
  int expectedSections,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = reportClient();
  addTearDown(client.close);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompanyUnifiedReportsPage(kind: 'overview', client: client),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(columns(tester, 'reports-kpi-grid'), expectedMetrics);
  expect(columns(tester, 'reports-detail-grid'), expectedSections);
  final metric = tester.widget<GridView>(
    find.byKey(const ValueKey('reports-kpi-grid')),
  );
  final detail = tester.widget<GridView>(
    find.byKey(const ValueKey('reports-detail-grid')),
  );
  expect(
    (metric.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
        .mainAxisExtent,
    112,
  );
  expect(
    (detail.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
        .mainAxisExtent,
    305,
  );
  expect(find.text('Indicadores del período'), findsOneWidget);
  expect(find.text('Detalle de operaciones'), findsOneWidget);
  expect(find.text('Exportar PDF del período'), findsOneWidget);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'test-token-22b-grid',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Reportes: grilla uniforme en escritorio', (tester) async {
    await verifyGrid(tester, const Size(1440, 900), 3, 2);
  });
  testWidgets('Reportes: grilla uniforme en tableta', (tester) async {
    await verifyGrid(tester, const Size(820, 1000), 2, 1);
  });
  testWidgets('Reportes: grilla sin overflow en móvil', (tester) async {
    await verifyGrid(tester, const Size(420, 900), 1, 1);
  });
}
