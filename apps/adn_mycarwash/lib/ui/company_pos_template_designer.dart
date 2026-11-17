import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../core/company_business_api.dart';
import 'company_pos_document_design.dart';
import 'company_pos_printing.dart';

/// Ajusta cada pagina PDF completa al panel disponible, sin alterar el PDF.
/// El ticket de demostracion usa dos articulos y una forma de pago.
/// Los formatos impresos conservan sus dimensiones originales.
double posPreviewFittedWidth({
  required String paper,
  required bool qrEnabled,
  required double viewportWidth,
  required double viewportHeight,
}) {
  final thermal = paper == '58MM' || paper == '80MM';
  final pageWidthMm = thermal
      ? (paper == '58MM' ? 58.0 : 80.0)
      : (paper == 'LETTER' ? 215.9 : 210.0);
  final pageHeightMm = thermal
      ? 175.0 + 2.0 * 12.0 + 1.0 * 7.0 + (qrEnabled ? 75.0 : 0.0)
      : (paper == 'LETTER' ? 279.4 : 297.0);
  final usableWidth = (viewportWidth - 32.0)
      .clamp(1.0, double.infinity)
      .toDouble();
  final usableHeight = (viewportHeight - 48.0)
      .clamp(1.0, double.infinity)
      .toDouble();
  final heightFit = usableHeight * pageWidthMm / pageHeightMm;
  final maxVisualWidth = thermal ? 195.0 : 390.0;
  return [
    usableWidth,
    heightFit,
    maxVisualWidth,
  ].reduce((a, b) => a < b ? a : b).clamp(1.0, maxVisualWidth).toDouble();
}

/// Diseñador por sucursal: recibo/factura con revisiones inmutables.
/// Los bloques fiscales, importes y números de venta no pueden omitirse.
class CompanyPosTemplateDesigner extends StatefulWidget {
  const CompanyPosTemplateDesigner({
    super.key,
    required this.api,
    required this.branchId,
    this.embedded = false,
  });

  final CompanyBusinessApi api;
  final int branchId;
  final bool embedded;

  @override
  State<CompanyPosTemplateDesigner> createState() =>
      _CompanyPosTemplateDesignerState();
}

class _CompanyPosTemplateDesignerState
    extends State<CompanyPosTemplateDesigner> {
  static const _teal = Color(0xFF0FA7B4);
  static const _panel = Color(0xFF0D1A1F);
  static const _surface = Color(0xFF142329);

  String _type = 'RECEIPT';
  Map<String, dynamic> _design = CompanyPosDocumentDesign.defaults('RECEIPT');
  int _revision = 0;
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  String? _error;
  Timer? _previewDebounce;
  int _previewVersion = 0;

  @override
  void dispose() {
    _previewDebounce?.cancel();
    super.dispose();
  }

  void _queuePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _previewVersion++);
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final type = _type;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        'GET',
        '/pos/document-designs',
        query: {'branch_id': '${widget.branchId}', 'document_type': type},
      );
      if (!mounted || type != _type) {
        return;
      }
      final data = Map<String, dynamic>.from(response['data'] as Map);
      setState(() {
        _revision = (data['revision'] as num?)?.toInt() ?? 0;
        _design = CompanyPosDocumentDesign.resolve(type, data['design']);
        // Un nuevo borrador usa el motor PDF 21C.4; la revisión anterior
        // queda inalterada para reimpresiones históricas.
        _design['renderer_version'] = 4;
        final sections = List<String>.from(_design['sections'] as List);
        if (!sections.contains('qr')) sections.add('qr');
        _design['sections'] = sections;
        _previewVersion++;
        _dirty = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || type != _type) {
        return;
      }
      setState(() {
        _error = 'No se pudo cargar el diseño: $e';
        _loading = false;
      });
    }
  }

  void _update(String key, Object? value) {
    setState(() {
      _design[key] = value;
      if (key == 'paper') {
        _design['layout_style'] = '$value'.endsWith('MM')
            ? 'ticket'
            : 'administrative';
      }
      _dirty = true;
    });
    _queuePreview();
  }

  Future<void> _switch(String type) async {
    if (_type == type || _saving) {
      return;
    }
    if (_dirty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Hay cambios sin guardar'),
          content: const Text(
            '¿Deseas descartarlos y abrir la otra plantilla?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Seguir editando'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Descartar cambios'),
            ),
          ],
        ),
      );
      if (proceed != true || !mounted) {
        return;
      }
    }
    setState(() => _type = type);
    await _load();
  }

  Future<void> _pickLogo() async {
    try {
      // file_picker 13.x: selección individual y lectura explícita del archivo.
      final picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg'],
      );
      if (picked == null || !mounted) {
        return;
      }
      final length = picked.lengthSync() ?? await picked.length();
      if (!mounted) {
        return;
      }
      if (length != null && length > 1048576) {
        setState(
          () => _error =
              'El logo supera 1 MB. Optimiza la imagen e inténtalo nuevamente.',
        );
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      if (bytes.length > 1048576) {
        setState(
          () => _error =
              'El logo supera 1 MB. Optimiza la imagen e inténtalo nuevamente.',
        );
        return;
      }
      // Firma básica del archivo; el backend valida tipo y dimensiones reales.
      final png = bytes.length > 8 && bytes[0] == 137 && bytes[1] == 80;
      final jpg = bytes.length > 3 && bytes[0] == 255 && bytes[1] == 216;
      if (!png && !jpg) {
        setState(() => _error = 'Utiliza únicamente una imagen PNG o JPG.');
        return;
      }
      setState(() => _error = null);
      _update('logo_base64', base64Encode(bytes));
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo seleccionar el logotipo: $e');
      }
    }
  }

  Future<void> _save() async {
    if (_saving || _loading) {
      return;
    }
    if (!RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch('${_design['primary_color']}') ||
        !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch('${_design['text_color']}') ||
        !RegExp(r'^#[0-9A-Fa-f]{6}$')
            .hasMatch('${_design['secondary_color']}') ||
        !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch('${_design['border_color']}') ||
        !RegExp(r'^#[0-9A-Fa-f]{6}$')
            .hasMatch('${_design['background_color']}')) {
      setState(() => _error = 'Los colores deben tener formato #RRGGBB.');
      return;
    }
    if (_design['qr_enabled'] == true &&
        '${_design['paper']}'.endsWith('MM') &&
        !CompanyPosDocumentDesign.isValidQrLink('${_design['qr_url'] ?? ''}')) {
      setState(
        () => _error = 'El QR necesita un enlace http:// o https:// válido.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        'POST',
        '/pos/document-designs',
        body: {
          'branch_id': widget.branchId,
          'document_type': _type,
          'expected_revision': _revision,
          'design': _design,
        },
      );
      if (!mounted) {
        return;
      }
      final result = Map<String, dynamic>.from(response['data'] as Map);
      setState(() {
        _revision = (result['revision'] as num?)?.toInt() ?? _revision + 1;
        _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Plantilla publicada. Las ventas anteriores conservan su diseño.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo guardar: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _previewPdf() async {
    try {
      await CompanyPosPrinting.previewDesign(_type, _design);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo abrir la vista previa PDF: $e');
      }
    }
  }

  Color _hex(Object? value) {
    final v = '$value'.replaceFirst('#', '');
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(v)) {
      return Colors.white;
    }
    return Color(int.parse('FF$v', radix: 16));
  }

  Widget _text(String key, String label, {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: TextFormField(
        key: ValueKey('design_${_type}_${_revision}_$key'),
        initialValue: '${_design[key] ?? ''}',
        minLines: lines,
        maxLines: lines,
        onChanged: (value) => _update(key, value),
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
  }

  Widget _choice(String field, String label, Map<String, String> options) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<String>(
        key: ValueKey('${_type}_${_revision}_$field'),
        initialValue: '${_design[field]}',
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: options.entries
            .map(
              (item) =>
                  DropdownMenuItem(value: item.key, child: Text(item.value)),
            )
            .toList(),
        onChanged: (v) {
          if (v != null) {
            _update(field, v);
          }
        },
      ),
    );
  }

  Widget _swatch(String key, String label) {
    const palette = [
      '#0FA7B4',
      '#171D24',
      '#FFFFFF',
      '#D4AF37',
      '#2F6E3F',
      '#A33443',
      '#1B365D',
      '#F5F0E7',
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 7),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final color in palette)
                InkWell(
                  onTap: () => _update(key, color),
                  borderRadius: BorderRadius.circular(9),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: _hex(color),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: _design[key] == color ? _teal : Colors.grey,
                        width: _design[key] == color ? 3 : 1,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 7),
          TextFormField(
            key: ValueKey('color_${_type}_${_revision}_$key'),
            initialValue: '${_design[key]}',
            decoration: const InputDecoration(
              helperText: 'Color personalizado (#RRGGBB)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (s) => _update(key, s),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String key, String label) => SwitchListTile.adaptive(
    title: Text(label),
    contentPadding: EdgeInsets.zero,
    value: _design[key] == true,
    onChanged: (v) => _update(key, v),
  );

  Widget _sectionOrder() {
    final blocks = List<String>.from(_design['sections'] as List);
    final hidden = List<String>.from(_design['hidden_sections'] as List);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Orden y visibilidad de las secciones',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Arrastra el icono para cambiar el orden. Los datos fiscales y los importes están protegidos.',
          style: TextStyle(fontSize: 12, color: Color(0xFF9CB1BB)),
        ),
        const SizedBox(height: 8),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: blocks.length,
          // onReorderItem entrega el índice destino ya corregido.
          onReorderItem: (oldIndex, newIndex) {
            final moved = blocks.removeAt(oldIndex);
            blocks.insert(newIndex, moved);
            _update('sections', blocks);
          },
          itemBuilder: (context, index) {
            final id = blocks[index];
            final optional = CompanyPosDocumentDesign.optionalSections.contains(
              id,
            );
            return Container(
              key: ValueKey('block_$id'),
              margin: const EdgeInsets.only(bottom: 5),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListTile(
                dense: true,
                leading: ReorderableDragStartListener(
                  index: index,
                  child: const Icon(Icons.drag_indicator),
                ),
                title: Text(CompanyPosDocumentDesign.labels[id] ?? id),
                subtitle: optional ? null : const Text('Obligatorio'),
                trailing: optional
                    ? Checkbox(
                        value: !hidden.contains(id),
                        onChanged: (v) {
                          if (v == true) {
                            hidden.remove(id);
                          } else if (!hidden.contains(id)) {
                            hidden.add(id);
                          }
                          _update('hidden_sections', hidden);
                        },
                      )
                    : const Icon(Icons.lock_outline, size: 17),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _editorPanel() => ListView(
    padding: const EdgeInsets.all(17),
    children: [
      const Text(
        'Identidad de marca',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 12),
      _text('brand_name', 'Nombre comercial (opcional)'),
      _text('title', 'Título personalizado'),
      _text('subtitle', 'Subtítulo'),
      _text('custom_note', 'Mensaje / promoción', lines: 2),
      _text('footer_text', 'Pie de página', lines: 2),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _pickLogo,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Subir logo PNG/JPG'),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Quitar logo',
            onPressed: () => _update('logo_base64', ''),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      const Text(
        'Máximo 1 MB. Se guarda en la plantilla, no en cada venta.',
        style: TextStyle(fontSize: 11, color: Color(0xFF9CB1BB)),
      ),
      const SizedBox(height: 20),
      const Text(
        'Apariencia',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      if (!'${_design['paper']}'.endsWith('MM')) ...[
        _swatch('primary_color', 'Color principal'),
        _swatch('secondary_color', 'Color de encabezados y paneles'),
        _swatch('border_color', 'Color de bordes y separadores'),
        _swatch('text_color', 'Color de texto'),
        _swatch('background_color', 'Fondo de paneles y total'),
        _choice('header_layout', 'Composición del encabezado', {
          'logo_left': 'Logo a la izquierda',
          'logo_center': 'Logo y título centrados',
          'logo_right': 'Logo a la derecha',
        }),
        _choice('summary_position', 'Ubicación del resumen y pagos', {
          'right': 'En paralelo, al final',
          'bottom': 'En bloques verticales',
        }),
        _choice('table_density', 'Espaciado de tabla', {
          'comfortable': 'Cómodo y elegante',
          'compact': 'Compacto',
        }),
      ] else
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Impresión térmica: blanco y negro, sin colores editables.',
            style: TextStyle(color: Color(0xFF9CB1BB)),
          ),
        ),
      _choice('font_family', 'Tipografía', {
        'helvetica': 'Helvetica',
        'times': 'Times',
        'courier': 'Courier',
      }),
      _choice('paper', 'Formato de papel', {
        '58MM': 'Térmico 58 mm',
        '80MM': 'Térmico 80 mm',
        'A4': 'Factura A4',
        'LETTER': 'Carta',
      }),
      _choice('layout_style', 'Estilo de documento', {
        'administrative': 'Administrativo (A4 / Carta)',
        'minimal': 'Minimalista',
        'ticket': 'Ticket térmico',
      }),
      _choice('table_style', 'Estilo de tabla', {
        'grid': 'Cuadrícula empresarial',
        'lines': 'Líneas divisorias',
        'plain': 'Sin bordes',
      }),
      _choice('logo_alignment', 'Ubicación del logotipo', {
        'left': 'Izquierda',
        'center': 'Centro',
        'right': 'Derecha',
      }),
      if (!'${_design['paper']}'.endsWith('MM')) ...[
        Text('Márgenes: ${_design['page_margin_mm']} mm'),
        Slider(
          min: 5,
          max: 30,
          divisions: 25,
          value: (_design['page_margin_mm'] as num).toDouble(),
          onChanged: (v) => _update('page_margin_mm', v.round()),
        ),
      ],
      _choice('alignment', 'Alineación principal', {
        'left': 'Izquierda',
        'center': 'Centro',
        'right': 'Derecha',
      }),
      Text('Tamaño de texto: ${_design['font_size']} pt'),
      Slider(
        min: 8,
        max: 16,
        divisions: 8,
        value: (_design['font_size'] as num).toDouble(),
        onChanged: (v) => _update('font_size', v.round()),
      ),
      Text('Tamaño de títulos: ${_design['heading_size']} pt'),
      Slider(
        min: 12,
        max: 32,
        divisions: 20,
        value: (_design['heading_size'] as num).toDouble(),
        onChanged: (v) => _update('heading_size', v.round()),
      ),
      Text('Ancho del logo: ${_design['logo_width_mm']} mm'),
      Slider(
        min: 10,
        max: 80,
        divisions: 14,
        value: (_design['logo_width_mm'] as num).toDouble(),
        onChanged: (v) => _update('logo_width_mm', v.round()),
      ),
      const SizedBox(height: 12),
      const Text(
        'Encabezados de las secciones',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      _text('item_section_title', 'Título de detalle de productos'),
      _text('customer_section_title', 'Título de datos del cliente'),
      _text('payment_section_title', 'Título de medios de pago'),
      if (_type == 'FISCAL_INVOICE')
        _text('fiscal_section_title', 'Título de información fiscal'),
      if ('${_design['paper']}'.endsWith('MM')) ...[
        const SizedBox(height: 12),
        const Text(
          'Código QR para el ticket',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        const Text(
          'Enlace a WhatsApp, sitio web o cualquier URL http(s). '
          'El mismo QR aparecerá en el PDF impreso.',
          style: TextStyle(fontSize: 12, color: Color(0xFF9CB1BB)),
        ),
        _toggle('qr_enabled', 'Incluir QR en el comprobante térmico'),
        if (_design['qr_enabled'] == true) ...[
          _text('qr_url', 'Enlace del QR (https://...)'),
          _text('qr_title', 'Título encima del QR'),
          _text('qr_caption', 'Texto debajo del QR'),
          _choice('qr_alignment', 'Alineación del QR', {
            'left': 'Izquierda',
            'center': 'Centro',
            'right': 'Derecha',
          }),
          Text('Tamaño QR: ${_design['qr_size_mm']} mm'),
          Slider(
            min: 18,
            max: 48,
            divisions: 30,
            value: (_design['qr_size_mm'] as num).toDouble(),
            onChanged: (v) => _update('qr_size_mm', v.round()),
          ),
          if (!CompanyPosDocumentDesign.isValidQrLink(
            '${_design['qr_url'] ?? ''}',
          ))
            const Text(
              'Introduce un enlace válido para activar el QR.',
              style: TextStyle(color: Color(0xFFFFBA80)),
            ),
        ],
      ],
      const SizedBox(height: 12),
      const Text(
        'Detalle del contenido',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
      _toggle('show_quantity', 'Mostrar cantidades en la tabla'),
      _toggle('show_unit_price', 'Mostrar precio unitario'),
      _toggle('show_sku', 'Mostrar SKU de productos'),
      _toggle('show_phone', 'Mostrar teléfono del comprador'),
      _toggle('show_email', 'Mostrar correo del comprador'),
      _toggle('show_address', 'Mostrar dirección del comprador'),
      _toggle('show_payment_details', 'Mostrar medios de pago y cambio'),
      _toggle('show_separators', 'Líneas divisorias'),
      const SizedBox(height: 14),
      _sectionOrder(),
      const SizedBox(height: 20),
      OutlinedButton.icon(
        onPressed: () => setState(() {
          _design = CompanyPosDocumentDesign.defaults(_type);
          _dirty = true;
          _previewVersion++;
        }),
        icon: const Icon(Icons.restart_alt),
        label: const Text('Restaurar diseño predeterminado'),
      ),
    ],
  );

  /// Previsualizacion del PDF real, escalada automaticamente para mostrar
  /// cada pagina completa. Abrir PDF conserva el tamaño original.
  Widget _preview() {
    final snapshot = Map<String, dynamic>.from(_design);
    final example = CompanyPosPrinting.demoSale(_type, snapshot);
    final key = ValueKey('pdf_live_${_type}_${_revision}_$_previewVersion');
    return Container(
      color: _panel,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Vista previa real del PDF',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _previewPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Abrir PDF'),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Vista ajustada a la pagina · Datos ficticios · '
            'No genera ventas ni consume CAI.',
            style: TextStyle(color: Color(0xFF9CB1BB), fontSize: 11),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, viewport) {
                final fittedWidth = posPreviewFittedWidth(
                  paper: '${snapshot['paper'] ?? '80MM'}',
                  qrEnabled: snapshot['qr_enabled'] == true,
                  viewportWidth: viewport.maxWidth,
                  viewportHeight: viewport.maxHeight,
                );
                return PdfPreview(
                  key: key,
                  build: (_) =>
                      CompanyPosPrinting.buildPdf(example, demo: true),
                  allowPrinting: false,
                  allowSharing: false,
                  canChangePageFormat: false,
                  canChangeOrientation: false,
                  canDebug: false,
                  maxPageWidth: fittedWidth,
                  onError: (context, error) => Center(
                    child: SelectableText(
                      'No se pudo renderizar el PDF: $error',
                      style: const TextStyle(color: Color(0xFFFFBA80)),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // El ancho efectivo del editor puede ser menor que el del navegador.
        final narrow = constraints.maxWidth < 840;
        final content = Column(
          children: [
            Container(
              padding: const EdgeInsets.all(17),
              color: _panel,
              child: Row(
                children: [
                  const Icon(Icons.design_services_outlined, color: _teal),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Diseñador de comprobantes',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        Text(
                          'Identidad por sucursal, versiones históricas y datos fiscales protegidos',
                          style: TextStyle(
                            color: Color(0xFF9CB1BB),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!widget.embedded)
                    IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'RECEIPT', label: Text('Recibo')),
                      ButtonSegment(
                        value: 'FISCAL_INVOICE',
                        label: Text('Factura'),
                      ),
                    ],
                    selected: {_type},
                    onSelectionChanged: (v) => _switch(v.first),
                  ),
                  Text(
                    'Versión $_revision',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            if (_error != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                color: const Color(0xFF6D2933),
                child: SelectableText(_error!),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : narrow
                  ? _editorPanel()
                  : Row(
                      children: [
                        Expanded(flex: 4, child: _editorPanel()),
                        Expanded(flex: 5, child: _preview()),
                      ],
                    ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(color: _panel),
              child: Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  if (narrow)
                    OutlinedButton(
                      onPressed: _loading ? null : _previewPdf,
                      child: const Text('Vista previa PDF'),
                    ),
                  if (!widget.embedded)
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                  FilledButton.icon(
                    onPressed: _loading || _saving || !_dirty ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Guardando...' : 'Publicar diseño'),
                  ),
                ],
              ),
            ),
          ],
        );
        if (widget.embedded) {
          return ColoredBox(color: _panel, child: content);
        }
        return Dialog(
          insetPadding: const EdgeInsets.all(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 1250,
              maxHeight: MediaQuery.sizeOf(context).height * .90,
            ),
            child: content,
          ),
        );
      },
    );
  }
}
