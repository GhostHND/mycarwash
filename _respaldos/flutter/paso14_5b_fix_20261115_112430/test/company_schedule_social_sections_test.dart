import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_schedule_section.dart';
import 'package:adn_mycarwash/ui/company_settings_page.dart';
import 'package:adn_mycarwash/ui/company_social_links_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'test-token',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  Widget wrapper(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  Map<String, dynamic> page(List<Map<String, dynamic>> rows) => {
    'data': rows,
    'current_page': 1,
    'last_page': 1,
  };

  testWidgets('Horario semanal se consulta y guarda con 7 dias', (
    tester,
  ) async {
    var loaded = false;
    var saved = false;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.url.path.endsWith('/settings/hours')) {
        if (request.method == 'GET') {
          loaded = true;
          return http.Response(jsonEncode({'days': []}), 200);
        }
        expect(request.method, 'PATCH');
        final payload = jsonDecode(request.body) as Map<String, dynamic>;
        final days = payload['days'] as List;
        expect(days.length, 7);
        expect(days.first['day_of_week'], 0);
        expect(days.last['day_of_week'], 6);
        expect(days.every((element) => element['is_closed'] == true), isTrue);
        saved = true;
        return http.Response(jsonEncode({'days': days}), 200);
      }
      if (request.url.path.endsWith('/special-hours')) {
        return http.Response(jsonEncode(page([])), 200);
      }
      throw StateError('Solicitud inesperada: ${request.url}');
    });

    await tester.pumpWidget(wrapper(CompanyScheduleSection(client: client)));
    await tester.pumpAndSettle();
    expect(loaded, isTrue);
    expect(find.text('Horario semanal'), findsOneWidget);
    final button = find.byKey(const ValueKey('weekly_save'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    client.close();
  });

  testWidgets('Fechas especiales crea un cierre por fecha', (tester) async {
    var created = false;
    final rows = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.url.path.endsWith('/settings/hours')) {
        return http.Response(jsonEncode({'days': []}), 200);
      }
      if (request.url.path.endsWith('/special-hours')) {
        if (request.method == 'GET')
          return http.Response(jsonEncode(page(rows)), 200);
        expect(request.method, 'POST');
        final data = jsonDecode(request.body) as Map<String, dynamic>;
        expect(data['special_date'], '2027-01-06');
        expect(data['is_closed'], isTrue);
        created = true;
        rows.add({...data, 'id': 9});
        return http.Response(jsonEncode({'special': rows.first}), 201);
      }
      throw StateError('Solicitud inesperada: ${request.url}');
    });

    await tester.pumpWidget(wrapper(CompanyScheduleSection(client: client)));
    await tester.pumpAndSettle();
    final newButton = find.text('Nueva fecha especial');
    await tester.ensureVisible(newButton);
    await tester.tap(newButton);
    await tester.pumpAndSettle();
    final date = find.byKey(const ValueKey('special_date'));
    await tester.enterText(date, '2027-01-06');
    await tester.ensureVisible(find.byKey(const ValueKey('special_save')));
    await tester.tap(find.byKey(const ValueKey('special_save')));
    await tester.pumpAndSettle();
    expect(created, isTrue);
    expect(find.textContaining('2027-01-06'), findsWidgets);
    client.close();
  });

  testWidgets('Redes sociales consulta y crea perfiles', (tester) async {
    var created = false;
    final rows = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      expect(request.url.path, '/api/v1/companies/1/social-links');
      if (request.method == 'GET')
        return http.Response(jsonEncode(page(rows)), 200);
      expect(request.method, 'POST');
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      expect(data['platform'], 'instagram');
      expect(data['url'], 'https://instagram.com/qa');
      created = true;
      rows.add({...data, 'id': 11});
      return http.Response(jsonEncode({'social': rows.first}), 201);
    });

    await tester.pumpWidget(wrapper(CompanySocialLinksSection(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron redes sociales.'), findsOneWidget);
    await tester.tap(find.text('Nueva red social'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('social_platform')),
      'instagram',
    );
    await tester.enterText(
      find.byKey(const ValueKey('social_url')),
      'https://instagram.com/qa',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('social_save')));
    await tester.tap(find.byKey(const ValueKey('social_save')));
    await tester.pumpAndSettle();
    expect(created, isTrue);
    expect(find.textContaining('instagram'), findsWidgets);
    client.close();
  });

  testWidgets('Mi Empresa conserva cinco pestanas y suma dos', (tester) async {
    var gotWeek = false;
    var gotSpecial = false;
    var gotSocial = false;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.url.path.endsWith('/settings/hours')) {
        gotWeek = true;
        return http.Response(jsonEncode({'days': []}), 200);
      }
      if (request.url.path.endsWith('/special-hours')) {
        gotSpecial = true;
        return http.Response(jsonEncode(page([])), 200);
      }
      if (request.url.path.endsWith('/social-links')) {
        gotSocial = true;
        return http.Response(jsonEncode(page([])), 200);
      }
      if (request.url.path.endsWith('/settings')) {
        return http.Response(
          jsonEncode({
            'company': {'id': 1, 'name': 'Negocio QA'},
            'profile': {},
            'branding': {},
            'preferences': {},
          }),
          200,
        );
      }
      throw StateError('Solicitud inesperada: ${request.url}');
    });

    await tester.pumpWidget(wrapper(CompanySettingsPage(client: client)));
    await tester.pumpAndSettle();
    for (final name in [
      'Información',
      'Contactos',
      'Identidad visual',
      'Datos fiscales',
      'Direcciones',
      'Horarios',
    ]) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.tap(find.text('Horarios'));
    await tester.pumpAndSettle();
    expect(gotWeek, isTrue);
    expect(gotSpecial, isTrue);
    // El encabezado del módulo y la pestaña comparten el mismo nombre.
    await tester.tap(find.text('Redes sociales').first);
    await tester.pumpAndSettle();
    expect(gotSocial, isTrue);
    client.close();
  });
}
