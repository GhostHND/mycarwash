import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../core/company_business_api.dart';
import 'company_pos_document_design.dart';
import 'company_pos_printing.dart';

/// Diseñador por sucursal: recibo/factura con revisiones inmutables.
/// Los bloques fiscales, importes y números de venta no pueden omitirse.
class CompanyPosTemplateDesigner extends StatefulWidget {
  const CompanyPosTemplateDesigner({
    super.key,
    required this.api,
    required this.branchId,
  });

  final CompanyBusinessApi api;
  final int branchId;

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
      _dirty = true;
    });
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
      if (length != null && length > 100000) {
        setState(
          () => _error = 'El logo supera 100 KB. Optimiza la imagen e inténtalo nuevamente.',
        );
        return;
      }
      final bytes = await picked.readAsBytes();
      if (!mounted) {
        return;
      }
      if (bytes.length > 100000) {
        setState(
          () => _error = 'El logo supera 100 KB. Optimiza la imagen e inténtalo nuevamente.',
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
            .hasMatch('${_design['background_color']}')) {
      setState(() => _error = 'Los colores deben tener formato #RRGGBB.');
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
        'Máximo 100 KB. Se guarda en la plantilla, no en cada venta.',
        style: TextStyle(fontSize: 11, color: Color(0xFF9CB1BB)),
      ),
      const SizedBox(height: 20),
      const Text(
        'Apariencia',
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 10),
      _swatch('primary_color', 'Color principal'),
      _swatch('text_color', 'Color de texto'),
      _swatch('background_color', 'Fondo del comprobante'),
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
        'Detalle del contenido',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
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
        }),
        icon: const Icon(Icons.restart_alt),
        label: const Text('Restaurar diseño predeterminado'),
      ),
    ],
  );

  Widget _preview() {
    final color = _hex(_design['primary_color']);
    final ink = _hex(_design['text_color']);
    final surface = _hex(_design['background_color']);
    final align = '${_design['alignment']}' == 'left'
        ? TextAlign.left
        : '${_design['alignment']}' == 'right'
        ? TextAlign.right
        : TextAlign.center;
    final hidden = List<String>.from(_design['hidden_sections'] as List);
    final order = List<String>.from(_design['sections'] as List);
    final bodySize = (_design['font_size'] as num).toDouble();
    final headingSize = (_design['heading_size'] as num).toDouble();
    final logo = '${_design['logo_base64'] ?? ''}';
    final widgets = <Widget>[];
    final fontFamily = switch ('${_design['font_family']}') {
      'times' => 'serif',
      'courier' => 'monospace',
      _ => 'sans-serif',
    };
    Widget label(String text, {bool title = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontFamily: fontFamily,
          color: title ? color : ink,
          fontSize: title ? headingSize : bodySize,
          fontWeight: title ? FontWeight.w700 : FontWeight.normal,
        ),
      ),
    );
    for (final name in order) {
      if (hidden.contains(name)) {
        continue;
      }
      switch (name) {
        case 'logo':
          if (logo.isNotEmpty) {
            try {
              final bytes = base64Decode(logo);
              widgets.add(
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Image.memory(
                    Uint8List.fromList(bytes),
                    height: (_design['logo_width_mm'] as num).toDouble() * 2.2,
                    fit: BoxFit.contain,
                  ),
                ),
              );
            } catch (_) {
              widgets.add(label('Logo inválido'));
            }
          }
          break;
        case 'brand':
          widgets.add(
            label(
              '${_design['brand_name']}'.trim().isEmpty
                  ? 'MI NEGOCIO'
                  : '${_design['brand_name']}',
              title: true,
            ),
          );
          widgets.add(label('${_design['subtitle']}'));
          break;
        case 'document':
          widgets.add(
            label(
              _type == 'FISCAL_INVOICE' ? 'FACTURA' : 'RECIBO NO FISCAL',
              title: true,
            ),
          );
          widgets.add(label('${_design['title']}'));
          break;
        case 'fiscal':
          if (_type == 'FISCAL_INVOICE') {
            widgets.add(
              label(
                'RTN · CAI · Número · Rango · Fecha límite\n(Datos fiscales protegidos)',
              ),
            );
          }
          break;
        case 'sale':
          widgets.add(label('Venta #EJEMPLO · Fecha 2026-11-17'));
          break;
        case 'customer':
          widgets.add(label('Cliente: CLIENTE DE PRUEBA'));
          if (_design['show_phone'] == true) {
            widgets.add(label('Tel: 0000-0000'));
          }
          if (_design['show_email'] == true) {
            widgets.add(label('Email: demo@ejemplo.test'));
          }
          if (_design['show_address'] == true) {
            widgets.add(label('Dirección de ejemplo'));
          }
          break;
        case 'items':
          if (_design['show_separators'] == true) {
            widgets.add(const Divider());
          }
          widgets.add(
            label(
              '2 x Aromatizante       L 200.00\n1 x Microfibra       L 50.00',
            ),
          );
          if (_design['show_sku'] == true) {
            widgets.add(label('SKU ARO-001 / MCF-002'));
          }
          break;
        case 'totals':
          if (_design['show_separators'] == true) {
            widgets.add(const Divider());
          }
          if (_type == 'FISCAL_INVOICE') {
            widgets.add(label('ISV 15%       L 37.50'));
          }
          widgets.add(
            label(
              _type == 'FISCAL_INVOICE'
                  ? 'TOTAL       L 287.50'
                  : 'TOTAL       L 250.00',
              title: true,
            ),
          );
          break;
        case 'payments':
          widgets.add(
            label(
              _design['show_payment_details'] == true
                  ? 'Efectivo L 250.00 · Cambio L 0.00'
                  : 'Total pagado',
            ),
          );
          break;
        case 'notes':
          widgets.add(label('${_design['custom_note']}'));
          break;
        case 'footer':
          widgets.add(label('${_design['footer_text']}'));
          break;
      }
    }
    widgets.add(const Divider());
    widgets.add(label('VISTA PREVIA — SIN VALIDEZ FISCAL'));
    return Container(
      color: _panel,
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Previsualización',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _previewPdf,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Ver PDF'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'La prueba en PDF usa valores ficticios; no crea ventas ni consume CAI.',
            style: TextStyle(color: Color(0xFF9CB1BB), fontSize: 11),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: SingleChildScrollView(
              child: Center(
                child: Container(
                  width: '${_design['paper']}'.endsWith('MM') ? 300 : 460,
                  constraints: const BoxConstraints(minHeight: 320),
                  padding: const EdgeInsets.all(16),
                  color: surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: widgets,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 840;
    return Dialog(
      insetPadding: const EdgeInsets.all(18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 1250,
          maxHeight: MediaQuery.sizeOf(context).height * .90,
        ),
        child: Column(
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
                  IconButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: SegmentedButton<String>(
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
                  ),
                  const SizedBox(width: 10),
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
              child: Row(
                children: [
                  if (narrow)
                    OutlinedButton(
                      onPressed: _loading ? null : _previewPdf,
                      child: const Text('Vista previa PDF'),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Cerrar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _loading || _saving || !_dirty ? null : _save,
                    icon: const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Guardando...' : 'Publicar diseño'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
