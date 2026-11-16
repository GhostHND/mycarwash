import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

enum BookingModule { shifts, roster, blocks, bookings }

class _Field {
  const _Field(
    this.key,
    this.name, {
    this.mandatory = false,
    this.option,
    this.date = false,
    this.clock = false,
    this.multiline = false,
  });
  final String key;
  final String name;
  final bool mandatory;
  final String? option;
  final bool date;
  final bool clock;
  final bool multiline;
}

class CompanyBookingPage extends StatefulWidget {
  const CompanyBookingPage({super.key, required this.module, this.client});
  final BookingModule module;
  final http.Client? client;

  @override
  State<CompanyBookingPage> createState() => _CompanyBookingPageState();
}

class _CompanyBookingPageState extends State<CompanyBookingPage> {
  static const Color _turquoise = Color(0xFF0FA7B4);
  static const Color _muted = Color(0xFF9BAEB6);
  static const Color _border = Color(0xFF20343C);
  static const Color _surface = Color(0xFF0A1519);

  late final http.Client _client;
  late final bool _ownsClient;
  final _search = TextEditingController();
  Timer? _debounce;
  int _version = 0;
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  String get _resource => switch (widget.module) {
    BookingModule.shifts => 'shifts',
    BookingModule.roster => 'roster',
    BookingModule.blocks => 'blocks',
    BookingModule.bookings => 'bookings',
  };
  String get _path => '/schedule/$_resource';
  String get _title => switch (widget.module) {
    BookingModule.shifts => 'Turnos de trabajo',
    BookingModule.roster => 'Asignaciones de turnos',
    BookingModule.blocks => 'Bloqueos de agenda',
    BookingModule.bookings => 'Reservas',
  };
  String get _single => switch (widget.module) {
    BookingModule.shifts => 'turno',
    BookingModule.roster => 'asignación',
    BookingModule.blocks => 'bloqueo',
    BookingModule.bookings => 'reserva',
  };
  String get _description => switch (widget.module) {
    BookingModule.shifts => 'Horarios laborales semanales por sucursal.',
    BookingModule.roster =>
      'Lavadores que cubren cada turno y fechas de vigencia.',
    BookingModule.blocks =>
      'Mantenimiento, cierres temporales y puestos no disponibles.',
    BookingModule.bookings =>
      'Citas verificadas contra horarios, personal y puestos.',
  };

  List<_Field> get _fields => switch (widget.module) {
    BookingModule.shifts => const [
      _Field('branch_id', 'Sucursal', mandatory: true, option: 'branches'),
      _Field('name', 'Nombre del turno', mandatory: true),
      _Field(
        'day_of_week',
        'Día de la semana',
        mandatory: true,
        option: 'weekdays',
      ),
      _Field('starts_at', 'Entrada', mandatory: true, clock: true),
      _Field('ends_at', 'Salida', mandatory: true, clock: true),
      _Field('notes', 'Observaciones', multiline: true),
    ],
    BookingModule.roster => const [
      _Field('shift_id', 'Turno', mandatory: true, option: 'shifts'),
      _Field('employee_id', 'Lavador', mandatory: true, option: 'employees'),
      _Field('effective_from', 'Vigente desde', mandatory: true, date: true),
      _Field('effective_to', 'Vigente hasta (opcional)', date: true),
      _Field('notes', 'Observaciones', multiline: true),
    ],
    BookingModule.blocks => const [
      _Field('branch_id', 'Sucursal', mandatory: true, option: 'branches'),
      _Field('bay_id', 'Puesto (vacío = toda la sucursal)', option: 'bays'),
      _Field('local_date', 'Fecha del bloqueo', mandatory: true, date: true),
      _Field('start_time', 'Desde', mandatory: true, clock: true),
      _Field('end_time', 'Hasta', mandatory: true, clock: true),
      _Field('reason', 'Motivo', mandatory: true),
    ],
    BookingModule.bookings => const [
      _Field('branch_id', 'Sucursal', mandatory: true, option: 'branches'),
      _Field('vehicle_id', 'Vehículo', mandatory: true, option: 'vehicles'),
      _Field('service_id', 'Servicio', mandatory: true, option: 'services'),
      _Field('bay_id', 'Puesto de lavado', mandatory: true, option: 'bays'),
      _Field('local_date', 'Fecha de la cita', mandatory: true, date: true),
      _Field('start_time', 'Hora de inicio', mandatory: true, clock: true),
      _Field('notes', 'Observaciones', multiline: true),
    ],
  };

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyBookingPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      _search.clear();
      _page = 1;
      _load();
    }
  }

  @override
  void dispose() {
    _version++;
    _debounce?.cancel();
    _search.dispose();
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.request(
        'GET',
        _path,
        query: {'q': _search.text.trim(), 'page': '$_page', 'per_page': '10'},
      );
      if (!mounted || version != _version) {
        return;
      }
      final raw = result['data'];
      setState(() {
        _rows = raw is List
            ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
        _page = int.tryParse('${result['current_page'] ?? 1}') ?? 1;
        _pages = int.tryParse('${result['last_page'] ?? 1}') ?? 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _version) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _page = 1;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _load();
      }
    });
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted),
    filled: true,
    fillColor: const Color(0xFF111F25),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: _border),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: _turquoise),
      borderRadius: BorderRadius.circular(10),
    ),
  );

  static String _label(String field, Map<String, dynamic> row) {
    if (field == 'branches') {
      return '${row['name']}';
    }
    if (field == 'bays') {
      return '${row['name']} (${row['code']})';
    }
    if (field == 'shifts') {
      return '${row['name']} (día ${row['day_of_week']})';
    }
    if (field == 'vehicles') {
      return [row['brand'], row['model'], row['plate']]
          .where((value) => value != null && '$value'.trim().isNotEmpty)
          .join(' · ');
    }
    if (field == 'services') {
      return '${row['name']} · ${row['duration_minutes']} min · L ${row['price']}';
    }
    return '${row['full_name'] ?? row['name'] ?? row['id']}';
  }

  List<DropdownMenuItem<String>> _choices(
    _Field field,
    Map<String, dynamic> options,
    String? branchId,
  ) {
    if (field.option == 'weekdays') {
      const days = [
        'Domingo',
        'Lunes',
        'Martes',
        'Miércoles',
        'Jueves',
        'Viernes',
        'Sábado',
      ];
      return [
        for (var i = 0; i < 7; i++)
          DropdownMenuItem<String>(value: '$i', child: Text(days[i])),
      ];
    }
    final raw = options[field.option];
    if (raw is! List) {
      return [];
    }
    return raw
        .whereType<Map>()
        .where((row) {
          if (field.option == 'bays' || field.option == 'shifts') {
            return branchId == null ||
                branchId.isEmpty ||
                '${row['branch_id']}' == branchId;
          }
          return true;
        })
        .map((row) {
          final map = Map<String, dynamic>.from(row);
          return DropdownMenuItem<String>(
            value: '${row['id']}',
            child: Text(
              _label(field.option!, map),
              overflow: TextOverflow.ellipsis,
            ),
          );
        })
        .toList();
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final current = DateTime.tryParse(controller.text);
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDate: current ?? DateTime.now(),
    );
    if (picked != null && mounted) {
      controller.text =
          '${picked.year.toString().padLeft(4, '0')}-'
          '${picked.month.toString().padLeft(2, '0')}-'
          '${picked.day.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _pickTime(TextEditingController controller) async {
    final parts = controller.text.split(':');
    final h = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
    final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
    final initial =
        h != null && h >= 0 && h < 24 && m != null && m >= 0 && m < 60
        ? TimeOfDay(hour: h, minute: m)
        : const TimeOfDay(hour: 9, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      controller.text =
          '${picked.hour.toString().padLeft(2, '0')}:'
          '${picked.minute.toString().padLeft(2, '0')}';
    }
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    Map<String, dynamic> options;
    try {
      final response = await _api.request('GET', '/schedule/options');
      options = Map<String, dynamic>.from(response['data'] as Map);
    } catch (error) {
      _notice('No se pudo cargar el formulario: $error', error: true);
      return;
    }
    if (!mounted) {
      return;
    }
    final fields = _fields;
    final controllers = <String, TextEditingController>{
      for (final field in fields)
        field.key: TextEditingController(
          text: field.clock && existing?[field.key] != null
              ? existing![field.key].toString().substring(0, 5)
              : (existing?[field.key] ?? '').toString(),
        ),
    };
    final key = GlobalKey<FormState>();
    var active =
        existing == null ||
        existing['is_active'] == true ||
        existing['is_active'] == 1;
    var saving = false;
    String? dialogError;
    // Evita liberar controladores mientras sigue montado el Overlay.
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          backgroundColor: _surface,
          title: Text(
            existing == null ? 'Nuevo $_single' : 'Editar $_single',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in fields) ...[
                      Builder(
                        builder: (context) {
                          if (field.option != null) {
                            final values = _choices(
                              field,
                              options,
                              controllers['branch_id']?.text,
                            );
                            final current = controllers[field.key]!.text;
                            final selected =
                                values.any((e) => e.value == current)
                                ? current
                                : null;
                            return DropdownButtonFormField<String>(
                              key: ValueKey('${field.key}:$selected'),
                              initialValue: selected,
                              isExpanded: true,
                              dropdownColor: _surface,
                              decoration: _decoration(field.name),
                              items: [
                                if (!field.mandatory)
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Sin asignar'),
                                  ),
                                ...values,
                              ],
                              onChanged:
                                  saving ||
                                      (existing != null &&
                                          field.key == 'branch_id')
                                  ? null
                                  : (value) {
                                      controllers[field.key]!.text =
                                          value ?? '';
                                      if (field.key == 'branch_id') {
                                        controllers['bay_id']?.clear();
                                        update(() {});
                                      }
                                    },
                              validator: (value) =>
                                  field.mandatory &&
                                      (value == null || value.isEmpty)
                                  ? 'Selecciona una opción.'
                                  : null,
                            );
                          }
                          return TextFormField(
                            key: ValueKey('booking_${field.key}'),
                            controller: controllers[field.key],
                            readOnly: field.date || field.clock,
                            onTap: field.date
                                ? () => _pickDate(controllers[field.key]!)
                                : field.clock
                                ? () => _pickTime(controllers[field.key]!)
                                : null,
                            enabled: !saving,
                            keyboardType: TextInputType.text,
                            maxLines: field.multiline ? 3 : 1,
                            style: const TextStyle(color: Colors.white),
                            decoration: _decoration(field.name).copyWith(
                              suffixIcon: field.date
                                  ? const Icon(Icons.calendar_month_outlined)
                                  : field.clock
                                  ? const Icon(Icons.access_time_outlined)
                                  : null,
                            ),
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (field.mandatory && v.isEmpty) {
                                return 'Este campo es obligatorio.';
                              }
                              if (field.date &&
                                  v.isNotEmpty &&
                                  !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) {
                                return 'Fecha inválida.';
                              }
                              if (field.clock &&
                                  v.isNotEmpty &&
                                  !RegExp(r'^([01]\d|2[0-3]):[0-5]\d$')
                                      .hasMatch(v)) {
                                return 'Hora inválida.';
                              }
                              return null;
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 13),
                    ],
                    if (widget.module != BookingModule.bookings)
                      SwitchListTile(
                        title: const Text('Activo'),
                        value: active,
                        activeThumbColor: _turquoise,
                        onChanged: saving
                            ? null
                            : (v) => update(() => active = v),
                      ),
                    if (dialogError != null)
                      Text(
                        dialogError!,
                        style: const TextStyle(color: Color(0xFFFF8995)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (key.currentState?.validate() != true) {
                        return;
                      }
                      update(() {
                        saving = true;
                        dialogError = null;
                      });
                      final data = <String, dynamic>{};
                      for (final f in fields) {
                        final v = controllers[f.key]!.text.trim();
                        if (v.isEmpty) {
                          data[f.key] = null;
                        } else if (f.option != null) {
                          data[f.key] = int.parse(v);
                        } else {
                          data[f.key] = v;
                        }
                      }
                      if (widget.module != BookingModule.bookings) {
                        data['is_active'] = active;
                      }
                      if (existing != null &&
                          (widget.module == BookingModule.shifts ||
                              widget.module == BookingModule.blocks ||
                              widget.module == BookingModule.bookings)) {
                        data.remove('branch_id');
                      }
                      try {
                        await _api.request(
                          existing == null ? 'POST' : 'PATCH',
                          existing == null ? _path : '$_path/${existing['id']}',
                          body: data,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          update(() {
                            saving = false;
                            dialogError = error.toString();
                          });
                        }
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              style: FilledButton.styleFrom(backgroundColor: _turquoise),
              label: Text(saving ? 'Guardando...' : 'Guardar $_single'),
            ),
          ],
        ),
      ),
    );
    try {
      final changed = await Navigator.of(
        context,
        rootNavigator: true,
      ).push<bool>(route);
      await route.completed;
      if (changed == true && mounted) {
        _notice('Registro guardado.');
        _page = 1;
        await _load();
      }
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _details(Map<String, dynamic> row) async {
    try {
      final result = await _api.request('GET', '$_path/${row['id']}');
      if (!mounted) {
        return;
      }
      final info = Map<String, dynamic>.from(result['data'] as Map);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _surface,
          title: Text('Detalle de $_single'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in info.entries)
                    if (![
                      'created_at',
                      'updated_at',
                      'deleted_at',
                    ].contains(f.key))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Text('${f.key}: ${f.value ?? '—'}'),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      _notice(error.toString(), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Eliminar $_single'),
        content: Text(
          '¿Confirmas eliminar el registro ${row['id']}? '
          'Se conservará el historial correspondiente.',
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
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _api.request('DELETE', '$_path/${row['id']}');
      if (!mounted) {
        return;
      }
      _notice('Registro eliminado de los activos.');
      await _load();
      if (_rows.isEmpty && _page > 1 && mounted) {
        _page--;
        await _load();
      }
    } catch (error) {
      _notice(error.toString(), error: true);
    }
  }

  String _summary(Map<String, dynamic> row) => switch (widget.module) {
    BookingModule.shifts =>
      '${row['name'] ?? 'Turno'} · Día ${row['day_of_week']} '
          '· ${row['starts_at']}–${row['ends_at']}',
    BookingModule.roster =>
      '${row['employee_name'] ?? row['employee_id']} '
          '· ${row['shift_name'] ?? row['shift_id']} '
          '· ${row['effective_from']}–${row['effective_to'] ?? 'Indefinido'}',
    BookingModule.blocks =>
      '${row['reason'] ?? 'Bloqueo'} · ${row['local_date']} '
          '· ${row['start_time']}–${row['end_time']}',
    BookingModule.bookings =>
      '${row['vehicle_label'] ?? 'Vehículo'} '
          '· ${row['service_name'] ?? 'Servicio'} '
          '· ${row['local_date']} ${row['start_time']}',
  };

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_description, style: const TextStyle(color: _muted)),
              ],
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text('Nuevo $_single'),
              style: FilledButton.styleFrom(backgroundColor: _turquoise),
            ),
          ],
        ),
        const SizedBox(height: 19),
        TextField(
          controller: _search,
          onChanged: _searchChanged,
          decoration: _decoration(
            'Buscar registros',
          ).copyWith(prefixIcon: const Icon(Icons.search, color: _turquoise)),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: _turquoise)),
          )
        else if (_error != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8995))),
              OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          )
        else if (_rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No hay registros.', style: TextStyle(color: _muted)),
            ),
          )
        else
          for (final row in _rows)
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_available_outlined, color: _turquoise),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _summary(row),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID ${row['id']}',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Consultar',
                    onPressed: () => _details(row),
                    icon: const Icon(Icons.visibility_outlined, color: _muted),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed: () => _edit(row),
                    icon: const Icon(Icons.edit_outlined, color: _turquoise),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed: () => _delete(row),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFE84657),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Página anterior',
              onPressed: _loading || _page <= 1
                  ? null
                  : () {
                      _page--;
                      _load();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              'Página $_page de $_pages',
              style: const TextStyle(color: _muted),
            ),
            IconButton(
              tooltip: 'Página siguiente',
              onPressed: _loading || _page >= _pages
                  ? null
                  : () {
                      _page++;
                      _load();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );
}
