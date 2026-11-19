import 'dart:async';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// Bloque 24A.2: panel de lavados EN_PROCESO con actualización cada 15 s.
/// Nunca limita el total de lavados; limita solamente las tarjetas visibles.
class CompanyDashboardActive24A2 extends StatefulWidget {
  const CompanyDashboardActive24A2({
    super.key,
    required this.client,
    this.branchId,
  });

  final http.Client client;
  final int? branchId;

  @override
  State<CompanyDashboardActive24A2> createState() =>
      _CompanyDashboardActive24A2State();
}

class _CompanyDashboardActive24A2State
    extends State<CompanyDashboardActive24A2> {
  static Color get _accent => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get _muted => CompanyVisualTheme.legacy(const Color(0xFFA6BAC2));
  Timer? _timer;
  int _serial = 0;
  int _offset = 0;
  bool _pending = false;
  bool _initial = true;
  int _total = 0;
  String? _error;
  bool _available = true;
  List<Map<String, dynamic>> _items = [];
  DateTime? _updated;

  @override
  void initState() {
    super.initState();
    _fetch();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _fetch());
  }

  @override
  void didUpdateWidget(covariant CompanyDashboardActive24A2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.branchId != widget.branchId ||
        oldWidget.client != widget.client) {
      _serial++;
      _pending = false;
      _offset = 0;
      _items = [];
      _total = 0;
      _initial = true;
      _error = null;
      _fetch();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _serial++;
    super.dispose();
  }

  Future<void> _fetch() async {
    if (_pending) return;
    final serial = ++_serial;
    _pending = true;
    try {
      final response = await CompanyBusinessApi(widget.client).request(
        'GET',
        '/dashboard/active-washes',
        query: {
          'offset': '$_offset',
          if (widget.branchId != null) 'branch_id': '${widget.branchId}',
        },
      );
      if (!mounted || serial != _serial) return;
      final payload = Map<String, dynamic>.from(response['data'] as Map);
      final total = (payload['total'] as num).toInt();
      final offset = (payload['offset'] as num).toInt();
      final rows = (payload['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      setState(() {
        _available = payload['available'] != false;
        _total = total;
        _items = rows;
        _offset = total > 4 ? (offset + rows.length) % total : 0;
        _updated = DateTime.now();
        _initial = false;
        _error = null;
      });
    } catch (error) {
      if (mounted && serial == _serial) {
        setState(() {
          _error = error.toString();
          _initial = false;
        });
      }
    } finally {
      if (serial == _serial) _pending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CompanyVisualTheme.legacy(const Color(0xFF0D2229)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                'Lavados activos · En vivo',
                style: TextStyle(
                  fontSize: 18,
                  color: CompanyVisualTheme.text,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                '$_total en proceso',
                key: const ValueKey('active_total'),
                style: TextStyle(
                  color: _accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (_total > 4)
                Text(
                  'Rotación cada 15 segundos',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
              if (_updated != null)
                Text(
                  'Actualizado: ${TimeOfDay.fromDateTime(_updated!).format(context)}',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              IconButton(
                onPressed: _pending ? null : _fetch,
                tooltip: 'Actualizar lavados activos',
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_initial) LinearProgressIndicator(color: _accent),
          if (_error != null)
            Text(
              'No se pudo actualizar la actividad: $_error',
              style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFECA7A7)), fontSize: 12),
            ),
          if (!_initial && _error == null && !_available)
            Text(
              'No está disponible la fuente de órdenes de lavado.',
              style: TextStyle(color: _muted),
            ),
          if (!_initial && _error == null && _available && _total == 0)
            Text(
              'No hay lavados en proceso en este momento.',
              key: ValueKey('active_empty'),
              style: TextStyle(color: _muted),
            ),
          if (_items.isNotEmpty)
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final columns = width >= 900
                    ? 4
                    : width >= 480
                    ? 2
                    : 1;
                final tileWidth = (width - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final row in _items)
                      SizedBox(
                        width: tileWidth,
                        child: Container(
                          key: ValueKey('active_wash_${row['id']}'),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: CompanyVisualTheme.legacy(const Color(0xFF13323A)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _accent.withValues(alpha: .3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (row['label'] ?? 'Orden #${row['id']}')
                                    .toString(),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: CompanyVisualTheme.text,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'EN PROCESO',
                                style: TextStyle(color: _accent, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
