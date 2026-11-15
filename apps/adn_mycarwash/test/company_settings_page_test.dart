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
      accessToken: 'token-de-pruebas',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );
  });

  tearDown(MyCarWashSession.clear);

  testWidgets('Mi Empresa carga datos reales mediante la API', (tester) async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token-de-pruebas');

      return http.Response(
        jsonEncode({
          'company': {
            'id': 1,
            'name': 'CarWash de Pruebas',
            'slug': 'carwash-pruebas',
          },
          'profile': {'commercial_name': 'CarWash de Pruebas'},
          'branding': {'primary_color': '#0FA7B4'},
          'preferences': {},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

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

    expect(find.text('Mi Empresa'), findsOneWidget);
    expect(find.text('CarWash de Pruebas'), findsWidgets);
    expect(find.text('Información general'), findsOneWidget);

    client.close();
  });

  testWidgets('La pestaña Contactos consulta la API autenticada', (
    tester,
  ) async {
    var contactsRequested = false;

    final client = MockClient((request) async {
      if (request.url.path.endsWith('/contacts')) {
        contactsRequested = true;

        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 5,
                'type': 'phone',
                'value': '9851-8558',
                'contact_person': 'Contacto QA',
                'label': 'Principal',
                'department': 'Administración',
              },
            ],
            'current_page': 1,
            'last_page': 1,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }

      return http.Response(
        jsonEncode({
          'company': {'id': 1, 'name': 'CarWash de Pruebas'},
          'profile': {},
          'branding': {},
          'preferences': {},
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

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

    await tester.tap(find.text('Contactos'));
    await tester.pumpAndSettle();

    expect(contactsRequested, isTrue);
    expect(find.text('Contacto QA'), findsOneWidget);
    expect(find.textContaining('9851-8558'), findsOneWidget);

    client.close();
  });
}
