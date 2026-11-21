import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_dashboard_24a_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(
    () => MyCarWashSession.begin(
      accessToken: 'dashboard-24a-token',
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
    testWidgets('24A.1 dashboard sin overflow en ${size.width}', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final paths = <String>[];
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/dashboard/overview')) {
          return http.Response(
            jsonEncode({
              'data': {
                'date': '2026-11-17',
                'user_name': 'Usuario Autenticado',
                'company_name': 'Empresa Prueba',
                'timezone': 'America/Tegucigalpa',
                'branches': [
                  {'id': 1, 'name': 'Principal'},
                ],
                'kpis': {
                  'sales_today': '1250.00',
                  'services_today': '1250.00',
                  'commissions_today': '400.00',
                  'expenses_today': '150.00',
                  'balance_today': '700.00',
                  'active_washes': 2,
                  'bookings_today': 3,
                  'clients': 12,
                  'vehicles': 11,
                  'staff': 4,
                },
                'warnings': [],
                'balance_note': 'Balance operativo.',
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.url.path.endsWith('/settings')) {
          return http.Response(
            jsonEncode({
              'branding': {
                'primary_color': '#0FA7B4',
                'button_color': '#0FA7B4',
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
            body: SingleChildScrollView(
              child: CompanyDashboard24APage(
                client: client,
                onNavigate: paths.add,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.textContaining('Usuario Autenticado'), findsOneWidget);
      expect(find.text('Servicios'), findsWidgets);
      expect(find.text('Balance comisiones'), findsOneWidget);
      expect(find.text('Gastos'), findsWidgets);
      expect(find.text('Balance de hoy'), findsOneWidget);
      expect(find.text('L 1250.00'), findsOneWidget);
      expect(find.text('Lavados activos'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('dashboard_action_Nueva reserva')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('dashboard_action_Nueva reserva')),
      );
      expect(paths, contains('Reservas'));
    });
  }
}
