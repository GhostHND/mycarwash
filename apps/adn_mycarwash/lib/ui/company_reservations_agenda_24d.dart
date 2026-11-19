import 'dart:async';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/business_identity.dart';
import '../core/company_business_api.dart';
import 'company_vehicle_cards_24c2.dart';

/// Presentación de Agenda. El backend conserva la validación final de reservas.
class CompanyReservationsAgenda24D extends StatefulWidget {
  const CompanyReservationsAgenda24D({
    super.key,
    required this.client,
    required this.onCreate,
    required this.onEdit,
    required this.onDetails,
    required this.onCancel,
    required this.onViewAll,
  });

  final http.Client client;
  final Future<void> Function(Map<String, String>) onCreate;
  final Future<void> Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>) onDetails;
  final Future<void> Function(Map<String, dynamic>) onCancel;
  final VoidCallback onViewAll;

  @override
  State<CompanyReservationsAgenda24D> createState() =>
      _CompanyReservationsAgenda24DState();
}

class _CompanyReservationsAgenda24DState
    extends State<CompanyReservationsAgenda24D> {
  DateTime _selected = DateTime.now();
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _weekly = false;
  bool _busy = true;
  bool _slotsBusy = false;
  String? _error;
  String? _availabilityMessage;
  int _requestVersion = 0;
  int _availableCount = 0;
  int _confirmedCount = 0;
  int _todayCount = 0;
  String? _branch;
  String? _service;
  String? _vehicle;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _vehicles = [];
  List<Map<String, dynamic>> _reservations = [];
  List<Map<String, dynamic>> _weekBookings = [];
  List<Map<String, dynamic>> _slots = [];
  Timer? _refreshTimer;

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);
  Color get _accent => Theme.of(context).colorScheme.primary;
  Color get _surface => Theme.of(context).colorScheme.surface;
  Color get _edge => _accent.withValues(alpha: .47);
  static Color get _muted => CompanyVisualTheme.legacy(const Color(0xFF9BAEB6));

  @override
  void initState() {
    super.initState();
    _initialize();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _reload();
      }
    });
  }

  @override
  void dispose() {
    _requestVersion++;
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static const _months = [
    'Enero',
    'Febrero',
    'Marzo',
    'Abril',
    'Mayo',
    'Junio',
    'Julio',
    'Agosto',
    'Septiembre',
    'Octubre',
    'Noviembre',
    'Diciembre',
  ];
  static const _days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  static List<Map<String, dynamic>> _records(dynamic raw) {
    if (raw is! List) {
      return [];
    }
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _initialize() async {
    final version = ++_requestVersion;
    try {
      final response = await _api.request('GET', '/schedule/options');
      if (!mounted || version != _requestVersion) {
        return;
      }
      final options = Map<String, dynamic>.from(response['data'] as Map);
      setState(() {
        _branches = _records(options['branches']);
        _services = _records(options['services']);
        _vehicles = _records(options['vehicles']);
        _branch = _branches.isNotEmpty ? '${_branches.first['id']}' : null;
        _service = _services.isNotEmpty ? '${_services.first['id']}' : null;
        _vehicle = _vehicles.isNotEmpty ? '${_vehicles.first['id']}' : null;
      });
      await _reload();
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _reload() async {
    if (!mounted) {
      return;
    }
    final version = ++_requestVersion;
    setState(() {
      _busy = true;
      _slotsBusy = true;
      _error = null;
    });
    try {
      final response = await _api.request(
        'GET',
        '/schedule/agenda-24d',
        query: {'date': _date(_selected), 'branch_id': ?_branch, 'limit': '30'},
      );
      if (!mounted || version != _requestVersion) {
        return;
      }
      setState(() {
        _reservations = _records(response['data']);
        _weekBookings = _records(response['week_bookings']);
        _confirmedCount =
            int.tryParse('${response['confirmed_on_date'] ?? 0}') ?? 0;
        _todayCount = int.tryParse('${response['today_count'] ?? 0}') ?? 0;
        _busy = false;
      });
      await _loadSlots(version);
    } catch (error) {
      if (mounted && version == _requestVersion) {
        setState(() {
          _busy = false;
          _slotsBusy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _loadSlots(int version) async {
    if (_branch == null || _service == null || _vehicle == null) {
      if (mounted && version == _requestVersion) {
        setState(() {
          _slots = [];
          _availableCount = 0;
          _slotsBusy = false;
          _availabilityMessage = 'Selecciona sucursal, servicio y vehículo.';
        });
      }
      return;
    }
    try {
      final response = await _api.request(
        'GET',
        '/schedule/availability-24d',
        query: {
          'date': _date(_selected),
          'branch_id': _branch!,
          'service_id': _service!,
          'vehicle_id': _vehicle!,
        },
      );
      if (!mounted || version != _requestVersion) {
        return;
      }
      final slots = _records(response['slots']);
      setState(() {
        _slots = slots;
        _availableCount = slots.where((s) => s['available'] == true).length;
        _availabilityMessage = response['message']?.toString();
        _slotsBusy = false;
      });
    } catch (error) {
      if (mounted && version == _requestVersion) {
        setState(() {
          _slots = [];
          _availableCount = 0;
          _slotsBusy = false;
          _availabilityMessage = '$error';
        });
      }
    }
  }

  void _setDate(DateTime next) {
    final today = DateTime.now();
    final d = DateTime(next.year, next.month, next.day);
    final horizon = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(const Duration(days: 180));
    if (d.isBefore(DateTime(today.year, today.month, today.day)) ||
        d.isAfter(horizon)) {
      return;
    }
    setState(() {
      _selected = d;
      _month = DateTime(d.year, d.month);
    });
    _reload();
  }

  void _changeMonth(int offset) {
    setState(() => _month = DateTime(_month.year, _month.month + offset));
  }

  Map<String, String> _defaults([Map<String, dynamic>? slot]) => {
    'branch_id': ?_branch,
    'service_id': ?_service,
    'vehicle_id': ?_vehicle,
    'local_date': _date(_selected),
    if (slot != null) 'start_time': '${slot['time']}',
    if (slot != null && slot['bay_id'] != null) 'bay_id': '${slot['bay_id']}',
  };

  Future<void> _create([Map<String, dynamic>? slot]) async {
    await widget.onCreate(_defaults(slot));
    if (mounted) {
      await _reload();
    }
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(17),
  }) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: _edge),
    ),
    child: child,
  );

  Widget _identity() => ValueListenableBuilder<BusinessIdentityData>(
    valueListenable: BusinessIdentity.current,
    builder: (context, identity, _) => Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Agenda y reservas',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Gestiona citas según disponibilidad de horarios, lavadores y puestos.',
                style: TextStyle(color: _muted),
              ),
            ],
          ),
        ),
        Container(width: 1, height: 64, color: _edge),
        const SizedBox(width: 14),
        SizedBox(
          width: 145,
          height: 76,
          child: identity.logoBytes == null
              ? Center(
                  child: Text(
                    identity.companyName.isEmpty
                        ? 'Mi empresa'
                        : identity.companyName,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: CompanyVisualTheme.text),
                  ),
                )
              : Image.memory(
                  identity.logoBytes!,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
        ),
      ],
    ),
  );

  Widget _selector(
    String label,
    String? value,
    List<Map<String, dynamic>> items,
    ValueChanged<String?> onChange,
    String Function(Map<String, dynamic>) formatter,
  ) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 150, maxWidth: 270),
    child: DropdownButtonFormField<String>(
      key: ValueKey('agenda_${label}_$value'),
      initialValue: value,
      isExpanded: true,
      dropdownColor: _surface,
      style: TextStyle(color: CompanyVisualTheme.text, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _muted),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
      ),
      items: items
          .map(
            (e) => DropdownMenuItem<String>(
              value: '${e['id']}',
              child: Text(formatter(e), overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: onChange,
    ),
  );

  Widget _metric(
    String label,
    String value,
    IconData icon,
    String detail,
  ) => _panel(
    padding: const EdgeInsets.all(15),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(color: _muted, fontSize: 13)),
              const SizedBox(height: 5),
              Text(
                value,
                style: TextStyle(
                  color: CompanyVisualTheme.text,
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(detail, style: TextStyle(color: _muted, fontSize: 11)),
            ],
          ),
        ),
        Icon(icon, color: _accent, size: 32),
      ],
    ),
  );

  Widget _calendar() {
    final offset = DateTime(_month.year, _month.month, 1).weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final today = DateTime.now();
    final end = DateTime(
      today.year,
      today.month,
      today.day,
    ).add(const Duration(days: 180));

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${_months[_month.month - 1]} ${_month.year}',
                  style: TextStyle(
                    color: CompanyVisualTheme.text,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Mes anterior',
                onPressed: () => _changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                tooltip: 'Mes siguiente',
                onPressed: () => _changeMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final day in _days)
                Expanded(
                  child: Center(
                    child: Text(
                      day,
                      style: TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          for (var week = 0; week < ((offset + days + 6) ~/ 7); week++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  for (var col = 0; col < 7; col++)
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final day = week * 7 + col - offset + 1;
                          if (day < 1 || day > days) {
                            return const SizedBox(height: 43);
                          }
                          final date = DateTime(_month.year, _month.month, day);
                          final disabled =
                              date.isBefore(
                                DateTime(today.year, today.month, today.day),
                              ) ||
                              date.isAfter(end);
                          final selected = _date(date) == _date(_selected);
                          final isToday = _date(date) == _date(today);
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: InkWell(
                              onTap: disabled ? null : () => _setDate(date),
                              borderRadius: BorderRadius.circular(9),
                              child: Container(
                                height: 43,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? _accent
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: isToday && !selected
                                        ? _accent
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  '$day',
                                  style: TextStyle(
                                    color: disabled
                                        ? _muted.withValues(alpha: .38)
                                        : selected
                                        ? Colors.black
                                        : Colors.white,
                                    fontWeight: selected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Text(
            'Fecha seleccionada: ${_date(_selected)}',
            style: TextStyle(color: _muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _weekCalendar() {
    final monday = _selected.subtract(Duration(days: _selected.weekday - 1));
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Semana seleccionada',
                  style: TextStyle(
                    color: CompanyVisualTheme.text,
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: () =>
                    _setDate(_selected.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left),
              ),
              IconButton(
                onPressed: () =>
                    _setDate(_selected.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 6,
            runSpacing: 7,
            children: [
              for (var i = 0; i < 7; i++)
                Builder(
                  builder: (context) {
                    final d = monday.add(Duration(days: i));
                    final today = DateTime.now();
                    final disabled =
                        d.isBefore(
                          DateTime(today.year, today.month, today.day),
                        ) ||
                        d.isAfter(
                          DateTime(
                            today.year,
                            today.month,
                            today.day,
                          ).add(const Duration(days: 180)),
                        );
                    return ChoiceChip(
                      label: Text('${_days[i]} ${d.day}'),
                      selected: _date(d) == _date(_selected),
                      onSelected: disabled ? null : (_) => _setDate(d),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            'Citas programadas por día · selecciona un día para ver disponibilidad.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, bounds) {
              final columns = bounds.maxWidth >= 530
                  ? 7
                  : bounds.maxWidth >= 320
                  ? 3
                  : 2;
              final width = (bounds.maxWidth - (columns - 1) * 6) / columns;
              return Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (var i = 0; i < 7; i++)
                    Builder(
                      builder: (context) {
                        final day = monday.add(Duration(days: i));
                        final bookings = _weekBookings
                            .where((b) => b['local_date'] == _date(day))
                            .toList();
                        return SizedBox(
                          width: width,
                          child: InkWell(
                            onTap: () => _setDate(day),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: _date(day) == _date(_selected)
                                      ? _accent
                                      : _edge,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${_days[i]} ${day.day}',
                                    style: TextStyle(
                                      color: CompanyVisualTheme.text,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (bookings.isEmpty)
                                    Text(
                                      'Sin citas',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                  for (final booking in bookings.take(5))
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Text(
                                        '${booking['start_time'] ?? ''} ${booking['vehicle_label'] ?? ''}',
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: _accent,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ),
                                  if (bookings.length > 5)
                                    Text(
                                      '+${bookings.length - 5}',
                                      style: TextStyle(
                                        color: _muted,
                                        fontSize: 10,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _availability() => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Horarios disponibles',
          style: TextStyle(
            color: CompanyVisualTheme.text,
            fontSize: 19,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(_date(_selected), style: TextStyle(color: _muted)),
        const SizedBox(height: 18),
        if (_slotsBusy)
          const Center(child: CircularProgressIndicator())
        else if (_slots.isEmpty)
          Text(
            _availabilityMessage ??
                'No hay horarios disponibles para esta fecha y servicio.',
            style: TextStyle(color: _muted),
          )
        else
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth;
              final col = width >= 310 ? 2 : 1;
              final cell = (width - (col - 1) * 10) / col;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final slot in _slots)
                    SizedBox(
                      width: cell,
                      child: Tooltip(
                        message: '${slot['reason'] ?? ''}',
                        child: InkWell(
                          onTap: slot['available'] == true
                              ? () => _create(slot)
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              color: slot['available'] == true
                                  ? _accent.withValues(alpha: .12)
                                  : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHighest,
                              border: Border.all(
                                color: slot['available'] == true
                                    ? _accent
                                    : _muted.withValues(alpha: .35),
                              ),
                            ),
                            child: Column(
                              children: [
                                Text(
                                  '${slot['time']}',
                                  style: TextStyle(
                                    color: CompanyVisualTheme.text,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 17,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  slot['available'] == true
                                      ? 'Disponible'
                                      : 'Ocupado',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: slot['available'] == true
                                        ? _accent
                                        : _muted,
                                  ),
                                ),
                              ],
                            ),
                          ),
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

  Widget _reservationRow(Map<String, dynamic> row) {
    final vehicle = int.tryParse('${row['vehicle_id']}') ?? 0;
    final plate = '${row['vehicle_plate'] ?? 'Sin placa'}';
    final brand = '${row['vehicle_brand'] ?? ''} ${row['vehicle_model'] ?? ''}'
        .trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh
            .withValues(alpha: .45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _edge.withValues(alpha: .58)),
      ),
      child: LayoutBuilder(
        builder: (context, bounds) {
          final narrow = bounds.maxWidth < 620;
          final photo = SizedBox(
            width: 76,
            height: 64,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: vehicle > 0
                  ? CompanyVehiclePhoto24C2(
                      client: widget.client,
                      vehicleId: vehicle,
                    )
                  : const Icon(Icons.directions_car_outlined),
            ),
          );
          final info = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                brand.isEmpty ? 'Vehículo registrado' : brand,
                style: TextStyle(
                  color: CompanyVisualTheme.text,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'Placa: $plate',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              Text(
                '${row['client_name'] ?? 'Cliente no disponible'}',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          );
          final date = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${row['local_date'] ?? ''}  ${row['start_time'] ?? ''}',
                style: TextStyle(color: CompanyVisualTheme.text),
              ),
              Text(
                '${row['service_name'] ?? 'Servicio'}',
                style: TextStyle(color: _muted),
              ),
            ],
          );
          final action = Wrap(
            spacing: 1,
            children: [
              IconButton(
                tooltip: 'Consultar',
                onPressed: () => widget.onDetails(row),
                icon: const Icon(Icons.visibility_outlined, size: 20),
              ),
              IconButton(
                tooltip: 'Reprogramar o editar',
                onPressed: () async {
                  await widget.onEdit(row);
                  if (mounted) {
                    await _reload();
                  }
                },
                icon: Icon(Icons.edit_outlined, color: _accent, size: 20),
              ),
              IconButton(
                tooltip: 'Cancelar reserva',
                onPressed: () async {
                  await widget.onCancel(row);
                  if (mounted) {
                    await _reload();
                  }
                },
                icon: Icon(
                  Icons.event_busy_outlined,
                  color: CompanyVisualTheme.legacy(const Color(0xFFE84657)),
                  size: 20,
                ),
              ),
            ],
          );
          if (narrow) {
            return Column(
              children: [
                Row(
                  children: [
                    photo,
                    const SizedBox(width: 10),
                    Expanded(child: info),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: date),
                    const SizedBox(width: 5),
                    action,
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              photo,
              const SizedBox(width: 12),
              Expanded(flex: 3, child: info),
              Expanded(flex: 2, child: date),
              Text(
                '${row['status'] ?? ''}',
                style: TextStyle(color: _accent, fontSize: 12),
              ),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _upcoming() => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Próximas reservas',
                style: TextStyle(
                  color: CompanyVisualTheme.text,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            TextButton(
              onPressed: widget.onViewAll,
              child: const Text('Ver todas'),
            ),
          ],
        ),
        const SizedBox(height: 13),
        if (_busy)
          const Center(child: CircularProgressIndicator())
        else if (_reservations.isEmpty)
          Text(
            'No hay próximas reservas',
            style: TextStyle(color: _muted),
          )
        else
          for (final row in _reservations) _reservationRow(row),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(5),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _identity(),
        const SizedBox(height: 19),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () => _create(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva reserva'),
              style: FilledButton.styleFrom(backgroundColor: _accent),
            ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _weekly = !_weekly),
              icon: const Icon(Icons.calendar_view_week_outlined),
              label: Text(_weekly ? 'Vista mensual' : 'Vista semanal'),
            ),
            IconButton(
              tooltip: 'Actualizar agenda',
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _selector('Sucursal', _branch, _branches, (v) {
              setState(() => _branch = v);
              _reload();
            }, (e) => '${e['name']}'),
            _selector('Servicio', _service, _services, (v) {
              setState(() => _service = v);
              _reload();
            }, (e) => '${e['name']} · ${e['duration_minutes']} min'),
            _selector(
              'Vehículo',
              _vehicle,
              _vehicles,
              (v) {
                setState(() => _vehicle = v);
                _reload();
              },
              (e) =>
                  '${e['brand'] ?? ''} ${e['model'] ?? ''} · ${e['plate'] ?? ''}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            final width = c.maxWidth;
            final cells = width >= 670
                ? 3
                : width >= 400
                ? 2
                : 1;
            final cell = (width - (cells - 1) * 12) / cells;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: cell,
                  child: _metric(
                    'Reservas del día',
                    _todayCount.toString(),
                    Icons.event_note_outlined,
                    'Hoy · sucursal seleccionada',
                  ),
                ),
                SizedBox(
                  width: cell,
                  child: _metric(
                    'Disponibles',
                    _slotsBusy
                        ? '…'
                        : (_branch == null ||
                                  _service == null ||
                                  _vehicle == null
                              ? '—'
                              : '$_availableCount'),
                    Icons.access_time,
                    'Fecha y servicio seleccionados',
                  ),
                ),
                SizedBox(
                  width: cell,
                  child: _metric(
                    'Confirmadas',
                    _confirmedCount.toString(),
                    Icons.verified_outlined,
                    'Fecha seleccionada',
                  ),
                ),
              ],
            );
          },
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _error!,
                    style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995))),
                  ),
                ),
                TextButton(onPressed: _reload, child: const Text('Reintentar')),
              ],
            ),
          ),
        const SizedBox(height: 15),
        LayoutBuilder(
          builder: (context, c) => c.maxWidth >= 650
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _weekly ? _weekCalendar() : _calendar()),
                    const SizedBox(width: 13),
                    Expanded(child: _availability()),
                  ],
                )
              : Column(
                  children: [
                    _weekly ? _weekCalendar() : _calendar(),
                    const SizedBox(height: 13),
                    _availability(),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        _upcoming(),
      ],
    ),
  );
}
