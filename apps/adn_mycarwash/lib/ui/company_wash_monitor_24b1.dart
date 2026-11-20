import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';

import '../core/mycarwash_session.dart';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import '../core/company_monitor_colors_24n27.dart';
import '../core/monitor_completion_queue_24n5.dart';
import '../core/monitor_device_weather_24n5.dart';
import 'package:http/http.dart' as http;

import '../core/business_identity.dart';
import '../core/company_business_api.dart';

/// Vista general de lavados: comparte la identidad visual de la empresa.
/// No configura ni otorga acceso a hardware Raspberry Pi.
class CompanyWashMonitor24B1 extends StatefulWidget {
  const CompanyWashMonitor24B1({super.key, this.client, this.kioskKey});
  final http.Client? client;
  final String? kioskKey;

  @override
  State<CompanyWashMonitor24B1> createState() => _CompanyWashMonitor24B1State();
}

class _CompanyWashMonitor24B1State extends State<CompanyWashMonitor24B1> {
  late final http.Client _client;
  late final bool _ownsClient;
  Timer? _timer;
  Timer? _clockTimer;
  Timer? _refreshTimer;
  Timer? _completionExitTimer;
  Timer? _completionEndTimer;
  Timer? _completionEnterTimer;
  Timer? _weatherTimer;
  final MonitorCompletionQueue24N5 _completionInbox = MonitorCompletionQueue24N5();
  Map<String, dynamic>? _currentCompletion;
  bool _completionVisible = false;
  bool _refreshInFlight = false;
  Map<String, String>? _deviceLocation;

  OverlayEntry? _monitorOverlay;
  final Map<int, Uint8List> _vehiclePhotos = <int, Uint8List>{};
  final Set<int> _photoFailures = <int>{};
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = <String, dynamic>{};
  int _offset = 0;
  int _total = 0;
  int _queuePage = 0;
  int _workerRotation = 0;
  bool _fullscreen = false;
  Map<String, String> _kioskColors = <String, String>{};
  DateTime _clock = DateTime.now();

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    // Un solo tema visual por empresa, compartido con todo el administrador.
    CompanyVisualTheme.current.addListener(_onCompanyColorsChanged);
    if (widget.kioskKey != null) {
      _bootstrapKiosk();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMonitor();
      });
    }
    _refresh();
    _refreshDeviceWeather();
    _weatherTimer = Timer.periodic(const Duration(minutes: 10), (_) => _refreshDeviceWeather());
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
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
      setState(() {});
      _monitorOverlay?.markNeedsBuild();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _refreshTimer?.cancel();
    _weatherTimer?.cancel();
    _completionEnterTimer?.cancel();
    _completionExitTimer?.cancel();
    _completionEndTimer?.cancel();
    _clockTimer?.cancel();
    _monitorOverlay?.remove();
    _monitorOverlay?.dispose();
    CompanyVisualTheme.current.removeListener(_onCompanyColorsChanged);
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  void _onCompanyColorsChanged() {
    if (!mounted) return;
    setState(() {});
    // OverlayEntry no siempre se reconstruye junto con el MaterialApp.
    _monitorOverlay?.markNeedsBuild();
  }

  Future<void> _refreshDeviceWeather() async {
    final result = await MonitorDeviceWeather24N5.locate();
    if (!mounted) return;
    setState(() => _deviceLocation = result);
    _refresh();
    _monitorOverlay?.markNeedsBuild();
  }

  void _activateNextCompletion() {
    if (!mounted || _currentCompletion != null) return;
    final next = _completionInbox.takeNext();
    if (next == null) return;
    _completionExitTimer?.cancel();
    _completionEndTimer?.cancel();
    _completionEnterTimer?.cancel();
    setState(() {
      _currentCompletion = next;
      _completionVisible = false;
    });
    _monitorOverlay?.markNeedsBuild();
    _loadVehiclePhotos();
    // A partir de aquí se cuentan EXACTAMENTE diez segundos de presentación.
    _completionEnterTimer = Timer(const Duration(milliseconds: 30), () {
      if (!mounted || _currentCompletion == null) return;
      setState(() => _completionVisible = true);
      _monitorOverlay?.markNeedsBuild();
    });
    _completionExitTimer = Timer(const Duration(milliseconds: 8800), () {
      if (!mounted) return;
      setState(() => _completionVisible = false);
      _monitorOverlay?.markNeedsBuild();
    });
    _completionEndTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      setState(() => _currentCompletion = null);
      _monitorOverlay?.markNeedsBuild();
      _activateNextCompletion();
    });
  }

  Future<void> _refresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      final response = widget.kioskKey == null
          ? await _api.request('GET', '/dashboard/monitor-24b2',
              query: _deviceLocation)
          : await _kioskGet('/monitor');
      final raw = response['data'];
      if (!mounted || raw is! Map) {
        return;
      }
      // Registrar sólo nuevas finalizaciones de órdenes completas (eventos
      // TO_STATUS TERMINADO). El primer sondeo fija el cursor sin reproducir
      // órdenes terminadas antes de abrir el monitor.
      _completionInbox.ingest(raw['completion_events']);
      setState(() {
        _data = Map<String, dynamic>.from(raw);
        _total = (raw['active_total'] as num?)?.toInt() ?? 0;
        _clock = DateTime.now();
        _error = null;
        _loading = false;
      });
      _monitorOverlay?.markNeedsBuild();
      _loadVehiclePhotos();
      _activateNextCompletion();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Datos no disponibles: $e';
        });
      }
    } finally {
      _refreshInFlight = false;
    }
  }

  Color _color(String name) {
    final custom = _kioskColors[name];
    if (custom != null && RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(custom)) {
      return Color(0xFF000000 | int.parse(custom.substring(1), radix: 16));
    }
    return CompanyMonitorColors24N27.resolve(name);
  }

  static const String _kioskBase = 'http://127.0.0.1:8787/api/index.php/api/v1';

  Future<Map<String, dynamic>> _kioskGet(String endpoint) async {
    final key = widget.kioskKey;
    if (key == null || key != 'local') {
      throw StateError('Dispositivo no vinculado.');
    }
    final response = await _client.get(
      Uri.parse('$_kioskBase/kiosk/rpi01c$endpoint'),
      headers: {'Accept': 'application/json', 'X-MCW-Kiosk-Key': key},
    ).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw StateError('Monitor no autorizado (HTTP ${response.statusCode}).');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Respuesta de monitoreo inválida.');
    }
    return decoded;
  }

  Future<void> _bootstrapKiosk() async {
    try {
      final data = await _kioskGet('/bootstrap');
      if (!mounted) return;
      final colors = data['colors'];
      final newColors = <String, String>{};
      if (colors is Map) {
        for (final entry in colors.entries) {
          if (entry.key is String && entry.value is String) {
            newColors[entry.key as String] = entry.value as String;
          }
        }
      }
      BusinessIdentity.current.value = BusinessIdentityData(
        companyName: (data['company_name'] ?? 'Mi empresa').toString(),
      );
      setState(() => _kioskColors = newColors);
      final logo = await _client.get(
        Uri.parse('$_kioskBase/kiosk/rpi01c/logo'),
        headers: {'X-MCW-Kiosk-Key': widget.kioskKey!},
      ).timeout(const Duration(seconds: 15));
      if (mounted && logo.statusCode == 200 &&
          logo.bodyBytes.isNotEmpty && logo.bodyBytes.length <= 2097152) {
        BusinessIdentity.setLogoBytes(logo.bodyBytes);
      }
    } catch (error) {
      if (mounted) setState(() => _error = 'Vinculación del monitor: $error');
    }
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

  String _name() => BusinessIdentity.current.value.companyName.trim().isEmpty
      ? 'Mi empresa'
      : BusinessIdentity.current.value.companyName;

  Future<void> _loadVehiclePhotos() async {
    final active = _data['active'];
    if (active is! List) return;
    final visible = active.length <= 4
        ? active
        : <dynamic>[
            ...active.skip(_offset % active.length).take(4),
            if (active.length - (_offset % active.length) < 4)
              ...active.take(4 - (active.length - (_offset % active.length))),
          ];
    final photosToLoad = <dynamic>[
      ?_currentCompletion,
      ...(_data['completion_events'] is List
          ? (_data['completion_events'] as List).reversed.take(5)
          : <dynamic>[]),
      ...visible,
    ];
    for (final item in photosToLoad) {
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
        final url = widget.kioskKey == null
            ? Uri.parse(
                '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/vehicles/$id/file')
            : Uri.parse('$_kioskBase/kiosk/rpi01c/photos/$id');
        final res = await _client
            .get(url, headers: widget.kioskKey == null
                ? MyCarWashSession.headers
                : {'X-MCW-Kiosk-Key': widget.kioskKey!})
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
              if (widget.kioskKey == null)
                Positioned(
                  right: 6,
                  top: 4,
                  child: IconButton(
                    tooltip: 'Salir del modo monitor',
                    onPressed: _closeMonitor,
                    icon: Icon(Icons.fullscreen_exit, color: CompanyVisualTheme.text),
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
      border: Border(bottom: BorderSide(color: _color('border_color'), width: 2)),
    ),
    child: Row(
      children: [
        Image.asset('assets/branding/logo_adn_blanco.png',
          height: 88, width: 170, fit: BoxFit.contain),
        const SizedBox(width: 24),
        Container(height: 72, width: 1, color: _color('primary_color')),
        const SizedBox(width: 30),
        Expanded(
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _businessLogo(82),
                const SizedBox(width: 22),
                Flexible(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_name(), maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: _style(28, heavy: true)),
                      if ((_data['slogan'] ?? '').toString().trim().isNotEmpty)
                        Text((_data['slogan'] ?? '').toString().trim(),
                          maxLines: 2, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _color('primary_color'),
                              letterSpacing: 2.5, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Container(height: 72, width: 1, color: _color('border_color')),
        const SizedBox(width: 16),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.calendar_month, color: _color('primary_color'), size: 22),
              const SizedBox(width: 8),
              Text(_dateText(), style: _style(13)),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.access_time, color: _color('primary_color'), size: 28),
              const SizedBox(width: 7),
              Text(_hourText(), style: _style(24, heavy: true)),
            ]),
          ],
        ),
        const SizedBox(width: 15),
        Container(height: 72, width: 1, color: _color('border_color')),
        const SizedBox(width: 12),
        SizedBox(width: 142, child: _weatherHeader()),
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
          Text(
            (weather['attribution'] ?? 'MET Norway').toString(),
            style: _style(9, color: 'muted_text_color'),
          ),
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

  Widget _completionPanel(Map<String, dynamic> event) {
    final people = event['washers'] is List
        ? (event['washers'] as List).map((e) => e.toString()).join(', ')
        : '';
    final name = '${event['brand'] ?? ''} ${event['model'] ?? ''}'.trim();
    final plate = (event['plate'] ?? '').toString();
    final service = (event['service'] ?? '').toString();
    final bay = (event['bay'] ?? 'Sin puesto').toString();
    final id = (event['vehicle_id'] as num?)?.toInt();
    final bytes = id == null || event['photo_on_kiosk'] != true
        ? null : _vehiclePhotos[id];
    return AnimatedOpacity(
      opacity: _completionVisible ? 1.0 : 0.0,
      duration: Duration(milliseconds: _completionVisible ? 770 : 1200),
      curve: Curves.easeInOut,
      child: Container(
        key: ValueKey('completion-${event['event_id']}'),
        width: double.infinity,
        decoration: BoxDecoration(
          color: _color('surface_color'),
          border: Border.all(color: _color('border_color'), width: 1.4),
          borderRadius: BorderRadius.circular(23),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: [
          Container(
            height: 70,
            decoration: BoxDecoration(border: Border(bottom:
                BorderSide(color: _color('border_color')))),
            child: Row(children: [
              const SizedBox(width: 22),
              Icon(Icons.person, size: 31, color: _color('primary_color')),
              const SizedBox(width: 12),
              Expanded(child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(people.contains(',') ? 'Lavadores' : 'Lavador', style: _style(13)),
                  Text(people.isEmpty ? 'Sin asignar' : people,
                    maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: _style(24, heavy: true)),
                ],
              )),
              Container(height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 23),
                alignment: Alignment.center,
                color: _color('primary_color'),
                child: Text(bay, style: TextStyle(color: _color('background_color'),
                    fontWeight: FontWeight.w800, fontSize: 24))),
            ]),
          ),
          Expanded(child: LayoutBuilder(builder: (context, constraints) {
            // En monitores con poca altura, la tarjeta conserva TODA su
            // informacion y reduce la escala de forma uniforme, sin recortar
            // la imagen, los textos, ni el progreso. En monitores altos mantiene
            // el tamano original y utiliza el espacio disponible.
            final availableHeight = constraints.maxHeight;
            final designHeight = availableHeight < 500 ? 500.0 : availableHeight;
            final designWidth = availableHeight > 0
                ? constraints.maxWidth * designHeight / availableHeight
                : constraints.maxWidth;
            final imageHeight =
                (designHeight * .38).clamp(90.0, 230.0).toDouble();
            return FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: SizedBox(
                width: designWidth,
                height: designHeight,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
              SizedBox(height: imageHeight,
                child: bytes == null
                    ? Icon(Icons.directions_car_filled, size: imageHeight * .7,
                        color: _color('primary_color'))
                    : Image.memory(bytes, fit: BoxFit.contain, gaplessPlayback: true)),
              Text(name.isEmpty ? 'Vehículo sin identificar' : name,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: _style(37, heavy: true), textAlign: TextAlign.center),
              Text(plate.isEmpty ? 'Placa no registrada' : 'Placa: $plate',
                style: _style(21), textAlign: TextAlign.center),
              Container(
                width: designWidth * .77,
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
                decoration: BoxDecoration(color: _color('sidebar_color'),
                  border: Border.all(color: _color('border_color')),
                  borderRadius: BorderRadius.circular(18)),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.local_car_wash, color: _color('primary_color'), size: 26),
                  const SizedBox(width: 10),
                  Flexible(child: Text(service.isEmpty ? 'Servicio no disponible' : service,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: _style(22, heavy: true))),
                ])),
              Column(children: [
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.check_circle_outline, color: _color('success_color'), size: 51),
                  const SizedBox(width: 14),
                  Text('Lavado terminado',
                      style: TextStyle(fontWeight: FontWeight.w800,
                        fontSize: 43, color: _color('success_color'))),
                ]),
                Text('Trabajo finalizado correctamente', style: _style(19)),
              ]),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 85), child: Row(children: [
                Expanded(child: TweenAnimationBuilder<double>(
                  key: ValueKey('progress-${event['event_id']}'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 1800),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) => ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: LinearProgressIndicator(value: value,
                      minHeight: 16,
                      color: _color('primary_color'),
                      backgroundColor: _color('sidebar_color'))))),
                const SizedBox(width: 16),
                Text('100 %', style: _style(21, heavy: true)),
              ])),
                  ],
                ),
              ),
            );
          })),
        ]),
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
            child: _currentCompletion != null
                ? _completionPanel(_currentCompletion!)
                : LayoutBuilder(
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
                  Text(
                    'Vista general de lavados',
                    style: TextStyle(
                      color: CompanyVisualTheme.text,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
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
