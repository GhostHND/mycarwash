import 'dart:convert';

import 'package:adn_mycarwash/core/company_visual_theme.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() => MyCarWashSession.begin(
    accessToken: 'qa-paleta',
    companyId: 41,
    apiBaseUrl: 'http://localhost:8000/api/v1',
  ));
  tearDown(() { MyCarWashSession.clear(); CompanyVisualTheme.reset(); });

  test('La paleta por defecto conserva 19 tonos oscuros y turquesa', () {
    expect(CompanyVisualTheme.defaults.length, 19);
    expect(CompanyVisualTheme.defaults['background_color'], '#050C0F');
    expect(CompanyVisualTheme.defaults['card_color'], '#071F23');
    expect(CompanyVisualTheme.defaults['primary_color'], '#00DCE5');
    CompanyVisualTheme.reset();
    expect(CompanyVisualTheme.background, const Color(0xFF050C0F));
    expect(CompanyVisualTheme.primary, const Color(0xFF00DCE5));
  });

  testWidgets('Restaurar colores guarda los 19 valores en la empresa actual', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final original = <String, dynamic>{
      ...CompanyVisualTheme.defaults,
      'background_color': '#FFFFFF',
      'card_color': '#FFFFFF',
      'text_color': '#FFFFFF',
      'visual_theme_version': 2,
    };
    var saved = false;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/companies/41/settings${request.method == 'PATCH' ? '/branding' : ''}');
      if (request.method == 'PATCH') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.length, 19);
        expect(body['background_color'], '#050C0F');
        expect(body['primary_color'], '#00DCE5');
        original.addAll(body);
        saved = true;
        return http.Response(jsonEncode({'branding': original}), 200);
      }
      return http.Response(jsonEncode({
        'company': {'id': 41, 'name': 'Empresa QA'},
        'profile': <String, dynamic>{},
        'branding': original,
        'preferences': <String, dynamic>{},
      }), 200);
    });
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SingleChildScrollView(
      child: CompanySettingsPage(client: client, configurationOnly: true),
    ))));
    await tester.pumpAndSettle();
    final tab = find.byKey(const ValueKey('admin_tab_24n_2'));
    await tester.ensureVisible(tab);
    await tester.tap(tab);
    await tester.pumpAndSettle();
    final reset = find.byKey(const ValueKey('admin_reset_palette_default'));
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('admin_confirm_default_palette')));
    await tester.pumpAndSettle();
    expect(saved, true);
    expect(CompanyVisualTheme.background, const Color(0xFF050C0F));
    expect(CompanyVisualTheme.card, const Color(0xFF071F23));
  });
}
