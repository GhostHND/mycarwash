import 'package:adn_mycarwash/ui/receipt_print_preview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget demo({
  String paper = 'thermal_80mm',
  String business = 'Auto Lavado QA',
  String footer = 'Gracias QA',
  int decimals = 2,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ReceiptPrintPreview(
          paper: paper,
          businessName: business,
          currencyCode: 'HNL',
          decimalPlaces: decimals,
          dateFormat: 'dd/MM/yyyy',
          timeFormat: '24h',
          footer: footer,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'Recibo sin CAI no usa denominacion de factura ni detalla impuesto',
    (tester) async {
      await tester.pumpWidget(demo());
      expect(find.text('RECIBO SIN VALOR FISCAL'), findsOneWidget);
      expect(find.text('SIN CAI · NO ES FACTURA'), findsOneWidget);
      expect(find.textContaining('ISV 15'), findsNothing);
      expect(find.text('L 200.00'), findsWidgets);
      expect(find.text('Gracias QA'), findsOneWidget);
    },
  );

  testWidgets('Factura con CAI exige datos reales antes de emitir', (
    tester,
  ) async {
    await tester.pumpWidget(demo());
    await tester.tap(find.byKey(const ValueKey('receipt_preview_fiscal')));
    await tester.pumpAndSettle();
    expect(find.text('FACTURA FISCAL · VISTA PREVIA'), findsOneWidget);
    expect(find.text('CAI: [AUTORIZACIÓN PENDIENTE]'), findsOneWidget);
    expect(find.text('ISV 15 % incluido'), findsOneWidget);
    expect(find.text('L 200.00'), findsOneWidget);
  });

  testWidgets('Puede alternar entre ambos sin emitir comprobantes', (
    tester,
  ) async {
    await tester.pumpWidget(demo());
    await tester.tap(find.byKey(const ValueKey('receipt_preview_fiscal')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('receipt_preview_nonfiscal')));
    await tester.pumpAndSettle();
    expect(find.text('RECIBO SIN VALOR FISCAL'), findsOneWidget);
    expect(find.text('SIN CAI · NO ES FACTURA'), findsOneWidget);
  });

  testWidgets('Papel térmico 58 mm se muestra con ancho apropiado', (
    tester,
  ) async {
    await tester.pumpWidget(demo(paper: 'thermal_58mm', decimals: 0));
    expect(find.textContaining('Térmico 58 mm'), findsOneWidget);
    expect(find.text('L 200'), findsWidgets);
    final size = tester.getSize(
      find.byKey(const ValueKey('receipt_preview_paper')),
    );
    expect(size.width, lessThanOrEqualTo(220));
  });
}
