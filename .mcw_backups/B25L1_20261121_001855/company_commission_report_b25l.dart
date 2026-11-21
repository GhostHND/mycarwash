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
  bool _loading = false;
  bool _exporting = false;
  String? _error;
  List<Map<String, dynamic>> _staff = [];
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
    try {
      final resp = await _api.request('GET', '/employees', query: {'per_page': '50'});
      if (mounted) {
        setState(() => _staff = (resp['data'] as List? ?? []).whereType<Map>()
            .map((r) => Map<String, dynamic>.from(r)).toList());
      }
    } catch (_) {
      // El reporte sigue funcionando incluso si no se puede cargar el selector.
    }
    await _load();
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
    if (_loading || _exporting || _error != null) return;
    setState(() => _exporting = true);
    try {
      final identity = BusinessIdentity.current.value;
      final palette = CompanyVisualTheme.current.value;
      final accent = _pdfColor(palette.primary);
      final secondary = _pdfColor(palette.secondary);
      final logo = identity.logoBytes == null ? null : pw.MemoryImage(identity.logoBytes!);
      final pdf = pw.Document();
      final employeeName = _employee == null ? 'Todos los lavadores' :
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
              pw.Text('PRODUCCIÓN Y COMISIONES DE LAVADORES',
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
          pw.Text('Reporte de producción', style: pw.TextStyle(fontSize: 19, fontWeight: pw.FontWeight.bold, color: secondary)),
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

  Widget _metric(String label, String value, IconData icon) {
    final cs = Theme.of(context).colorScheme;
    return Container(width: 230, padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: cs.surface, border: Border.all(color: cs.primary),
        borderRadius: BorderRadius.circular(15)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Icon(icon, color: cs.primary, size: 18), const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)))]),
        const SizedBox(height: 10), Text(value, style: TextStyle(
          fontWeight: FontWeight.bold, fontSize: 23, color: cs.onSurface)),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final summaries = (_totals['employees'] as List? ?? []).whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r)).toList();
    return ListView(padding: const EdgeInsets.all(22), children: [
      Container(padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: cs.surface, border: Border.all(color: cs.primary),
          borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          Icon(Icons.payments_outlined, size: 33, color: cs.primary), const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Producción y comisiones de lavadores', style: TextStyle(
              fontSize: 25, fontWeight: FontWeight.w800, color: cs.onSurface)),
            Text('Trabajos realizados, vehículo, horario, porcentaje y comisión reconocida.',
              style: TextStyle(color: cs.onSurfaceVariant)),
          ])),
        ])),
      const SizedBox(height: 15),
      Wrap(spacing: 10, runSpacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
        for (final period in ['Hoy','Semana','Mes','Año'])
          OutlinedButton(onPressed: () => _choosePeriod(period),
            style: OutlinedButton.styleFrom(backgroundColor:
              _period == period ? cs.primary.withValues(alpha: .20) : null),
            child: Text(period)),
        OutlinedButton.icon(onPressed: _chooseCustom, icon: const Icon(Icons.date_range),
          label: Text('${_date(_from)} — ${_date(_to)}')),
        DropdownButton<int?>(value: _employee, hint: const Text('Todos los lavadores'),
          items: [const DropdownMenuItem<int?>(value: null, child: Text('Todos los lavadores')),
            for (final e in _staff.where((e) => '${e['position']}' == 'washer'))
              DropdownMenuItem<int?>(value: int.tryParse('${e['id']}'),
                child: Text('${e['full_name']}'))],
          onChanged: (v) {setState(() => _employee = v); _load();}),
        DropdownButton<String>(value: _paper,
          items: const [DropdownMenuItem(value: 'Carta', child: Text('Carta')),
            DropdownMenuItem(value: 'A4', child: Text('A4'))],
          onChanged: (v) => setState(() => _paper = v ?? 'Carta')),
        OutlinedButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Actualizar')),
        FilledButton.icon(onPressed: _loading || _exporting ? null : _pdf,
          icon: const Icon(Icons.picture_as_pdf_outlined),
          label: Text(_exporting ? 'Preparando...' : 'Imprimir / guardar PDF')),
      ]),
      if (_loading) const LinearProgressIndicator(),
      if (_error != null) Padding(padding: const EdgeInsets.all(12),
        child: Text(_error!, style: TextStyle(color: cs.error))),
      const SizedBox(height: 17),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _metric('Comisiones reconocidas', _money(_totals['total_recognized']), Icons.account_balance_wallet_outlined),
        _metric('Pendientes por asistencia', _money(_totals['total_pending']), Icons.schedule_outlined),
        _metric('Servicios registrados', '${_totals['total_services'] ?? 0}', Icons.local_car_wash_outlined),
      ]),
      const SizedBox(height: 20),
      Text('Resumen por lavador', style: TextStyle(fontSize: 19,
        fontWeight: FontWeight.bold, color: cs.onSurface)),
      const SizedBox(height: 10),
      if (summaries.isEmpty) const Text('Sin servicios reconocidos en este período.')
      else Wrap(spacing: 12, runSpacing: 12, children: [
        for (final e in summaries)
          Container(width: 290, padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(color: cs.surface,
              border: Border.all(color: cs.primary), borderRadius: BorderRadius.circular(14)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${e['name']}', style: TextStyle(fontSize: 17,
                fontWeight: FontWeight.w700, color: cs.onSurface)),
              const SizedBox(height: 7), Text('Comisión: ${_money(e['recognized'])}'),
              Text('Servicios: ${e['recognized_services']}'),
              Text('Pendiente: ${_money(e['pending'])}', style: TextStyle(color: cs.onSurfaceVariant)),
            ])),
      ]),
      const SizedBox(height: 20),
      Text('Detalle de cada servicio', style: TextStyle(fontSize: 19,
        fontWeight: FontWeight.bold, color: cs.onSurface)),
      const SizedBox(height: 9),
      if (_rows.isEmpty) const Text('Sin trabajos en el período consultado.'),
      for (final r in _rows)
        Container(margin: const EdgeInsets.only(bottom: 9), padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: cs.surface,
            border: Border.all(color: cs.primary.withValues(alpha: .6)),
            borderRadius: BorderRadius.circular(13)),
          child: Wrap(spacing: 16, runSpacing: 7,
            crossAxisAlignment: WrapCrossAlignment.center, children: [
              SizedBox(width: 180, child: Text('${r['employee_name']} · ${r['date']} ${r['time']}')),
              SizedBox(width: 180, child: Text('${r['plate']} · ${r['vehicle']}')),
              SizedBox(width: 180, child: Text('${r['service_name']}')),
              Text('Precio: ${_money(r['price'])}'), Text('${r['percent']} %'),
              Text('Comisión: ${_money(r['commission'])}',
                style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold)),
              Text(r['recognized'] == true ? 'Reconocida' : 'Sin asistencia válida',
                style: TextStyle(color: r['recognized'] == true ? cs.primary : cs.error)),
            ])),
      const SizedBox(height: 14),
      Text('Las comisiones son gasto de personal devengado, no comprobante de pago. No restarlas nuevamente como egreso de caja.',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
    ]);
  }
}
