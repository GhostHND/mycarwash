import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_cash_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'test-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  for (final module in CashModule.values) {
    testWidgets('${module.name}: listado y formulario de nuevo registro', (
      tester,
    ) async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/cash/options')) {
          return http.Response(
            jsonEncode({
              'data': {
                'branches': [
                  {'id': 1, 'name': 'Principal'},
                ],
                'registers': [
                  {'id': 1, 'name': 'Caja principal', 'branch_id': 1},
                ],
                'sessions': [
                  {'id': 1, 'register_id': 1, 'opening_cash': '100.00'},
                ],
                'categories': [
                  {'id': 1, 'name': 'Mantenimiento'},
                ],
              },
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'data': <Map<String, dynamic>>[],
              'current_page': 1,
              'last_page': 1,
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response(
          jsonEncode({'message': 'Sin datos de prueba'}),
          422,
          headers: {'content-type': 'application/json'},
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanyCashPage(module: module, client: client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CompanyCashPage), findsOneWidget);
      expect(find.text('No hay registros.'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(find.textContaining('Guardar'), findsWidgets);
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      client.close();
    });
  }

  testWidgets('sesiones cerradas: detalle disponible, edición eliminada', (
    tester,
  ) async {
    final client = MockClient((request) async {
      if (request.method == 'GET') {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 7,
                'register_id': 1,
                'register_name': 'Principal',
                'status': 'CLOSED',
                'expected_current': '100.00',
                'opening_cash': '100.00',
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
        '{}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyCashPage(module: CashModule.sessions, client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('Consultar'), findsOneWidget);
    final buttons = tester.widgetList<IconButton>(find.byType(IconButton));
    expect(
      buttons.where((b) => b.tooltip == 'Editar').single.onPressed,
      isNull,
    );
    expect(
      buttons.where((b) => b.tooltip == 'Eliminar').single.onPressed,
      isNull,
    );
    client.close();
  });
}
