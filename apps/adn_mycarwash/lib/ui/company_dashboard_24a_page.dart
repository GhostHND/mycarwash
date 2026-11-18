import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/mycarwash_session.dart';
import '../core/business_identity.dart';
import '../core/company_business_api.dart';
import 'company_product_photo_24j.dart';
import 'company_dashboard_art_24a3.dart';

/// Dashboard 24A.3. Datos únicamente de las APIs del negocio autenticado.
/// La referencia visual es orientativa; no genera indicadores ficticios.
class CompanyDashboard24APage extends StatefulWidget {
  const CompanyDashboard24APage({
    super.key,
    required this.onNavigate,
    this.client,
  });
  final ValueChanged<String> onNavigate;
  final http.Client? client;

  @override
  State<CompanyDashboard24APage> createState() =>
      _CompanyDashboard24APageState();
}

class _CompanyDashboard24APageState extends State<CompanyDashboard24APage> {
  static const Color _bg = Color(0xFF050C0F);
  static const Color _card = Color(0xFF071E23);
  static const Color _surface = Color(0xFF0B292F);
  static const Color _cyan = Color(0xFF00DCE5);
  static const Color _accent = Color(0xFF0FA7B4);
  static const Color _white = Color(0xFFF4F7F8);
  static const Color _muted = Color(0xFFA5B6BB);
  static const Color _pink = Color(0xFFEC488A);

  late final http.Client _client;
  late final bool _ownsClient;
  late final CompanyBusinessApi _api;
  Timer? _ticker;
  int _serial = 0;
  int? _branch;
  int _offset = 0;
  bool _busy = false;
  bool _first = true;
  String? _error;
  Map<String, dynamic>? _summary;
  Map<String, dynamic>? _details;
  DateTime? _updated;
  // Fotos privadas existentes. Una solicitud por vehiculo y sesion de pagina.
  final Map<int, Future<Uint8List?>> _vehiclePhotos = {};

  Future<Uint8List?> _fetchVehiclePhoto(int vehicleId) async {
    if (vehicleId <= 0 || !MyCarWashSession.isAuthenticated) {
      return null;
    }
    try {
      final uri = Uri.parse(
        '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/vehicles/$vehicleId/file',
      );
      final response = await _client
          .get(uri, headers: MyCarWashSession.headers)
          .timeout(const Duration(seconds: 15));
      final mime = response.headers['content-type'] ?? '';
      if (response.statusCode != 200 ||
          !(mime.startsWith('image/jpeg') ||
              mime.startsWith('image/png') ||
              mime.startsWith('image/webp')) ||
          response.bodyBytes.isEmpty ||
          response.bodyBytes.length > 2097152) {
        return null;
      }
      return response.bodyBytes;
    } catch (_) {
      return null;
    }
  }

  Widget _vehiclePhoto(dynamic rawId, dynamic hasPhoto) {
    final id = _integer(rawId);
    if (hasPhoto != true || id <= 0) {
      return const Icon(
        Icons.directions_car_filled_outlined,
        color: _cyan,
        size: 38,
      );
    }
    return FutureBuilder<Uint8List?>(
      future: _vehiclePhotos.putIfAbsent(id, () => _fetchVehiclePhoto(id)),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 54,
            child: Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _cyan),
              ),
            ),
          );
        }
        final bytes = snapshot.data;
        if (bytes == null) {
          return const Icon(
            Icons.directions_car_filled_outlined,
            color: _cyan,
            size: 38,
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(
            bytes,
            width: double.infinity,
            height: 70,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => const Icon(
              Icons.directions_car_filled_outlined,
              color: _cyan,
              size: 38,
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _api = CompanyBusinessApi(_client);
    _load();
    _ticker = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _load(silent: true),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _serial++;
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (_busy) {
      return;
    }
    _busy = true;
    final current = ++_serial;
    if (!silent) {
      setState(() => _error = null);
    }
    try {
      final query = <String, String>{
        if (_branch != null) 'branch_id': '$_branch',
      };
      final summaryResponse = await _api.request(
        'GET',
        '/dashboard/overview',
        query: query,
      );
      Map<String, dynamic>? visual;
      String? detailFailure;
      try {
        final r = await _api.request(
          'GET',
          '/dashboard/visual-24a3',
          query: {...query, 'offset': '$_offset'},
        );
        if (r['data'] is Map) {
          visual = Map<String, dynamic>.from(r['data'] as Map);
        }
      } catch (error) {
        detailFailure = error.toString();
      }
      if (!mounted || current != _serial) {
        return;
      }
      final newSummary = Map<String, dynamic>.from(
        summaryResponse['data'] as Map,
      );
      setState(() {
        _summary = newSummary;
        _details = visual;
        _error = detailFailure;
        _first = false;
        _updated = DateTime.now();
        final total = _integer(visual?['active_total']);
        final active = _rows(visual?['active']);
        _offset = total > 4
            ? (_integer(visual?['active_offset']) + active.length) % total
            : 0;
      });
    } catch (error) {
      if (mounted && current == _serial) {
        setState(() {
          _error = error.toString();
          _first = false;
        });
      }
    } finally {
      _busy = false;
    }
  }

  static int _integer(dynamic raw) =>
      raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0;
  static List<Map<String, dynamic>> _rows(dynamic raw) => raw is List
      ? raw.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
      : <Map<String, dynamic>>[];
  String _money(dynamic value) {
    if (value == null) {
      return 'Sin datos';
    }
    final number = double.tryParse('$value');
    if (number == null) {
      return 'Sin datos';
    }
    return 'L ${number.toStringAsFixed(2)}';
  }

  String _greeting(String name) {
    final hour = _details?['business_hour'] is num
        ? (_details!['business_hour'] as num).toInt()
        : DateTime.now().hour;
    final prefix = hour < 12
        ? 'Buenos días'
        : hour < 18
        ? 'Buenas tardes'
        : 'Buenas noches';
    return name.trim().isEmpty ? prefix : '$prefix, $name';
  }

  String _displayDate(String raw) {
    final day = DateTime.tryParse(raw);
    if (day == null) {
      return raw;
    }
    const weekdays = [
      'lunes',
      'martes',
      'miércoles',
      'jueves',
      'viernes',
      'sábado',
      'domingo',
    ];
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final text = weekdays[day.weekday - 1];
    return '${text[0].toUpperCase()}${text.substring(1)} ${day.day} de ${months[day.month - 1]} de ${day.year}';
  }

  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(14),
  }) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _accent.withValues(alpha: .40)),
      boxShadow: [
        BoxShadow(color: _accent.withValues(alpha: .045), blurRadius: 14),
      ],
    ),
    child: child,
  );

  Widget _title(String label, IconData icon, {String? subtitle}) => Row(
    children: [
      Icon(icon, color: _cyan, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 2,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _action(
    String title,
    IconData icon,
    String? destination, {
    Color borderColor = _accent,
    bool highlighted = false,
  }) => OutlinedButton.icon(
    key: ValueKey<String>('dashboard_action_$title'),
    onPressed: destination == null
        ? () => _load()
        : () => widget.onNavigate(destination),
    icon: Icon(icon, size: 17),
    label: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
    style: OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
      backgroundColor: highlighted ? _cyan : _card,
      foregroundColor: highlighted ? _bg : _white,
      side: BorderSide(color: borderColor, width: 1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
      textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );

  void _openSearch() {
    final input = TextEditingController();
    var results = <Map<String, dynamic>>[];
    var searching = false;
    String? failure;
    StateSetter? update;
    Future<void> submit() async {
      final q = input.text.trim();
      if (q.length < 2) return;
      update?.call(() {
        searching = true;
        failure = null;
      });
      try {
        final payload = await _api.request(
          'GET',
          '/dashboard/search-24a3',
          query: {'q': q, if (_branch != null) 'branch_id': '$_branch'},
        );
        if (!mounted) return;
        update?.call(() {
          results = _rows((payload['data'] as Map)['items']);
          searching = false;
        });
      } catch (error) {
        if (!mounted) return;
        update?.call(() {
          failure = error.toString();
          searching = false;
        });
      }
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          update = setDialogState;
          return AlertDialog(
            backgroundColor: _card,
            title: const Text(
              'Búsqueda global',
              style: TextStyle(color: _white),
            ),
            content: SizedBox(
              width: 470,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: input,
                    autofocus: true,
                    onSubmitted: (_) => submit(),
                    decoration: const InputDecoration(
                      hintText: 'Cliente, placa, vehículo, reserva u orden',
                      prefixIcon: Icon(Icons.search, color: _cyan),
                    ),
                  ),
                  const SizedBox(height: 9),
                  if (searching) const LinearProgressIndicator(color: _cyan),
                  if (failure != null)
                    Text(failure!, style: const TextStyle(color: _pink)),
                  if (results.isNotEmpty)
                    SizedBox(
                      height: math.min(results.length * 50.0, 270.0),
                      child: ListView.builder(
                        itemCount: results.length,
                        itemBuilder: (context, index) {
                          final item = results[index];
                          return ListTile(
                            dense: true,
                            title: Text(
                              '${item['label']}',
                              maxLines: 1,
                              style: const TextStyle(color: _white),
                            ),
                            subtitle: Text(
                              '${item['kind']}',
                              style: const TextStyle(color: _muted),
                            ),
                            onTap: () {
                              Navigator.of(dialogContext).pop();
                              widget.onNavigate('${item['destination']}');
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('Cerrar'),
              ),
              FilledButton(
                onPressed: searching ? null : submit,
                child: const Text('Buscar'),
              ),
            ],
          );
        },
      ),
    ).whenComplete(input.dispose);
  }

  Widget _topbar() => LayoutBuilder(
    builder: (context, c) {
      final small = c.maxWidth < 740;
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 16),
        decoration: const BoxDecoration(
          color: Color(0xFF051419),
          border: Border(bottom: BorderSide(color: Color(0xFF0B6871))),
        ),
        child: Row(
          children: [
            ValueListenableBuilder<BusinessIdentityData>(
              valueListenable: BusinessIdentity.current,
              builder: (context, identity, _) => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (identity.logoBytes != null)
                    Image.memory(
                      identity.logoBytes!,
                      width: 40,
                      height: 40,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    )
                  else
                    const Icon(
                      Icons.local_car_wash_rounded,
                      color: _cyan,
                      size: 27,
                    ),
                  const SizedBox(width: 12),
                  const SizedBox(
                    height: 28,
                    child: VerticalDivider(color: _accent, thickness: 1),
                  ),
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: small ? 125 : 250),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          identity.companyName.trim().isEmpty
                              ? 'Mi Empresa'
                              : identity.companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _white,
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const Text(
                          'Dashboard',
                          style: TextStyle(color: _muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            if (!small) ...[
              SizedBox(
                width: math.min(310, c.maxWidth * .28),
                child: TextField(
                  readOnly: true,
                  onTap: _openSearch,
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(
                      Icons.search,
                      color: _muted,
                      size: 20,
                    ),
                    hintText: 'Buscar cliente, vehículo, reserva u orden...',
                    hintStyle: const TextStyle(color: _muted, fontSize: 11),
                    suffixIcon: const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 13,
                        horizontal: 5,
                      ),
                      child: Text(
                        'Ctrl+K',
                        style: TextStyle(color: _muted, fontSize: 9),
                      ),
                    ),
                    filled: true,
                    fillColor: _card,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
            ],
            IconButton(
              onPressed: null,
              tooltip: 'Notificaciones: módulo no disponible',
              icon: const Icon(
                Icons.notifications_none_outlined,
                color: _muted,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Perfil',
              icon: const Icon(Icons.account_circle_outlined, color: _cyan),
              color: _card,
              onSelected: (value) => widget.onNavigate(value),
              itemBuilder: (_) => [
                const PopupMenuItem(
                  value: 'Mi Empresa',
                  child: Text('Mi empresa'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Widget _banner(Map<String, dynamic> data) => Container(
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: _card,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _accent.withValues(alpha: .50)),
    ),
    child: Stack(
      children: [
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: Opacity(
              opacity: .48,
              child: Image.memory(
                base64Decode(dashboardCarArt24A3),
                width: 440,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(21),
          child: LayoutBuilder(
            builder: (context, c) {
              final compact = c.maxWidth < 700;
              final name = (data['user_name'] ?? '').toString();
              final date = (data['date'] ?? '').toString();
              final text = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayDate(date),
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _greeting(name),
                    maxLines: compact ? 3 : 2,
                    style: TextStyle(
                      color: _white,
                      fontSize: compact ? 25 : 33,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Esta es una vista completa de tus operaciones, reservas, ventas, producción e inventario.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _action(
                        'Nueva reserva',
                        Icons.calendar_month_outlined,
                        'Reservas',
                        highlighted: true,
                      ),
                      _action(
                        'Nueva orden de lavado',
                        Icons.directions_car,
                        'Órdenes de lavado',
                        borderColor: _pink,
                      ),
                      _action(
                        'Venta POS',
                        Icons.shopping_cart_outlined,
                        'Smart POS',
                      ),
                      _action('Actualizar', Icons.refresh, null),
                    ],
                  ),
                ],
              );
              final brand = ValueListenableBuilder<BusinessIdentityData>(
                valueListenable: BusinessIdentity.current,
                builder: (context, identity, _) => Container(
                  width: compact ? double.infinity : 170,
                  constraints: const BoxConstraints(minHeight: 122),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: _accent),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (identity.logoBytes != null)
                        Image.memory(
                          identity.logoBytes!,
                          height: 75,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        )
                      else
                        const Icon(
                          Icons.storefront_outlined,
                          color: _cyan,
                          size: 40,
                        ),
                      const SizedBox(height: 8),
                      Text(
                        identity.companyName.isEmpty
                            ? (data['company_name'] ?? '').toString()
                            : identity.companyName,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              );
              return compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [text, const SizedBox(height: 12), brand],
                    )
                  : Row(
                      children: [
                        Expanded(child: text),
                        const SizedBox(width: 15),
                        brand,
                      ],
                    );
            },
          ),
        ),
      ],
    ),
  );

  Widget _kpis(Map<String, dynamic> data) {
    final k = data['kpis'] is Map
        ? Map<String, dynamic>.from(data['kpis'] as Map)
        : <String, dynamic>{};
    final elements = <(String, String, IconData, Color)>[
      (
        'Ventas de hoy',
        _money(k['sales_today']),
        Icons.shopping_cart_outlined,
        _cyan,
      ),
      (
        'Gastos de hoy',
        _money(k['expenses_today']),
        Icons.payments_outlined,
        _pink,
      ),
      (
        'Balance de hoy',
        _money(k['balance_today']),
        Icons.account_balance_wallet_outlined,
        _cyan,
      ),
      (
        'Lavados activos',
        k['active_washes']?.toString() ?? 'Sin datos',
        Icons.local_car_wash_outlined,
        _cyan,
      ),
      (
        'Reservaciones de hoy',
        k['bookings_today']?.toString() ?? 'Sin datos',
        Icons.calendar_month_outlined,
        _pink,
      ),
      (
        'Clientes',
        k['clients']?.toString() ?? 'Sin datos',
        Icons.people_alt_outlined,
        _cyan,
      ),
      (
        'Vehículos',
        k['vehicles']?.toString() ?? 'Sin datos',
        Icons.directions_car_outlined,
        _cyan,
      ),
      (
        'Personal',
        k['staff']?.toString() ?? 'Sin datos',
        Icons.badge_outlined,
        const Color(0xFFFFC242),
      ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final cols = c.maxWidth >= 1300
            ? 8
            : c.maxWidth >= 770
            ? 4
            : c.maxWidth >= 350
            ? 2
            : 1;
        final cell = (c.maxWidth - (cols - 1) * 10) / cols;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final (label, value, icon, color) in elements)
              SizedBox(
                width: cell,
                child: _panel(
                  padding: const EdgeInsets.all(11),
                  child: SizedBox(
                    height: 94,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(icon, color: color, size: 20),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _white,
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Sin datos comparativos',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: _muted, fontSize: 9),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _production() {
    final rows = _rows(_details?['production']);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'Producción por lavador',
            Icons.person_outline,
            subtitle: 'Hoy · Lavados completados por participante',
          ),
          const SizedBox(height: 15),
          if (_details?['production'] == null)
            const Text(
              'No está disponible la fuente de productividad.',
              style: TextStyle(color: _muted),
            )
          else if (rows.isEmpty)
            const Text(
              'Sin lavados completados hoy.',
              style: TextStyle(color: _muted),
            )
          else
            for (var i = 0; i < math.min(rows.length, 5); i++) ...[
              Row(
                children: [
                  CircleAvatar(
                    radius: 13,
                    backgroundColor: _surface,
                    child: Text(
                      '${i + 1}',
                      style: const TextStyle(color: _cyan, fontSize: 11),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      (rows[i]['name'] ?? '').toString(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _white, fontSize: 11),
                    ),
                  ),
                  Text(
                    '${rows[i]['completed']} lavados',
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              LinearProgressIndicator(
                value:
                    _integer(rows[i]['completed']) /
                    math.max(1, _integer(rows.first['completed'])),
                color: _cyan,
                backgroundColor: _surface,
                minHeight: 5,
                borderRadius: BorderRadius.circular(8),
              ),
              const SizedBox(height: 9),
            ],
          const Text(
            'Participación compartida; ingresos no atribuidos.',
            style: TextStyle(color: _muted, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _services() {
    final rows = _rows(_details?['services']);
    final total = rows.fold<int>(0, (v, e) => v + _integer(e['count']));
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Lavados más solicitados', Icons.donut_large),
          const SizedBox(height: 14),
          if (_details?['services'] == null)
            const Text('Fuente no disponible.', style: TextStyle(color: _muted))
          else if (rows.isEmpty)
            const Text(
              'Sin lavados completados hoy.',
              style: TextStyle(color: _muted),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final compact = c.maxWidth < 240;
                final donut = SizedBox(
                  height: 110,
                  width: 110,
                  child: CustomPaint(
                    painter: _DonutPainter(
                      rows.map((e) => _integer(e['count'])).toList(),
                    ),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$total',
                            style: const TextStyle(
                              color: _white,
                              fontWeight: FontWeight.w900,
                              fontSize: 23,
                            ),
                          ),
                          const Text(
                            'Lavados hoy',
                            style: TextStyle(color: _muted, fontSize: 9),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                final legend = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < math.min(rows.length, 5); i++)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 4,
                              backgroundColor: _DonutPainter
                                  .colors[i % _DonutPainter.colors.length],
                            ),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                '${rows[i]['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _white,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                            Text(
                              '${total == 0 ? 0 : (_integer(rows[i]['count']) * 100 / total).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                return compact
                    ? Column(children: [donut, legend])
                    : Row(
                        children: [
                          donut,
                          const SizedBox(width: 10),
                          Expanded(child: legend),
                        ],
                      );
              },
            ),
        ],
      ),
    );
  }

  Widget _topProduct() {
    final item = _details?['top_item'];
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Artículo más vendido', Icons.shopping_bag_outlined),
          const SizedBox(height: 20),
          if (item is! Map)
            const Text(
              'Sin ventas POS confirmadas hoy.',
              style: TextStyle(color: _muted),
            )
          else ...[
            Center(
              child: CompanyProductPhotoView24J(
                client: _client,
                itemId: int.tryParse('${item['id']}'),
                size: 78,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${item['name']}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 15),
            Text(
              'Unidades vendidas: ${item['units']}',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            const SizedBox(height: 5),
            Text(
              'Ingresos: ${_money(item['revenue'])}',
              style: const TextStyle(
                color: _cyan,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _trend() {
    final rows = _rows(_details?['trend']);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title('Ventas y gastos', Icons.show_chart),
          const SizedBox(height: 10),
          const Row(
            children: [
              CircleAvatar(radius: 4, backgroundColor: _cyan),
              SizedBox(width: 5),
              Text('Ventas POS', style: TextStyle(color: _muted, fontSize: 10)),
              SizedBox(width: 10),
              CircleAvatar(radius: 4, backgroundColor: _pink),
              SizedBox(width: 5),
              Text('Gastos', style: TextStyle(color: _muted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 9),
          if (rows.isEmpty)
            const Text(
              'Sin datos para graficar.',
              style: TextStyle(color: _muted),
            )
          else
            SizedBox(
              height: 135,
              child: CustomPaint(
                painter: _LinesPainter(rows),
                child: const SizedBox.expand(),
              ),
            ),
          const SizedBox(height: 8),
          const Text(
            'Últimos 7 días · ventas POS vs. egresos de caja',
            style: TextStyle(color: _muted, fontSize: 9),
          ),
        ],
      ),
    );
  }

  Widget _analytics() => LayoutBuilder(
    builder: (context, c) {
      final cols = c.maxWidth >= 1160
          ? 4
          : c.maxWidth >= 600
          ? 2
          : 1;
      final width = (c.maxWidth - (cols - 1) * 10) / cols;
      final panels = [_production(), _services(), _topProduct(), _trend()];
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in panels) SizedBox(width: width, child: item),
        ],
      );
    },
  );

  Widget _bookings() {
    final rows = _rows(_details?['bookings']);
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'Reservaciones del día',
            Icons.calendar_month_outlined,
            subtitle: 'Total: ${_details?['bookings_total'] ?? 'Sin datos'}',
          ),
          const SizedBox(height: 13),
          const Row(
            children: [
              SizedBox(
                width: 53,
                child: Text(
                  'Hora',
                  style: TextStyle(color: _cyan, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  'Vehículo',
                  style: TextStyle(color: _cyan, fontSize: 11),
                ),
              ),
              Expanded(
                child: Text(
                  'Cliente',
                  style: TextStyle(color: _cyan, fontSize: 11),
                ),
              ),
            ],
          ),
          const Divider(color: _surface),
          if (_details?['bookings'] == null)
            const Text(
              'Datos de reservas no disponibles.',
              style: TextStyle(color: _muted),
            )
          else if (rows.isEmpty)
            const Text(
              'No hay reservaciones confirmadas hoy.',
              style: TextStyle(color: _muted),
            )
          else
            for (final item in rows.take(5))
              InkWell(
                onTap: () => widget.onNavigate('Reservas'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 53,
                        child: Text(
                          '${item['time']}',
                          style: const TextStyle(color: _white, fontSize: 10),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${item['vehicle']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _white, fontSize: 10),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          '${item['client']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _white, fontSize: 10),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          if (rows.length > 5)
            TextButton(
              onPressed: () => widget.onNavigate('Reservas'),
              child: const Text('Ver todas las reservaciones'),
            ),
        ],
      ),
    );
  }

  Widget _active() {
    final items = _rows(_details?['active']);
    final count = _details?['active_total'];
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(
            'Lavados activos · En vivo',
            Icons.local_car_wash_outlined,
            subtitle: count == null
                ? 'Datos no disponibles'
                : 'Órdenes en proceso ($count) · Rotación cada 15 s si hay más de 4',
          ),
          const SizedBox(height: 12),
          if (_details?['active'] == null)
            const Text(
              'No fue posible consultar los lavados activos.',
              style: TextStyle(color: _muted),
            )
          else if (items.isEmpty)
            const Text(
              'No hay lavados en proceso en este momento.',
              style: TextStyle(color: _muted),
            )
          else
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 620
                    ? 4
                    : c.maxWidth >= 300
                    ? 2
                    : 1;
                final tile = (c.maxWidth - (cols - 1) * 8) / cols;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: tile,
                        child: Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: _surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _accent.withValues(alpha: .5),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (item['bay'] ?? 'Orden #${item['id']}')
                                    .toString(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _cyan,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Center(
                                child: _vehiclePhoto(
                                  item['vehicle_id'],
                                  item['photo_available'],
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${item['vehicle']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                (_rowsList(item['washers']).isEmpty)
                                    ? 'Lavador sin asignar'
                                    : _rowsList(item['washers']).join(', '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _muted,
                                  fontSize: 10,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'En proceso · Avance no registrado',
                                style: TextStyle(color: _cyan, fontSize: 9),
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

  static List<String> _rowsList(dynamic raw) =>
      raw is List ? raw.map((e) => '$e').toList() : <String>[];

  Widget _operations() => LayoutBuilder(
    builder: (context, c) {
      if (c.maxWidth < 800) {
        return Column(
          children: [_bookings(), const SizedBox(height: 10), _active()],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 37, child: _bookings()),
          const SizedBox(width: 10),
          Expanded(flex: 63, child: _active()),
        ],
      );
    },
  );

  Widget _shortcuts() => _panel(
    child: LayoutBuilder(
      builder: (context, c) {
        final items = <(String, IconData, String)>[
          ('Agenda', Icons.calendar_month, 'Reservas'),
          ('Clientes', Icons.people, 'Clientes'),
          ('Vehículos', Icons.directions_car, 'Vehículos'),
          ('Inventario', Icons.inventory_2, 'Inventario'),
          ('Reportes', Icons.bar_chart, 'Resumen de reportes'),
          ('Caja y bancos', Icons.account_balance, 'Caja y ventas'),
        ];
        final cols = c.maxWidth >= 950
            ? 6
            : c.maxWidth >= 500
            ? 3
            : 2;
        final w = (c.maxWidth - (cols - 1) * 8) / cols;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _title('Accesos rápidos', Icons.bolt),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, icon, dest) in items)
                  SizedBox(
                    width: w,
                    child: OutlinedButton(
                      onPressed: () => widget.onNavigate(dest),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 15,
                          horizontal: 7,
                        ),
                        side: const BorderSide(color: _accent),
                        foregroundColor: _white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 16, color: _cyan),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                          const Icon(
                            Icons.chevron_right,
                            color: _cyan,
                            size: 16,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final data = _summary;
    final branches = _rows(data?['branches']);
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openSearch,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          color: _bg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _topbar(),
              const SizedBox(height: 10),
              if (branches.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SizedBox(
                    width: 260,
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      key: ValueKey<int?>(_branch),
                      initialValue: _branch,
                      decoration: const InputDecoration(
                        labelText: 'Sucursal',
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Todas las sucursales'),
                        ),
                        for (final b in branches)
                          DropdownMenuItem<int?>(
                            value: _integer(b['id']),
                            child: Text(
                              '${b['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        setState(() {
                          _branch = v;
                          _offset = 0;
                        });
                        _load();
                      },
                    ),
                  ),
                ),
              if (_first) const LinearProgressIndicator(color: _cyan),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'No se pudo actualizar parte del Dashboard: $_error',
                          style: const TextStyle(color: _pink, fontSize: 11),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _load(),
                        icon: const Icon(Icons.refresh, color: _cyan),
                      ),
                    ],
                  ),
                ),
              if (data != null) ...[
                _banner(data),
                const SizedBox(height: 11),
                _kpis(data),
                const SizedBox(height: 11),
                _analytics(),
                const SizedBox(height: 11),
                _operations(),
                const SizedBox(height: 11),
                _shortcuts(),
                if (_updated != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 9),
                    child: Text(
                      'Última actualización: ${TimeOfDay.fromDateTime(_updated!).format(context)}',
                      style: const TextStyle(color: _muted, fontSize: 10),
                    ),
                  ),
              ] else if (!_first && _error == null)
                const Text(
                  'No hay información del Dashboard.',
                  style: TextStyle(color: _muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.values);
  final List<int> values;
  static const colors = <Color>[
    Color(0xFF00DCE5),
    Color(0xFFA96CFA),
    Color(0xFFEC488A),
    Color(0xFF7E48EB),
    Color(0xFF00D99A),
    Color(0xFFFFC242),
  ];
  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (a, b) => a + b);
    if (total == 0) {
      return;
    }
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * .42;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 15;
    var angle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final sweep = 2 * math.pi * values[i] / total;
      paint.color = colors[i % colors.length];
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        angle,
        sweep,
        false,
        paint,
      );
      angle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.values != values;
}

class _LinesPainter extends CustomPainter {
  _LinesPainter(this.rows);
  final List<Map<String, dynamic>> rows;
  @override
  void paint(Canvas canvas, Size size) {
    if (rows.length < 2) {
      return;
    }
    final maxV = rows.fold<double>(
      1,
      (v, row) =>
          math.max(v, math.max(_num(row['sales']), _num(row['expenses']))),
    );
    final lines = [const Color(0xFF00DCE5), const Color(0xFFEC488A)];
    for (var j = 0; j < 2; j++) {
      final key = j == 0 ? 'sales' : 'expenses';
      final path = Path();
      var drawn = false;
      for (var i = 0; i < rows.length; i++) {
        if (rows[i][key] == null) {
          drawn = false;
          continue;
        }
        final p = Offset(
          i * size.width / (rows.length - 1),
          size.height * (1 - _num(rows[i][key]) / maxV),
        );
        if (!drawn) {
          path.moveTo(p.dx, p.dy);
          drawn = true;
        } else {
          path.lineTo(p.dx, p.dy);
        }
        canvas.drawCircle(p, 3, Paint()..color = lines[j]);
      }
      final stroke = Paint();
      stroke.color = lines[j];
      stroke.strokeWidth = 2;
      stroke.style = PaintingStyle.stroke;
      canvas.drawPath(path, stroke);
    }
  }

  static double _num(dynamic raw) =>
      raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  @override
  bool shouldRepaint(covariant _LinesPainter old) => old.rows != rows;
}
