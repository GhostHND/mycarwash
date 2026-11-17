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
    'qr',
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
    'qr': 'Código QR y enlace',
  };

  static const optionalSections = <String>{
    'logo',
    'brand',
    'notes',
    'footer',
    'qr',
  };

  static Map<String, dynamic> defaults(String type) => <String, dynamic>{
    'title': type == 'FISCAL_INVOICE' ? 'FACTURA' : 'RECIBO DE COMPRA',
    'subtitle': 'Gracias por su compra',
    'brand_name': '',
    'footer_text': 'Gracias por preferirnos',
    'custom_note': '',
    'primary_color': '#0FA7B4',
    'secondary_color': '#142D3B',
    'border_color': '#DAE2E8',
    'header_layout': 'logo_left',
    'summary_position': 'right',
    'table_density': 'comfortable',
    'renderer_version': 4,
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
    'qr_enabled': false,
    'qr_url': '',
    'qr_title': 'ESCANEA Y VISÍTANOS',
    'qr_caption': '',
    'qr_size_mm': 28,
    'qr_alignment': 'center',
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
    // Las ventas anteriores no tienen renderer_version. Su PDF se conserva
    // exactamente con el motor anterior, aunque se cambie el diseño vigente.
    if (saved is Map && !saved.containsKey('renderer_version')) {
      result['renderer_version'] = 3;
    }
    return result;
  }

  /// Impide codificar esquemas arbitrarios o acciones en los QR de comprobantes.
  static bool isValidQrLink(String value) {
    final url = Uri.tryParse(value.trim());
    return value.trim().length <= 800 &&
        url != null &&
        (url.scheme == 'https' || url.scheme == 'http') &&
        url.host.isNotEmpty &&
        url.userInfo.isEmpty;
  }
}
