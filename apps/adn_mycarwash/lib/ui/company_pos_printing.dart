import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'company_pos_document_design.dart';

/// Renderer de PDFs basado en versiones de diseño publicadas por sucursal.
/// Nunca modifica el subtotal, el ISV, el CAI, los correlativos ni una venta.
class CompanyPosPrinting {
  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
      : <Map<String, dynamic>>[];

  static pw.Font _font(String name) {
    switch (name) {
      case 'times':
        return pw.Font.times();
      case 'courier':
        return pw.Font.courier();
      default:
        return pw.Font.helvetica();
    }
  }

  static PdfColor _color(Object? value, String fallback) {
    final v = '$value';
    if (RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v)) {
      return PdfColor.fromHex(v);
    }
    return PdfColor.fromHex(fallback);
  }

  static pw.TextAlign _align(String value) {
    switch (value) {
      case 'left':
        return pw.TextAlign.left;
      case 'right':
        return pw.TextAlign.right;
      default:
        return pw.TextAlign.center;
    }
  }

  static pw.Widget _line(
    String label,
    String amount,
    pw.TextStyle style, {
    bool bold = false,
  }) {
    final s = bold ? style.copyWith(fontWeight: pw.FontWeight.bold) : style;
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        children: [
          pw.Expanded(child: pw.Text(label, style: s)),
          pw.Text(amount, style: s),
        ],
      ),
    );
  }

  static Future<Uint8List> buildPdf(
    Map<String, dynamic> sale, {
    bool demo = false,
  }) async {
    final invoice = sale['document_type'] == 'FISCAL_INVOICE';
    // Un CAI de ejemplo nunca se presenta como una factura autorizada.
    final clearlyFictitious =
        invoice &&
        ('${sale['fiscal_cai'] ?? ''}' ==
                'AAAAAA-BBBBBB-CCCCCC-DDDDDD-EEEEEE-00' ||
            '${sale['fiscal_rtn'] ?? ''}' == '00000000000000');
    final type = invoice ? 'FISCAL_INVOICE' : 'RECEIPT';
    final design = CompanyPosDocumentDesign.resolve(
      type,
      sale['document_design'],
    );
    final base = _font('${design['font_family']}');
    final size = (design['font_size'] as num).toDouble();
    final heading = (design['heading_size'] as num).toDouble();
    final primary = _color(design['primary_color'], '#0FA7B4');
    final textColor = _color(design['text_color'], '#202B30');
    final background = _color(design['background_color'], '#FFFFFF');
    final alignment = _align('${design['alignment']}');
    final lineStyle = pw.TextStyle(
      font: base,
      fontSize: size,
      color: textColor,
    );
    final smallStyle = lineStyle.copyWith(fontSize: math.max(7.0, size - 1.0));
    final titleStyle = lineStyle.copyWith(
      fontSize: heading,
      color: primary,
      fontWeight: pw.FontWeight.bold,
    );
    final compact = '${design['paper']}'.endsWith('MM');
    final mm = PdfPageFormat.mm;
    final paper = '${design['paper']}';
    final format = paper == 'A4'
        ? PdfPageFormat.a4
        : paper == 'LETTER'
        ? PdfPageFormat.letter
        : PdfPageFormat(
            (paper == '58MM' ? 58 : 80) * mm,
            math.max(
                  155,
                  120 +
                      (_rows(sale['lines']).length +
                              _rows(sale['payments']).length) *
                          13,
                ) *
                mm,
            marginAll: 3 * mm,
          );
    final showSeparators = design['show_separators'] == true;
    final hidden = (design['hidden_sections'] is List)
        ? List<String>.from(design['hidden_sections'] as List)
        : <String>[];
    final sections = (design['sections'] is List)
        ? List<String>.from(design['sections'] as List)
        : List<String>.from(CompanyPosDocumentDesign.sections);
    final brand = '${design['brand_name']}'.trim().isEmpty
        ? '${sale['company_name'] ?? sale['fiscal_legal_name'] ?? 'Negocio'}'
        : '${design['brand_name']}';

    pw.Widget centerText(String value, {pw.TextStyle? style}) =>
        pw.Text(value, textAlign: alignment, style: style ?? lineStyle);
    pw.Widget separator() => showSeparators
        ? pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Divider(color: primary, thickness: .65),
          )
        : pw.SizedBox(height: 6);
    pw.Widget footer(String text, {bool prominent = false}) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 5),
      child: centerText(
        text,
        style: prominent
            ? smallStyle.copyWith(fontWeight: pw.FontWeight.bold)
            : smallStyle,
      ),
    );

    final blocks = <pw.Widget>[];
    for (final section in sections) {
      if (hidden.contains(section) &&
          CompanyPosDocumentDesign.optionalSections.contains(section)) {
        continue;
      }
      switch (section) {
        case 'logo':
          final raw = '${design['logo_base64'] ?? ''}';
          if (raw.isNotEmpty) {
            try {
              final bytes = base64Decode(raw);
              if (bytes.length <= 100000) {
                blocks.add(
                  pw.Center(
                    child: pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 7),
                      child: pw.Image(
                        pw.MemoryImage(bytes),
                        width: (design['logo_width_mm'] as num).toDouble() * mm,
                        height:
                            math.min(
                              45.0,
                              (design['logo_width_mm'] as num).toDouble(),
                            ) *
                            mm,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  ),
                );
              }
            } catch (_) {
              // Nunca invalidar un comprobante por un logo dañado.
            }
          }
          break;
        case 'brand':
          blocks.add(centerText(brand, style: titleStyle));
          if ('${design['subtitle']}'.trim().isNotEmpty) {
            blocks.add(footer('${design['subtitle']}'));
          }
          blocks.add(separator());
          break;
        case 'document':
          // La clase fiscal/no fiscal nunca depende de texto editable.
          blocks.add(
            centerText(
              invoice ? 'FACTURA' : 'RECIBO NO FISCAL',
              style: titleStyle.copyWith(
                fontSize: math.max(size + 3, heading - 3),
              ),
            ),
          );
          if ('${design['title']}'.trim().isNotEmpty) {
            blocks.add(footer('${design['title']}'));
          }
          if (demo || clearlyFictitious) {
            blocks.add(
              footer(
                'VISTA PREVIA / DATOS DE PRUEBA - SIN VALIDEZ FISCAL',
                prominent: true,
              ),
            );
          }
          break;
        case 'fiscal':
          if (invoice) {
            blocks.add(separator());
            // Estos datos se imprimen SIEMPRE, sin importar el diseño visual.
            blocks.add(
              pw.Text(
                'Emisor: ${sale['fiscal_legal_name'] ?? ''}',
                style: lineStyle,
              ),
            );
            blocks.add(
              pw.Text('RTN: ${sale['fiscal_rtn'] ?? ''}', style: lineStyle),
            );
            blocks.add(
              pw.Text(
                'Factura: ${sale['fiscal_number'] ?? ''}',
                style: lineStyle,
              ),
            );
            blocks.add(
              pw.Text('CAI: ${sale['fiscal_cai'] ?? ''}', style: lineStyle),
            );
            blocks.add(
              pw.Text(
                'Rango: ${sale['fiscal_range_start'] ?? ''} a ${sale['fiscal_range_end'] ?? ''}',
                style: smallStyle,
              ),
            );
            blocks.add(
              pw.Text(
                'Fecha límite: ${sale['fiscal_expires_on'] ?? ''}',
                style: lineStyle,
              ),
            );
          }
          break;
        case 'sale':
          blocks.add(separator());
          blocks.add(pw.Text('Venta: #${sale['id'] ?? ''}', style: lineStyle));
          blocks.add(
            pw.Text('Fecha: ${sale['posted_at'] ?? ''}', style: lineStyle),
          );
          break;
        case 'customer':
          blocks.add(separator());
          blocks.add(
            pw.Text(
              'Cliente: ${sale['customer_name'] ?? 'Consumidor final'}',
              style: lineStyle,
            ),
          );
          final identity = '${sale['customer_identity'] ?? ''}';
          if (identity.isNotEmpty) {
            blocks.add(pw.Text('Identidad/RTN: $identity', style: lineStyle));
          }
          if (design['show_phone'] == true &&
              '${sale['customer_phone'] ?? ''}'.isNotEmpty) {
            blocks.add(
              pw.Text('Tel: ${sale['customer_phone']}', style: lineStyle),
            );
          }
          if (design['show_email'] == true &&
              '${sale['customer_email'] ?? ''}'.isNotEmpty) {
            blocks.add(
              pw.Text('Email: ${sale['customer_email']}', style: lineStyle),
            );
          }
          if (design['show_address'] == true &&
              '${sale['customer_address'] ?? ''}'.isNotEmpty) {
            blocks.add(
              pw.Text(
                'Dirección: ${sale['customer_address']}',
                style: lineStyle,
              ),
            );
          }
          break;
        case 'items':
          blocks.add(separator());
          for (final item in _rows(sale['lines'])) {
            var label = '${item['name_snapshot']} x${item['quantity']}';
            if (design['show_sku'] == true &&
                '${item['sku_snapshot'] ?? ''}'.isNotEmpty) {
              label += '\nSKU: ${item['sku_snapshot']}';
            }
            blocks.add(_line(label, 'L ${item['line_total']}', lineStyle));
          }
          break;
        case 'totals':
          blocks.add(separator());
          blocks.add(_line('Subtotal', 'L ${sale['subtotal']}', lineStyle));
          blocks.add(
            _line('Descuento', 'L ${sale['discount_amount']}', lineStyle),
          );
          if (invoice) {
            blocks.add(
              _line(
                'ISV ${((sale['tax_rate_bps'] as num?) ?? 1500) / 100}%',
                'L ${sale['tax_amount']}',
                lineStyle,
              ),
            );
          }
          blocks.add(
            _line(
              'TOTAL',
              'L ${sale['total']}',
              lineStyle.copyWith(fontSize: size + 2, color: primary),
              bold: true,
            ),
          );
          break;
        case 'payments':
          blocks.add(separator());
          if (design['show_payment_details'] == true) {
            for (final payment in _rows(sale['payments'])) {
              blocks.add(
                pw.Text(
                  '${payment['channel']}: L ${payment['amount']}',
                  style: lineStyle,
                ),
              );
            }
            if (sale['cash_received'] != null) {
              blocks.add(
                pw.Text(
                  'Recibido: L ${sale['cash_received']}',
                  style: lineStyle,
                ),
              );
              blocks.add(
                pw.Text('Cambio: L ${sale['change_given']}', style: lineStyle),
              );
            }
          } else {
            blocks.add(
              pw.Text('Total pagado: L ${sale['total']}', style: lineStyle),
            );
          }
          break;
        case 'notes':
          if ('${design['custom_note']}'.trim().isNotEmpty) {
            blocks.add(footer('${design['custom_note']}'));
          }
          break;
        case 'footer':
          if ('${design['footer_text']}'.trim().isNotEmpty) {
            blocks.add(footer('${design['footer_text']}'));
          }
          break;
      }
    }
    // No se puede quitar la indicación legal aunque se oculten bloques decorativos.
    if (!invoice) {
      blocks.add(footer('DOCUMENTO INTERNO SIN VALOR FISCAL', prominent: true));
    }
    if ((demo || clearlyFictitious) && invoice) {
      blocks.add(footer('SIMULACIÓN SIN CAI AUTORIZADO', prominent: true));
    }
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: format,
        theme: pw.ThemeData.withFont(base: base),
        margin: pw.EdgeInsets.all(compact ? 0 : 34),
        // Cada bloque es paginable; un carrito grande no desborda una sola página.
        build: (_) => blocks
            .map(
              (block) => pw.Container(
                color: background,
                padding: pw.EdgeInsets.symmetric(
                  horizontal: compact ? 2 : 12,
                  vertical: compact ? 1 : 3,
                ),
                child: block,
              ),
            )
            .toList(),
      ),
    );
    return pdf.save();
  }

  static Future<void> printSale(Map<String, dynamic> sale) async {
    final invoice = sale['document_type'] == 'FISCAL_INVOICE';
    await Printing.layoutPdf(
      name: '${invoice ? 'factura' : 'recibo'}_pos_${sale['id']}',
      onLayout: (_) => buildPdf(sale),
    );
  }

  /// Impresión de demostración: JAMÁS genera venta ni utiliza CAI real.
  static Future<void> previewDesign(
    String type,
    Map<String, dynamic> design,
  ) async {
    final example = <String, dynamic>{
      'id': 'DEMO',
      'company_name': 'MI NEGOCIO',
      'document_type': type,
      'document_design': design,
      'posted_at': '2026-11-17 12:00:00',
      'fiscal_legal_name': 'EMPRESA DEMOSTRACIÓN',
      'fiscal_rtn': 'NO APLICA',
      'fiscal_number': 'SIMULACIÓN',
      'fiscal_cai': 'NO APLICA',
      'fiscal_range_start': 'N/A',
      'fiscal_range_end': 'N/A',
      'fiscal_expires_on': 'N/A',
      'customer_name': 'Cliente de ejemplo',
      'customer_identity': '0000000000',
      'customer_phone': '0000-0000',
      'customer_email': 'cliente@ejemplo.test',
      'customer_address': 'Dirección de prueba',
      'lines': [
        {
          'name_snapshot': 'Aromatizante',
          'sku_snapshot': 'ART-001',
          'quantity': '2',
          'line_total': '200.00',
        },
        {
          'name_snapshot': 'Microfibra',
          'sku_snapshot': 'ART-002',
          'quantity': '1',
          'line_total': '50.00',
        },
      ],
      'subtotal': '250.00',
      'discount_amount': '0.00',
      'tax_amount': type == 'FISCAL_INVOICE' ? '37.50' : '0.00',
      'tax_rate_bps': type == 'FISCAL_INVOICE' ? 1500 : 0,
      'total': type == 'FISCAL_INVOICE' ? '287.50' : '250.00',
      'payments': [
        {
          'channel': 'CASH',
          'amount': type == 'FISCAL_INVOICE' ? '287.50' : '250.00',
        },
      ],
      'cash_received': type == 'FISCAL_INVOICE' ? '287.50' : '250.00',
      'change_given': '0.00',
    };
    await Printing.layoutPdf(
      name: 'VISTA_PREVIA_SIN_VALIDEZ_FISCAL',
      onLayout: (_) => buildPdf(example, demo: true),
    );
  }
}
