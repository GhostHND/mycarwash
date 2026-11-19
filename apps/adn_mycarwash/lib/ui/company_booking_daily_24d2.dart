import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// Avisos del día por sucursal. La asignación NO inicia una orden operativa.
class CompanyBookingDaily24D2 extends StatefulWidget {
  const CompanyBookingDaily24D2({
    super.key,
    required this.client,
    required this.branchId,
  });

  final http.Client client;
  final String branchId;

  @override
  State<CompanyBookingDaily24D2> createState() =>
      _CompanyBookingDaily24D2State();
}

class _CompanyBookingDaily24D2State extends State<CompanyBookingDaily24D2> {
  bool _loading = true;
  bool _dialogOpen = false;
  bool _morningSeen = false;
  bool _reminderSeen = false;
  bool _receptionSeen = false;
  Timer? _arrivalPoller;
  bool _arrivalChecking = false;
  String? _error;
  Map<String, dynamic> _data = {};

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _refresh();
    _arrivalPoller = Timer.periodic(const Duration(seconds: 30), (_) => _checkArrival24N7());
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkArrival24N7());
  }

  @override
  void dispose() {
    _arrivalPoller?.cancel();
    super.dispose();
  }

  Future<void> _checkArrival24N7() async {
    if (!mounted || _dialogOpen || _arrivalChecking) { return; }
    _arrivalChecking = true;
    try {
      final response = await _api.request('GET', '/workflow/arrival-reminders-24n7',
        query: {'branch_id': widget.branchId});
      final rows = _items(response['data']);
      if (!mounted || rows.isEmpty || _dialogOpen) { return; }
      _dialogOpen = true;
      try {
        await showDialog<void>(context: context, barrierDismissible: false,
          builder: (dialog) => AlertDialog(
            title: const Text('Reservas próximas · revisar llegada'),
            content: SizedBox(width: 550, child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Estas citas comienzan dentro de los próximos 10 minutos. '
                  'Confirma la recepción real del vehículo en Órdenes de lavado → Reservadas.'),
                const SizedBox(height: 10),
                for (final row in rows)
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text('${row['vehicle_label']} · ${row['plate']}'),
                    subtitle: Text('${row['client_name'] ?? 'Cliente'} · ${row['local_time']} · ${row['service_name']}'),
                  ),
              ]),
            )),
            actions: [FilledButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Entendido · revisar en Reservadas'),
            )],
          ),
        );
        for (final row in rows) {
          try {
            await _api.request('POST',
              '/workflow/reservations-24n7/${row['id']}/arrival-read');
          } catch (_) {
            // Un error de red conserva el aviso pendiente para reintentar.
          }
        }
      } finally {
        _dialogOpen = false;
      }
    } catch (_) {
      // Fallo de red: la siguiente consulta volverá a intentar.
    } finally {
      _arrivalChecking = false;
    }
  }

  List<Map<String, dynamic>> _items(dynamic value) {
    if (value is! List) {
      return [];
    }
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _refresh() async {
    try {
      final data = await _api.request(
        'GET',
        '/schedule/daily-24d2',
        query: {'branch_id': widget.branchId},
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkAlerts());
    } catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$error';
        });
      }
    }
  }

  void _checkAlerts() {
    if (!mounted || _dialogOpen) {
      return;
    }
    final pending = _items(_data['today'])
        .where((r) => r['employee_id'] == null)
        .toList();
    if (pending.isNotEmpty && !_morningSeen) {
      _morningSeen = true;
      _openAssignment(pending);
      return;
    }
    final today = _items(_data['today']);
    if (today.isNotEmpty && !_receptionSeen) {
      _receptionSeen = true;
      _openReceptionReview24N7(today);
      return;
    }
    final tomorrow = _items(_data['tomorrow']);
    if (tomorrow.isNotEmpty && !_reminderSeen) {
      _reminderSeen = true;
      _openReminder(tomorrow);
    }
  }

  Future<void> _openReceptionReview24N7(List<Map<String, dynamic>> today) async {
    if (!mounted || _dialogOpen) { return; }
    _dialogOpen = true;
    await showDialog<void>(context: context, builder: (dialog) => AlertDialog(
      title: const Text('Vehículos con reserva para hoy'),
      content: SizedBox(width: 550, child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Comprueba cuáles vehículos han llegado. '
            'En Órdenes de lavado → Reservadas puedes marcar su recepción; '
            'después pasarán a Nuevas para la asignación operativa.'),
          const SizedBox(height: 10),
          for (final row in today)
            ListTile(
              leading: const Icon(Icons.directions_car_outlined),
              title: Text('${row['brand'] ?? ''} ${row['model'] ?? ''} · ${row['plate'] ?? ''}'),
              subtitle: Text('${row['local_time']} · ${row['employee_name'] ?? 'Lavador por asignar'}'),
            ),
        ]),
      )),
      actions: [FilledButton(onPressed: () => Navigator.pop(dialog),
        child: const Text('Entendido'))],
    ));
    _dialogOpen = false;
  }

  String _summary(Map<String, dynamic> booking) {
    return '${booking['brand'] ?? ''} ${booking['model'] ?? ''} · ${booking['plate'] ?? ''}'
        ' · ${booking['client_name'] ?? 'Cliente'} · ${booking['local_time'] ?? ''}';
  }

  Future<void> _openAssignment(List<Map<String, dynamic>> pending) async {
    if (!mounted || _dialogOpen) {
      return;
    }
    _dialogOpen = true;
    final staff = _items(_data['employees']);
    final assignments = <int, int>{};
    String? feedback;
    var busy = false;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, update) => AlertDialog(
          title: const Text('Asignación obligatoria de reservas de hoy'),
          content: SizedBox(
            width: 600,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Selecciona un lavador para cada cita confirmada. '
                    'Las órdenes no comenzarán hasta que se inicie el lavado mediante el flujo operativo.',
                  ),
                  const SizedBox(height: 14),
                  for (final booking in pending)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${booking['service_name'] ?? 'Servicio'} · ${_summary(booking)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'Lavador asignado',
                            ),
                            items: [
                              for (final employee in staff)
                                DropdownMenuItem<int>(
                                  value: int.tryParse('${employee['id']}'),
                                  child: Text('${employee['full_name']}'),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (id) {
                                    if (id != null) {
                                      update(
                                        () =>
                                            assignments[booking['id'] as int] =
                                                id,
                                      );
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                  Text(
                    feedback ?? '',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(dialogContext).pop(),
              child: const Text('Corregir turnos'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      if (assignments.length != pending.length) {
                        update(
                          () => feedback =
                              'Debes asignar todas las reservas pendientes.',
                        );
                        return;
                      }
                      update(() {
                        busy = true;
                        feedback = null;
                      });
                      try {
                        for (final booking in pending) {
                          await _api.request(
                            'POST',
                            '/schedule/daily-24d2/${booking['id']}/assign',
                            body: {
                              'employee_id': assignments[booking['id'] as int],
                            },
                          );
                        }
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (error) {
                        update(() {
                          busy = false;
                          feedback = '$error';
                        });
                      }
                    },
              child: Text(busy ? 'Guardando…' : 'Guardar asignaciones'),
            ),
          ],
        ),
      ),
    );
    _dialogOpen = false;
    if (mounted) {
      await _refresh();
    }
  }

  Future<void> _openReminder(List<Map<String, dynamic>> tomorrow) async {
    if (!mounted || _dialogOpen) {
      return;
    }
    _dialogOpen = true;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Reservas programadas para mañana'),
        content: SizedBox(
          width: 550,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final row in tomorrow)
                  ListTile(
                    leading: const Icon(Icons.notifications_active_outlined),
                    title: Text(
                      '${row['client_name'] ?? 'Cliente'} · ${row['service_name'] ?? 'Lavado'}',
                    ),
                    subtitle: Text(
                      '${row['brand'] ?? ''} ${row['model'] ?? ''} · ${row['plate'] ?? ''} · '
                      '${row['local_time'] ?? ''}',
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              try {
                await _api.request(
                  'POST',
                  '/schedule/daily-24d2/reminder-read',
                  body: {'branch_id': int.parse(widget.branchId)},
                );
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
              } catch (error) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext)
                      .showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
    _dialogOpen = false;
    if (mounted) {
      await _refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _items(_data['today'])
        .where((r) => r['employee_id'] == null)
        .toList();
    final tomorrow = _items(_data['tomorrow']);
    if (_loading) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (_error != null) {
      return TextButton.icon(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text(
          'No se pudieron cargar los avisos diarios. Reintentar.',
        ),
      );
    }
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        if (pending.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _openAssignment(pending),
            icon: const Icon(Icons.assignment_ind_outlined),
            label: Text('Asignaciones de hoy pendientes: ${pending.length}'),
          ),
        if (tomorrow.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => _openReminder(tomorrow),
            icon: const Icon(Icons.notifications_outlined),
            label: Text('Reservas de mañana: ${tomorrow.length}'),
          ),
      ],
    );
  }
}

/// Se monta una sola vez en el administrador al iniciar sesión.
/// La selección de sucursal permite revisar también otras sedes.
class CompanyBookingDailyStartup24D2 extends StatefulWidget {
  const CompanyBookingDailyStartup24D2({super.key});

  @override
  State<CompanyBookingDailyStartup24D2> createState() =>
      _CompanyBookingDailyStartup24D2State();
}

class _CompanyBookingDailyStartup24D2State
    extends State<CompanyBookingDailyStartup24D2> {
  final http.Client _client = http.Client();
  List<Map<String, dynamic>> _branches = [];
  String? _branch;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final response = await CompanyBusinessApi(_client)
          .request('GET', '/schedule/options');
      final raw = response['data'];
      if (raw is! Map || raw['branches'] is! List) {
        return;
      }
      final branches = (raw['branches'] as List)
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      String? firstPending;
      String? firstTomorrow;
      for (final branch in branches) {
        try {
          final id = '${branch['id']}';
          final daily = await CompanyBusinessApi(_client)
              .request('GET', '/schedule/daily-24d2', query: {'branch_id': id});
          final pending = int.tryParse('${daily['pending_count'] ?? 0}') ?? 0;
          if (pending > 0) {
            firstPending = id;
            break;
          }
          if (firstTomorrow == null &&
              daily['tomorrow'] is List &&
              (daily['tomorrow'] as List).isNotEmpty) {
            firstTomorrow = id;
          }
        } catch (_) {
          // El panel concreto mostrará el error y permitirá reintentar.
        }
      }
      if (mounted) {
        setState(() {
          _branches = branches;
          _branch =
              firstPending ??
              firstTomorrow ??
              (branches.isEmpty ? null : '${branches.first['id']}');
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    }
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () {
            setState(() => _error = null);
            _initialize();
          },
          icon: const Icon(Icons.refresh),
          label: const Text('Consultar avisos diarios de reservas'),
        ),
      );
    }
    if (_branch == null) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_branches.length > 1)
            SizedBox(
              width: 270,
              child: DropdownButtonFormField<String>(
                key: ValueKey('branch-dropdown-$_branch'),
                initialValue: _branch,
                decoration: const InputDecoration(
                  labelText: 'Avisos diarios · sucursal',
                ),
                items: [
                  for (final row in _branches)
                    DropdownMenuItem(
                      value: '${row['id']}',
                      child: Text('${row['name']}'),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _branch = value);
                  }
                },
              ),
            ),
          CompanyBookingDaily24D2(
            key: ValueKey('booking-daily-$_branch'),
            client: _client,
            branchId: _branch!,
          ),
        ],
      ),
    );
  }
}
