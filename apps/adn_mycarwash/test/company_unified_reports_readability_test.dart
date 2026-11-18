import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_unified_reports_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.Client reportsClient() => MockClient((request) async {
  if (request.url.path.endsWith('/pos/options')) {
    return http.Response(
      jsonEncode({
        'data': {
          'branches': <Object>[],
          'methods': <Object>[],
          'sessions': <Object>[],
          'banks': <Object>[],
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
            {'label': 'Ingresos POS', 'value': 'L 2,880.00'},
            {'label': 'Ventas POS confirmadas', 'value': '7'},
            {
              'label': 'Cobros de lavados registrados por medio de pago',
              'value': 'L 350.00',
            },
          ],
          'sections': [
            {
              'title': 'Ventas POS por día',
              'columns': {
                'date': 'Fecha',
                'count': 'Ventas',
                'total': 'Total HNL',
              },
              'rows': [
                {'date': '2026-11-17', 'count': '7', 'total': '2880.00'},
              ],
              'note': 'Un pago mixto no duplica la venta.',
            },
            {
              'title': 'Cobros POS por canal',
              'columns': {
                'channel': 'Canal',
                'count': 'Pagos',
                'amount': 'Importe HNL',
              },
              'rows': [
                {'channel': 'BANK', 'count': '3', 'amount': '1170.00'},
                {'channel': 'CASH', 'count': '6', 'amount': '1710.00'},
              ],
              'note': '',
            },
          ],
          'warnings': <Object>[],
        },
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('{}', 404);
});

Future<void> expectReadable(WidgetTester tester, Size screen) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final client = reportsClient();
  addTearDown(client.close);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CompanyUnifiedReportsPage(kind: 'overview', client: client),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final initialLayoutError = tester.takeException();
  expect(
    initialLayoutError,
    isNull,
    reason: 'Desbordamiento en KPI, filtros o encabezado antes de desplazar',
  );
  await tester.ensureVisible(find.text('Detalle de operaciones'));
  await tester.pumpAndSettle();
  final tableFinder = find.byKey(
    const ValueKey('report-data-Ventas POS por día'),
  );
  expect(tableFinder, findsOneWidget);
  final table = tester.widget<DataTable>(tableFinder);
  expect(table.headingTextStyle?.fontSize, 15);
  expect(table.dataTextStyle?.fontSize, 16);
  expect(table.dataRowMinHeight, 52);
  final cardFinder = find.byKey(
    const ValueKey('report-section-Ventas POS por día'),
  );
  final cardWidth = tester.getSize(cardFinder).width;
  final tableWidth = tester.getSize(tableFinder).width;
  // Ancho util = ancho de tarjeta - 2 * (padding 17 + borde 1).
  // No relajar la prueba por comodidad: verificar el area util real.
  expect(tableWidth, greaterThanOrEqualTo(cardWidth - 36.1));
  expect(find.text('1 registro'), findsWidgets);
  final payments = find.byKey(
    const ValueKey('report-data-Cobros POS por canal'),
  );
  expect(payments, findsOneWidget);
  final paymentTable = tester.widget<DataTable>(payments);
  expect(paymentTable.headingTextStyle?.fontSize, 15);
  expect(paymentTable.dataTextStyle?.fontSize, 16);
  expect(tester.takeException(), isNull);
}

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'test-token-22b3',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  testWidgets('Reportes: tablas legibles y ancho completo en escritorio', (
    tester,
  ) async {
    await expectReadable(tester, const Size(1440, 900));
  });
  testWidgets('Reportes: tablas legibles sin desbordamiento en movil', (
    tester,
  ) async {
    await expectReadable(tester, const Size(420, 900));
  });
}
