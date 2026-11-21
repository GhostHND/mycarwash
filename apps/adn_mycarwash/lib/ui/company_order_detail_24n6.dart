import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';
import '../core/mycarwash_session.dart';

/// Detalle administrativo de una orden. No reemplaza las rutas ni los
/// formularios existentes: consulta la orden por su ID y usa sus callbacks.
class CompanyOrderDetail24N6 extends StatefulWidget {
  const CompanyOrderDetail24N6({
    super.key,
    required this.orderId,
    required this.client,
    required this.onEdit,
    required this.onAdvance,
  });

  final int orderId;
  final http.Client client;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onAdvance;

  @override
  State<CompanyOrderDetail24N6> createState() => _CompanyOrderDetail24N6State();
}

class _CompanyOrderDetail24N6State extends State<CompanyOrderDetail24N6> {
  Map<String, dynamic>? _order;
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;
  bool _acting = false;
  String? _error;
  int _requestVersion = 0;

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);
  Color get _accent => CompanyVisualTheme.primary;
  Color get _text => CompanyVisualTheme.text;
  Color get _muted => CompanyVisualTheme.muted;
  Color get _line => CompanyVisualTheme.border;
  Color get _card => CompanyVisualTheme.card;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant CompanyOrderDetail24N6 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.orderId != widget.orderId) {
      _order = null;
      _history = [];
      _refresh();
    }
  }

  @override
  void dispose() {
    _requestVersion++;
    super.dispose();
  }

  Future<void> _refresh() async {
    final version = ++_requestVersion;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.request('GET', '/workflow/orders/${widget.orderId}'),
        _api.request('GET', '/workflow/orders/${widget.orderId}/history'),
      ]);
      if (!mounted || version != _requestVersion) return;
      final row = results[0]['data'];
      if (row is! Map) throw const FormatException('Orden no disponible.');
      final history = results[1]['data'];
      setState(() {
        _order = Map<String, dynamic>.from(row);
        _history = history is List
            ? history.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
            : [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted || version != _requestVersion) return;
      setState(() { _error = '$e'; _loading = false; });
    }
  }

  static String _read(dynamic value, [String fallback = 'No registrado']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty || text == 'null' ? fallback : text;
  }

  static String _status(String code) => switch (code) {
    'EN_ESPERA' => 'En espera',
    'ASIGNADO' => 'Asignado',
    'EN_PROCESO' => 'En proceso',
    'TERMINADO' => 'Terminado',
    'ENTREGADO' => 'Entregado',
    'CANCELADO' => 'Cancelado',
    _ => code.isEmpty ? 'Sin estado' : code.replaceAll('_', ' '),
  };

  Color _statusColor(String code) => switch (code) {
    'EN_ESPERA' => CompanyVisualTheme.warning,
    'EN_PROCESO' || 'ASIGNADO' => CompanyVisualTheme.primary,
    'TERMINADO' || 'ENTREGADO' => CompanyVisualTheme.success,
    'CANCELADO' => CompanyVisualTheme.danger,
    _ => CompanyVisualTheme.muted,
  };

  String _money(dynamic value) {
    final number = double.tryParse('$value');
    return number == null ? 'No disponible' : 'L ${number.toStringAsFixed(2)}';
  }

  String _date(dynamic value, String fallback) {
    final text = _read(value, '');
    if (text.isEmpty) return fallback;
    final valueUtc = DateTime.tryParse(
      text.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text)
          ? text.replaceFirst(' ', 'T')
          : '${text.replaceFirst(' ', 'T')}Z',
    );
    if (valueUtc == null) return text;
    final parsed = valueUtc.toUtc().subtract(const Duration(hours: 6));
    String two(int v) => v.toString().padLeft(2, '0');
    final hour = parsed.hour % 12 == 0 ? 12 : parsed.hour % 12;
    final period = parsed.hour < 12 ? 'a. m.' : 'p. m.';
    return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year} '
        '$hour:${two(parsed.minute)}:${two(parsed.second)} $period';
  }

  double? _progress(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    if (status == 'TERMINADO' || status == 'ENTREGADO') return 1;
    if (status != 'EN_PROCESO') return 0;
    final startText = '${row['started_at'] ?? ''}'.replaceFirst(' ', 'T');
    final started = DateTime.tryParse(
      startText.isEmpty ? startText : (startText.endsWith('Z') ? startText : '${startText}Z'),
    );
    final minutes = double.tryParse('${row['estimated_minutes'] ?? ''}');
    if (started == null || minutes == null || minutes <= 0) return null;
    return (DateTime.now().difference(started).inSeconds / (minutes * 60))
        .clamp(0.0, 1.0).toDouble();
  }

  Widget _panel(Widget child, {EdgeInsetsGeometry? padding}) => Container(
    width: double.infinity,
    padding: padding ?? const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _line, width: 1),
    ),
    child: child,
  );

  Widget _vehicleImage(Map<String, dynamic> row) {
    final id = int.tryParse('${row['vehicle_id'] ?? ''}');
    final placeholder = Icon(Icons.directions_car_outlined, size: 66, color: _muted);
    if (id == null || id <= 0 || row['vehicle_photo_exists'] != true) {
      return Center(child: placeholder);
    }
    return Image.network(
      '${MyCarWashSession.apiBaseUrl}/companies/'
      '${MyCarWashSession.companyId}/media/vehicles/$id/file',
      headers: MyCarWashSession.headers,
      fit: BoxFit.contain,
      alignment: Alignment.center,
      errorBuilder: (context, error, stackTrace) => Center(child: placeholder),
    );
  }

  Widget _vehicle(Map<String, dynamic> row) {
    final brandLogo = _read(row['brand_logo_url'], '');
    final vehicleName = _read(row['vehicle_name'] ?? row['vehicle_label'], 'Vehículo sin identificar');
    return _panel(LayoutBuilder(builder: (context, size) {
      final compact = size.maxWidth < 360;
      final photo = Container(
        width: compact ? double.infinity : 190,
        height: 136,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: CompanyVisualTheme.surface,
          borderRadius: BorderRadius.circular(13),
        ),
        child: _vehicleImage(row),
      );
      final details = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (brandLogo.startsWith('https://'))
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Image.network(
                brandLogo, width: 47, height: 32, fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
              ),
            ),
          Text(vehicleName, softWrap: true, style: TextStyle(
            color: _text, fontSize: 20, fontWeight: FontWeight.w800,
          )),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              border: Border.all(color: _accent),
              borderRadius: BorderRadius.circular(21),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.badge_outlined, color: _accent, size: 18),
              const SizedBox(width: 7),
              Flexible(child: Text(_read(row['plate'], 'Sin placa'),
                softWrap: true, style: TextStyle(color: _text, fontWeight: FontWeight.w700))),
            ]),
          ),
        ],
      );
      if (compact) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          photo, const SizedBox(height: 12), details,
        ]);
      }
      return Row(children: [photo, const SizedBox(width: 15), Expanded(child: details)]);
    }));
  }

  Widget _stateAndProgress(Map<String, dynamic> row) {
    final state = '${row['status'] ?? ''}';
    final progress = _progress(row);
    return _panel(LayoutBuilder(builder: (context, limits) {
      final compact = limits.maxWidth < 360;
      final status = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Estado actual', style: TextStyle(color: _muted)),
        const SizedBox(height: 13),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _statusColor(state).withValues(alpha: .18),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.sync, color: _statusColor(state), size: 20),
            const SizedBox(width: 8),
            Text(_status(state), style: TextStyle(
              color: _statusColor(state), fontWeight: FontWeight.w800,
            )),
          ]),
        ),
      ]);
      final chart = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Progreso estimado', style: TextStyle(color: _muted)),
        const SizedBox(height: 8),
        Text(progress == null ? 'No disponible' : '${(progress * 100).round()} %',
          style: TextStyle(color: _accent, fontSize: progress == null ? 16 : 29,
            fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        ClipRRect(borderRadius: BorderRadius.circular(12), child: LinearProgressIndicator(
          minHeight: 12, value: progress ?? 0,
          backgroundColor: _line, valueColor: AlwaysStoppedAnimation<Color>(_accent),
        )),
      ]);
      if (compact) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          status, const SizedBox(height: 18), chart,
        ]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: status),
        Container(width: 1, height: 92, color: _line, margin: const EdgeInsets.symmetric(horizontal: 17)),
        Expanded(child: chart),
      ]);
    }));
  }

  Widget _field(IconData icon, String title, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: _accent, size: 23),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: _muted, fontSize: 12)),
        const SizedBox(height: 3),
        SelectableText(value, style: TextStyle(color: _text,
          fontWeight: FontWeight.w700, fontSize: 15)),
      ])),
    ],
  );

  Widget _information(Map<String, dynamic> row) {
    final assignments = row['assignments'] is List ? row['assignments'] as List : [];
    final washers = assignments.whereType<Map>()
        .map((a) => '${a['full_name'] ?? ''}${a['is_primary'] == true || a['is_primary'] == 1 ? ' (principal)' : ''}')
        .where((name) => name.trim().isNotEmpty).join(', ');
    final items = <Widget>[
      _field(Icons.person_outline, 'Cliente', _read(row['client_name'])),
      _field(Icons.local_car_wash_outlined, 'Servicio', _read(row['service_name'])),
      _field(Icons.garage_outlined, 'Bahía / Puesto', _read(row['bay_name'], 'Sin asignar')),
      _field(Icons.calendar_today_outlined, 'Inicio', _date(row['started_at'], 'Sin iniciar')),
      _field(Icons.outlined_flag, 'Finalización', _date(row['completed_at'], 'Sin terminar')),
      _field(Icons.sell_outlined, 'Importe cotizado', _money(row['quoted_price'])),
      _field(Icons.groups_outlined, 'Lavadores asignados', washers.isEmpty ? 'Sin asignar' : washers),
    ];
    return _panel(LayoutBuilder(builder: (context, bounds) {
      final columns = bounds.maxWidth >= 850 ? 3 : bounds.maxWidth >= 520 ? 2 : 1;
      final gap = 14.0;
      final width = (bounds.maxWidth - (columns - 1) * gap) / columns;
      return Wrap(spacing: gap, runSpacing: 22,
        children: [for (final item in items) SizedBox(width: width, child: item)],
      );
    }));
  }

  Widget _serviceLinesB25H(Map<String, dynamic> order) {
    final raw = order['service_lines_b25'];
    if (raw is! List || raw.isEmpty) return const SizedBox.shrink();
    final lines = raw.whereType<Map>().toList();
    final total = lines.fold<double>(0, (sum, line) =>
        sum + (double.tryParse('${line['price']}') ?? 0));
    final commission = lines.fold<double>(0, (sum, line) =>
        sum + (double.tryParse('${line['commission_amount']}') ?? 0));
    return _panel(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [Icon(Icons.format_list_bulleted, color: _accent),
        const SizedBox(width: 10), Expanded(child: Text('Servicios de esta orden',
          style: TextStyle(color: _text, fontSize: 20, fontWeight: FontWeight.w800)))]),
      const SizedBox(height: 12),
      for (var i = 0; i < lines.length; i++) ...[
        if (i > 0) Divider(color: _line),
        LayoutBuilder(builder: (context, size) {
          final line = lines[i];
          final service = _read(line['service_name'], 'Servicio ${i+1}');
          return Wrap(spacing: 16, runSpacing: 7, alignment: WrapAlignment.spaceBetween, children: [
            SizedBox(width: size.maxWidth > 650 ? size.maxWidth * .36 : size.maxWidth,
              child: Text(service, style: TextStyle(color: _text, fontWeight: FontWeight.w700))),
            Text('Precio: ${_money(line['price'])}', style: TextStyle(color: _text)),
            Text('Comisión: ${line['commission_percent'] ?? 0} %', style: TextStyle(color: _muted)),
            Text('Importe comisión: ${_money(line['commission_amount'])}', style: TextStyle(color: _accent)),
          ]);
        }),
      ],
      Divider(color: _line),
      Wrap(spacing: 24, runSpacing: 8, children: [
        Text('Total del cliente: L ${total.toStringAsFixed(2)}',
          style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
        Text('Comisión prevista: L ${commission.toStringAsFixed(2)}',
          style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
      ]),
      const SizedBox(height: 5),
      Text('La comisión prevista no implica pago autorizado: requiere asistencia válida y trabajo terminado.',
        style: TextStyle(color: _muted, fontSize: 11)),
    ]));
  }

  Widget _timeline() {
    final events = _history;
    return _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.history, color: _accent, size: 26),
        const SizedBox(width: 10),
        Text('Historial de la orden', style: TextStyle(
          color: _text, fontSize: 20, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 17),
      if (events.isEmpty) Text('Sin eventos registrados', style: TextStyle(color: _muted)),
      for (var i = 0; i < events.length; i++)
        _timelineEvent(events[i], i == events.length - 1, i != events.length - 1),
    ]));
  }

  Widget _timelineEvent(Map<String, dynamic> event, bool last, bool connecting) {
    final to = '${event['to_status'] ?? ''}';
    final stamp = _date(event['occurred_at'], 'Fecha no disponible');
    final reason = _read(event['reason'], '');
    return Container(
      decoration: BoxDecoration(
        color: last ? _accent.withValues(alpha: .09) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Column(children: [
          Icon(last ? Icons.radio_button_checked : Icons.check_circle,
            color: _accent, size: 24),
          if (connecting) Container(width: 2, height: 25, color: _accent),
        ]),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_status(to), style: TextStyle(color: _text,
            fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 3),
          Text(stamp, style: TextStyle(color: _muted, fontSize: 12)),
          if (reason.isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 3),
              child: Text(reason, style: TextStyle(color: _muted, fontSize: 12))),
        ])),
        if (last) Text('Actual', style: TextStyle(color: _accent, fontSize: 12)),
      ]),
    );
  }

  Future<void> _edit() async {
    if (_order == null || _acting) return;
    setState(() => _acting = true);
    try {
      await widget.onEdit(Map<String, dynamic>.from(_order!));
      await _refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  String? _nextStatus(Map<String, dynamic> order) => switch ('${order['status']}') {
    'ASIGNADO' => 'EN_PROCESO',
    'EN_PROCESO' => 'TERMINADO',
    'TERMINADO' => 'ENTREGADO',
    _ => null,
  };

  Future<void> _advance() async {
    final row = _order;
    if (row == null || _acting) return;
    final next = _nextStatus(row);
    if (next == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar cambio de estado'),
        content: Text('Orden: ${_read(row['tracking_code'])}\n'
          'Vehículo: ${_read(row['vehicle_label'])}\n'
          'Placa: ${_read(row['plate'])}\n'
          'Estado actual: ${_status('${row['status']}')}\n'
          'Nuevo estado: ${_status(next)}\n\n'
          '${next == 'TERMINADO' ? 'Se registrará la finalización y el monitor podrá mostrar “Lavado terminado”.' : 'Esta operación actualizará la orden cuando el servidor la confirme.'}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _acting = true);
    try {
      await widget.onAdvance(Map<String, dynamic>.from(row));
      await _refresh();
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewport = MediaQuery.sizeOf(context);
    final width = (viewport.width * .87).clamp(290.0, 1320.0).toDouble();
    final height = (viewport.height * .92).clamp(320.0, 900.0).toDouble();
    return ValueListenableBuilder<CompanyPalette>(
      valueListenable: CompanyVisualTheme.current,
      builder: (context, palette, child) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: width,
          height: height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: CompanyVisualTheme.surface,
              border: Border.all(color: _accent),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 18, 14, 13),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(Icons.assignment_turned_in_outlined,
                      size: 29, color: _accent),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Detalle de orden', style: TextStyle(
                      color: _text, fontWeight: FontWeight.w800, fontSize: 24)),
                    const SizedBox(height: 3),
                    SelectableText(_read(_order?['tracking_code'], 'Cargando orden...'),
                      style: TextStyle(color: _muted)),
                  ])),
                  if (_order != null)
                    IconButton(tooltip: 'Copiar código',
                      onPressed: () => Clipboard.setData(ClipboardData(
                        text: '${_order?['tracking_code'] ?? ''}')),
                      icon: Icon(Icons.copy_outlined, color: _muted)),
                  IconButton(tooltip: 'Cerrar',
                    onPressed: _acting ? null : () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: _text)),
                ])),
              Divider(height: 1, color: _line),
              Expanded(child: _loading
                ? Center(child: CircularProgressIndicator(color: _accent))
                : _error != null
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text('No se pudo cargar la orden', style: TextStyle(color: _text)),
                    const SizedBox(height: 8),
                    Text(_error!, style: TextStyle(color: _muted)),
                    TextButton(onPressed: _refresh, child: const Text('Reintentar')),
                  ]))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(18),
                    child: LayoutBuilder(builder: (context, constraints) {
                      final row = _order!;
                      final wide = constraints.maxWidth >= 950;
                      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        if (wide) Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(child: _vehicle(row)),
                          const SizedBox(width: 12),
                          Expanded(child: _stateAndProgress(row)),
                        ]) else ...[
                          _vehicle(row), const SizedBox(height: 12),
                          _stateAndProgress(row),
                        ],
                        const SizedBox(height: 13),
                        _information(row),
                        const SizedBox(height: 13),
                        _serviceLinesB25H(row),
                        const SizedBox(height: 13),
                        _timeline(),
                      ]);
                    }),
                  )),
              Divider(height: 1, color: _line),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 13),
                child: Wrap(alignment: WrapAlignment.end, spacing: 10, runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      key: const ValueKey('order_detail_edit_24n6'),
                      onPressed: (_loading || _error != null || _acting) ? null : _edit,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Editar orden'),
                    ),
                    if (_order != null && _nextStatus(_order!) != null)
                      FilledButton.icon(
                        key: const ValueKey('order_detail_status_24n6'),
                        onPressed: _acting || _loading ? null : _advance,
                        icon: const Icon(Icons.check),
                        label: const Text('Cambiar estado'),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
