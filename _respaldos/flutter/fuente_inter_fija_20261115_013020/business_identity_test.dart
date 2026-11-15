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
      accessToken: 'token-test',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );
  });

  tearDown(() {
    BusinessIdentity.reset();
    MyCarWashSession.clear();
  });

  test('Permite seleccionar fuentes empresariales', () {
    BusinessIdentity.setFont('Montserrat');

    expect(BusinessIdentity.current.value.fontFamily, 'Montserrat');

    BusinessIdentity.setFont('Poppins');

    expect(BusinessIdentity.current.value.fontFamily, 'Poppins');
  });

  test('Impide configurar fuentes desconocidas', () {
    expect(
      () => BusinessIdentity.setFont('Fuente inexistente'),
      throwsArgumentError,
    );
  });

  test('Recupera tipografia y empresa desde Laravel', () async {
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer token-test');

      return http.Response(
        jsonEncode({
          'company': {'id': 1, 'name': 'CarWash de Pruebas'},
          'profile': {'commercial_name': 'Autolavado QA'},
          'branding': {'font_family': 'Poppins', 'business_logo_path': null},
        }),
        200,
      );
    });

    final ok = await BusinessIdentity.refresh(client: client);

    expect(ok, isTrue);
    expect(BusinessIdentity.current.value.fontFamily, 'Poppins');
    expect(BusinessIdentity.current.value.companyName, 'Autolavado QA');

    client.close();
  });

  test('El cierre de sesion limpia la identidad local', () {
    BusinessIdentity.setFont('Lato');

    BusinessIdentity.reset();

    expect(BusinessIdentity.current.value.fontFamily, 'Inter');
    expect(BusinessIdentity.current.value.logoBytes, isNull);
    expect(BusinessIdentity.current.value.companyName, isEmpty);
  });
}
