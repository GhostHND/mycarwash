import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_dashboard_active_24a2.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'test-live',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    ),
  );
  tearDown(MyCarWashSession.clear);

  for (final size in <Size>[
    const Size(1580, 990),
    const Size(820, 950),
    const Size(390, 800),
  ]) {
    testWidgets('24A.2 solo un lavado visible y sin overflow ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final client = MockClient(
        (request) async => http.Response(
          jsonEncode({
            'data': {
              'total': 1,
              'offset': 0,
              'items': [
                {'id': 21, 'label': 'Orden #21'},
              ],
            },
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
              child: CompanyDashboardActive24A2(client: client),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('active_wash_21')), findsOneWidget);
      expect(find.byKey(const ValueKey('active_total')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('24A.2 cinco activos rotan 4 + 1 cada 15 segundos', (
    tester,
  ) async {
    final offsets = <int>[];
    final client = MockClient((request) async {
      final offset = int.parse(request.url.queryParameters['offset'] ?? '0');
      offsets.add(offset);
      final visible = List.generate(
        offset == 0 ? 4 : 1,
        (i) => {'id': offset + i + 1, 'label': 'Orden #${offset + i + 1}'},
      );
      return http.Response(
        jsonEncode({
          'data': {'total': 5, 'offset': offset, 'items': visible},
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
            child: CompanyDashboardActive24A2(client: client),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(offsets, [0]);
    expect(find.byKey(const ValueKey('active_wash_4')), findsOneWidget);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(offsets, [0, 4]);
    expect(find.byKey(const ValueKey('active_wash_5')), findsOneWidget);
    expect(find.byKey(const ValueKey('active_wash_4')), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    await tester.pump();
    expect(offsets, [0, 4, 0]);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('24A.2 sin activos no presenta tarjetas ficticias', (
    tester,
  ) async {
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'data': {'total': 0, 'offset': 0, 'items': []},
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
            child: CompanyDashboardActive24A2(client: client),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('active_empty')), findsOneWidget);
    expect(find.text('0 en proceso'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
