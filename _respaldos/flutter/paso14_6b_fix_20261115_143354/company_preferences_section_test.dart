import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_preferences_section.dart';
import 'package:adn_mycarwash/ui/company_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _defaults = <String, dynamic>{
  'locale': 'es-HN',
  'currency_code': 'HNL',
  'timezone': 'America/Tegucigalpa',
  'date_format': 'dd/MM/yyyy',
  'time_format': '24h',
  'default_theme': 'system',
  'invoice_paper_size': 'letter',
  'country_phone_code': '+504',
  'decimal_places': 2,
  'enable_sound_alerts': true,
  'receipt_footer': null,
};

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'preferences-qa-token',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  Widget app(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  testWidgets('Preferencias carga datos autenticados de su empresa', (
    tester,
  ) async {
    var reads = 0;
    final client = MockClient((request) async {
      expect(request.method, 'GET');
      expect(request.headers['Authorization'], 'Bearer preferences-qa-token');
      expect(request.url.path, '/api/v1/companies/1/settings/preferences');
      reads++;
      return http.Response(
        jsonEncode({
          'preferences': {..._defaults, 'receipt_footer': 'Gracias QA'},
        }),
        200,
      );
    });
    await tester.pumpWidget(app(CompanyPreferencesSection(client: client)));
    await tester.pumpAndSettle();
    expect(reads, 1);
    expect(find.text('Preferencias empresariales'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('preferences_currency')),
    );
    expect(field.controller!.text, 'HNL');
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('preferences_footer')),
          )
          .controller!
          .text,
      'Gracias QA',
    );
    client.close();
  });

  testWidgets('Preferencias guarda todos los campos mediante PATCH', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer preferences-qa-token');
      expect(request.url.path, '/api/v1/companies/1/settings/preferences');
      if (request.method == 'GET') {
        return http.Response(jsonEncode({'preferences': _defaults}), 200);
      }
      expect(request.method, 'PATCH');
      saved = Map<String, dynamic>.from(jsonDecode(request.body) as Map);
      return http.Response(
        jsonEncode({
          'message': 'Guardado',
          'preferences': {..._defaults, ...saved!},
        }),
        200,
      );
    });
    await tester.pumpWidget(app(CompanyPreferencesSection(client: client)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('preferences_currency')),
      'USD',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('preferences_footer')),
    );
    await tester.enterText(
      find.byKey(const ValueKey('preferences_footer')),
      'Gracias por preferirnos',
    );
    final button = find.byKey(const ValueKey('preferences_save'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(saved, isNotNull);
    expect(saved!['currency_code'], 'USD');
    expect(saved!['receipt_footer'], 'Gracias por preferirnos');
    expect(saved!['timezone'], 'America/Tegucigalpa');
    expect(saved!['enable_sound_alerts'], true);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey('preferences_currency')),
          )
          .controller!
          .text,
      'USD',
    );
    client.close();
  });

  testWidgets('Preferencias invalida no hace PATCH', (tester) async {
    var writes = 0;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        writes++;
      }
      return http.Response(jsonEncode({'preferences': _defaults}), 200);
    });
    await tester.pumpWidget(app(CompanyPreferencesSection(client: client)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('preferences_decimals')),
      '9',
    );
    final button = find.byKey(const ValueKey('preferences_save'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(find.text('Ingresa un entero entre 0 y 4.'), findsOneWidget);
    client.close();
  });

  testWidgets('Mi Empresa conserva siete pestanas y muestra Preferencias', (
    tester,
  ) async {
    var preferencesRequested = false;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer preferences-qa-token');
      if (request.url.path.endsWith('/settings/preferences')) {
        preferencesRequested = true;
        return http.Response(jsonEncode({'preferences': _defaults}), 200);
      }
      if (request.url.path.endsWith('/settings')) {
        return http.Response(
          jsonEncode({
            'company': {'id': 1, 'name': 'Empresa QA'},
            'profile': <String, dynamic>{},
            'branding': <String, dynamic>{},
            'preferences': <String, dynamic>{},
          }),
          200,
        );
      }
      throw StateError('Petición no esperada: ${request.url.path}');
    });
    await tester.pumpWidget(app(CompanySettingsPage(client: client)));
    await tester.pumpAndSettle();
    for (final tab in [
      'Información',
      'Contactos',
      'Identidad visual',
      'Datos fiscales',
      'Direcciones',
      'Horarios',
      'Redes sociales',
      'Preferencias',
    ]) {
      expect(find.text(tab), findsOneWidget);
    }
    final tab = find.text('Preferencias');
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    expect(preferencesRequested, isTrue);
    expect(find.text('Preferencias empresariales'), findsOneWidget);
    client.close();
  });

  testWidgets('Solo lectura: Laravel rechaza guardar con 403', (tester) async {
    var writes = 0;
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(jsonEncode({'preferences': _defaults}), 200);
      }
      writes++;
      return http.Response(jsonEncode({'message': 'Sin permiso'}), 403);
    });
    await tester.pumpWidget(app(CompanyPreferencesSection(client: client)));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('preferences_save'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(
      find.text('No tienes permiso para realizar esta operación.'),
      findsOneWidget,
    );
    client.close();
  });
}
