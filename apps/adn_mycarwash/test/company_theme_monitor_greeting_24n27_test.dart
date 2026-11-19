import 'dart:convert';

import 'package:adn_mycarwash/core/company_monitor_colors_24n27.dart';
import 'package:adn_mycarwash/core/company_visual_theme.dart';
import 'package:adn_mycarwash/core/dashboard_greeting_24n27.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_wash_monitor_24b1.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() {
    CompanyVisualTheme.reset();
    MyCarWashSession.clear();
  });

  test('24N.2.7: limites de saludo segun hora LOCAL', () {
    String at(int hour, int minute, [String name = 'Eduardo']) =>
        dashboardGreeting24N27(DateTime(2026, 11, 18, hour, minute), name);
    expect(at(4, 59), 'Buenas noches, Eduardo');
    expect(at(5, 0), 'Buenos días, Eduardo');
    expect(at(11, 59), 'Buenos días, Eduardo');
    expect(at(12, 0), 'Buenos días, Eduardo');
    expect(at(12, 1), 'Buenas tardes, Eduardo');
    expect(at(18, 0), 'Buenas tardes, Eduardo');
    expect(at(18, 1), 'Buenas noches, Eduardo');
    expect(at(20, 54), 'Buenas noches, Eduardo');
    expect(at(0, 0), 'Buenas noches, Eduardo');
    expect(at(8, 1, '  '), 'Buenos días');
  });

  test('24N.2.7: monitor sigue los colores globales y sus cambios', () {
    CompanyVisualTheme.load({
      ...CompanyVisualTheme.defaults,
      'background_color': '#112233',
      'card_color': '#223344',
      'primary_color': '#AACCEE',
      'border_color': '#778899',
      'selected_color': '#445566',
      'text_color': '#F7F7F7',
    });
    expect(CompanyMonitorColors24N27.resolve('background_color'), const Color(0xFF112233));
    expect(CompanyMonitorColors24N27.resolve('surface_color'), const Color(0xFF223344));
    expect(CompanyMonitorColors24N27.resolve('primary_color'), const Color(0xFFAACCEE));
    expect(CompanyMonitorColors24N27.resolve('border_color'), const Color(0xFF778899));
    expect(CompanyMonitorColors24N27.resolve('queue_color'), const Color(0xFF445566));
    expect(CompanyMonitorColors24N27.resolve('text_color'), const Color(0xFFF7F7F7));
    CompanyVisualTheme.load({...CompanyVisualTheme.defaults, 'primary_color': '#CAFE01'});
    expect(CompanyMonitorColors24N27.resolve('primary_color'), const Color(0xFFCAFE01));
  });

  testWidgets('24N.2.7: desaparece Colores y no se consulta otro tema', (tester) async {
    MyCarWashSession.begin(
      accessToken: 'token-monitor-unico',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final requestedPaths = <String>[];
    final client = MockClient((request) async {
      requestedPaths.add(request.url.path);
      if (request.url.path.endsWith('/dashboard/monitor-24b2')) {
        return http.Response(jsonEncode({'data': {'active': [], 'active_total': 0}}), 200,
            headers: {'content-type': 'application/json'});
      }
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: CompanyWashMonitor24B1(client: client)),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Vista general de lavados'), findsOneWidget);
    expect(find.text('Colores'), findsNothing);
    expect(find.text('Guardar colores'), findsNothing);
    expect(find.text('Modo monitor'), findsOneWidget);
    expect(requestedPaths, isNot(contains('/api/v1/companies/1/monitor-theme-24b')));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
