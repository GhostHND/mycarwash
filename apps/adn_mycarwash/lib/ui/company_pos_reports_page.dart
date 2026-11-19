import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// Bloque 22A: indicadores comerciales confirmados del Smart POS.
/// Solo lectura. No incluye los lavados ni sustituye la contabilidad.
class CompanyPosReportsPage extends StatefulWidget {
  const CompanyPosReportsPage({super.key, this.client});
  final http.Client? client;

  @override
  State<CompanyPosReportsPage> createState() => _CompanyPosReportsPageState();
}

class _CompanyPosReportsPageState extends State<CompanyPosReportsPage> {
  static Color get accent => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get panel => CompanyVisualTheme.legacy(const Color(0xFF0F2026));
  static Color get muted => CompanyVisualTheme.legacy(const Color(0xFF9DB0B8));
  late final http.Client _client;
  late final bool _ownsClient;
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  DateTime _from = DateTime.now().subtract(const Duration(days: 29));
  DateTime _to = DateTime.now();
  int _branch = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _branches = [];
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _initialize();
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  static String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static List<Map<String, dynamic>> _list(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  Future<void> _initialize() async {
    try {
      final options = await _api.request('GET', '/pos/options');
      final data = Map<String, dynamic>.from(options['data'] as Map);
      if (!mounted) {
        return;
      }
      setState(() => _branches = _list(data['branches']));
      await _load();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final query = <String, String>{'from': _date(_from), 'to': _date(_to)};
      if (_branch != 0) {
        query['branch_id'] = '$_branch';
      }
      final json = await _api.request(
        'GET',
        '/pos/reports/summary',
        query: query,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _report = Map<String, dynamic>.from(json['data'] as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _chooseDates() async {
    final result = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      helpText: 'Período del reporte POS',
    );
    if (!mounted || result == null) {
      return;
    }
    if (result.duration.inDays > 365) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El período no puede superar 366 días.')),
      );
      return;
    }
    setState(() {
      _from = result.start;
      _to = result.end;
    });
    await _load();
  }

  void _copyDailyCsv() {
    final report = _report;
    if (report == null) {
      return;
    }
    final text = StringBuffer('Fecha,Numero_de_ventas,Total_HNL\n');
    for (final row in _list(report['daily'])) {
      text.writeln('${row['day']},${row['sales_count']},${row['total']}');
    }
    Clipboard.setData(ClipboardData(text: text.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV diario copiado. Puedes pegarlo en Excel.'),
      ),
    );
  }

  Widget _kpi(String label, String value, IconData icon) => Container(
    width: 208,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(icon, color: accent, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          value,
          style: TextStyle(
            color: CompanyVisualTheme.text,
            fontWeight: FontWeight.bold,
            fontSize: 23,
          ),
        ),
      ],
    ),
  );

  Widget _section(String title, Widget content) => Container(
    padding: const EdgeInsets.all(17),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            color: CompanyVisualTheme.text,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 14),
        content,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final report = _report;
    final kpi = report == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(report['kpis'] as Map);
    final daily = _list(report?['daily']);
    final methods = _list(report?['payment_channels']);
    final products = _list(report?['top_products']);
    final docs = _list(report?['documents']);
    final largest = daily.fold<double>(0, (max, e) {
      final n = double.tryParse('${e['total'] ?? '0'}') ?? 0;
      return n > max ? n : max;
    });
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1200),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Reportes Smart POS',
                style: TextStyle(
                  color: CompanyVisualTheme.text,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Ventas confirmadas · Filtros por sucursal y período',
                style: TextStyle(color: muted),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(_branch),
                      initialValue: _branch,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Sucursal',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('Todas las sucursales'),
                        ),
                        for (final row in _branches)
                          DropdownMenuItem(
                            value: int.tryParse('${row['id']}') ?? -1,
                            child: Text(
                              '${row['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() => _branch = value);
                        _load();
                      },
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _chooseDates,
                    icon: const Icon(Icons.date_range_outlined),
                    label: Text('${_date(_from)} — ${_date(_to)}'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: daily.isEmpty ? null : _copyDailyCsv,
                    icon: const Icon(Icons.copy_all_outlined),
                    label: const Text('Copiar CSV diario'),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              if (_loading) LinearProgressIndicator(color: accent),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'No se pudo cargar el reporte: $_error',
                    style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF9CA4))),
                  ),
                ),
              if (report != null) ...[
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _kpi(
                      'Ventas',
                      '${kpi['sales_count'] ?? 0}',
                      Icons.receipt_long,
                    ),
                    _kpi(
                      'Total cobrado',
                      'L ${kpi['total'] ?? '0.00'}',
                      Icons.payments_outlined,
                    ),
                    _kpi(
                      'Descuentos',
                      'L ${kpi['discounts'] ?? '0.00'}',
                      Icons.sell_outlined,
                    ),
                    _kpi(
                      'ISV registrado',
                      'L ${kpi['tax'] ?? '0.00'}',
                      Icons.account_balance_outlined,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _section(
                  'Ventas por día',
                  daily.isEmpty
                      ? Text(
                          'No hay ventas confirmadas en este período.',
                          style: TextStyle(color: muted),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final row in daily)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            '${row['day']} · ${row['sales_count']} ventas',
                                            style: TextStyle(
                                              color: muted,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        Text(
                                          'L ${row['total']}',
                                          style: TextStyle(
                                            color: CompanyVisualTheme.text,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 5),
                                    LinearProgressIndicator(
                                      value: largest <= 0
                                          ? 0
                                          : ((double.tryParse(
                                                          '${row['total']}',
                                                        ) ??
                                                        0) /
                                                    largest)
                                                .clamp(0.0, 1.0)
                                                .toDouble(),
                                      minHeight: 7,
                                      color: accent,
                                      backgroundColor: Colors.white12,
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 720;
                    final left = _section(
                      'Cobros por canal',
                      methods.isEmpty
                          ? Text(
                              'Sin cobros',
                              style: TextStyle(color: muted),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final row in methods)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      '${row['channel']}',
                                      style: TextStyle(
                                        color: CompanyVisualTheme.text,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${row['payment_count']} movimientos',
                                      style: TextStyle(color: muted),
                                    ),
                                    trailing: Text(
                                      'L ${row['amount']}',
                                      style: TextStyle(color: accent),
                                    ),
                                  ),
                              ],
                            ),
                    );
                    final right = _section(
                      'Tipo de documento',
                      docs.isEmpty
                          ? Text(
                              'Sin documentos',
                              style: TextStyle(color: muted),
                            )
                          : Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                for (final row in docs)
                                  ListTile(
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    title: Text(
                                      row['document_type'] == 'FISCAL_INVOICE'
                                          ? 'Factura'
                                          : 'Recibo',
                                      style: TextStyle(
                                        color: CompanyVisualTheme.text,
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${row['sales_count']} ventas',
                                      style: TextStyle(color: muted),
                                    ),
                                    trailing: Text(
                                      'L ${row['total']}',
                                      style: TextStyle(color: accent),
                                    ),
                                  ),
                              ],
                            ),
                    );
                    if (narrow) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [left, const SizedBox(height: 12), right],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: 12),
                        Expanded(child: right),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _section(
                  'Los 10 productos más vendidos',
                  products.isEmpty
                      ? Text(
                          'Sin artículos vendidos',
                          style: TextStyle(color: muted),
                        )
                      : Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final row in products)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  '${row['name']}',
                                  style: TextStyle(color: CompanyVisualTheme.text),
                                ),
                                subtitle: Text(
                                  'SKU: ${row['sku']} · Unidades: ${row['quantity']}',
                                  style: TextStyle(color: muted),
                                ),
                                trailing: Text(
                                  'L ${row['gross_line_amount']}',
                                  style: TextStyle(color: accent),
                                ),
                              ),
                          ],
                        ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Reporte operativo de ventas Smart POS confirmadas. '
                  'No incluye cobros de lavados ni equivale a estados contables oficiales.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
