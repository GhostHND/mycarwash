import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/business_identity.dart';
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';

/// B25L. Reporte administrativo de comisiones reconocidas, no constancia de pago.
class CompanyCommissionReportB25L extends StatefulWidget {
  const CompanyCommissionReportB25L({super.key});
  @override
  State<CompanyCommissionReportB25L> createState() => _CommissionReportState();
}

class _CommissionReportState extends State<CompanyCommissionReportB25L> {
  final http.Client _client = http.Client();
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  late DateTime _from;
  late DateTime _to;
  String _period = 'Hoy';
  String _paper = 'Carta';
  int? _employee;
  String _reportScope = 'general';
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  List<Map<String, dynamic>> _staff = [];
  String? _staffError;
  bool _staffLoading = false;
  List<Map<String, dynamic>> _rows = [];
  Map<String, dynamic> _totals = {};

  static String _date(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static double _amount(dynamic v) => double.tryParse('$v') ?? 0;
  static String _money(dynamic v) => 'L ${_amount(v).toStringAsFixed(2)}';

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _from = DateTime(today.year, today.month, today.day);
    _to = _from;
    _initialize();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  Future<void> _initialize() async {
    await _loadStaff();
    await _load();
  }

  Future<void> _loadStaff() async {
    if (!mounted) return;
    setState(() { _staffLoading = true; _staffError = null; });
    try {
      final staff = <Map<String, dynamic>>[];
      // Misma paginacion comprobada en Personal (6 empleados por pagina).
      // No exigir per_page=200: algunas APIs rechazan ese limite.
      for (var page = 1; page <= 100; page++) {
        final resp = await _api.request('GET', '/employees', query: {
          'q': '', 'page': '$page', 'per_page': '6',
        });
        final data = resp['data'];
        if (data is! List) {
          throw const FormatException('La respuesta de /employees no contiene una lista data.');
        }
        staff.addAll(data.whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r)));
        final lastPage = int.tryParse('${resp['last_page'] ?? page}') ?? page;
        if (page >= lastPage || data.isEmpty) break;
        if (page == 100) {
          throw const FormatException('Se excedio el limite de paginas del catalogo de empleados.');
        }
      }
      if (!mounted) return;
      setState(() { _staff = staff; _staffError = null; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _staffError = 'No fue posible consultar el personal: $e'; });
    } finally {
      if (mounted) setState(() => _staffLoading = false);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await _api.request('GET', '/commissions/report-b25l', query: {
        'from': _date(_from), 'to': _date(_to),
        if (_employee != null) 'employee_id': '$_employee',
      });
      final data = Map<String, dynamic>.from(resp['data'] as Map);
      if (!mounted) return;
      setState(() {
        _rows = (data['rows'] as List? ?? []).whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r)).toList();
        _totals = data;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _choosePeriod(String period) {
    final n = DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    setState(() {
      _period = period;
      switch (period) {
        case 'Hoy':
          _from = today; _to = today;
        case 'Semana':
          _from = today.subtract(Duration(days: today.weekday - 1));
          _to = _from.add(const Duration(days: 6));
        case 'Mes':
          _from = DateTime(today.year, today.month);
          _to = DateTime(today.year, today.month + 1, 0);
        case 'Año':
          _from = DateTime(today.year);
          _to = DateTime(today.year, 12, 31);
      }
    });
    _load();
  }

  Future<void> _chooseCustom() async {
    final range = await showDateRangePicker(
      context: context, firstDate: DateTime(2020), lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(start: _from, end: _to),
    );
    if (range == null || !mounted) return;
    if (range.duration.inDays > 366) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecciona un máximo de 367 días.')));
      return;
    }
    setState(() { _from = range.start; _to = range.end; _period = 'Personalizado'; });
    _load();
  }

  static PdfColor _pdfColor(Color c) => PdfColor(c.r, c.g, c.b);
  Future<void> _pdf() async {
    if (_loading || _exporting || _error != null ||
        (_reportScope == 'individual' && _employee == null)) {
      return;
    }
    setState(() => _exporting = true);
    try {
      final identity = BusinessIdentity.current.value;
      final palette = CompanyVisualTheme.current.value;
      final accent = _pdfColor(palette.primary);
      final secondary = _pdfColor(palette.secondary);
      final logo = identity.logoBytes == null ? null : pw.MemoryImage(identity.logoBytes!);
      final pdf = pw.Document();
      final employeeName = _reportScope == 'general' ? 'Todos los lavadores' :
          _staff.where((e) => '${e['id']}' == '$_employee')
              .map((e) => '${e['full_name']}').firstOrNull ?? 'Lavador seleccionado';
      final rows = _rows.map((r) => <String>[
        '${r['date'] ?? ''}', '${r['time'] ?? ''}', '${r['employee_name'] ?? ''}',
        '${r['plate'] ?? ''} ${r['vehicle'] ?? ''}', '${r['service_name'] ?? ''}',
        _money(r['price']), '${r['percent'] ?? ''}%', _money(r['commission']),
        r['recognized'] == true ? 'Reconocida' : 'Sin asistencia',
      ]).toList();
      pdf.addPage(pw.MultiPage(
        pageFormat: _paper == 'A4' ? PdfPageFormat.a4.landscape : PdfPageFormat.letter.landscape,
        maxPages: 200, margin: const pw.EdgeInsets.all(28),
        header: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: accent, width: 2))),
          child: pw.Row(children: [
            if (logo != null) ...[pw.Image(logo, height: 52, width: 68, fit: pw.BoxFit.contain), pw.SizedBox(width: 12)],
            pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(identity.companyName.isEmpty ? 'Mi Empresa' : identity.companyName,
                  style: pw.TextStyle(color: secondary, fontWeight: pw.FontWeight.bold, fontSize: 16)),
              pw.Text(_reportScope == 'general' ? 'REPORTE GENERAL DE COMISIONES' : 'REPORTE INDIVIDUAL DE COMISIONES',
                  style: pw.TextStyle(color: accent, fontWeight: pw.FontWeight.bold, fontSize: 9)),
              pw.Text('${_date(_from)} a ${_date(_to)} · $employeeName', style: const pw.TextStyle(fontSize: 9)),
            ])),
          ]),
        ),
        footer: (ctx) => pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('ADN MyCarWash · Comisiones devengadas, no comprobante de pago', style: const pw.TextStyle(fontSize: 8)),
          pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}', style: const pw.TextStyle(fontSize: 8)),
        ]),
        build: (ctx) => [
          pw.SizedBox(height: 12),
          pw.Text(_reportScope == 'general' ? 'Reporte general de producción' : 'Reporte individual de producción', style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: secondary)),
          pw.SizedBox(height: 9),
          pw.Text('Comisiones reconocidas: ${_money(_totals['total_recognized'])}',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: accent)),
          pw.Text('Pendientes de validar asistencia: ${_money(_totals['total_pending'])}',
              style: const pw.TextStyle(fontSize: 11)),
          pw.Text('Servicios: ${_totals['total_services'] ?? 0}', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 15),
          if (rows.isEmpty) pw.Text('No hay trabajos para este período.')
          else pw.TableHelper.fromTextArray(
            headers: const ['Fecha','Hora','Lavador','Vehículo','Servicio','Precio','%','Comisión','Estado'],
            data: rows, headerDecoration: pw.BoxDecoration(color: accent),
            headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 7, fontWeight: pw.FontWeight.bold),
            cellStyle: const pw.TextStyle(fontSize: 7),
            cellPadding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 5),
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
          ),
          pw.SizedBox(height: 10),
          pw.Text('Las comisiones reconocidas son costo de personal devengado. No se consideran pagadas hasta registrar una liquidación. No volver a restarlas como egreso si ya fueron descontadas del balance.',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        ],
      ));
      final bytes = await pdf.save();
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'Comisiones_${_date(_from)}_${_date(_to)}');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo exportar el PDF: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  bool _isWasher(Map<String, dynamic> employee) {
    final position = '${employee['position'] ?? ''}'.trim().toLowerCase();
    return position == 'washer' || position == 'lavador';
  }

  List<Map<String, dynamic>> get _washers => _staff.where(_isWasher).toList();

  void _setScope(String scope) {
    if (_reportScope == scope) return;
    setState(() {
      _reportScope = scope;
      _employee = scope == 'general' ? null :
          (_washers.isEmpty ? null : int.tryParse('${_washers.first['id']}'));
    });
    if (scope == 'general' || _employee != null) {
      _load();
    } else {
      setState(() { _rows = []; _totals = {}; });
    }
  }

  Widget _metric(String label, String value, IconData icon, double width) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: 112),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.primary),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Container(width: 46, height: 46,
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: .12),
            border: Border.all(color: cs.primary),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: cs.primary, size: 23)),
        const SizedBox(width: 14),
        Expanded(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
            const SizedBox(height: 6),
            Text(value, style: TextStyle(color: cs.onSurface,
              fontSize: 25, fontWeight: FontWeight.w800)),
          ],
        )),
      ]),
    );
  }

  Widget _filterPill(String period) {
    final cs = Theme.of(context).colorScheme;
    return OutlinedButton(
      onPressed: () => _choosePeriod(period),
      style: OutlinedButton.styleFrom(
        backgroundColor: _period == period ? cs.primary.withValues(alpha: .18) : cs.surface,
        side: BorderSide(color: _period == period ? cs.primary : cs.outline),
        shape: const StadiumBorder(),
      ),
      child: Text(period),
    );
  }

  Widget _summaryCard(Map<String, dynamic> employee, double width) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: width,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border.all(color: cs.primary),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${employee['name'] ?? 'Lavador'}', style: TextStyle(
            fontSize: 17, fontWeight: FontWeight.w800, color: cs.onSurface)),
          const SizedBox(height: 11),
          Text('Comisión reconocida: ${_money(employee['recognized'])}'),
          const SizedBox(height: 4),
          Text('Servicios: ${employee['services'] ?? 0}'),
          const SizedBox(height: 4),
          Text('Pendiente por asistencia: ${_money(employee['pending'])}',
            style: TextStyle(color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summaries = (_totals['employees'] as List? ?? []).whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r)).toList();
    return Padding(
      padding: const EdgeInsets.all(22),
      child: LayoutBuilder(builder: (context, constraints) {
        final width = constraints.maxWidth;
        final metricWidth = width >= 980 ? (width - 28) / 3 :
            (width >= 600 ? (width - 14) / 2 : width);
        final employeeWidth = width >= 850 ? (width - 28) / 3 :
            (width >= 560 ? (width - 14) / 2 : width);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border.all(color: cs.primary),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(children: [
                Container(
                  width: 54, height: 54,
                  decoration: BoxDecoration(
                    border: Border.all(color: cs.primary),
                    borderRadius: BorderRadius.circular(14),
                    color: cs.primary.withValues(alpha: .10),
                  ),
                  child: Icon(Icons.payments_outlined, color: cs.primary, size: 29),
                ),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Producción y comisiones de lavadores',
                      style: TextStyle(fontSize: width < 540 ? 20 : 25,
                        fontWeight: FontWeight.w800, color: cs.onSurface)),
                    const SizedBox(height: 3),
                    Text('Trabajos realizados, vehículo, horario, porcentaje y comisión reconocida.',
                      style: TextStyle(color: cs.onSurface, fontSize: 13)),
                    const SizedBox(height: 5),
                    Text('Reportes por período y empleado con detalle verificable',
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
                  ],
                )),
              ]),
            ),
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border.all(color: cs.outline),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Wrap(
                spacing: 9, runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final period in ['Hoy', 'Semana', 'Mes', 'Año']) _filterPill(period),
                  OutlinedButton.icon(
                    onPressed: _chooseCustom,
                    icon: const Icon(Icons.date_range_outlined, size: 18),
                    label: Text('${_date(_from)} — ${_date(_to)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Actualizar'),
                  ),
                  DropdownButton<String>(
                    value: _paper,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'Carta', child: Text('Carta')),
                      DropdownMenuItem(value: 'A4', child: Text('A4')),
                    ],
                    onChanged: (v) => setState(() => _paper = v ?? 'Carta'),
                  ),
                  FilledButton.icon(
                    onPressed: _loading || _exporting || _error != null ||
                        (_reportScope == 'individual' && _employee == null) ? null : _pdf,
                    icon: const Icon(Icons.picture_as_pdf_outlined, size: 19),
                    label: Text(_exporting ? 'Preparando PDF...' : 'Imprimir / guardar PDF'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12, runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('TIPO DE REPORTE', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: cs.onSurfaceVariant)),
                ChoiceChip(
                  label: const Text('General · Todos los lavadores'),
                  selected: _reportScope == 'general',
                  onSelected: (_) => _setScope('general'),
                ),
                ChoiceChip(
                  label: const Text('Individual · Un lavador'),
                  selected: _reportScope == 'individual',
                  onSelected: (_) => _setScope('individual'),
                ),
                if (_reportScope == 'individual')
                  Container(
                    constraints: BoxConstraints(maxWidth: width < 450 ? width : 300),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: cs.surface,
                      border: Border.all(color: cs.primary),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: DropdownButton<int>(
                      value: _washers.any((e) => int.tryParse('${e['id']}') == _employee)
                          ? _employee : null,
                      isExpanded: true,
                      underline: const SizedBox.shrink(),
                      hint: const Text('Seleccionar lavador'),
                      items: [
                        for (final e in _washers)
                          DropdownMenuItem<int>(
                            value: int.tryParse('${e['id']}'),
                            child: Text('${e['full_name']}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() => _employee = value);
                        if (value != null) _load();
                      },
                    ),
                  ),
              ],
            ),
            if (_reportScope == 'individual' && _staffLoading)
              const Padding(
                padding: EdgeInsets.only(top: 9),
                child: LinearProgressIndicator(),
              ),
            if (_reportScope == 'individual' && _staffError != null)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text(_staffError!, style: TextStyle(color: cs.error)),
              ),
            if (_reportScope == 'individual' && !_staffLoading &&
                _staffError == null && _washers.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Text('El catálogo respondió sin lavadores activos identificables.',
                  style: TextStyle(color: cs.error)),
              ),
            if (_loading) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
            ],
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(_error!, style: TextStyle(color: cs.error)),
            ),
            const SizedBox(height: 20),
            Row(children: [
              Icon(Icons.dashboard_outlined, color: cs.primary, size: 19),
              const SizedBox(width: 9),
              Text('Indicadores del período', style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 14, runSpacing: 14, children: [
              _metric('Comisiones reconocidas', _money(_totals['total_recognized']),
                Icons.account_balance_wallet_outlined, metricWidth),
              _metric('Pendientes por asistencia', _money(_totals['total_pending']),
                Icons.schedule_outlined, metricWidth),
              _metric('Servicios registrados', '${_totals['total_services'] ?? 0}',
                Icons.local_car_wash_outlined, metricWidth),
            ]),
            const SizedBox(height: 24),
            Text(_reportScope == 'general' ? 'Resumen por lavador' : 'Resumen del lavador',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 12),
            if (summaries.isEmpty)
              const Text('Sin servicios para el período y filtro seleccionados.')
            else
              Wrap(spacing: 14, runSpacing: 14, children: [
                for (final employee in summaries)
                  _summaryCard(employee, employeeWidth),
              ]),
            const SizedBox(height: 24),
            Text('Detalle de cada servicio', style: TextStyle(
              fontSize: 19, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 11),
            if (_rows.isEmpty)
              const Text('Sin trabajos en el período consultado.'),
            for (final r in _rows)
              Container(
                margin: const EdgeInsets.only(bottom: 9),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: cs.surface,
                  border: Border.all(color: cs.primary.withValues(alpha: .65)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Wrap(
                  spacing: 20, runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(width: 190,
                      child: Text('${r['employee_name']} · ${r['date']} ${r['time']}')),
                    SizedBox(width: 190,
                      child: Text('${r['plate']} · ${r['vehicle']}')),
                    SizedBox(width: 190, child: Text('${r['service_name']}')),
                    Text('Precio: ${_money(r['price'])}'),
                    Text('${r['percent']} %'),
                    Text('Comisión: ${_money(r['commission'])}',
                      style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
                    Text(r['recognized'] == true ? 'Reconocida' : 'Sin asistencia válida',
                      style: TextStyle(color: r['recognized'] == true ? cs.primary : cs.error)),
                  ],
                ),
              ),
            const SizedBox(height: 15),
            Text('Las comisiones son gasto de personal devengado, no comprobante de pago. '
              'No restarlas nuevamente como egreso de caja.',
              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        );
      }),
    );
  }
}
