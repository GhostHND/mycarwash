import 'dart:convert';

import 'package:adn_mycarwash/core/business_identity.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    BusinessIdentity.reset();

    MyCarWashSession.begin(
      accessToken: 'token-pruebas',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );
  });

  tearDown(() {
    BusinessIdentity.reset();
    MyCarWashSession.clear();
  });

  test('ADN MyCarWash utiliza solo Inter', () {
    expect(BusinessIdentity.supportedFonts, ['Inter']);
    expect(BusinessIdentity.current.value.fontFamily, 'Inter');
  });

  test('No permite seleccionar fuentes diferentes', () {
    expect(() => BusinessIdentity.setFont('Montserrat'), throwsArgumentError);

    expect(BusinessIdentity.current.value.fontFamily, 'Inter');
  });

  test('Ignora fuentes alternativas en datos recuperados', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token-pruebas');

      return http.Response(
        jsonEncode({
          'company': {'id': 1, 'name': 'CarWash de Pruebas'},
          'profile': {'commercial_name': 'Autolavado QA'},
          'branding': {'font_family': 'Montserrat', 'business_logo_path': null},
        }),
        200,
      );
    });

    final result = await BusinessIdentity.refresh(client: client);

    expect(result, isTrue);
    expect(BusinessIdentity.current.value.fontFamily, 'Inter');
    expect(BusinessIdentity.current.value.companyName, 'Autolavado QA');

    client.close();
  });

  test('Cerrar sesion reinicia la identidad local', () {
    BusinessIdentity.reset();

    expect(BusinessIdentity.current.value.fontFamily, 'Inter');
    expect(BusinessIdentity.current.value.logoBytes, isNull);
  });
}
