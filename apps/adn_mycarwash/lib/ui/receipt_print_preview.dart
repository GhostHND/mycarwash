import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Vista previa visual, sin emisión ni impresión.
/// El tipo de documento no determina la obligación de ISV.
class ReceiptPrintPreview extends StatefulWidget {
  const ReceiptPrintPreview({
    super.key,
    required this.paper,
    required this.businessName,
    required this.currencyCode,
    required this.decimalPlaces,
    required this.dateFormat,
    required this.timeFormat,
    required this.footer,
  });

  final String paper;
  final String businessName;
  final String currencyCode;
  final int decimalPlaces;
  final String dateFormat;
  final String timeFormat;
  final String footer;

  @override
  State<ReceiptPrintPreview> createState() => _ReceiptPrintPreviewState();
}

class _ReceiptPrintPreviewState extends State<ReceiptPrintPreview> {
  static const _muted = Color(0xFF9BAEB6);
  static const _ink = Color(0xFF171717);
  bool _fiscal = false;

  bool get _thermal => widget.paper.startsWith('thermal_');
  String get _paperLabel => switch (widget.paper) {
    'thermal_58mm' => 'Térmico 58 mm',
    'thermal_80mm' => 'Térmico 80 mm',
    'a4' => 'Hoja A4',
    _ => 'Hoja carta',
  };

  double get _width => switch (widget.paper) {
    'thermal_58mm' => 219.0,
    'thermal_80mm' => 302.0,
    'a4' => 794.0,
    _ => 816.0,
  };

  String _money(num amount) {
    final decimals = widget.decimalPlaces.clamp(0, 4).toInt();
    final code = widget.currencyCode.trim().toUpperCase();
    final symbol = code == 'HNL' ? 'L' : (code.isEmpty ? 'L' : code);
    return '$symbol ${amount.toStringAsFixed(decimals)}';
  }

  String get _date => switch (widget.dateFormat) {
    'MM/dd/yyyy' => '11/15/2026',
    'yyyy-MM-dd' => '2026-11-15',
    _ => '15/11/2026',
  };

  String get _time => widget.timeFormat == '12h' ? '2:35 p. m.' : '14:35';

  Widget _line(String title, String value, double size, {bool strong = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: _ink,
                fontSize: size,
                fontWeight: strong ? FontWeight.w800 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: _ink,
              fontSize: size,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _receipt(double width) {
    final size = _thermal
        ? (widget.paper == 'thermal_58mm' ? 10.0 : 11.0)
        : 14.0;
    final padding = _thermal ? 12.0 : 43.0;
    const sampleTotal = 200.0;
    const sampleIsvRate = 0.15;
    // Ejemplo de desglose fiscal del impuesto INCLUIDO en un precio final.
    // No constituye motor tributario ni autoriza omitir impuestos.
    const taxableBase = sampleTotal / (1 + sampleIsvRate);
    const includedTax = sampleTotal - taxableBase;
    final business = widget.businessName.trim().isEmpty
        ? 'MI EMPRESA'
        : widget.businessName.trim().toUpperCase();
    final aspect = widget.paper == 'a4' ? 1.414 : 1.294;
    return Container(
      key: const ValueKey('receipt_preview_paper'),
      width: width,
      constraints: BoxConstraints(minHeight: _thermal ? 0.0 : width * aspect),
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE0E0E0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33000000),
            blurRadius: 12,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: _ink, fontSize: size),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'VISTA PREVIA · NO VÁLIDA PARA EMISIÓN',
              key: const ValueKey('receipt_demo_stamp'),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: size * 0.9,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              business,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: size * 1.35,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              _fiscal
                  ? 'FACTURA FISCAL · VISTA PREVIA'
                  : 'RECIBO SIN VALOR FISCAL',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: size * 1.13,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 5),
            if (_fiscal) ...[
              Text('RTN del emisor: [CONFIGURAR]', textAlign: TextAlign.center),
              Text(
                'CAI: [AUTORIZACIÓN PENDIENTE]',
                textAlign: TextAlign.center,
              ),
              Text(
                'Rango autorizado: [PENDIENTE]',
                textAlign: TextAlign.center,
              ),
              Text('Fecha límite: [PENDIENTE]', textAlign: TextAlign.center),
              Text('Factura N.º: [PENDIENTE]', textAlign: TextAlign.center),
            ] else ...[
              const Text(
                'SIN CAI · NO ES FACTURA',
                textAlign: TextAlign.center,
              ),
            ],
            const Divider(height: 24, color: Color(0xFF555555)),
            Text('Orden: VISTA PREVIA'),
            Text('Fecha: $_date · Hora: $_time'),
            const Text('Cliente: Consumidor final (muestra)'),
            const Divider(height: 24, color: Color(0xFF555555)),
            _line('1 × Lavado exterior', _money(150), size),
            _line('1 × Aspirado', _money(50), size),
            const Divider(height: 24, color: Color(0xFF555555)),
            if (_fiscal) ...[
              _line('Base gravada (muestra)', _money(taxableBase), size),
              _line('ISV 15 % incluido', _money(includedTax), size),
            ] else ...[
              _line('Servicios', _money(sampleTotal), size),
            ],
            _line(
              'TOTAL A PAGAR',
              _money(sampleTotal),
              size * 1.12,
              strong: true,
            ),
            const SizedBox(height: 8),
            const Text('Forma de pago: Efectivo (muestra)'),
            const Divider(height: 24, color: Color(0xFF555555)),
            if (widget.footer.trim().isNotEmpty) ...[
              Text(widget.footer.trim(), textAlign: TextAlign.center),
              const SizedBox(height: 10),
            ],
            Text(
              _fiscal
                  ? 'VISTA PREVIA SIN VALIDEZ FISCAL. REQUIERE CAI VIGENTE.'
                  : 'COMPROBANTE OPERATIVO. NO SUSTITUYE FACTURA FISCAL.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: _ink,
                fontSize: size * 0.9,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Vista previa del documento impreso',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '$_paperLabel · Vista ilustrativa. No corresponde a una venta registrada.',
          style: const TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const ValueKey('receipt_preview_nonfiscal'),
              label: const Text('Recibo sin valor fiscal'),
              selected: !_fiscal,
              onSelected: (_) => setState(() => _fiscal = false),
            ),
            ChoiceChip(
              key: const ValueKey('receipt_preview_fiscal'),
              label: const Text('Factura con CAI (vista previa)'),
              selected: _fiscal,
              onSelected: (_) => setState(() => _fiscal = true),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF111F25),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF20343C)),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : 500.0;
              final width = math.min(maxWidth, _width);
              return Align(
                alignment: Alignment.topCenter,
                child: _receipt(width),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Vista previa solamente: no imprime, no genera folios ni modifica la venta. '
          'El documento elegido no cambia por sí mismo la obligación tributaria. '
          'La factura real requerirá CAI, rango, vencimiento y autorización fiscal válidos.',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
      ],
    );
  }
}
