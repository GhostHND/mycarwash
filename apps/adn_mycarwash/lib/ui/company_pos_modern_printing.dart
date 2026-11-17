import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_pos_document_design.dart';

/// Motor 21C.4. Un único PDF para vista previa, impresión y reimpresión.
/// No determina impuestos, CAI ni totales: siempre usa el snapshot de la venta.
class CompanyPosModernPrinting {
  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
      : <Map<String, dynamic>>[];

  static String _s(
    Map<String, dynamic> map,
    String key, [
    String fallback = '',
  ]) => '${map[key] ?? fallback}';
  static pw.Font _font(String value) => switch (value) {
    'times' => pw.Font.times(),
    'courier' => pw.Font.courier(),
    _ => pw.Font.helvetica(),
  };
  static PdfColor _color(Object? raw, String fallback) {
    final value = '$raw';
    return PdfColor.fromHex(
      RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value) ? value : fallback,
    );
  }

  static pw.Widget _logo(Map<String, dynamic> d, bool thermal) {
    try {
      final bytes = base64Decode('${d['logo_base64'] ?? ''}');
      if (bytes.isEmpty || bytes.length > 1048576) return pw.SizedBox();
      final maxMm = thermal ? 48.0 : 65.0;
      final width = math.min(
        maxMm,
        ((d['logo_width_mm'] as num?) ?? 32).toDouble(),
      );
      return pw.Image(
        pw.MemoryImage(bytes),
        width: width * PdfPageFormat.mm,
        height: math.min(28.0, width * .72) * PdfPageFormat.mm,
        fit: pw.BoxFit.contain,
      );
    } catch (_) {
      return pw.SizedBox();
    }
  }

  static pw.Widget _qr(
    Map<String, dynamic> d,
    bool thermal,
    pw.TextStyle style,
  ) {
    final enabled = d['qr_enabled'] == true;
    final url = '${d['qr_url'] ?? ''}'.trim();
    if (!thermal || !enabled || !CompanyPosDocumentDesign.isValidQrLink(url)) {
      return pw.SizedBox();
    }
    final title = '${d['qr_title'] ?? ''}';
    final caption = '${d['qr_caption'] ?? ''}';
    final width =
        ((d['qr_size_mm'] as num?) ?? 28)
            .toDouble()
            .clamp(18.0, 48.0)
            .toDouble() *
        PdfPageFormat.mm;
    final align = switch ('${d['qr_alignment']}') {
      'left' => pw.MainAxisAlignment.start,
      'right' => pw.MainAxisAlignment.end,
      _ => pw.MainAxisAlignment.center,
    };
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (title.trim().isNotEmpty)
            pw.Text(
              title,
              textAlign: pw.TextAlign.center,
              style: style.copyWith(fontWeight: pw.FontWeight.bold),
            ),
          pw.SizedBox(height: 5),
          pw.Row(
            mainAxisAlignment: align,
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: url,
                drawText: false,
                width: width,
                height: width,
                color: PdfColors.black,
                backgroundColor: PdfColors.white,
              ),
            ],
          ),
          if (caption.trim().isNotEmpty) ...[
            pw.SizedBox(height: 4),
            pw.Text(caption, style: style, textAlign: pw.TextAlign.center),
          ],
        ],
      ),
    );
  }

  static Future<Uint8List> buildPdf(
    Map<String, dynamic> sale, {
    bool demo = false,
  }) async {
    final invoice = sale['document_type'] == 'FISCAL_INVOICE';
    final type = invoice ? 'FISCAL_INVOICE' : 'RECEIPT';
    final d = CompanyPosDocumentDesign.resolve(type, sale['document_design']);
    final paper = '${d['paper']}';
    final thermal = paper == '58MM' || paper == '80MM';
    final mm = PdfPageFormat.mm;
    final primary = thermal
        ? PdfColors.black
        : _color(d['primary_color'], '#0FA7B4');
    final secondary = thermal
        ? PdfColors.black
        : _color(d['secondary_color'], '#142D3B');
    final border = thermal
        ? PdfColors.black
        : _color(d['border_color'], '#DAE2E8');
    final ink = thermal ? PdfColors.black : _color(d['text_color'], '#202B30');
    final soft = thermal
        ? PdfColors.white
        : _color(d['background_color'], '#FFFFFF');
    final font = _font('${d['font_family']}');
    final size = ((d['font_size'] as num?) ?? 10).toDouble();
    final heading = ((d['heading_size'] as num?) ?? 17).toDouble();
    final regular = pw.TextStyle(font: font, fontSize: size, color: ink);
    final small = regular.copyWith(fontSize: math.max(size - 1, 7));
    final strong = regular.copyWith(fontWeight: pw.FontWeight.bold);
    final standout = regular.copyWith(
      fontSize: heading,
      fontWeight: pw.FontWeight.bold,
      color: primary,
    );
    final sections = List<String>.from(d['sections'] as List);
    final hidden = List<String>.from(d['hidden_sections'] as List);
    final brand = '${d['brand_name'] ?? ''}'.trim().isNotEmpty
        ? '${d['brand_name']}'
        : _s(sale, 'company_name', _s(sale, 'fiscal_legal_name', 'Mi negocio'));
    final demonstration =
        demo ||
        (invoice &&
            (_s(sale, 'fiscal_cai') ==
                    'AAAAAA-BBBBBB-CCCCCC-DDDDDD-EEEEEE-00' ||
                _s(sale, 'fiscal_rtn') == '00000000000000'));
    final margin = thermal
        ? 2.5
        : ((d['page_margin_mm'] as num?) ?? 14).toDouble();
    final format = switch (paper) {
      'A4' => PdfPageFormat.a4,
      'LETTER' => PdfPageFormat.letter,
      _ => PdfPageFormat(
        (paper == '58MM' ? 58 : 80) * mm,
        math.max(
              175.0,
              175.0 +
                  _rows(sale['lines']).length * 12.0 +
                  _rows(sale['payments']).length * 7.0 +
                  (d['qr_enabled'] == true ? 75.0 : 0.0),
            ) *
            mm,
      ),
    };

    pw.Widget txt(String value, {pw.TextStyle? style, pw.TextAlign? align}) =>
        pw.Text(value, style: style ?? regular, textAlign: align);
    pw.Widget rule() => d['show_separators'] == true
        ? pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Divider(color: border, thickness: thermal ? .65 : .8),
          )
        : pw.SizedBox(height: 7);
    pw.Widget headingBar(String value) => thermal
        ? txt(value, style: strong, align: pw.TextAlign.center)
        : pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            color: secondary,
            child: txt(
              value.toUpperCase(),
              style: strong.copyWith(color: PdfColors.white),
            ),
          );
    pw.Widget detail(String name, String value, {bool bold = false}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 2),
          child: pw.Row(
            children: [
              pw.Expanded(child: txt(name, style: bold ? strong : regular)),
              txt(value, style: bold ? strong : regular),
            ],
          ),
        );
    pw.Widget panel(String label, List<pw.Widget> contents) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [headingBar(label), pw.SizedBox(height: 5), ...contents],
    );

    final issuer = <pw.Widget>[
      txt(brand, style: standout),
      if ('${d['subtitle'] ?? ''}'.trim().isNotEmpty)
        txt('${d['subtitle']}', style: small),
      if (invoice) ...[
        pw.SizedBox(height: 4),
        txt('Razón social: ${_s(sale, 'fiscal_legal_name')}', style: small),
        txt('RTN: ${_s(sale, 'fiscal_rtn')}', style: small),
      ],
    ];
    final document = <pw.Widget>[
      txt(
        invoice ? 'FACTURA' : 'RECIBO NO FISCAL',
        style: strong.copyWith(fontSize: heading * .88, color: secondary),
        align: pw.TextAlign.right,
      ),
      txt(
        invoice
            ? 'N.º ${_s(sale, 'fiscal_number')}'
            : 'Venta N.º ${_s(sale, 'id')}',
        style: strong,
        align: pw.TextAlign.right,
      ),
      txt(
        'Fecha: ${_s(sale, 'posted_at')}',
        style: small,
        align: pw.TextAlign.right,
      ),
      if (demonstration)
        txt(
          'PRUEBA / SIN VALIDEZ FISCAL',
          style: small.copyWith(color: PdfColors.red),
          align: pw.TextAlign.right,
        ),
    ];

    // Documento empresarial: encabezado lateral, receptor, detalle tabular,
    // base imponible / impuesto y bloque de pagos. Se conserva edición modular
    // de los bloques de contenido y variantes para alineación/colores/márgenes.
    final blocks = <pw.Widget>[];
    if (!thermal) {
      final logo = _logo(d, false);
      final headerPosition = '${d['header_layout']}';
      final centered = headerPosition == 'logo_center';
      final logoRight = headerPosition == 'logo_right';
      final left = pw.Column(
        crossAxisAlignment: centered
            ? pw.CrossAxisAlignment.center
            : pw.CrossAxisAlignment.start,
        children: [if (!logoRight && !hidden.contains('logo')) logo, ...issuer],
      );
      final right = pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.end,
        children: [
          if (logoRight && !hidden.contains('logo')) logo,
          ...document,
        ],
      );
      blocks.add(
        pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 12),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: primary, width: 2.5),
            ),
          ),
          child: centered
              ? pw.Column(
                  children: [
                    if (!hidden.contains('logo')) logo,
                    ...issuer,
                    pw.SizedBox(height: 9),
                    ...document,
                  ],
                )
              : pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Expanded(flex: 6, child: left),
                    pw.SizedBox(width: 12),
                    pw.Expanded(flex: 4, child: right),
                  ],
                ),
        ),
      );
      if (invoice) {
        blocks.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 10),
            child: pw.Container(
              padding: const pw.EdgeInsets.all(9),
              color: soft,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  txt('CAI: ${_s(sale, 'fiscal_cai')}', style: strong),
                  txt(
                    'Rango autorizado: ${_s(sale, 'fiscal_range_start')} a ${_s(sale, 'fiscal_range_end')}',
                    style: small,
                  ),
                  txt(
                    'Fecha límite: ${_s(sale, 'fiscal_expires_on')}',
                    style: small,
                  ),
                ],
              ),
            ),
          ),
        );
      }
      blocks.add(pw.SizedBox(height: 16));
    } else {
      if (!hidden.contains('logo')) {
        blocks.add(pw.Center(child: _logo(d, true)));
      }
      if (!hidden.contains('brand')) {
        blocks.add(
          pw.Center(
            child: txt(brand, style: standout, align: pw.TextAlign.center),
          ),
        );
      }
      blocks.add(
        pw.Center(
          child: txt(
            invoice ? 'FACTURA' : 'RECIBO NO FISCAL',
            style: strong.copyWith(fontSize: math.max(heading - 2, size + 2)),
            align: pw.TextAlign.center,
          ),
        ),
      );
      blocks.add(
        pw.Center(
          child: txt(
            'Venta #${_s(sale, 'id')} · ${_s(sale, 'posted_at')}',
            style: small,
            align: pw.TextAlign.center,
          ),
        ),
      );
      if (invoice) {
        blocks.add(rule());
        blocks.add(
          txt('Emisor: ${_s(sale, 'fiscal_legal_name')}', style: small),
        );
        blocks.add(txt('RTN: ${_s(sale, 'fiscal_rtn')}', style: small));
        blocks.add(txt('Factura: ${_s(sale, 'fiscal_number')}', style: small));
        blocks.add(txt('CAI: ${_s(sale, 'fiscal_cai')}', style: small));
        blocks.add(
          txt(
            'Rango: ${_s(sale, 'fiscal_range_start')} a ${_s(sale, 'fiscal_range_end')}',
            style: small,
          ),
        );
        blocks.add(
          txt('Fecha límite: ${_s(sale, 'fiscal_expires_on')}', style: small),
        );
      }
      if (demonstration) {
        blocks.add(
          txt(
            'PRUEBA SIN VALIDEZ FISCAL',
            style: strong,
            align: pw.TextAlign.center,
          ),
        );
      }
      blocks.add(rule());
    }

    pw.Widget customer() {
      final lines = <pw.Widget>[
        txt('Nombre: ${_s(sale, 'customer_name', 'Consumidor final')}'),
        if (_s(sale, 'customer_identity').isNotEmpty)
          txt('Identidad/RTN: ${_s(sale, 'customer_identity')}'),
        if (d['show_phone'] == true && _s(sale, 'customer_phone').isNotEmpty)
          txt('Tel: ${_s(sale, 'customer_phone')}'),
        if (d['show_email'] == true && _s(sale, 'customer_email').isNotEmpty)
          txt('Correo: ${_s(sale, 'customer_email')}'),
        if (d['show_address'] == true &&
            _s(sale, 'customer_address').isNotEmpty)
          txt('Dirección: ${_s(sale, 'customer_address')}'),
      ];
      if (thermal) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [headingBar('${d['customer_section_title']}'), ...lines],
        );
      }
      return pw.Container(
        padding: const pw.EdgeInsets.all(9),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: border, width: .8),
        ),
        child: panel('${d['customer_section_title']}', lines),
      );
    }

    pw.Widget items() {
      final entries = _rows(sale['lines']);
      final showQty = d['show_quantity'] == true;
      final showPrice = d['show_unit_price'] == true;
      if (thermal) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            headingBar('${d['item_section_title']}'),
            rule(),
            for (final line in entries) ...[
              txt(_s(line, 'name_snapshot'), style: strong),
              detail(
                '${showQty ? '${_s(line, 'quantity')} x ' : ''}'
                    '${showPrice ? 'L ${_s(line, 'unit_price')}' : ''}',
                'L ${_s(line, 'line_total')}',
              ),
              if (d['show_sku'] == true && _s(line, 'sku_snapshot').isNotEmpty)
                txt('SKU: ${_s(line, 'sku_snapshot')}', style: small),
            ],
          ],
        );
      }
      final labels = <String>[
        'DESCRIPCIÓN',
        if (showQty) 'CANT.',
        if (showPrice) 'PRECIO',
        'IMPORTE',
      ];
      final matrix = <List<String>>[
        labels,
        for (final line in entries)
          <String>[
            '${_s(line, 'name_snapshot')}'
                '${d['show_sku'] == true && _s(line, 'sku_snapshot').isNotEmpty ? '\nSKU: ${_s(line, 'sku_snapshot')}' : ''}',
            if (showQty) _s(line, 'quantity'),
            if (showPrice) 'L ${_s(line, 'unit_price')}',
            'L ${_s(line, 'line_total')}',
          ],
      ];
      final compact = d['table_density'] == 'compact';
      final borderStyle = switch ('${d['table_style']}') {
        'plain' => null,
        'lines' => pw.TableBorder(
          horizontalInside: pw.BorderSide(color: border, width: .5),
        ),
        _ => pw.TableBorder.all(color: border, width: .5),
      };
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          headingBar('${d['item_section_title']}'),
          pw.Table(
            border: borderStyle,
            columnWidths: <int, pw.TableColumnWidth>{
              0: const pw.FlexColumnWidth(4),
              for (var i = 1; i < labels.length; i++)
                i: const pw.FlexColumnWidth(1.5),
            },
            children: [
              for (var i = 0; i < matrix.length; i++)
                pw.TableRow(
                  decoration: i == 0 ? pw.BoxDecoration(color: primary) : null,
                  children: [
                    for (final value in matrix[i])
                      pw.Padding(
                        padding: pw.EdgeInsets.all(compact ? 4 : 7),
                        child: txt(
                          value,
                          style: i == 0
                              ? strong.copyWith(color: PdfColors.white)
                              : regular,
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ],
      );
    }

    pw.Widget totals() => panel('RESUMEN DE IMPORTES', [
      detail('Subtotal', 'L ${_s(sale, 'subtotal', '0.00')}'),
      detail('Descuento', 'L ${_s(sale, 'discount_amount', '0.00')}'),
      if (invoice)
        detail(
          'ISV ${((sale['tax_rate_bps'] as num?) ?? 1500) / 100}%',
          'L ${_s(sale, 'tax_amount', '0.00')}',
        ),
      rule(),
      pw.Container(
        color: soft,
        padding: const pw.EdgeInsets.all(6),
        child: detail('TOTAL', 'L ${_s(sale, 'total', '0.00')}', bold: true),
      ),
    ]);

    pw.Widget payments() => panel('${d['payment_section_title']}', [
      if (d['show_payment_details'] == true) ...[
        for (final pay in _rows(sale['payments']))
          detail(_s(pay, 'channel'), 'L ${_s(pay, 'amount', '0.00')}'),
        if (sale['cash_received'] != null)
          detail('Recibido', 'L ${_s(sale, 'cash_received')}'),
        if (sale['cash_received'] != null)
          detail('Cambio', 'L ${_s(sale, 'change_given', '0.00')}'),
      ] else
        detail('Total pagado', 'L ${_s(sale, 'total', '0.00')}'),
    ]);

    // El usuario puede reordenar los bloques de contenido. El encabezado
    // legal obligatorio se conserva arriba para garantizar legibilidad.
    var grouped = false;
    for (final section in sections) {
      if (hidden.contains(section) &&
          CompanyPosDocumentDesign.optionalSections.contains(section)) {
        continue;
      }
      if (!thermal &&
          <String>{
            'brand',
            'logo',
            'document',
            'fiscal',
            'sale',
          }.contains(section)) {
        continue;
      }
      if (thermal &&
          <String>{
            'brand',
            'logo',
            'document',
            'fiscal',
            'sale',
          }.contains(section)) {
        continue;
      }
      switch (section) {
        case 'customer':
          blocks.add(customer());
          blocks.add(pw.SizedBox(height: 12));
          break;
        case 'items':
          blocks.add(items());
          blocks.add(pw.SizedBox(height: 12));
          break;
        case 'payments':
        case 'totals':
          if (!thermal && d['summary_position'] == 'right' && !grouped) {
            blocks.add(
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: payments()),
                  pw.SizedBox(width: 15),
                  pw.Expanded(child: totals()),
                ],
              ),
            );
            grouped = true;
            blocks.add(pw.SizedBox(height: 14));
          } else if (thermal || d['summary_position'] != 'right') {
            blocks.add(section == 'totals' ? totals() : payments());
            blocks.add(pw.SizedBox(height: 8));
          }
          break;
        case 'qr':
          blocks.add(_qr(d, thermal, small));
          break;
        case 'notes':
          if ('${d['custom_note'] ?? ''}'.trim().isNotEmpty) {
            blocks.add(txt('${d['custom_note']}', align: pw.TextAlign.center));
          }
          break;
        case 'footer':
          if ('${d['footer_text'] ?? ''}'.trim().isNotEmpty) {
            blocks.add(
              txt(
                '${d['footer_text']}',
                style: small,
                align: pw.TextAlign.center,
              ),
            );
          }
          break;
      }
    }
    blocks.add(pw.SizedBox(height: 8));
    blocks.add(
      pw.Center(
        child: txt(
          invoice
              ? (demonstration
                    ? 'DOCUMENTO DE PRUEBA - SIN VALIDEZ FISCAL'
                    : 'DOCUMENTO FISCAL')
              : 'DOCUMENTO INTERNO SIN VALOR FISCAL',
          style: small,
        ),
      ),
    );

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        margin: pw.EdgeInsets.all(margin * mm),
        theme: pw.ThemeData.withFont(base: font),
        build: (_) => blocks,
      ),
    );
    return pdf.save();
  }
}
