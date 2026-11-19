import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// Primero se reserva un espacio real. La orden se crea al recibir el vehículo.
class CompanyNewOrderReservation24N7 extends StatefulWidget {
  const CompanyNewOrderReservation24N7({super.key, required this.client});

  final http.Client client;

  @override
  State<CompanyNewOrderReservation24N7> createState() =>
      _CompanyNewOrderReservation24N7State();
}

class _CompanyNewOrderReservation24N7State
    extends State<CompanyNewOrderReservation24N7> {
  static const accent = Color(0xFF0FA7B4);
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _slots = [];
  int? _branch;
  int? _vehicle;
  int? _service;
  Map<String, dynamic>? _slot;
  DateTime _date = DateTime.now();
  bool _busy = false;
  bool _loading = true;
  String? _error;
  int _generation = 0;

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _rows(dynamic list) => list is List
      ? list.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList()
      : <Map<String, dynamic>>[];

  Future<void> _loadOptions() async {
    try {
      final response = await _api.request('GET', '/schedule/options');
      if (!mounted) { return; }
      final data = response['data'];
      if (data is! Map) { throw StateError('No se encontraron opciones de agenda.'); }
      setState(() {
        _branches = _rows(data['branches']);
        _vehicles = _rows(data['vehicles']);
        _services = _rows(data['services']);
        _loading = false;
      });
    } catch (e) {
      if (mounted) { setState(() { _loading = false; _error = '$e'; }); }
    }
  }

  void _selectionChanged() {
    setState(() { _slot = null; _slots = []; _error = null; });
    if (_branch != null && _vehicle != null && _service != null) {
      _loadSlots();
    }
  }

  Future<void> _loadSlots() async {
    final branch = _branch;
    final vehicle = _vehicle;
    final service = _service;
    if (branch == null || vehicle == null || service == null) { return; }
    final version = ++_generation;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _api.request('GET', '/schedule/availability-24d', query: {
        'branch_id': '$branch', 'vehicle_id': '$vehicle',
        'service_id': '$service', 'date': _day(_date),
      });
      if (!mounted || version != _generation) { return; }
      setState(() { _slots = _rows(result['slots']); _busy = false; });
    } catch (e) {
      if (!mounted || version != _generation) { return; }
      setState(() { _busy = false; _error = '$e'; });
    }
  }

  Widget _select(String label, int? value, List<Map<String, dynamic>> data,
      String Function(Map<String, dynamic>) labelFor, ValueChanged<int?> onChange) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int>(
        isExpanded: true,
        initialValue: value,
        decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
        items: data.map((row) => DropdownMenuItem<int>(
          value: int.tryParse('${row['id']}'),
          child: Text(labelFor(row), overflow: TextOverflow.ellipsis),
        )).toList(),
        onChanged: _busy ? null : onChange,
      ),
    );
  }

  Future<void> _save() async {
    final slot = _slot;
    if (_branch == null || _vehicle == null || _service == null || slot == null) {
      setState(() => _error = 'Selecciona sucursal, vehículo, servicio y un horario disponible.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      await _api.request('POST', '/schedule/bookings', body: {
        'branch_id': _branch, 'bay_id': slot['bay_id'], 'vehicle_id': _vehicle,
        'service_id': _service, 'local_date': _day(_date),
        'start_time': slot['time'],
      });
      if (mounted) { Navigator.of(context).pop(_day(_date)); }
    } catch (e) {
      if (mounted) { setState(() { _busy = false; _error = '$e'; }); }
    }
  }

  @override
  Widget build(BuildContext context) {
    final available = _slots.where((row) => row['available'] == true).toList();
    return AlertDialog(
      backgroundColor: const Color(0xFF071F23),
      title: const Text('Nueva orden · Reservar horario'),
      content: SizedBox(
        width: 570,
        child: SingleChildScrollView(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Primero selecciona un cupo disponible según la duración del lavado. '
                        'La orden aparecerá en Nuevas cuando confirmes que el vehículo llegó al negocio.'),
                    const SizedBox(height: 16),
                    _select('Sucursal', _branch, _branches, (e) => '${e['name']}', (v) {
                      setState(() => _branch = v);
                      _selectionChanged();
                    }),
                    _select('Vehículo', _vehicle, _vehicles,
                        (e) => '${e['brand'] ?? ''} ${e['model'] ?? ''} · ${e['plate'] ?? ''}', (v) {
                      setState(() => _vehicle = v);
                      _selectionChanged();
                    }),
                    _select('Servicio', _service, _services,
                        (e) => '${e['name']} · ${e['duration_minutes']} minutos', (v) {
                      setState(() => _service = v);
                      _selectionChanged();
                    }),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () async {
                        final picked = await showDatePicker(
                          context: context, initialDate: _date,
                          firstDate: DateTime.now().subtract(const Duration(days: 1)),
                          lastDate: DateTime.now().add(const Duration(days: 180)),
                        );
                        if (picked != null) { setState(() => _date = picked); _selectionChanged(); }
                      },
                      icon: const Icon(Icons.calendar_month, color: accent),
                      label: Text('Fecha: ${_day(_date)}'),
                    ),
                    const SizedBox(height: 12),
                    const Text('Horarios disponibles', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 7),
                    if (_busy) const LinearProgressIndicator(color: accent),
                    if (!_busy && _branch != null && _service != null && _vehicle != null && available.isEmpty)
                      const Padding(padding: EdgeInsets.all(8),
                        child: Text('No existen cupos disponibles para esa fecha y duración.')),
                    Wrap(spacing: 8, runSpacing: 6, children: [
                      for (final row in available)
                        ChoiceChip(
                          label: Text('${row['time']}'),
                          selected: _slot?['time'] == row['time'] && _slot?['bay_id'] == row['bay_id'],
                          onSelected: _busy ? null : (_) => setState(() => _slot = row),
                        ),
                    ]),
                    if (_error != null) Padding(padding: const EdgeInsets.only(top: 10),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
                  ],
                ),
        ),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Cancelar')),
        FilledButton(onPressed: _busy || _loading ? null : _save,
          child: Text(_busy ? 'Verificando...' : 'Confirmar reserva')),
      ],
    );
  }
}
