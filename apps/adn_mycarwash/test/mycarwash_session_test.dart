import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';

void main() {
  tearDown(MyCarWashSession.clear);

  test('La sesion inicia con empresa y token', () {
    MyCarWashSession.begin(
      accessToken: 'token-temporal-de-prueba',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );

    expect(MyCarWashSession.isAuthenticated, isTrue);
    expect(MyCarWashSession.companyId, 1);
    expect(
      MyCarWashSession.headers['Authorization'],
      'Bearer token-temporal-de-prueba',
    );
  });

  test('La sesion conserva la URL de la API', () {
    MyCarWashSession.begin(
      accessToken: 'token-de-prueba',
      companyId: 2,
      apiBaseUrl: 'http://192.168.1.10:8000/api/v1',
    );

    expect(MyCarWashSession.apiBaseUrl, 'http://192.168.1.10:8000/api/v1');
  });

  test('Cerrar sesion elimina los datos locales', () {
    MyCarWashSession.begin(
      accessToken: 'token-de-prueba',
      companyId: 1,
      apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
    );

    MyCarWashSession.clear();

    expect(MyCarWashSession.isAuthenticated, isFalse);
    expect(() => MyCarWashSession.companyId, throwsStateError);
    expect(() => MyCarWashSession.headers, throwsStateError);
  });

  test('Rechaza sesiones incompletas', () {
    expect(
      () => MyCarWashSession.begin(
        accessToken: '',
        companyId: 1,
        apiBaseUrl: 'http://127.0.0.1:8000/api/v1',
      ),
      throwsArgumentError,
    );
  });
}
