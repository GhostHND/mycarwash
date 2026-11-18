import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: '24n-test-token',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  testWidgets('Configuracion muestra ocho areas y conserva informacion', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/contacts')) {
        return http.Response(
          jsonEncode({'data': [], 'current_page': 1, 'last_page': 1}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'company': {'id': 1, 'name': 'Auto Servicios de QA'},
          'profile': {'commercial_name': 'Auto Servicios de QA'},
          'branding': {},
          'preferences': {},
        }),
        200,
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanySettingsPage(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin_hero_24n')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_sections_24n')), findsOneWidget);
    expect(find.text('Mi Empresa'), findsOneWidget);
    expect(find.text('Auto Servicios de QA'), findsWidgets);
    expect(find.text('Información general'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      expect(find.byKey(ValueKey('admin_tab_24n_$i')), findsOneWidget);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('admin_tab_24n_1')));
    await tester.tap(find.text('Contactos').first);
    await tester.pumpAndSettle();
    expect(find.text('Nuevo contacto'), findsOneWidget);
  });
}
