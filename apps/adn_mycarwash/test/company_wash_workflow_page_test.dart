import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_wash_workflow_page.dart';
import 'package:adn_mycarwash/ui/company_media_photo_dialog.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'token-test',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });

  tearDown(MyCarWashSession.clear);

  http.Client clientForTests() => MockClient((request) async {
    if (request.url.path.endsWith('/workflow/branches')) {
      return http.Response(
        jsonEncode({
          'data': [
            {'id': 1, 'name': 'Sucursal QA'},
          ],
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/media/vehicles/1')) {
      return http.Response(
        jsonEncode({
          'data': {'exists': false, 'show_on_kiosk': false, 'url': null},
        }),
        200,
      );
    }
    return http.Response(
      jsonEncode({'data': [], 'current_page': 1, 'last_page': 1}),
      200,
    );
  });

  testWidgets('Órdenes consulta API y muestra estado vacío', (tester) async {
    final client = clientForTests();
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyWashWorkflowPage(
              module: WashModule.orders,
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Órdenes de lavado'), findsOneWidget);
    expect(find.text('Sin registros para mostrar.'), findsOneWidget);
    expect(find.byKey(const ValueKey('workflow_create')), findsOneWidget);
  });

  testWidgets('Puestos abre formulario con sucursales', (tester) async {
    final client = clientForTests();
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyWashWorkflowPage(
              module: WashModule.bays,
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('workflow_create')));
    await tester.pumpAndSettle();
    expect(find.text('Nuevo registro · Puestos de lavado'), findsOneWidget);
    expect(find.text('Nombre del puesto'), findsOneWidget);
    expect(find.text('Sucursal'), findsOneWidget);
  });

  testWidgets('Cola muestra estado cuando no existen órdenes', (tester) async {
    final client = clientForTests();
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyWashWorkflowPage(
              module: WashModule.queue,
              client: client,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Cola operativa'), findsOneWidget);
    expect(find.text('Sin registros para mostrar.'), findsOneWidget);
  });

  testWidgets('Fotografía de vehículo inicia sin imagen', (tester) async {
    final client = clientForTests();
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => showDialog<void>(
                context: ctx,
                builder: (_) => CompanyMediaPhotoDialog(
                  client: client,
                  kind: 'vehicles',
                  recordId: 1,
                  title: 'Auto QA',
                ),
              ),
              child: const Text('Abrir foto'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Abrir foto'));
    await tester.pumpAndSettle();
    expect(find.text('Fotografía · Auto QA'), findsOneWidget);
    expect(find.text('Subir fotografía'), findsOneWidget);
    expect(find.text('Permitir foto en pantalla Raspberry'), findsOneWidget);
  });
}
