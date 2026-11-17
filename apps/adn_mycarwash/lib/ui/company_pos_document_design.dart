/// Esquema visual del editor de comprobantes. Nunca sustituye los importes,
/// datos del CAI ni el identificador fiscal almacenados en Laravel.
class CompanyPosDocumentDesign {
  static const sections = <String>[
    'logo',
    'brand',
    'document',
    'fiscal',
    'sale',
    'customer',
    'items',
    'totals',
    'payments',
    'notes',
    'footer',
  ];

  static const labels = <String, String>{
    'logo': 'Logotipo',
    'brand': 'Nombre comercial',
    'document': 'Tipo de documento',
    'fiscal': 'Datos fiscales obligatorios',
    'sale': 'Número y fecha',
    'customer': 'Datos del cliente',
    'items': 'Productos y cantidades',
    'totals': 'Importes e impuestos',
    'payments': 'Medios de pago y cambio',
    'notes': 'Mensaje personalizado',
    'footer': 'Pie de página',
  };

  static const optionalSections = <String>{'logo', 'brand', 'notes', 'footer'};

  static Map<String, dynamic> defaults(String type) => <String, dynamic>{
    'title': type == 'FISCAL_INVOICE' ? 'FACTURA' : 'RECIBO DE COMPRA',
    'subtitle': 'Gracias por su compra',
    'brand_name': '',
    'footer_text': 'Gracias por preferirnos',
    'custom_note': '',
    'primary_color': '#0FA7B4',
    'text_color': '#202B30',
    'background_color': '#FFFFFF',
    'font_family': 'helvetica',
    'font_size': 10,
    'heading_size': 17,
    'alignment': 'center',
    'paper': type == 'FISCAL_INVOICE' ? 'A4' : '80MM',
    'layout_style': type == 'FISCAL_INVOICE' ? 'administrative' : 'ticket',
    'table_style': 'grid',
    'logo_alignment': 'center',
    'page_margin_mm': 14,
    'show_quantity': true,
    'show_unit_price': true,
    'item_section_title': 'DETALLE DE PRODUCTOS',
    'customer_section_title': 'DATOS DEL CLIENTE',
    'payment_section_title': 'FORMAS DE PAGO',
    'fiscal_section_title': 'INFORMACIÓN FISCAL',
    'logo_base64': '',
    'logo_width_mm': 32,
    'show_sku': false,
    'show_phone': true,
    'show_email': false,
    'show_address': false,
    'show_payment_details': true,
    'show_separators': true,
    'sections': List<String>.from(sections),
    'hidden_sections': <String>[],
  };

  static Map<String, dynamic> resolve(String type, Object? saved) {
    final result = defaults(type);
    if (saved is Map) {
      for (final entry in saved.entries) {
        if (entry.key is String && result.containsKey(entry.key)) {
          result[entry.key as String] = entry.value;
        }
      }
    }
    return result;
  }
}
