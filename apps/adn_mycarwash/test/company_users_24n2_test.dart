import 'dart:convert';

import 'package:adn_mycarwash/core/company_visual_theme.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_settings_page.dart';
import 'package:adn_mycarwash/ui/company_users_24n2_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => MyCarWashSession.begin(
    accessToken: 'test-24n2',
    companyId: 11,
    apiBaseUrl: 'http://localhost:8000/api/v1',
    permissions: ['nav.users.view', 'nav.company.view'],
    legacyFullAccess: false,
  ));
  tearDown(() { MyCarWashSession.clear(); CompanyVisualTheme.reset(); });

  test('El tema conserva valores HEX y protege defaults heredados', () {
    CompanyVisualTheme.load({
      'background_color': '#112233', 'card_color': '#ABCDEF',
      'text_color': '#FFFFFF', 'visual_theme_version': 2,
    });
    expect(CompanyVisualTheme.background, const Color(0xFF112233));
    expect(CompanyVisualTheme.card, const Color(0xFFABCDEF));
    expect(CompanyVisualTheme.text, Colors.white);
    CompanyVisualTheme.load({
      'background_color': '#FFFFFF', 'surface_color': '#F5F7F8',
      'text_color': '#1D1D1B', 'visual_theme_version': 0,
    });
    expect(CompanyVisualTheme.background, const Color(0xFF050C0F));
  });

  testWidgets('Mi empresa contiene seis secciones y Configuracion contiene dos', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final client = MockClient((req) async => http.Response(jsonEncode({
      'company': {'id': 11, 'name': 'Carwash QA'},
      'profile': {}, 'branding': {}, 'preferences': {},
    }), 200));
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CompanySettingsPage(client: client),
    ))));
    await tester.pumpAndSettle();
    for (final index in [0,1,3,4,5,6]) {
      expect(find.byKey(ValueKey('admin_tab_24n_$index')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('admin_tab_24n_2')), findsNothing);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CompanySettingsPage(client: client, configurationOnly: true),
    ))));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('admin_tab_24n_2')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_tab_24n_7')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_tab_24n_0')), findsNothing);
  });

  testWidgets('Usuarios muestra cuentas y roles obtenidos por API autenticada', (tester) async {
    final client = MockClient((req) async {
      expect(req.headers['Authorization'], 'Bearer test-24n2');
      expect(req.url.path, '/api/v1/companies/11/users');
      return http.Response(jsonEncode({
        'users': [
          {'id': 99, 'name': 'María Pruebas', 'email': 'maria@example.test',
           'status': 'active', 'employee_id': 5, 'employee_name': 'María Pruebas',
           'role_ids': [7]},
        ],
        'roles': [
          {'id': 7, 'name': 'Lavador', 'code': 'custom_1',
           'is_system': false, 'permissions': ['nav.washes.view']},
        ],
        'available_employees': [],
        'permissions': [
          {'id': 1, 'code': 'nav.washes.view', 'description': 'Ver lavados'},
        ],
        'can_manage_users': true, 'can_manage_roles': true,
      }), 200, headers: {'content-type': 'application/json'});
    });
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CompanyUsers24N2Page(client: client),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('María Pruebas'), findsWidgets);
    expect(find.text('Rol: Lavador'), findsOneWidget);
    await tester.tap(find.text('Roles y permisos'));
    await tester.pumpAndSettle();
    expect(find.text('Editar permisos'), findsOneWidget);
  });
}
