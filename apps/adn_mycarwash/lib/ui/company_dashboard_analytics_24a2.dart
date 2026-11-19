import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// 24A.2: gráficas de solo lectura; no modifica los ocho KPI del 24A.1.
class CompanyDashboardAnalytics24A2 extends StatefulWidget {
  const CompanyDashboardAnalytics24A2({
    super.key,
    required this.client,
    this.branchId,
  });

  final http.Client client;
  final int? branchId;

  @override
  State<CompanyDashboardAnalytics24A2> createState() =>
      _CompanyDashboardAnalytics24A2State();
}

class _CompanyDashboardAnalytics24A2State
    extends State<CompanyDashboardAnalytics24A2> {
  static Color get _accent => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get _panel => CompanyVisualTheme.legacy(const Color(0xFF0D2229));
  static Color get _muted => CompanyVisualTheme.legacy(const Color(0xFFA6BAC2));
  int _days = 7;
  int _serial = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyDashboardAnalytics24A2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId ||
        oldWidget.client != widget.client) {
      _load();
    }
  }

  @override
  void dispose() {
    _serial++;
    super.dispose();
  }

  Future<void> _load() async {
    final serial = ++_serial;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await CompanyBusinessApi(widget.client).request(
        'GET',
        '/dashboard/analytics',
        query: {
          'days': _days.toString(),
          if (widget.branchId != null) 'branch_id': widget.branchId.toString(),
        },
      );
      if (!mounted || serial != _serial) {
        return;
      }
      setState(() {
        _data = Map<String, dynamic>.from(response['data'] as Map);
        _loading = false;
      });
    } catch (e) {
      if (!mounted || serial != _serial) {
        return;
      }
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Widget _section(String title, Widget content) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: _panel,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _accent.withValues(alpha: .34)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: CompanyVisualTheme.text,
          ),
        ),
        const SizedBox(height: 14),
        content,
      ],
    ),
  );

  Widget _sales(Map<String, dynamic> data) {
    if (data['pos_available'] != true || data['pos_daily'] is! List) {
      return Text(
        'Fuente de ventas no disponible.',
        style: TextStyle(color: _muted),
      );
    }
    final rows = (data['pos_daily'] as List).whereType<Map>().toList();
    final values = rows
        .map((e) => double.tryParse((e['amount']).toString()) ?? 0)
        .toList();
    final maximum = values.fold<double>(0, (a, b) => b > a ? b : a);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total del período: L ${data['pos_total']}',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: CompanyVisualTheme.text,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 164,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth < 1
                  ? 1.0
                  : constraints.maxWidth;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width > rows.length * 26 ? width : rows.length * 26.0,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < rows.length; i++)
                        Expanded(
                          child: Tooltip(
                            message:
                                '${rows[i]['date']}: L ${rows[i]['amount']} (${rows[i]['count']} ventas)',
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Container(
                                    height: maximum == 0
                                        ? 2
                                        : 124 * values[i] / maximum + 2,
                                    decoration: BoxDecoration(
                                      color: _accent,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                  const SizedBox(height: 7),
                                  Text(
                                    (rows[i]['date'] ?? '')
                                        .toString()
                                        .split('-')
                                        .last,
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: _muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 9),
        Text(
          (data['sales_note'] ?? '').toString(),
          style: TextStyle(fontSize: 11, color: _muted),
        ),
      ],
    );
  }

  Widget _washes(Map<String, dynamic> data) {
    if (data['wash_available'] != true || data['wash_statuses'] is! List) {
      return Text(
        'Fuente de lavados no disponible.',
        style: TextStyle(color: _muted),
      );
    }
    final rows = (data['wash_statuses'] as List).whereType<Map>().toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.isEmpty)
          Text(
            'No hay órdenes de lavado registradas.',
            style: TextStyle(color: _muted),
          ),
        Wrap(
          spacing: 9,
          runSpacing: 9,
          children: [
            for (final row in rows)
              Container(
                constraints: const BoxConstraints(minWidth: 125),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: CompanyVisualTheme.legacy(const Color(0xFF122F37)),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _accent.withValues(alpha: .3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (row['status']).toString(),
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      (row['count']).toString(),
                      style: TextStyle(
                        color: CompanyVisualTheme.text,
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          (data['wash_note'] ?? '').toString(),
          style: TextStyle(fontSize: 11, color: _muted),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 22),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 10,
          children: [
            Text(
              'Analítica operativa',
              style: TextStyle(
                color: CompanyVisualTheme.text,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
            DropdownButton<int>(
              value: _days,
              dropdownColor: _panel,
              items: const [
                DropdownMenuItem(value: 7, child: Text('Últimos 7 días')),
                DropdownMenuItem(value: 30, child: Text('Últimos 30 días')),
              ],
              onChanged: _loading
                  ? null
                  : (value) {
                      if (value != null) {
                        setState(() => _days = value);
                        _load();
                      }
                    },
            ),
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Actualizar analítica',
            ),
          ],
        ),
        if (_loading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: LinearProgressIndicator(color: _accent),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'No se pudo cargar la analítica: $_error',
              style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFECA7A7))),
            ),
          ),
        if (_data != null) ...[
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 850;
              final sales = _section(
                'Ventas Smart POS por día',
                _sales(_data!),
              );
              final washes = _section(
                'Estados actuales de lavados',
                _washes(_data!),
              );
              return narrow
                  ? Column(
                      children: [sales, const SizedBox(height: 12), washes],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: sales),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: washes),
                      ],
                    );
            },
          ),
          if (_data!['warnings'] is List &&
              (_data!['warnings'] as List).isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                (_data!['warnings'] as List).join(' • '),
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ),
        ],
      ],
    );
  }
}
