import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

class CompanyScheduleSection extends StatefulWidget {
  const CompanyScheduleSection({super.key, required this.client});

  final http.Client client;

  @override
  State<CompanyScheduleSection> createState() => _CompanyScheduleSectionState();
}

class _DaySchedule {
  _DaySchedule();

  bool closed = true;
  final open = TextEditingController();
  final close = TextEditingController();
  final breakStart = TextEditingController();
  final breakEnd = TextEditingController();
  final notes = TextEditingController();

  static String _shortTime(Object? value) {
    final text = (value ?? '').toString();
    return text.length >= 5 ? text.substring(0, 5) : text;
  }

  void read(Map record) {
    closed = record['is_closed'] == true || record['is_closed'] == 1;
    open.text = _shortTime(record['opens_at']);
    close.text = _shortTime(record['closes_at']);
    breakStart.text = _shortTime(record['break_starts_at']);
    breakEnd.text = _shortTime(record['break_ends_at']);
    notes.text = (record['notes'] ?? '').toString();
  }

  void dispose() {
    open.dispose();
    close.dispose();
    breakStart.dispose();
    breakEnd.dispose();
    notes.dispose();
  }
}

class _CompanyScheduleSectionState extends State<CompanyScheduleSection> {
  static const turquoise = Color(0xFF0FA7B4);
  static const surface = Color(0xFF0A1519);
  static const border = Color(0xFF20343C);
  static const muted = Color(0xFF9BAEB6);
  static const daysOfWeek = <String>[
    'Domingo',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];

  final _days = List<_DaySchedule>.generate(7, (_) => _DaySchedule());
  final _search = TextEditingController();
  Timer? _debounce;
  int _specialRequestVersion = 0;
  int _page = 1;
  int _lastPage = 1;
  bool _loadingWeek = true;
  bool _savingWeek = false;
  bool _loadingSpecial = true;
  String? _weekError;
  String? _specialError;
  List<Map<String, dynamic>> _specials = [];

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _loadWeek();
    _loadSpecial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _specialRequestVersion++;
    _search.dispose();
    for (final day in _days) {
      day.dispose();
    }
    super.dispose();
  }

  void _notice(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
      ),
    );
  }

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: muted),
    filled: true,
    fillColor: const Color(0xFF111F25),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: border),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: turquoise),
      borderRadius: BorderRadius.circular(10),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFFE84657)),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFFE84657)),
      borderRadius: BorderRadius.circular(10),
    ),
  );

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFF11242C), Color(0xFF0A171D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: const Color(0xFF2A414A)),
    ),
    child: child,
  );

  Future<void> _loadWeek() async {
    setState(() {
      _loadingWeek = true;
      _weekError = null;
    });
    try {
      final response = await _api.request('GET', '/settings/hours');
      if (!mounted) return;
      final raw = response['days'];
      if (raw is! List) {
        throw const FormatException('El horario recibido no es una lista.');
      }
      // No tocar los controladores hasta tener una respuesta válida.
      for (final row in raw.whereType<Map>()) {
        final index = int.tryParse('${row['day_of_week']}');
        if (index != null && index >= 0 && index <= 6) {
          _days[index].read(row);
        }
      }
      setState(() => _loadingWeek = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _weekError = error.toString();
        _loadingWeek = false;
      });
    }
  }

  static bool _validTime(String value) =>
      RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value);

  String? _validateWeek() {
    for (var i = 0; i < _days.length; i++) {
      final d = _days[i];
      if (d.notes.text.length > 255) {
        return '${daysOfWeek[i]}: las notas no deben superar 255 caracteres.';
      }
      if (d.closed) continue;
      final open = d.open.text.trim();
      final close = d.close.text.trim();
      final start = d.breakStart.text.trim();
      final end = d.breakEnd.text.trim();
      if (!_validTime(open) ||
          !_validTime(close) ||
          open.compareTo(close) >= 0) {
        return '${daysOfWeek[i]}: elige apertura y cierre válidos.';
      }
      if (start.isEmpty != end.isEmpty) {
        return '${daysOfWeek[i]}: el descanso requiere inicio y fin.';
      }
      if (start.isNotEmpty &&
          (!_validTime(start) ||
              !_validTime(end) ||
              start.compareTo(end) >= 0 ||
              start.compareTo(open) < 0 ||
              end.compareTo(close) > 0)) {
        return '${daysOfWeek[i]}: el descanso debe estar dentro de la jornada.';
      }
    }
    return null;
  }

  Future<void> _saveWeek() async {
    if (_savingWeek || _loadingWeek || _weekError != null) return;
    final validation = _validateWeek();
    if (validation != null) {
      _notice(validation, isError: true);
      return;
    }
    final payload = <String, dynamic>{
      'days': [
        for (var i = 0; i < 7; i++)
          {
            'day_of_week': i,
            'is_closed': _days[i].closed,
            'opens_at': _days[i].closed ? null : _days[i].open.text.trim(),
            'closes_at': _days[i].closed ? null : _days[i].close.text.trim(),
            'break_starts_at':
                _days[i].closed || _days[i].breakStart.text.trim().isEmpty
                ? null
                : _days[i].breakStart.text.trim(),
            'break_ends_at':
                _days[i].closed || _days[i].breakEnd.text.trim().isEmpty
                ? null
                : _days[i].breakEnd.text.trim(),
            'notes': _days[i].notes.text.trim().isEmpty
                ? null
                : _days[i].notes.text.trim(),
          },
      ],
    };
    setState(() => _savingWeek = true);
    try {
      await _api.request('PATCH', '/settings/hours', body: payload);
      if (!mounted) return;
      _notice('Horarios semanales guardados en MySQL.');
    } catch (error) {
      _notice(error.toString(), isError: true);
    } finally {
      if (mounted) setState(() => _savingWeek = false);
    }
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final parts = controller.text.split(':');
    final hour = parts.length == 2 ? int.tryParse(parts[0]) : null;
    final minute = parts.length == 2 ? int.tryParse(parts[1]) : null;
    final initial =
        hour != null &&
            minute != null &&
            hour >= 0 &&
            hour <= 23 &&
            minute >= 0 &&
            minute <= 59
        ? TimeOfDay(hour: hour, minute: minute)
        : const TimeOfDay(hour: 8, minute: 0);
    final chosen = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (chosen == null || !mounted) return;
    controller.text =
        '${chosen.hour.toString().padLeft(2, '0')}:${chosen.minute.toString().padLeft(2, '0')}';
    setState(() {});
  }

  Widget _timeSelector(String label, TextEditingController value) => SizedBox(
    width: 143,
    child: TextField(
      controller: value,
      readOnly: true,
      onTap: () => _pickTime(value),
      style: const TextStyle(color: Colors.white),
      decoration: _decor(label).copyWith(
        suffixIcon: const Icon(Icons.access_time, color: turquoise, size: 18),
      ),
    ),
  );

  Widget _weeklyPanel() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Horario semanal',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 20,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Domingo a sábado. Los horarios deben estar dentro del mismo día.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 20),
        if (_loadingWeek)
          const Center(child: CircularProgressIndicator(color: turquoise))
        else if (_weekError != null) ...[
          Text(_weekError!, style: const TextStyle(color: Color(0xFFFF8995))),
          TextButton(
            onPressed: _loadWeek,
            child: const Text('Reintentar horario'),
          ),
        ] else ...[
          for (var i = 0; i < 7; i++) ...[
            Container(
              padding: const EdgeInsets.all(14),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: _days[i].closed
                    ? const Color(0xFF17232A)
                    : const Color(0xFF122C33),
                border: Border.all(
                  color: _days[i].closed
                      ? border
                      : turquoise.withValues(alpha: 0.38),
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          daysOfWeek[i],
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Text('Cerrado', style: TextStyle(color: muted)),
                      Switch(
                        key: ValueKey('weekly_closed_$i'),
                        value: _days[i].closed,
                        activeThumbColor: turquoise,
                        onChanged: _savingWeek
                            ? null
                            : (value) =>
                                  setState(() => _days[i].closed = value),
                      ),
                    ],
                  ),
                  if (!_days[i].closed) ...[
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _timeSelector('Abre', _days[i].open),
                        _timeSelector('Cierra', _days[i].close),
                        _timeSelector('Inicio descanso', _days[i].breakStart),
                        _timeSelector('Fin descanso', _days[i].breakEnd),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _days[i].notes,
                    maxLength: 255,
                    style: const TextStyle(color: Colors.white),
                    decoration: _decor('Observaciones (opcional)'),
                  ),
                ],
              ),
            ),
          ],
          FilledButton.icon(
            key: const ValueKey('weekly_save'),
            onPressed: _savingWeek ? null : _saveWeek,
            icon: const Icon(Icons.save_outlined),
            label: Text(
              _savingWeek ? 'Guardando...' : 'Guardar horario semanal',
            ),
            style: FilledButton.styleFrom(
              backgroundColor: turquoise,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ],
    ),
  );

  Future<void> _loadSpecial() async {
    final version = ++_specialRequestVersion;
    setState(() {
      _loadingSpecial = true;
      _specialError = null;
    });
    try {
      final result = await _api.request(
        'GET',
        '/special-hours',
        query: {'q': _search.text.trim(), 'page': '$_page', 'per_page': '10'},
      );
      if (!mounted || version != _specialRequestVersion) return;
      final rows = result['data'];
      setState(() {
        _specials = rows is List
            ? rows
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
            : [];
        _page = int.tryParse('${result['current_page'] ?? 1}') ?? 1;
        _lastPage = int.tryParse('${result['last_page'] ?? 1}') ?? 1;
        _loadingSpecial = false;
      });
    } catch (error) {
      if (!mounted || version != _specialRequestVersion) return;
      setState(() {
        _specialError = error.toString();
        _loadingSpecial = false;
      });
    }
  }

  void _onSpecialSearch(String value) {
    _debounce?.cancel();
    setState(() => _page = 1);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadSpecial();
    });
  }

  Future<void> _editSpecial([Map<String, dynamic>? existing]) async {
    final formKey = GlobalKey<FormState>();
    var date = (existing?['special_date'] ?? '').toString();
    var reason = (existing?['reason'] ?? '').toString();
    var notes = (existing?['notes'] ?? '').toString();
    var opens = _DaySchedule._shortTime(existing?['opens_at']);
    var closes = _DaySchedule._shortTime(existing?['closes_at']);
    var closed =
        existing == null ||
        existing['is_closed'] == 1 ||
        existing['is_closed'] == true;
    var saving = false;
    String? error;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          backgroundColor: surface,
          title: Text(
            existing == null ? 'Nueva fecha especial' : 'Editar fecha especial',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 490,
            child: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const ValueKey('special_date'),
                      initialValue: date,
                      enabled: !saving,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9-]')),
                        LengthLimitingTextInputFormatter(10),
                      ],
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor('Fecha (AAAA-MM-DD)'),
                      onChanged: (v) => date = v.trim(),
                      validator: (v) {
                        final text = (v ?? '').trim();
                        return RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)
                            ? null
                            : 'Escribe una fecha AAAA-MM-DD.';
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: reason,
                      enabled: !saving,
                      maxLength: 190,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor('Motivo'),
                      onChanged: (v) => reason = v,
                    ),
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Negocio cerrado ese día',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                        Switch(
                          value: closed,
                          activeThumbColor: turquoise,
                          onChanged: saving
                              ? null
                              : (v) => updateDialog(() => closed = v),
                        ),
                      ],
                    ),
                    if (!closed) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        initialValue: opens,
                        enabled: !saving,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decor('Abre (HH:mm)'),
                        onChanged: (v) => opens = v.trim(),
                        validator: (v) => _validTime((v ?? '').trim())
                            ? null
                            : 'Hora inválida (HH:mm).',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: closes,
                        enabled: !saving,
                        style: const TextStyle(color: Colors.white),
                        decoration: _decor('Cierra (HH:mm)'),
                        onChanged: (v) => closes = v.trim(),
                        validator: (v) => _validTime((v ?? '').trim())
                            ? null
                            : 'Hora inválida (HH:mm).',
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: notes,
                      enabled: !saving,
                      maxLines: 3,
                      maxLength: 5000,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor('Notas (opcional)'),
                      onChanged: (v) => notes = v,
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFFF8995)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              key: const ValueKey('special_save'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) return;
                      if (!closed && opens.compareTo(closes) >= 0) {
                        updateDialog(
                          () => error =
                              'La apertura debe ser anterior al cierre.',
                        );
                        return;
                      }
                      updateDialog(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final payload = <String, dynamic>{
                          'special_date': date,
                          'reason': reason.trim().isEmpty
                              ? null
                              : reason.trim(),
                          'is_closed': closed,
                          'opens_at': closed ? null : opens,
                          'closes_at': closed ? null : closes,
                          'notes': notes.trim().isEmpty ? null : notes.trim(),
                        };
                        await _api.request(
                          existing == null ? 'POST' : 'PATCH',
                          existing == null
                              ? '/special-hours'
                              : '/special-hours/${existing['id']}',
                          body: payload,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          updateDialog(() {
                            error = e.toString();
                            saving = false;
                          });
                        }
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: turquoise),
              child: Text(saving ? 'Guardando...' : 'Guardar fecha especial'),
            ),
          ],
        ),
      ),
    );
    if (changed == true && mounted) {
      _notice('Fecha especial guardada.');
      await _loadSpecial();
    }
  }

  Future<void> _deleteSpecial(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        title: const Text(
          'Eliminar fecha especial',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '¿Eliminar ${item['special_date']}? Esta acción no se puede deshacer.',
          style: const TextStyle(color: muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _api.request('DELETE', '/special-hours/${item['id']}');
      _notice('Fecha especial eliminada.');
      if (_specials.length == 1 && _page > 1) {
        _page--;
      }
      await _loadSpecial();
    } catch (e) {
      _notice(e.toString(), isError: true);
    }
  }

  Widget _specialPanel() => _panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            const Text(
              'Fechas especiales',
              style: TextStyle(
                fontSize: 20,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _editSpecial(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva fecha especial'),
              style: FilledButton.styleFrom(backgroundColor: turquoise),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Feriados, cierres y horarios excepcionales por fecha.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _search,
          onChanged: _onSpecialSearch,
          style: const TextStyle(color: Colors.white),
          decoration: _decor('Buscar por fecha, motivo o nota')
              .copyWith(prefixIcon: const Icon(Icons.search, color: turquoise)),
        ),
        const SizedBox(height: 14),
        if (_loadingSpecial)
          const Center(child: CircularProgressIndicator(color: turquoise))
        else if (_specialError != null) ...[
          Text(
            _specialError!,
            style: const TextStyle(color: Color(0xFFFF8995)),
          ),
          TextButton(
            onPressed: _loadSpecial,
            child: const Text('Reintentar fechas'),
          ),
        ] else if (_specials.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text(
              'No hay fechas especiales registradas.',
              style: TextStyle(color: muted),
            ),
          )
        else
          for (final item in _specials) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF12242C),
                border: Border.all(color: const Color(0xFF2A414A)),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event, color: turquoise),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['special_date']} · ${item['reason'] ?? 'Sin motivo'}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item['is_closed'] == 1 || item['is_closed'] == true
                              ? 'Cerrado'
                              : '${_DaySchedule._shortTime(item['opens_at'])} – ${_DaySchedule._shortTime(item['closes_at'])}',
                          style: const TextStyle(color: muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar fecha especial',
                    onPressed: () => _editSpecial(item),
                    icon: const Icon(Icons.edit_outlined, color: turquoise),
                  ),
                  IconButton(
                    tooltip: 'Eliminar fecha especial',
                    onPressed: () => _deleteSpecial(item),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFE84657),
                    ),
                  ),
                ],
              ),
            ),
          ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Página anterior de fechas',
              onPressed: _loadingSpecial || _page <= 1
                  ? null
                  : () {
                      _page--;
                      _loadSpecial();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              'Página $_page de $_lastPage',
              style: const TextStyle(color: muted),
            ),
            IconButton(
              tooltip: 'Página siguiente de fechas',
              onPressed: _loadingSpecial || _page >= _lastPage
                  ? null
                  : () {
                      _page++;
                      _loadSpecial();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Column(
    children: [_weeklyPanel(), const SizedBox(height: 18), _specialPanel()],
  );
}
