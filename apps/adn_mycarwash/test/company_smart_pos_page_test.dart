import 'dart:async';
import 'dart:convert';

import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_smart_pos_page.dart';
import 'package:adn_mycarwash/ui/company_pos_document_design.dart';
import 'package:adn_mycarwash/ui/company_pos_template_designer.dart';
import 'package:adn_mycarwash/core/company_business_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  setUp(() {
    MyCarWashSession.begin(
      accessToken: 'pos-test-token',
      companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1',
    );
  });
  tearDown(MyCarWashSession.clear);

  MockClient clientFor({
    required void Function(Map<String, dynamic>) onSale,
    bool openCash = true,
    http.Response? Function(Map<String, dynamic>)? overrideSaleResponse,
    Future<http.Response>? productsAfterSale,
    void Function(Map<String, dynamic>)? onDocumentDesign,
  }) {
    var saleAttempted = false;
    return MockClient((request) async {
      if (request.url.path.endsWith('/pos/options')) {
        return http.Response(
          jsonEncode({
            'data': {
              'branches': [
                {'id': 1, 'name': 'Principal'},
              ],
              'methods': [
                {'id': 1, 'name': 'Efectivo', 'channel': 'CASH'},
                {'id': 2, 'name': 'Transferencia', 'channel': 'BANK'},
              ],
              'sessions': openCash
                  ? [
                      {'id': 1, 'branch_id': 1, 'name': 'Caja'},
                    ]
                  : [],
              'banks': [
                {'id': 1, 'branch_id': 1, 'alias': 'Banco Demo'},
              ],
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/pos/products')) {
        if (saleAttempted && productsAfterSale != null) {
          return productsAfterSale;
        }
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 1,
                'sku': 'ARO-01',
                'name': 'Aromatizante',
                'unit': 'unidad',
                'sale_price': '150.00',
                'stock': '5.000',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/pos/customers')) {
        return http.Response(
          jsonEncode({
            'data': [
              {
                'id': 12,
                'full_name': 'Ana Compradora',
                'identity_document': '08011990',
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.url.path.endsWith('/pos/document-designs')) {
        if (request.method == 'POST') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          onDocumentDesign?.call(body);
          return http.Response(
            jsonEncode({
              'data': {'revision': 1, 'saved': true},
            }),
            201,
            headers: {'content-type': 'application/json'},
          );
        }
        final type = request.url.queryParameters['document_type'] ?? 'RECEIPT';
        return http.Response(
          jsonEncode({
            'data': {
              'document_type': type,
              'revision': 0,
              'saved': false,
              'design': CompanyPosDocumentDesign.defaults(type),
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      if (request.method == 'POST' && request.url.path.endsWith('/pos/sales')) {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        onSale(body);
        saleAttempted = true;
        final custom = overrideSaleResponse?.call(body);
        if (custom != null) {
          return custom;
        }
        return http.Response(
          jsonEncode({
            'data': {
              'id': 9,
              'status': 'POSTED',
              'posted_at': '2026-11-16 10:00:00',
              'subtotal': '150.00',
              'discount_amount': '0.00',
              'total': '150.00',
              'customer_name': body['customer_type'] == 'NEW'
                  ? 'Cliente Nuevo'
                  : 'Consumidor final',
              'cash_received': '200.00',
              'change_given': '50.00',
              'lines': [
                {
                  'name_snapshot': 'Aromatizante',
                  'quantity': '1.000',
                  'line_total': '150.00',
                },
              ],
              'payments': [
                {'channel': 'CASH', 'amount': '150.00'},
              ],
            },
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response(
        jsonEncode({'data': []}),
        200,
        headers: {'content-type': 'application/json'},
      );
    });
  }

  testWidgets('Editor de comprobantes publica configuraciones por sucursal', (
    tester,
  ) async {
    Map<String, dynamic>? saved;
    final client = clientFor(
      onSale: (_) {},
      onDocumentDesign: (body) => saved = body,
    );
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CompanyPosTemplateDesigner(
            api: CompanyBusinessApi(client),
            branchId: 1,
            embedded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Diseñador de comprobantes'), findsOneWidget);
    expect(find.text('Identidad de marca'), findsOneWidget);
    final field = find.byKey(const ValueKey('design_RECEIPT_0_brand_name'));
    await tester.ensureVisible(field);
    await tester.enterText(field, 'GUZA Autolavado');
    await tester.pumpAndSettle();
    final publish = find.widgetWithText(FilledButton, 'Publicar diseño');
    await tester.ensureVisible(publish);
    await tester.tap(publish);
    await tester.pumpAndSettle();
    expect(saved?['branch_id'], 1);
    expect(saved?['document_type'], 'RECEIPT');
    expect((saved?['design'] as Map)['brand_name'], 'GUZA Autolavado');
    expect(
      (saved?['design'] as Map)['sections'],
      CompanyPosDocumentDesign.sections,
    );
    expect((saved?['design'] as Map)['layout_style'], 'ticket');
  });

  testWidgets('Smart POS no muestra diseñador en escritorio ni móvil', (
    tester,
  ) async {
    final client = clientFor(onSale: (_) {});
    addTearDown(client.close);
    final page = MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(child: CompanySmartPosPage(client: client)),
      ),
    );
    await tester.pumpWidget(page);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pos_design_document')), findsNothing);
    expect(find.text('Diseñar comprobantes'), findsNothing);

    // Repite la validación en el diseño estrecho, que antes conservaba
    // una llamada a _openDesigner eliminada al mover el módulo al menú.
    tester.view.physicalSize = const Size(550, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pos_design_document')), findsNothing);
    expect(find.text('Diseñar recibo y factura'), findsNothing);
  });

  testWidgets('Selector muestra factura e impide cobrar si falta CAI', (
    tester,
  ) async {
    final client = clientFor(onSale: (_) {});
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanySmartPosPage(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar al carrito'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Factura'));
    await tester.tap(find.text('Factura'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ISV (15%): L 22.50'), findsOneWidget);
    expect(find.textContaining('Total: L 172.50'), findsOneWidget);
    expect(find.textContaining('Factura bloqueada:'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continuar al cobro'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'Continuar al cobro abre la ventana y confirma consumidor final',
    (tester) async {
      Map<String, dynamic>? posted;
      final client = clientFor(onSale: (body) => posted = body);
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanySmartPosPage(client: client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Aromatizante'), findsOneWidget);
      await tester.tap(find.byTooltip('Agregar al carrito'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Subtotal: L 150.00'), findsOneWidget);
      await tester.ensureVisible(find.byKey(const ValueKey('pos_checkout')));
      await tester.tap(find.byKey(const ValueKey('pos_checkout')));
      await tester.pumpAndSettle();
      expect(find.text('Finalizar venta'), findsOneWidget);
      expect(find.text('Consumidor final'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pos_confirm_payment')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Venta #9 confirmada'), findsOneWidget);
      expect(find.byKey(const ValueKey('pos_print_receipt')), findsOneWidget);
      await tester.tap(find.text('No, finalizar'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pos_print_receipt')), findsNothing);
      expect(posted?['customer_type'], 'CONSUMER');
      expect(posted?['document_type'], 'RECEIPT');
      expect((posted?['payments'] as List).first['amount'], '150.00');
    },
  );

  testWidgets('El alta rápida de cliente viaja dentro de la venta', (
    tester,
  ) async {
    Map<String, dynamic>? posted;
    final client = clientFor(onSale: (body) => posted = body);
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanySmartPosPage(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar al carrito'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pos_checkout')));
    await tester.tap(find.byKey(const ValueKey('pos_checkout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente nuevo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pos_customer_name')));
    await tester.enterText(
      find.byKey(const ValueKey('pos_customer_name')),
      'Cliente Nuevo',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('pos_confirm_payment')),
    );
    await tester.tap(find.byKey(const ValueKey('pos_confirm_payment')));
    await tester.pumpAndSettle();
    expect(posted?['customer_type'], 'NEW');
    expect((posted?['customer'] as Map)['full_name'], 'Cliente Nuevo');
    expect(find.textContaining('Venta #9 confirmada'), findsOneWidget);
  });

  testWidgets(
    'Error HTTP de cobro es visible junto al botón y mantiene clave segura',
    (tester) async {
      final requests = <Map<String, dynamic>>[];
      final client = clientFor(
        onSale: requests.add,
        overrideSaleResponse: (_) => http.Response(
          jsonEncode({
            'message': 'Caja cerrada en la sucursal',
            'errors': {
              'cash_session_id': ['La caja debe estar abierta.'],
            },
          }),
          422,
          headers: {'content-type': 'application/json'},
        ),
      );
      addTearDown(client.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CompanySmartPosPage(client: client),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Agregar al carrito'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('pos_checkout')));
      await tester.tap(find.byKey(const ValueKey('pos_checkout')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pos_confirm_payment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pos_payment_error')), findsOneWidget);
      expect(find.text('Finalizar venta'), findsOneWidget);
      expect(requests.length, 1);
      final firstKey = requests.single['idempotency_key'];
      await tester.tap(find.byKey(const ValueKey('pos_confirm_payment')));
      await tester.pumpAndSettle();
      expect(requests.length, 2);
      expect(requests.last['idempotency_key'], firstKey);
    },
  );

  testWidgets('El comprobante se muestra sin esperar la recarga del catálogo', (
    tester,
  ) async {
    final gate = Completer<http.Response>();
    addTearDown(() {
      if (!gate.isCompleted) {
        gate.complete(
          http.Response(
            jsonEncode({'data': []}),
            200,
            headers: {'content-type': 'application/json'},
          ),
        );
      }
    });
    final client = clientFor(onSale: (_) {}, productsAfterSale: gate.future);
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanySmartPosPage(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar al carrito'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pos_checkout')));
    await tester.tap(find.byKey(const ValueKey('pos_checkout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pos_confirm_payment')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Venta #9 confirmada'), findsOneWidget);
    expect(gate.isCompleted, isFalse);
  });

  testWidgets('Si no hay caja abierta muestra error permanente y no cobra', (
    tester,
  ) async {
    var calls = 0;
    final client = clientFor(openCash: false, onSale: (_) => calls++);
    addTearDown(client.close);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanySmartPosPage(client: client),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Agregar al carrito'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('pos_checkout')));
    await tester.tap(find.byKey(const ValueKey('pos_checkout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('pos_confirm_payment')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pos_payment_error')), findsOneWidget);
    expect(calls, 0);
  });
}
