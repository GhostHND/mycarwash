import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'company_pos_document_design.dart';
import 'company_pos_modern_printing.dart';

/// Layout modular 21C.3. Reads only the immutable sale/document snapshot.
/// Fiscal numbering, tax and totals always come from Laravel, never the editor.
class CompanyPosAdvancedPrinting {
  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  static pw.Font _font(String value) => switch (value) {
    'times' => pw.Font.times(),
    'courier' => pw.Font.courier(),
    _ => pw.Font.helvetica(),
  };

  static PdfColor _color(dynamic value, String fallback) {
    final raw = '$value';
    return PdfColor.fromHex(
      RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(raw) ? raw : fallback,
    );
  }

  static pw.TextAlign _align(dynamic value) => switch ('$value') {
    'left' => pw.TextAlign.left,
    'right' => pw.TextAlign.right,
    _ => pw.TextAlign.center,
  };

  static pw.Widget _detail(
    String left,
    String right,
    pw.TextStyle style, {
    bool bold = false,
  }) {
    final effective = bold
        ? style.copyWith(fontWeight: pw.FontWeight.bold)
        : style;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(left, style: effective)),
          pw.Text(right, style: effective),
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
    final design = CompanyPosDocumentDesign.resolve(
      type,
      sale['document_design'],
    );
    // Las revisiones publicadas antes de 21C.4 mantienen el PDF anterior.
    if ((design['renderer_version'] as num?)?.toInt() == 4) {
      return CompanyPosModernPrinting.buildPdf(sale, demo: demo);
    }
    final paper = '${design['paper']}';
    final thermal = paper == '58MM' || paper == '80MM';
    final mm = PdfPageFormat.mm;
    final primary = thermal
        ? PdfColors.black
        : _color(design['primary_color'], '#0FA7B4');
    final ink = thermal
        ? PdfColors.black
        : _color(design['text_color'], '#202B30');
    final bg = thermal
        ? PdfColors.white
        : _color(design['background_color'], '#FFFFFF');
    final border = thermal ? PdfColors.black : primary;
    final font = _font('${design['font_family']}');
    final size = (design['font_size'] as num).toDouble();
    final heading = (design['heading_size'] as num).toDouble();
    final body = pw.TextStyle(font: font, fontSize: size, color: ink);
    final fine = body.copyWith(fontSize: math.max(7.0, size - 1));
    final title = body.copyWith(
      fontSize: heading,
      color: primary,
      fontWeight: pw.FontWeight.bold,
    );
    final order = List<String>.from(design['sections'] as List);
    final hidden = List<String>.from(design['hidden_sections'] as List);
    final lineStyle = '${design['table_style']}';
    final showRules = design['show_separators'] == true;
    final layout = thermal ? 'ticket' : '${design['layout_style']}';
    final brandName = '${design['brand_name']}'.trim().isNotEmpty
        ? '${design['brand_name']}'
        : '${sale['company_name'] ?? sale['fiscal_legal_name'] ?? 'Negocio'}';
    final fake =
        demo ||
        (invoice &&
            ('${sale['fiscal_cai'] ?? ''}' ==
                    'AAAAAA-BBBBBB-CCCCCC-DDDDDD-EEEEEE-00' ||
                '${sale['fiscal_rtn'] ?? ''}' == '00000000000000'));

    pw.Widget text(String value, {pw.TextStyle? style, pw.TextAlign? align}) =>
        pw.Text(
          value,
          style: style ?? body,
          textAlign:
              align ??
              (thermal ? pw.TextAlign.center : _align(design['alignment'])),
        );
    pw.Widget rule() => showRules
        ? pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Divider(color: border, thickness: thermal ? .55 : .9),
          )
        : pw.SizedBox(height: 6);
    pw.Widget caption(String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 6),
      child: text(
        value,
        style: fine.copyWith(fontWeight: pw.FontWeight.bold),
        align: thermal ? pw.TextAlign.center : pw.TextAlign.left,
      ),
    );
    pw.Widget panel(String headingText, List<pw.Widget> contents) {
      if (thermal || layout == 'minimal') {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [rule(), caption(headingText), ...contents],
        );
      }
      return pw.Padding(
        padding: const pw.EdgeInsets.only(top: 7),
        child: pw.Container(
          padding: const pw.EdgeInsets.all(9),
          decoration: pw.BoxDecoration(
            color: bg,
            border: pw.Border.all(color: border, width: .7),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [caption(headingText), ...contents],
          ),
        ),
      );
    }

    final blocks = <pw.Widget>[];
    for (final section in order) {
      if (hidden.contains(section) &&
          CompanyPosDocumentDesign.optionalSections.contains(section)) {
        continue;
      }
      switch (section) {
        case 'logo':
          final encoded = '${design['logo_base64'] ?? ''}';
          if (encoded.isNotEmpty) {
            try {
              final bytes = base64Decode(encoded);
              if (bytes.isNotEmpty && bytes.length <= 1048576) {
                final width = math.min(
                  (design['logo_width_mm'] as num).toDouble(),
                  thermal ? (paper == '58MM' ? 49.0 : 71.0) : 80.0,
                );
                final image = pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.Image(
                    pw.MemoryImage(bytes),
                    width: width * mm,
                    height: math.min(width, 43.0) * mm,
                    fit: pw.BoxFit.contain,
                  ),
                );
                blocks.add(
                  pw.Row(
                    mainAxisAlignment: switch ('${design['logo_alignment']}') {
                      'left' => pw.MainAxisAlignment.start,
                      'right' => pw.MainAxisAlignment.end,
                      _ => pw.MainAxisAlignment.center,
                    },
                    children: [image],
                  ),
                );
              }
            } catch (_) {
              // Corrupt logo must never make an issued receipt unprintable.
            }
          }
          break;
        case 'brand':
          blocks.add(
            pw.Column(
              children: [
                text(brandName, style: title, align: pw.TextAlign.center),
                if ('${design['subtitle']}'.trim().isNotEmpty)
                  text('${design['subtitle']}', align: pw.TextAlign.center),
              ],
            ),
          );
          break;
        case 'document':
          blocks.add(
            pw.Column(
              children: [
                rule(),
                text(
                  invoice ? 'FACTURA' : 'RECIBO NO FISCAL',
                  style: title.copyWith(
                    fontSize: math.max(heading - 2, size + 2),
                  ),
                  align: pw.TextAlign.center,
                ),
                if ('${design['title']}'.trim().isNotEmpty)
                  text(
                    '${design['title']}',
                    style: fine,
                    align: pw.TextAlign.center,
                  ),
                if (fake)
                  text(
                    'DOCUMENTO DE PRUEBA - SIN VALIDEZ FISCAL',
                    style: fine.copyWith(fontWeight: pw.FontWeight.bold),
                    align: pw.TextAlign.center,
                  ),
              ],
            ),
          );
          break;
        case 'fiscal':
          if (invoice) {
            blocks.add(
              panel('${design['fiscal_section_title']}', [
                text(
                  'Emisor: ${sale['fiscal_legal_name'] ?? ''}',
                  align: pw.TextAlign.left,
                ),
                text(
                  'RTN: ${sale['fiscal_rtn'] ?? ''}',
                  align: pw.TextAlign.left,
                ),
                text(
                  'Factura: ${sale['fiscal_number'] ?? ''}',
                  align: pw.TextAlign.left,
                ),
                text(
                  'CAI: ${sale['fiscal_cai'] ?? ''}',
                  align: pw.TextAlign.left,
                ),
                text(
                  'Rango: ${sale['fiscal_range_start'] ?? ''} a ${sale['fiscal_range_end'] ?? ''}',
                  style: fine,
                  align: pw.TextAlign.left,
                ),
                text(
                  'Fecha límite: ${sale['fiscal_expires_on'] ?? ''}',
                  align: pw.TextAlign.left,
                ),
              ]),
            );
          }
          break;
        case 'sale':
          blocks.add(
            panel('INFORMACIÓN DEL DOCUMENTO', [
              text('Venta: #${sale['id'] ?? ''}', align: pw.TextAlign.left),
              text(
                'Fecha: ${sale['posted_at'] ?? ''}',
                align: pw.TextAlign.left,
              ),
            ]),
          );
          break;
        case 'customer':
          final contents = <pw.Widget>[
            text(
              'Nombre: ${sale['customer_name'] ?? 'Consumidor final'}',
              align: pw.TextAlign.left,
            ),
            if ('${sale['customer_identity'] ?? ''}'.isNotEmpty)
              text(
                'Identidad / RTN: ${sale['customer_identity']}',
                align: pw.TextAlign.left,
              ),
            if (design['show_phone'] == true &&
                '${sale['customer_phone'] ?? ''}'.isNotEmpty)
              text(
                'Teléfono: ${sale['customer_phone']}',
                align: pw.TextAlign.left,
              ),
            if (design['show_email'] == true &&
                '${sale['customer_email'] ?? ''}'.isNotEmpty)
              text(
                'Correo: ${sale['customer_email']}',
                align: pw.TextAlign.left,
              ),
            if (design['show_address'] == true &&
                '${sale['customer_address'] ?? ''}'.isNotEmpty)
              text(
                'Dirección: ${sale['customer_address']}',
                align: pw.TextAlign.left,
              ),
          ];
          blocks.add(panel('${design['customer_section_title']}', contents));
          break;
        case 'items':
          final items = _rows(sale['lines']);
          final showQty = design['show_quantity'] == true;
          final showPrice = design['show_unit_price'] == true;
          final labels = <String>[
            'DESCRIPCIÓN',
            if (showQty) 'CANT.',
            if (showPrice) 'PRECIO',
            'IMPORTE',
          ];
          final matrix = <List<String>>[
            labels,
            for (final item in items)
              <String>[
                '${item['name_snapshot'] ?? ''}'
                    '${design['show_sku'] == true && '${item['sku_snapshot'] ?? ''}'.isNotEmpty ? '\nSKU: ${item['sku_snapshot']}' : ''}',
                if (showQty) '${item['quantity']}',
                if (showPrice) 'L ${item['unit_price'] ?? '-'}',
                'L ${item['line_total'] ?? '0.00'}',
              ],
          ];
          if (thermal) {
            blocks.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  rule(),
                  caption('ARTÍCULOS'),
                  for (final item in items) ...[
                    text(
                      '${item['name_snapshot'] ?? ''}',
                      align: pw.TextAlign.left,
                    ),
                    _detail(
                      '${showQty ? '${item['quantity']} x ' : ''}'
                          '${showPrice ? 'L ${item['unit_price'] ?? '-'}' : ''}',
                      'L ${item['line_total'] ?? '0.00'}',
                      fine,
                    ),
                  ],
                ],
              ),
            );
          } else {
            final widths = <int, pw.TableColumnWidth>{
              0: const pw.FlexColumnWidth(4),
            };
            for (var i = 1; i < labels.length; i++) {
              widths[i] = const pw.FlexColumnWidth(1.4);
            }
            blocks.add(
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  rule(),
                  caption('${design['item_section_title']}'),
                  pw.Table(
                    columnWidths: widths,
                    border: lineStyle == 'plain'
                        ? null
                        : lineStyle == 'lines'
                        ? pw.TableBorder(
                            horizontalInside: pw.BorderSide(
                              color: border,
                              width: .55,
                            ),
                          )
                        : pw.TableBorder.all(color: border, width: .55),
                    children: [
                      for (
                        var rowIndex = 0;
                        rowIndex < matrix.length;
                        rowIndex++
                      )
                        pw.TableRow(
                          decoration: rowIndex == 0
                              ? pw.BoxDecoration(color: primary)
                              : null,
                          children: [
                            for (final cell in matrix[rowIndex])
                              pw.Padding(
                                padding: const pw.EdgeInsets.all(6),
                                child: pw.Text(
                                  cell,
                                  style: rowIndex == 0
                                      ? fine.copyWith(
                                          color: PdfColors.white,
                                          fontWeight: pw.FontWeight.bold,
                                        )
                                      : body,
                                ),
                              ),
                          ],
                        ),
                    ],
                  ),
                ],
              ),
            );
          }
          break;
        case 'totals':
          blocks.add(
            panel('RESUMEN DE IMPORTES', [
              _detail('Subtotal', 'L ${sale['subtotal'] ?? '0.00'}', body),
              _detail(
                'Descuento',
                'L ${sale['discount_amount'] ?? '0.00'}',
                body,
              ),
              if (invoice)
                _detail(
                  'ISV ${((sale['tax_rate_bps'] as num?) ?? 1500) / 100}%',
                  'L ${sale['tax_amount'] ?? '0.00'}',
                  body,
                ),
              rule(),
              _detail(
                'TOTAL',
                'L ${sale['total'] ?? '0.00'}',
                title.copyWith(fontSize: math.max(size + 2, heading - 2)),
                bold: true,
              ),
            ]),
          );
          break;
        case 'payments':
          final details = <pw.Widget>[];
          if (design['show_payment_details'] == true) {
            for (final payment in _rows(sale['payments'])) {
              details.add(
                _detail(
                  '${payment['channel'] ?? ''}',
                  'L ${payment['amount'] ?? '0.00'}',
                  body,
                ),
              );
            }
            if (sale['cash_received'] != null) {
              details.add(
                _detail('Recibido', 'L ${sale['cash_received']}', body),
              );
              details.add(
                _detail('Cambio', 'L ${sale['change_given'] ?? '0.00'}', body),
              );
            }
          } else {
            details.add(
              text(
                'Total pagado: L ${sale['total'] ?? '0.00'}',
                align: pw.TextAlign.left,
              ),
            );
          }
          blocks.add(panel('${design['payment_section_title']}', details));
          break;
        case 'notes':
          if ('${design['custom_note']}'.trim().isNotEmpty) {
            blocks.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8),
                child: text(
                  '${design['custom_note']}',
                  align: pw.TextAlign.center,
                ),
              ),
            );
          }
          break;
        case 'footer':
          if ('${design['footer_text']}'.trim().isNotEmpty) {
            blocks.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 10),
                child: text(
                  '${design['footer_text']}',
                  style: fine,
                  align: pw.TextAlign.center,
                ),
              ),
            );
          }
          break;
      }
    }
    // Preserve legal designations regardless of user-selected block order.
    blocks.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(top: 8),
        child: text(
          invoice
              ? (fake ? 'SIMULACIÓN SIN VALIDEZ FISCAL' : 'DOCUMENTO FISCAL')
              : 'DOCUMENTO INTERNO SIN VALOR FISCAL',
          style: fine.copyWith(fontWeight: pw.FontWeight.bold),
          align: pw.TextAlign.center,
        ),
      ),
    );
    final pdf = pw.Document();
    final margin = thermal ? 2.5 : (design['page_margin_mm'] as num).toDouble();
    final pageFormat = paper == 'A4'
        ? PdfPageFormat.a4
        : paper == 'LETTER'
        ? PdfPageFormat.letter
        : PdfPageFormat(
            (paper == '58MM' ? 58 : 80) * mm,
            math.max(
                  170,
                  110 +
                      _rows(sale['lines']).length * 17 +
                      _rows(sale['payments']).length * 12,
                ) *
                mm,
            marginAll: margin * mm,
          );
    pdf.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: pw.EdgeInsets.all(margin * mm),
        theme: pw.ThemeData.withFont(base: font),
        build: (_) => [
          for (final block in blocks)
            pw.Container(
              color: bg,
              padding: pw.EdgeInsets.symmetric(vertical: thermal ? 1 : 4),
              child: block,
            ),
        ],
      ),
    );
    return pdf.save();
  }
}
