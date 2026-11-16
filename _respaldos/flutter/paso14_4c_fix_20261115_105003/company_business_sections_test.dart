import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_addresses_section.dart';
import 'package:adn_mycarwash/ui/company_fiscal_section.dart';
import 'package:adn_mycarwash/ui/company_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'token-de-pruebas',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );
  });

  tearDown(MyCarWashSession.clear);

  Widget wrapper(Widget content) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: content)),
  );

  testWidgets('Datos fiscales consulta y guarda con sesion', (tester) async {
    bool got = false;
    bool saved = false;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token-de-pruebas');
      expect(request.url.path, '/api/v1/companies/1/settings/fiscal');
      if (request.method == 'GET') {
        got = true;
        return http.Response(
          jsonEncode({
            'fiscal': {
              'legal_name': 'CarWash Demo S.A.',
              'tax_id': '00000000000000',
              'is_tax_exempt': 0,
            },
          }),
          200,
        );
      }
      expect(request.method, 'PATCH');
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      expect(data['legal_name'], 'CarWash QA S.A.');
      saved = true;
      return http.Response(jsonEncode({'fiscal': data}), 200);
    });

    await tester.pumpWidget(wrapper(CompanyFiscalSection(client: client)));
    await tester.pumpAndSettle();
    expect(got, isTrue);

    final field = find.byKey(const ValueKey('fiscal_legal_name'));
    await tester.enterText(field, 'CarWash QA S.A.');
    final button = find.text('Guardar datos fiscales');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(saved, isTrue);
    client.close();
  });

  testWidgets('Direcciones lista y crea registros con sesion', (tester) async {
    bool created = false;
    final rows = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token-de-pruebas');
      expect(request.url.path, '/api/v1/companies/1/addresses');
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({'data': rows, 'current_page': 1, 'last_page': 1}),
          200,
        );
      }
      expect(request.method, 'POST');
      final data = jsonDecode(request.body) as Map<String, dynamic>;
      expect(data['full_address'], 'Dirección QA Flutter');
      created = true;
      rows.add({...data, 'id': 15, 'is_primary': true});
      return http.Response(
        jsonEncode({'message': 'Creada', 'address': rows.first}),
        201,
      );
    });

    await tester.pumpWidget(wrapper(CompanyAddressesSection(client: client)));
    await tester.pumpAndSettle();
    expect(find.text('No se encontraron direcciones.'), findsOneWidget);
    await tester.tap(find.text('Nueva dirección'));
    await tester.pumpAndSettle();
    final addressField = find.byKey(const ValueKey('address_full_address'));
    await tester.ensureVisible(addressField);
    await tester.enterText(addressField, 'Dirección QA Flutter');
    await tester.tap(find.text('Guardar dirección'));
    await tester.pumpAndSettle();
    expect(created, isTrue);
    expect(find.text('Dirección QA Flutter'), findsOneWidget);
    client.close();
  });

  testWidgets('Mi Empresa conserva las tres pestañas originales y suma dos', (
    tester,
  ) async {
    bool requestedFiscal = false;
    bool requestedAddresses = false;
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/settings/fiscal')) {
        requestedFiscal = true;
        return http.Response(jsonEncode({'fiscal': null}), 200);
      }
      if (request.url.path.endsWith('/addresses')) {
        requestedAddresses = true;
        return http.Response(
          jsonEncode({'data': [], 'current_page': 1, 'last_page': 1}),
          200,
        );
      }
      return http.Response(
        jsonEncode({
          'company': {'id': 1, 'name': 'CarWash QA'},
          'profile': {},
          'branding': {},
          'preferences': {},
        }),
        200,
      );
    });
    await tester.pumpWidget(wrapper(CompanySettingsPage(client: client)));
    await tester.pumpAndSettle();
    for (final title in [
      'Información',
      'Contactos',
      'Identidad visual',
      'Datos fiscales',
      'Direcciones',
    ]) {
      expect(find.text(title), findsWidgets);
    }
    await tester.tap(find.text('Datos fiscales').first);
    await tester.pumpAndSettle();
    expect(requestedFiscal, isTrue);
    await tester.tap(find.text('Direcciones').first);
    await tester.pumpAndSettle();
    expect(requestedAddresses, isTrue);
    client.close();
  });
}
