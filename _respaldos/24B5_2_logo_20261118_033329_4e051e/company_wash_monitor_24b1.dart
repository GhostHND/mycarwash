import 'dart:async';
import 'dart:typed_data';

import '../core/mycarwash_session.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/business_identity.dart';
import '../core/company_business_api.dart';

/// Bloque 24B.1: vista administrativa y tema editable del monitor.
/// No configura ni otorga acceso a hardware Raspberry Pi.
class CompanyWashMonitor24B1 extends StatefulWidget {
  const CompanyWashMonitor24B1({super.key, this.client});
  final http.Client? client;

  @override
  State<CompanyWashMonitor24B1> createState() => _CompanyWashMonitor24B1State();
}

class _CompanyWashMonitor24B1State extends State<CompanyWashMonitor24B1> {
  static const fields = <String, String>{
    'primary_color': 'Acentos (antes azul/turquesa)',
    'secondary_color': 'Color secundario',
    'accent_color': 'Destacados',
    'background_color': 'Fondo del monitor',
    'surface_color': 'Fondo de tarjetas',
    'text_color': 'Texto principal',
    'muted_text_color': 'Texto secundario',
    'sidebar_color': 'Panel secundario',
    'button_color': 'Botones e indicadores',
    'success_color': 'Estado completado',
    'warning_color': 'Estado en espera',
    'danger_color': 'Estado de error',
    'border_color': 'Bordes',
    'queue_color': 'Barra inferior de espera',
  };
  static const defaults = <String, String>{
    'primary_color': '#00DCE5',
    'secondary_color': '#0B292F',
    'accent_color': '#00DCE5',
    'background_color': '#050C0F',
    'surface_color': '#071E23',
    'text_color': '#F4F7F8',
    'muted_text_color': '#A5B6BB',
    'sidebar_color': '#0B292F',
    'button_color': '#00DCE5',
    'success_color': '#00D99A',
    'warning_color': '#F59E0B',
    'danger_color': '#EC488A',
    'border_color': '#00DCE5',
    'queue_color': '#073039',
  };
  late final http.Client _client;
  late final bool _ownsClient;
  late final Map<String, TextEditingController> _controllers;
  Timer? _timer;
  Timer? _clockTimer;
  OverlayEntry? _monitorOverlay;
  final Map<int, Uint8List> _vehiclePhotos = <int, Uint8List>{};
  final Set<int> _photoFailures = <int>{};
  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};
  int _offset = 0;
  int _total = 0;
  int _queuePage = 0;
  int _workerRotation = 0;
  bool _editing = false;
  bool _fullscreen = false;
  DateTime _clock = DateTime.now();

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _controllers = {
      for (final entry in fields.entries)
        entry.key: TextEditingController(text: defaults[entry.key]),
    };
    _loadTheme();
    _refresh();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _clock = DateTime.now());
        _monitorOverlay?.markNeedsBuild();
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) {
        return;
      }
      _offset = _total > 4 ? (_offset + 4) % _total : 0;
      _queuePage += 3;
      _workerRotation += 1;
      _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _clockTimer?.cancel();
    _monitorOverlay?.remove();
    _monitorOverlay?.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<void> _loadTheme() async {
    try {
      final response = await _api.request('GET', '/monitor-theme-24b');
      final raw = response['colors'];
      if (!mounted || raw is! Map) {
        return;
      }
      for (final key in fields.keys) {
        final color = (raw[key] ?? '').toString();
        if (RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
          _controllers[key]!.text = color.toUpperCase();
        }
      }
      setState(() {});
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo cargar el tema: $e');
      }
    }
  }

  Future<void> _saveTheme() async {
    if (_saving) {
      return;
    }
    final values = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      final v = entry.value.text.trim().toUpperCase();
      if (!RegExp(r'^#[0-9A-F]{6}$').hasMatch(v)) {
        setState(() => _error = '${fields[entry.key]}: utiliza #RRGGBB');
        return;
      }
      values[entry.key] = v;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.request('PATCH', '/monitor-theme-24b', body: values);
      if (mounted) {
        setState(() => _editing = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se guardaron los colores: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _refresh() async {
    try {
      final response = await _api.request('GET', '/dashboard/monitor-24b2');
      final raw = response['data'];
      if (!mounted || raw is! Map) {
        return;
      }
      setState(() {
        _data = Map<String, dynamic>.from(raw);
        _total = (raw['active_total'] as num?)?.toInt() ?? 0;
        _clock = DateTime.now();
        _error = null;
        _loading = false;
      });
      _monitorOverlay?.markNeedsBuild();
      _loadVehiclePhotos();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Datos no disponibles: $e';
        });
      }
    }
  }

  Color _color(String name) {
    final code = _controllers[name]?.text.trim() ?? defaults[name]!;
    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(code)) {
      return Color(
        int.parse(defaults[name]!.substring(1), radix: 16) | 0xFF000000,
      );
    }
    return Color(int.parse(code.substring(1), radix: 16) | 0xFF000000);
  }

  Widget _businessLogo(double size) {
    return ValueListenableBuilder<BusinessIdentityData>(
      valueListenable: BusinessIdentity.current,
      builder: (context, info, _) {
        final bytes = info.logoBytes;
        return SizedBox(
          height: size,
          width: size,
          child: bytes == null
              ? Icon(
                  Icons.local_car_wash,
                  color: _color('primary_color'),
                  size: size * .7,
                )
              : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
        );
      },
    );
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _color('surface_color'),
      border: Border.all(color: _color('border_color').withValues(alpha: .65)),
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );

  String _name() => BusinessIdentity.current.value.companyName.trim().isEmpty
      ? 'Mi empresa'
      : BusinessIdentity.current.value.companyName;

  Future<void> _loadVehiclePhotos() async {
    final active = _data['active'];
    if (active is! List) {
      return;
    }
    final visible = active.length <= 4
        ? active
        : <dynamic>[
            ...active.skip(_offset % active.length).take(4),
            if (active.length - (_offset % active.length) < 4)
              ...active.take(4 - (active.length - (_offset % active.length))),
          ];
    for (final item in visible) {
      if (item is! Map || item['photo_enabled'] != true) {
        continue;
      }
      final id = (item['vehicle_id'] as num?)?.toInt();
      if (id == null ||
          _vehiclePhotos.containsKey(id) ||
          _photoFailures.contains(id)) {
        continue;
      }
      try {
        final url = Uri.parse(
          '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/vehicles/$id/file',
        );
        final res = await _client
            .get(url, headers: MyCarWashSession.headers)
            .timeout(const Duration(seconds: 12));
        if (!mounted) {
          return;
        }
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          setState(() => _vehiclePhotos[id] = res.bodyBytes);
          _monitorOverlay?.markNeedsBuild();
        } else {
          _photoFailures.add(id);
        }
      } catch (_) {
        _photoFailures.add(id);
      }
    }
  }

  void _openMonitor() {
    if (_monitorOverlay != null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (overlayContext) => Material(
        color: _color('background_color'),
        child: SafeArea(
          child: Stack(
            children: [
              Positioned.fill(child: _monitor()),
              Positioned(
                right: 6,
                top: 4,
                child: IconButton(
                  tooltip: 'Salir del modo monitor',
                  onPressed: _closeMonitor,
                  icon: const Icon(Icons.fullscreen_exit, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    _monitorOverlay = entry;
    Overlay.of(context).insert(entry);
  }

  void _closeMonitor() {
    final entry = _monitorOverlay;
    _monitorOverlay = null;
    entry?.remove();
    entry?.dispose();
  }

  TextStyle _style(
    double size, {
    bool heavy = false,
    String color = 'text_color',
  }) => TextStyle(
    fontSize: size,
    fontWeight: heavy ? FontWeight.w800 : FontWeight.w500,
    color: _color(color),
  );

  String _dateText() {
    const days = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
    const months = [
      'Ene',
      'Feb',
      'Mar',
      'Abr',
      'May',
      'Jun',
      'Jul',
      'Ago',
      'Sep',
      'Oct',
      'Nov',
      'Dic',
    ];
    return '${days[_clock.weekday - 1]}, ${_clock.day} de ${months[_clock.month - 1]} ${_clock.year}';
  }

  String _hourText() {
    final h = _clock.hour % 12 == 0 ? 12 : _clock.hour % 12;
    final m = _clock.minute.toString().padLeft(2, '0');
    return '$h:$m ${_clock.hour < 12 ? 'a. m.' : 'p. m.'}';
  }

  Widget _monitorHeader() => Container(
    height: 116,
    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [_color('surface_color'), _color('background_color')],
      ),
      border: Border(
        bottom: BorderSide(color: _color('border_color'), width: 2),
      ),
    ),
    child: Row(
      children: [
        Image.asset(
          'assets/branding/logo_adn.png',
          height: 88,
          width: 170,
          fit: BoxFit.contain,
        ),
        Container(height: 72, width: 1, color: _color('primary_color')),
        const SizedBox(width: 20),
        _businessLogo(88),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _name(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _style(29, heavy: true),
              ),
              Text(
                'CENTRO DE LAVADO',
                style: TextStyle(
                  color: _color('primary_color'),
                  letterSpacing: 4,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Container(height: 72, width: 1, color: _color('border_color')),
        const SizedBox(width: 14),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.calendar_month,
                  color: _color('primary_color'),
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(_dateText(), style: _style(13)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  color: _color('primary_color'),
                  size: 28,
                ),
                const SizedBox(width: 7),
                Text(_hourText(), style: _style(24, heavy: true)),
              ],
            ),
          ],
        ),
        const SizedBox(width: 15),
        Container(height: 72, width: 1, color: _color('border_color')),
        const SizedBox(width: 12),
        SizedBox(width: 135, child: _weatherHeader()),
      ],
    ),
  );

  Widget _weatherHeader() {
    final raw = _data['weather'];
    final weather = raw is Map ? raw : <String, dynamic>{};
    final available = weather['available'] == true;
    final city = (weather['location'] ?? '').toString().trim();
    final symbol = (weather['symbol'] ?? '').toString();
    final icon = !available
        ? Icons.cloud_off_outlined
        : symbol.contains('rain')
        ? Icons.water_drop_outlined
        : symbol.contains('snow')
        ? Icons.ac_unit
        : symbol.contains('cloud') || symbol.contains('fog')
        ? Icons.cloud_outlined
        : Icons.wb_sunny_outlined;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: _color('primary_color'), size: 29),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                available ? '${weather['temperature_c']} °C' : 'Sin clima',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _style(22, heavy: true),
              ),
            ),
          ],
        ),
        Text(
          city.isEmpty ? 'Ubicación no configurada' : city,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _style(11),
        ),
        if (available)
          Text('MET Norway', style: _style(9, color: 'muted_text_color')),
      ],
    );
  }

  List<Map<String, dynamic>> _workerQueues() {
    final raw = _data['worker_queues'];
    if (raw is! List) {
      return <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList();
  }

  Widget _personalQueue(Map item) {
    final rawIds = item['worker_ids'];
    final ids = rawIds is List
        ? rawIds.map((id) => id.toString()).toSet()
        : <String>{};
    final personal = _workerQueues()
        .where((q) => ids.contains((q['employee_id'] ?? '').toString()))
        .toList();
    final seen = <String>{};
    final tasks = <Map<String, dynamic>>[];
    for (final worker in personal) {
      final orders = worker['orders'];
      if (orders is! List) {
        continue;
      }
      for (final candidate in orders) {
        if (candidate is! Map) {
          continue;
        }
        final id = (candidate['id'] ?? '').toString();
        if (seen.add(id)) {
          tasks.add(Map<String, dynamic>.from(candidate));
        }
      }
    }
    final total = tasks.length;
    final pages = (total + 2) ~/ 3;
    final start = total == 0 ? 0 : ((_queuePage ~/ 3) % pages) * 3;
    final visible = tasks.skip(start).take(3).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _color('sidebar_color'),
        border: Border.all(color: _color('border_color')),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_list_numbered,
                size: 19,
                color: _color('primary_color'),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Cola del lavador ($total)',
                  style: _style(14, heavy: true),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (total > 3)
                Text(
                  '${start + 1}–${(start + 3 > total ? total : start + 3)} / $total',
                  style: _style(10, color: 'muted_text_color'),
                ),
            ],
          ),
          const SizedBox(height: 5),
          if (visible.isEmpty)
            Text(
              'Sin lavados pendientes',
              style: _style(12, color: 'muted_text_color'),
            ),
          for (var index = 0; index < visible.length; index++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      '${start + index + 1}.',
                      style: _style(12, color: 'primary_color'),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      '${visible[index]['brand'] ?? ''} ${visible[index]['model'] ?? ''}'
                          .trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _style(12, heavy: true),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'En espera',
                    style: _style(10, color: 'muted_text_color'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _vehiclePhoto(Map item) {
    final id = (item['vehicle_id'] as num?)?.toInt();
    final photoPublic = item['photo_on_kiosk'] == true;
    final bytes = id == null || (_monitorOverlay != null && !photoPublic)
        ? null
        : _vehiclePhotos[id];
    return SizedBox(
      height: 145,
      width: double.infinity,
      child: bytes == null
          ? Icon(
              Icons.directions_car_filled,
              color: _color('primary_color'),
              size: 117,
            )
          : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true),
    );
  }

  int? _liveProgress(Map item) {
    final duration = (item['estimated_minutes'] as num?)?.toInt();
    final start = DateTime.tryParse((item['started_at'] ?? '').toString());
    if (duration == null || duration <= 0 || start == null) {
      return null;
    }
    final seconds = _clock
        .difference(start.toLocal())
        .inSeconds
        .clamp(0, 864000);
    return (seconds / (duration * 60) * 100).floor().clamp(0, 100).toInt();
  }

  String _remaining(Map item) {
    final duration = (item['estimated_minutes'] as num?)?.toInt();
    final start = DateTime.tryParse((item['started_at'] ?? '').toString());
    if (duration == null || duration <= 0 || start == null) {
      return 'Por determinar';
    }
    final elapsed = _clock
        .difference(start.toLocal())
        .inSeconds
        .clamp(0, 864000);
    final remaining = (duration * 60 - elapsed).clamp(0, 864000);
    if (remaining == 0) {
      return 'Tiempo estimado cumplido';
    }
    final mins = (remaining / 60).ceil();
    return '${mins.toString().padLeft(2, '0')} min';
  }

  Widget _washCard(Map item) {
    final names = item['washers'] is List
        ? (item['washers'] as List).map((e) => e.toString()).join(', ')
        : '';
    final vehicle = '${item['brand'] ?? ''} ${item['model'] ?? ''}'.trim();
    final plate = (item['plate'] ?? '').toString();
    final service = (item['service'] ?? '').toString();
    final progress = _liveProgress(item);
    final bay = (item['bay'] ?? 'Sin bahía').toString();
    return Container(
      decoration: BoxDecoration(
        color: _color('surface_color'),
        border: Border.all(color: _color('border_color')),
        borderRadius: BorderRadius.circular(23),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: 58,
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _color('border_color'))),
            ),
            child: Row(
              children: [
                const SizedBox(width: 12),
                Icon(Icons.person, size: 31, color: _color('primary_color')),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Lavador', style: _style(11)),
                      Text(
                        names.isEmpty ? 'Sin asignar' : names,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _style(15, heavy: true),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  height: 58,
                  alignment: Alignment.center,
                  color: _color('primary_color'),
                  child: Text(
                    bay,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: _color('background_color'),
                      fontWeight: FontWeight.w800,
                      fontSize: 19,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _vehiclePhoto(item),
          Text(
            vehicle.isEmpty ? 'Vehículo sin identificar' : vehicle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _style(24, heavy: true),
          ),
          Text(
            plate.isEmpty ? 'Placa no registrada' : 'Placa: $plate',
            style: _style(15),
          ),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              height: 43,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _color('sidebar_color'),
                border: Border.all(
                  color: _color('border_color').withValues(alpha: .5),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_car_wash,
                    size: 22,
                    color: _color('primary_color'),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      service.isEmpty ? 'Servicio no disponible' : service,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: _style(14, heavy: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: LinearProgressIndicator(
                      value: progress == null ? 0 : progress / 100,
                      minHeight: 15,
                      color: _color('primary_color'),
                      backgroundColor: _color('sidebar_color'),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                Text(
                  progress == null ? '—' : '$progress %',
                  style: _style(15, heavy: true),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.timer_outlined, color: _color('text_color'), size: 30),
              const SizedBox(width: 9),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tiempo restante estimado:', style: _style(12)),
                  Text(_remaining(item), style: _style(19, heavy: true)),
                ],
              ),
            ],
          ),
          const Spacer(),
          _personalQueue(item),
        ],
      ),
    );
  }

  Widget _queue() {
    final queues = _workerQueues()
        .where((q) => q['orders'] is List && (q['orders'] as List).isNotEmpty)
        .toList();
    final current = queues.isEmpty
        ? null
        : queues[_workerRotation % queues.length];
    final orders = current?['orders'];
    final next = orders is List && orders.isNotEmpty ? orders.first : null;
    final hasNext = next is Map;
    final vehicle = hasNext
        ? '${next['brand'] ?? ''} ${next['model'] ?? ''}'.trim()
        : '';
    final plate = hasNext ? (next['plate'] ?? '').toString() : '';
    final service = hasNext ? (next['service'] ?? '').toString() : '';
    final worker = (current?['worker'] ?? '').toString();
    return Container(
      height: 100,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: _color('queue_color'),
        border: Border.all(color: _color('border_color')),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(Icons.more_time, size: 42, color: _color('primary_color')),
          const SizedBox(width: 12),
          Text('Siguiente en cola', style: _style(21, heavy: true)),
          const SizedBox(width: 12),
          Expanded(
            child: hasNext
                ? Row(
                    children: [
                      Icon(
                        Icons.directions_car,
                        color: _color('text_color'),
                        size: 30,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              vehicle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(16, heavy: true),
                            ),
                            Text(
                              plate.isEmpty ? 'Sin placa' : 'Placa: $plate',
                              style: _style(12),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Cola de lavador:', style: _style(11)),
                            Text(
                              worker,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _style(15, heavy: true),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Text(
                          service,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: _style(14, heavy: true),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: _color('primary_color'),
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Text(
                          'En espera »',
                          style: TextStyle(
                            color: _color('background_color'),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  )
                : Text(
                    'No hay vehículos en espera',
                    textAlign: TextAlign.end,
                    style: _style(16, color: 'muted_text_color'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _monitor() {
    final all = _data['active'] is List ? _data['active'] as List : <dynamic>[];
    final offset = all.isEmpty ? 0 : _offset % all.length;
    final visible = all.length <= 4
        ? all
        : <dynamic>[
            ...all.skip(offset).take(4),
            if (all.length - offset < 4) ...all.take(4 - (all.length - offset)),
          ];
    return Container(
      padding: const EdgeInsets.all(14),
      color: _color('background_color'),
      child: Column(
        children: [
          _monitorHeader(),
          const SizedBox(height: 14),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final count = visible.length;
                if (count == 0) {
                  return Center(
                    child: Text(
                      'No hay lavados activos',
                      style: _style(23, heavy: true),
                    ),
                  );
                }
                final cards = <Widget>[
                  for (final item in visible)
                    Expanded(child: _washCard(item as Map)),
                ];
                if (width < 760) {
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: visible.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 12),
                    itemBuilder: (context, index) => SizedBox(
                      width: 300,
                      child: _washCard(visible[index] as Map),
                    ),
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < cards.length; i++) ...[
                      if (i != 0) const SizedBox(width: 12),
                      cards[i],
                    ],
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          _queue(),
        ],
      ),
    );
  }

  Widget _editor() => _panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Personalización del monitor por empresa',
          style: TextStyle(
            color: _color('text_color'),
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Cambiar el color principal actualiza los elementos turquesa. Cada color se guarda por empresa, separado del tema administrativo.',
          style: TextStyle(color: _color('muted_text_color')),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final entry in fields.entries)
              SizedBox(
                width: 270,
                child: Row(
                  children: [
                    Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: _color(entry.key),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controllers[entry.key],
                        style: TextStyle(color: _color('text_color')),
                        decoration: InputDecoration(
                          labelText: entry.value,
                          labelStyle: TextStyle(
                            color: _color('muted_text_color'),
                          ),
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _saving ? null : _saveTheme,
          icon: const Icon(Icons.save),
          label: Text(_saving ? 'Guardando...' : 'Guardar colores'),
        ),
      ],
    ),
  );

  // 24B.1.2: el administrador aloja esta pagina en un SingleChildScrollView.
  // Su altura debe ser acotada antes de utilizar Expanded o GridView.
  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final monitorHeight = (viewportHeight - 100.0)
        .clamp(800.0, 1100.0)
        .toDouble();
    return SizedBox(
      height: monitorHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_fullscreen)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 10,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text(
                    'Vista general de lavados',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => setState(() => _editing = !_editing),
                    icon: const Icon(Icons.palette),
                    label: const Text('Colores'),
                  ),
                  TextButton.icon(
                    onPressed: _openMonitor,
                    icon: const Icon(Icons.fullscreen),
                    label: const Text('Modo monitor'),
                  ),
                  IconButton(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
              ),
            ),
          if (_fullscreen)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => setState(() => _fullscreen = false),
                icon: const Icon(Icons.fullscreen_exit),
                label: const Text('Volver al administrador'),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                _error!,
                style: const TextStyle(color: Colors.orangeAccent),
              ),
            ),
          if (_editing)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 255),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: _editor(),
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _monitor(),
          ),
        ],
      ),
    );
  }
}
