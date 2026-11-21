// ignore_for_file: curly_braces_in_flow_control_structures, unnecessary_string_interpolations
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/business_identity.dart';
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';
import '../core/dashboard_greeting_24n27.dart';
import '../core/mycarwash_session.dart';

/// Portal acotado para trabajadores de lavado. Ningun CRUD administrativo.
/// El aislamiento verdadero se comprueba ademas en el servidor Laravel.
class CompanyWasherPortal24N3 extends StatefulWidget {
  const CompanyWasherPortal24N3({super.key, this.client});

  static const Map<String, List<String>> categories = {
    'Inicio': ['Resumen'],
    'Mis trabajos': ['Órdenes asignadas', 'Mi agenda'],
    'Asistencia': ['Marcar asistencia', 'Mi historial'],
    'Perfil': ['Datos personales', 'Cambiar contraseña'],
  };

  final http.Client? client;

  @override
  State<CompanyWasherPortal24N3> createState() =>
      _CompanyWasherPortal24N3State();
}

class _CompanyWasherPortal24N3State extends State<CompanyWasherPortal24N3> {
  late final http.Client _client;
  late final bool _ownsClient;
  late final CompanyBusinessApi _api;

  String _category = 'Inicio';
  String _page = 'Resumen';
  bool _loading = false;
  bool _working = false;
  String? _error;
  List<Map<String, dynamic>> _orders = [];
  int _ordersPageNumber = 1;
  int _ordersLastPage = 1;
  Map<String, dynamic> _statusCounts = {};

  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _attendance = [];
  bool _onDuty = false;
  Map<String, dynamic> _me = {};
  DateTime _anchor = DateTime.now();
  String _calendarView = 'week';
  String _attendanceMonth = '';
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _oldPassword = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();
  bool _expanded = true;



  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _api = CompanyBusinessApi(_client);
    _attendanceMonth = _month(DateTime.now());
    BusinessIdentity.refresh(client: _client);
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _oldPassword.dispose();
    _newPassword.dispose();
    _confirmPassword.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  static String _date(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static String _month(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is! List) return [];
    return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  String get _firstName => (_me['name'] ?? '').toString().trim().split(' ').first;

  Future<void> _load() async {
    if (!MyCarWashSession.isAuthenticated || !MyCarWashSession.isWasher) return;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.request('GET', '/washer/orders', query: {'page': '$_ordersPageNumber'}),
        _api.request('GET', '/washer/me'),
        _api.request('GET', '/washer/agenda', query: {
          'date': _date(_anchor), 'view': _calendarView,
        }),
        _api.request('GET', '/washer/attendance', query: {
          'month': _attendanceMonth,
        }),
      ]);
      if (!mounted) return;
      final user = results[1]['user'];
      setState(() {
        _orders = _rows(results[0]['data']);
        _ordersLastPage = (results[0]['last_page'] as num?)?.toInt() ?? 1;
        _statusCounts = results[0]['status_counts'] is Map
            ? Map<String, dynamic>.from(results[0]['status_counts'] as Map)
            : {};
        _me = user is Map ? Map<String, dynamic>.from(user) : {};
        _bookings = _rows(results[2]['data']);
        _attendance = _rows(results[3]['data']);
        _onDuty = results[3]['on_duty'] == true;
        _name.text = (_me['name'] ?? '').toString();
        _email.text = (_me['email'] ?? '').toString();
        _phone.text = (_me['phone'] ?? '').toString();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _navigate(String category, String page) {
    if (_working) return;
    setState(() { _category = category; _page = page; });
    _load();
  }

  Future<void> _act(String method, String path, Map<String, dynamic> body) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      final result = await _api.request(method, path, body: body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((result['message'] ?? 'Acción realizada.').toString()),
      ));
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: CompanyVisualTheme.danger),
      );
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _changePassword() async {
    if (_newPassword.text.length < 10) {
      _showMessage('La nueva contraseña debe tener al menos 10 caracteres.');
      return;
    }
    if (_newPassword.text != _confirmPassword.text) {
      _showMessage('Las nuevas contraseñas no coinciden.');
      return;
    }
    if (_working) return;
    setState(() => _working = true);
    try {
      await _api.request('PATCH', '/washer/password', body: {
        'current_password': _oldPassword.text,
        'password': _newPassword.text,
        'password_confirmation': _confirmPassword.text,
      });
      _oldPassword.clear();
      _newPassword.clear();
      _confirmPassword.clear();
      if (!mounted) return;
      _showMessage('Contraseña actualizada. Inicia sesión nuevamente.');
      _exit();
    } catch (e) {
      _showMessage('$e');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  void _exit() {
    MyCarWashSession.clear();
    BusinessIdentity.reset();
    Navigator.of(context).pop();
  }

  Color get _primary => CompanyVisualTheme.primary;
  Color get _text => CompanyVisualTheme.text;
  Color get _muted => CompanyVisualTheme.muted;

  Widget _card(Widget child, {EdgeInsetsGeometry? padding}) => Container(
    decoration: BoxDecoration(
      color: CompanyVisualTheme.card,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: CompanyVisualTheme.border),
    ),
    padding: padding ?? const EdgeInsets.all(20),
    child: child,
  );

  Widget _headline(String title, String subtitle, IconData icon) => Row(
    children: [
      Icon(icon, color: _primary, size: 28),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: _text, fontSize: 21, fontWeight: FontWeight.w800)),
          Text(subtitle, style: TextStyle(color: _muted, fontSize: 12)),
        ])),
      IconButton(onPressed: _loading ? null : _load,
        tooltip: 'Actualizar', icon: Icon(Icons.refresh, color: _primary)),
    ],
  );

  Widget _empty(String label) => _card(Padding(
    padding: const EdgeInsets.symmetric(vertical: 30),
    child: Center(child: Text(label, style: TextStyle(color: _muted))),
  ));

  Widget _stat(String label, String value, IconData icon) => SizedBox(
    width: 210,
    child: _card(Row(children: [
      Icon(icon, color: _primary), const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: _muted, fontSize: 12)),
        Text(value, style: TextStyle(color: _text, fontSize: 24, fontWeight: FontWeight.w800)),
      ])),
    ])),
  );

  Widget _home() {
    final active = int.tryParse('${_statusCounts['EN_PROCESO'] ?? 0}') ?? 0;
    final pending = int.tryParse('${_statusCounts['ASIGNADO'] ?? 0}') ?? 0;
    final completed = int.tryParse('${_statusCounts['TERMINADO'] ?? 0}') ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _headline(dashboardGreeting24N27(DateTime.now(), _firstName),
        'Este panel muestra únicamente tus actividades asignadas.', Icons.home_outlined),
      const SizedBox(height: 18),
      Wrap(spacing: 12, runSpacing: 12, children: [
        _stat('En proceso', '$active', Icons.local_car_wash_outlined),
        _stat('Pendientes', '$pending', Icons.pending_actions_outlined),
        _stat('Terminados', '$completed', Icons.check_circle_outline),
        _stat('Mi asistencia', _onDuty ? 'En turno' : 'Sin entrada', Icons.how_to_reg_outlined),
      ]),
      const SizedBox(height: 18),
      _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Accesos rápidos', style: TextStyle(color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        Wrap(spacing: 10, runSpacing: 10, children: [
          OutlinedButton.icon(onPressed: () => _navigate('Mis trabajos', 'Órdenes asignadas'),
            icon: const Icon(Icons.car_repair), label: const Text('Mis órdenes')),
          OutlinedButton.icon(onPressed: () => _navigate('Mis trabajos', 'Mi agenda'),
            icon: const Icon(Icons.calendar_month), label: const Text('Mi agenda')),
          OutlinedButton.icon(onPressed: () => _navigate('Asistencia', 'Marcar asistencia'),
            icon: const Icon(Icons.access_time), label: const Text('Marcar asistencia')),
        ]),
      ])),
    ]);
  }

  String _status(String value) => switch (value) {
    'ASIGNADO' => 'Asignado',
    'EN_PROCESO' => 'En proceso',
    'TERMINADO' => 'Terminado',
    'ENTREGADO' => 'Entregado',
    'CANCELADO' => 'Cancelado',
    _ => value,
  };

  Widget _ordersPage() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _headline('Mis trabajos', 'Solo los lavados que tienes asignados; no puedes editar ni crear órdenes.',
          Icons.local_car_wash_outlined),
      const SizedBox(height: 18),
      if (_orders.isEmpty) _empty('No tienes órdenes asignadas.')
      else ..._orders.map((order) {
        final id = int.tryParse('${order['id']}') ?? 0;
        final version = int.tryParse('${order['version']}') ?? 0;
        final status = '${order['status']}';
        final vehicle = [order['brand'], order['model'], order['plate']]
            .where((part) => part != null && '$part'.trim().isNotEmpty).join(' ');
        return Padding(padding: const EdgeInsets.only(bottom: 12), child: _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: Text('Orden #$id · $vehicle', style: TextStyle(
                color: _text, fontWeight: FontWeight.w700, fontSize: 16))),
              Chip(label: Text(_status(status))),
            ]),
            const SizedBox(height: 6),
            Text('${order['service_name'] ?? 'Servicio'}', style: TextStyle(color: _muted)),
            const SizedBox(height: 12),
            if (status == 'ASIGNADO') FilledButton.icon(
              onPressed: _working || id <= 0 || version <= 0 ? null : () =>
                  _act('POST', '/washer/orders/$id/start', {'expected_version': version}),
              icon: const Icon(Icons.play_arrow), label: const Text('Iniciar lavado'),
            ),
            if (status == 'EN_PROCESO') FilledButton.icon(
              onPressed: _working || id <= 0 || version <= 0 ? null : () =>
                  _act('POST', '/washer/orders/$id/finish', {'expected_version': version}),
              icon: const Icon(Icons.check), label: const Text('Terminar lavado'),
            ),
          ],
        )));
      }),
      if (_ordersLastPage > 1) _card(Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(onPressed: _ordersPageNumber <= 1 ? null : () {
            setState(() => _ordersPageNumber--); _load();
          }, icon: const Icon(Icons.chevron_left)),
          Text('Página $_ordersPageNumber de $_ordersLastPage'),
          IconButton(onPressed: _ordersPageNumber >= _ordersLastPage ? null : () {
            setState(() => _ordersPageNumber++); _load();
          }, icon: const Icon(Icons.chevron_right)),
        ],
      )),
    ]);
  }

  Widget _agendaPage() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _headline('Mi agenda', 'Únicamente reservas agendadas para ti.', Icons.calendar_month_outlined),
      const SizedBox(height: 18),
      _card(Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 12,
        runSpacing: 12, children: [
          SegmentedButton<String>(segments: const [
            ButtonSegment(value: 'day', label: Text('Día')),
            ButtonSegment(value: 'week', label: Text('Semana')),
            ButtonSegment(value: 'month', label: Text('Mes')),
          ], selected: {_calendarView}, onSelectionChanged: (values) {
            setState(() => _calendarView = values.first);
            _load();
          }),
          OutlinedButton.icon(onPressed: () async {
            final selected = await showDatePicker(context: context,
              initialDate: _anchor, firstDate: DateTime(2020), lastDate: DateTime(2100));
            if (!mounted) return;
            if (selected != null) { setState(() => _anchor = selected); _load(); }
          }, icon: const Icon(Icons.event), label: Text(_date(_anchor))),
        ])),
      const SizedBox(height: 14),
      if (_bookings.isEmpty) _empty('No tienes reservas asignadas en este período.')
      else ..._bookings.map((booking) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _card(Row(children: [
          Icon(Icons.event_available_outlined, color: _primary),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${booking['date'] ?? ''} · ${booking['time'] ?? ''}',
              style: TextStyle(fontWeight: FontWeight.w800, color: _text)),
            Text('${booking['service'] ?? 'Lavado'} · ${booking['vehicle'] ?? ''}',
              style: TextStyle(color: _muted)),
          ])),
        ])),
      )),
    ]);
  }

  static String _displayMoment(dynamic value) {
    if (value == null) return 'Sin registrar';
    final raw = value.toString().trim();
    if (raw.isEmpty) return 'Sin registrar';
    final parsed = DateTime.tryParse(raw.replaceFirst(' ', 'T') +
        (raw.endsWith('Z') || raw.contains('+') ? '' : 'Z'));
    if (parsed == null) return raw;
    final local = parsed.toUtc().subtract(const Duration(hours: 6));
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final period = local.hour < 12 ? 'a. m.' : 'p. m.';
    return '${_date(local)} $h:${local.minute.toString().padLeft(2, '0')} $period';
  }

  Widget _attendancePage({required bool history}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _headline(history ? 'Mi historial de asistencia' : 'Marcar asistencia',
        'Las marcas se registran con la hora del servidor; no se pueden editar.',
        Icons.how_to_reg_outlined),
      const SizedBox(height: 18),
      if (!history) _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_onDuty ? 'Tu jornada está iniciada' : 'No tienes una entrada activa',
          style: TextStyle(color: _text, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        FilledButton.icon(onPressed: _working ? null : () => _act('POST',
          _onDuty ? '/washer/attendance/check-out' : '/washer/attendance/check-in', {}),
          icon: Icon(_onDuty ? Icons.logout : Icons.login),
          label: Text(_onDuty ? 'Marcar salida' : 'Marcar entrada')),
      ])),
      if (!history) const SizedBox(height: 20),
      _card(Row(children: [
        Expanded(child: Text('Mes de consulta', style: TextStyle(color: _text, fontWeight: FontWeight.bold))),
        IconButton(onPressed: () { final parts = _attendanceMonth.split('-').map(int.parse).toList();
          final d = DateTime(parts[0], parts[1] - 1); setState(() => _attendanceMonth = _month(d)); _load();
        }, icon: const Icon(Icons.chevron_left)),
        Text(_attendanceMonth),
        IconButton(onPressed: () { final parts = _attendanceMonth.split('-').map(int.parse).toList();
          final d = DateTime(parts[0], parts[1] + 1); setState(() => _attendanceMonth = _month(d)); _load();
        }, icon: const Icon(Icons.chevron_right)),
      ])),
      const SizedBox(height: 12),
      if (_attendance.isEmpty) _empty('No hay registros para este mes.')
      else ..._attendance.map((entry) => Padding(padding: const EdgeInsets.only(bottom: 10),
        child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Fecha: ${entry['work_date'] ?? ''}', style: TextStyle(
            fontWeight: FontWeight.bold, color: _text)),
          Text('Entrada: ${_displayMoment(entry['check_in_at'])}', style: TextStyle(color: _muted)),
          Text('Salida: ${_displayMoment(entry['check_out_at'])}', style: TextStyle(color: _muted)),
        ])),
      )),
    ]);
  }

  Widget _profilePage({required bool password}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _headline(password ? 'Cambiar contraseña' : 'Mis datos personales',
        password ? 'Protege tu cuenta con una contraseña nueva.' :
        'Solo puedes actualizar tu información personal.',
        Icons.person_outline),
      const SizedBox(height: 18),
      _card(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 580),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (!password) ...[
            TextField(controller: _name, decoration: const InputDecoration(labelText: 'Nombre')),
            const SizedBox(height: 14),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Correo electrónico')),
            const SizedBox(height: 14),
            TextField(controller: _phone, keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Teléfono')),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _working ? null : () {
              if (_name.text.trim().length < 2 || !_email.text.contains('@')) {
                _showMessage('Revisa el nombre y correo electrónico.');
                return;
              }
              _act('PATCH', '/washer/me', {
                'name': _name.text.trim(), 'email': _email.text.trim(),
                'phone': _phone.text.trim(),
              });
            }, icon: const Icon(Icons.save_outlined), label: const Text('Guardar mis datos')),
          ] else ...[
            TextField(controller: _oldPassword, obscureText: true,
              decoration: const InputDecoration(labelText: 'Contraseña actual')),
            const SizedBox(height: 14),
            TextField(controller: _newPassword, obscureText: true,
              decoration: const InputDecoration(labelText: 'Nueva contraseña (mínimo 10 caracteres)')),
            const SizedBox(height: 14),
            TextField(controller: _confirmPassword, obscureText: true,
              decoration: const InputDecoration(labelText: 'Confirmar contraseña nueva')),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _working ? null : _changePassword,
              icon: const Icon(Icons.lock_reset), label: const Text('Cambiar contraseña')),
          ],
        ]))),
    ]);
  }

  Widget _content() {
    if (_loading) return Center(child: CircularProgressIndicator(color: _primary));
    if (_error != null) return _card(Column(mainAxisSize: MainAxisSize.min, children: [
      Text('No se pudieron cargar tus datos: $_error', style: TextStyle(color: _text)),
      const SizedBox(height: 14),
      FilledButton(onPressed: _load, child: const Text('Reintentar')),
    ]));
    return switch (_page) {
      'Órdenes asignadas' => _ordersPage(),
      'Mi agenda' => _agendaPage(),
      'Marcar asistencia' => _attendancePage(history: false),
      'Mi historial' => _attendancePage(history: true),
      'Datos personales' => _profilePage(password: false),
      'Cambiar contraseña' => _profilePage(password: true),
      _ => _home(),
    };
  }

  IconData _icon(String category) => switch (category) {
    'Mis trabajos' => Icons.local_car_wash_outlined,
    'Asistencia' => Icons.access_time_outlined,
    'Perfil' => Icons.person_outline,
    _ => Icons.home_outlined,
  };

  Widget _sidebar() => Container(
    color: CompanyVisualTheme.sidebar,
    child: Column(children: [
      Padding(padding: const EdgeInsets.all(18), child: Row(children: [
        Icon(Icons.local_car_wash, color: _primary), const SizedBox(width: 10),
        Expanded(child: Text('ADN MyCarWash', style: TextStyle(
          fontWeight: FontWeight.bold, color: _text, fontSize: 16))),
      ])),
      Divider(color: CompanyVisualTheme.border),
      Expanded(child: ListView(children: CompanyWasherPortal24N3.categories.entries.map((entry) =>
        ExpansionTile(
          initiallyExpanded: entry.key == _category,
          key: ValueKey('${entry.key}:${entry.key == _category}'),
          leading: Icon(_icon(entry.key), color: _primary),
          title: Text(entry.key, style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
          children: entry.value.map((page) => ListTile(
            selected: _category == entry.key && _page == page,
            selectedColor: _primary,
            title: Text(page, style: TextStyle(fontSize: 13,
              color: _category == entry.key && _page == page ? _primary : _muted)),
            onTap: () => _navigate(entry.key, page),
            contentPadding: const EdgeInsets.only(left: 60, right: 14),
          )).toList(),
        ),
      ).toList())),
      Divider(color: CompanyVisualTheme.border),
      ListTile(leading: Icon(Icons.logout, color: _primary),
        title: Text('Cerrar sesión', style: TextStyle(color: _text)), onTap: _exit),
    ]),
  );

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      appBar: narrow ? AppBar(
        title: Text('MyCarWash · $_category'),
        backgroundColor: CompanyVisualTheme.sidebar,
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))],
      ) : null,
      drawer: narrow ? Drawer(child: _sidebar()) : null,
      body: Row(children: [
        if (!narrow) SizedBox(width: _expanded ? 245.0 : 0.0,
          child: _expanded ? _sidebar() : const SizedBox.shrink()),
        Expanded(child: Column(children: [
          if (!narrow) Align(alignment: Alignment.centerLeft,
            child: IconButton(tooltip: 'Mostrar u ocultar menú',
              onPressed: () => setState(() => _expanded = !_expanded),
              icon: Icon(Icons.menu, color: _primary))),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1360),
              child: _content()),
          )),
        ])),
      ]),
    );
  }
}
