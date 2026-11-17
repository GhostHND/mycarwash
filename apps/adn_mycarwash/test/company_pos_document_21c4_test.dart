import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/company_pos_document_design.dart';
import 'package:adn_mycarwash/ui/company_pos_printing.dart';

void main() {
  test('21C.4: QR acepta enlaces http(s) y rechaza esquemas inseguros', () {
    expect(
      CompanyPosDocumentDesign.isValidQrLink('https://wa.me/50499990000'),
      isTrue,
    );
    expect(
      CompanyPosDocumentDesign.isValidQrLink('https://miempresa.hn/'),
      isTrue,
    );
    expect(
      CompanyPosDocumentDesign.isValidQrLink('javascript:alert(1)'),
      isFalse,
    );
    expect(
      CompanyPosDocumentDesign.isValidQrLink('file:///etc/passwd'),
      isFalse,
    );
    expect(
      CompanyPosDocumentDesign.isValidQrLink(
        'https://usuario:clave@ejemplo.com',
      ),
      isFalse,
    );
    expect(
      CompanyPosDocumentDesign.isValidQrLink('una dirección suelta'),
      isFalse,
    );
  });

  test('21C.4: el editor nuevo conserva marcador y sección QR', () {
    final design = CompanyPosDocumentDesign.defaults('RECEIPT');
    expect(design['renderer_version'], 4);
    expect((design['sections'] as List).contains('qr'), isTrue);
    expect(CompanyPosDocumentDesign.optionalSections.contains('qr'), isTrue);
    final previous = Map<String, dynamic>.from(design)
      ..remove('renderer_version')
      ..remove('qr_enabled');
    expect(
      CompanyPosDocumentDesign.resolve('RECEIPT', previous)['renderer_version'],
      3,
    );
  });

  test(
    '21C.4: el PDF térmico con QR se genera desde los datos de prueba',
    () async {
      final design = CompanyPosDocumentDesign.defaults('RECEIPT');
      design['paper'] = '80MM';
      design['qr_enabled'] = true;
      design['qr_url'] = 'https://wa.me/50499990000';
      design['qr_title'] = 'Escríbenos';
      design['qr_caption'] = 'Gracias por preferirnos';
      final demo = CompanyPosPrinting.demoSale('RECEIPT', design);
      final pdf = await CompanyPosPrinting.buildPdf(demo, demo: true);
      expect(ascii.decode(pdf.sublist(0, 4)), '%PDF');
      expect(pdf.length, greaterThan(500));
    },
  );

  test('21C.4: las plantillas A4 generan PDF con diseño empresarial', () async {
    final design = CompanyPosDocumentDesign.defaults('FISCAL_INVOICE');
    design['paper'] = 'A4';
    design['primary_color'] = '#0FA7B4';
    final demo = CompanyPosPrinting.demoSale('FISCAL_INVOICE', design);
    final pdf = await CompanyPosPrinting.buildPdf(demo, demo: true);
    expect(ascii.decode(pdf.sublist(0, 4)), '%PDF');
    expect(pdf.length, greaterThan(500));
  });
}
