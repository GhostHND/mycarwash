import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'master_form_24n9.dart';

/// Oficina comercial de MyCarWash, independiente de ADN Software Master.
/// Únicamente consume rutas protegidas por MasterOnly24N8.
class MasterOffice24N9 extends StatefulWidget {
  const MasterOffice24N9({super.key});

  @override
  State<MasterOffice24N9> createState() => _MasterOffice24N9State();
}

class _MasterOffice24N9State extends State<MasterOffice24N9> {
  static const _api = String.fromEnvironment(
    'MYCARWASH_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );
  static const _bg = Color(0xFF040D11);
  static const _panel = Color(0xFF081C22);
  static const _panel2 = Color(0xFF0B262D);
  static const _line = Color(0xFF294C55);
  static const _accent = Color(0xFF00D6DC);
  static const _soft = Color(0xFFA3BBC2);
  static const _success = Color(0xFF43D6A1);
  static const _danger = Color(0xFFFF8092);
  static const _amber = Color(0xFFF5C36B);

  static const _titles = <String>[
    'Dashboard',
    'Empresas',
    'Clientes comerciales',
    'Planes',
    'Suscripciones',
    'Facturas',
    'Pagos',
    'Notificaciones',
    'Auditoría',
  ];
  static const _icons = <IconData>[
    Icons.space_dashboard_outlined,
    Icons.apartment_rounded,
    Icons.groups_2_outlined,
    Icons.layers_outlined,
    Icons.verified_user_outlined,
    Icons.receipt_long_rounded,
    Icons.payments_outlined,
    Icons.notifications_active_outlined,
    Icons.history_rounded,
  ];
  static const _resources = <String>[
    '',
    'companies',
    'customers',
    'plans',
    'subscriptions',
    'invoices',
    'payments',
    'notices',
    'activity',
  ];
  static const _descriptions = <String>[
    'La operación comercial de MyCarWash en tiempo real',
    'Gestiona las empresas, sus administradores y el acceso al sistema',
    'Propietarios y clientes que contratan MyCarWash',
    'Precios, disponibilidad y módulos incluidos por nivel',
    'Asignaciones, renovaciones, mora y suspensiones sin eliminar datos',
    'Documentos de cobro, vencimientos e historial',
    'Registra, verifica y confirma pagos de suscripciones',
    'Mensajes para el administrador de una empresa o para todas',
    'Historial inmutable de acciones de los operadores maestros',
  ];

  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _search = TextEditingController();
  Timer? _searchTimer;
  String? _token;
  String? _error;
  String _filter = 'Todas';
  int _section = 0;
  int _page = 1;
  int _lastPage = 1;
  int _total = 0;
  bool _loggingIn = false;
  bool _loading = false;
  bool _loadingRows = false;
  bool _processing = false;
  Map<String, dynamic> _workspace = {};
  List<Map<String, dynamic>> _pageRows = [];

  @override
  void dispose() {
    _searchTimer?.cancel();
    _email.dispose();
    _password.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, dynamic>? payload,
  ]) async {
    final request = http.Request(method, Uri.parse('$_api/master/$path'));
    request.headers['Accept'] = 'application/json';
    request.headers['Content-Type'] = 'application/json';
    if (_token != null) {
      request.headers['Authorization'] = 'Bearer $_token';
    }
    if (payload != null) {
      request.body = jsonEncode(payload);
    }
    final client = http.Client();
    late final http.Response response;
    try {
      final streamed = await client
          .send(request)
          .timeout(const Duration(seconds: 30));
      response = await http.Response.fromStream(streamed);
    } finally {
      client.close();
    }
    Map<String, dynamic> decoded = {};
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(response.body) as Map);
    } catch (_) {
      decoded = {};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errors = decoded['errors'];
      String message =
          decoded['message']?.toString() ?? 'Error HTTP ${response.statusCode}';
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        message = first is List && first.isNotEmpty
            ? first.first.toString()
            : first.toString();
      }
      if (response.statusCode == 401 && mounted) {
        setState(() => _token = null);
      }
      throw Exception(message);
    }
    return decoded;
  }

  Future<void> _login() async {
    if (_loggingIn) {
      return;
    }
    setState(() {
      _loggingIn = true;
      _error = null;
    });
    try {
      final response = await _call('POST', 'auth/token', {
        'email': _email.text.trim().toLowerCase(),
        'password': _password.text,
      });
      final token = response['access_token']?.toString();
      if (token == null || token.isEmpty) {
        throw Exception('No se pudo iniciar la sesión maestra.');
      }
      _token = token;
      _password.clear();
      await _load();
    } catch (e) {
      _token = null;
      if (mounted) {
        setState(() => _error = _cleanError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loggingIn = false);
      }
    }
  }

  String _cleanError(Object e) => e.toString().replaceFirst('Exception: ', '');

  Future<void> _load() async {
    if (_token == null) {
      return;
    }
    if (mounted) {
      setState(() => _loading = true);
    }
    try {
      final response = await _call('GET', 'workspace-24n9');
      if (mounted) {
        setState(() => _workspace = response);
      }
      if (_section != 0) {
        await _loadRows();
      }
    } catch (e) {
      _notice(_cleanError(e), bad: true);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadRows() async {
    if (_token == null || _section == 0) {
      return;
    }
    final currentSection = _section;
    final search = Uri.encodeQueryComponent(_search.text.trim());
    if (mounted) {
      setState(() => _loadingRows = true);
    }
    try {
      final response = await _call(
        'GET',
        'records-24n9/${_resources[currentSection]}?page=$_page&per_page=18&search=$search',
      );
      if (mounted && currentSection == _section) {
        final raw = response['data'];
        setState(() {
          _pageRows = raw is List
              ? raw
                    .whereType<Map>()
                    .map((r) => Map<String, dynamic>.from(r))
                    .toList()
              : [];
          _lastPage = (response['last_page'] as num?)?.toInt() ?? 1;
          _total = (response['total'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      _notice(_cleanError(e), bad: true);
    } finally {
      if (mounted && currentSection == _section) {
        setState(() => _loadingRows = false);
      }
    }
  }

  void _navigate(int section) {
    if (_section == section) {
      return;
    }
    _searchTimer?.cancel();
    setState(() {
      _section = section;
      _page = 1;
      _filter = 'Todas';
      _search.clear();
      _pageRows = [];
    });
    if (section != 0) {
      _loadRows();
    }
  }

  void _onSearch(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 380), () {
      if (!mounted || _section == 0) {
        return;
      }
      setState(() => _page = 1);
      _loadRows();
    });
  }

  Future<void> _changePage(int delta) async {
    final next = _page + delta;
    if (next < 1 || next > _lastPage) {
      return;
    }
    setState(() => _page = next);
    await _loadRows();
  }

  Future<void> _logout() async {
    try {
      await _call('POST', 'auth/logout', {});
    } catch (_) {
      // Invalidar el token del cliente incluso si la red falla.
    }
    if (mounted) {
      setState(() {
        _token = null;
        _workspace = {};
        _pageRows = [];
        _section = 0;
      });
    }
  }

  void _notice(String text, {bool bad = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: bad ? const Color(0xFF713243) : _panel2,
        content: Text(text),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _txt(dynamic value, [String fallback = '—']) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? fallback : result;
  }

  String _money(dynamic value) {
    if (value == null) {
      return 'Sin precio';
    }
    final number = num.tryParse(value.toString());
    if (number == null) {
      return 'L ${_txt(value)}';
    }
    final formatted = number.toStringAsFixed(2);
    final parts = formatted.split('.');
    final digits = parts.first.replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
    return 'L $digits.${parts.last}';
  }

  Map<String, dynamic> _object(dynamic source) {
    return source is Map
        ? Map<String, dynamic>.from(source)
        : <String, dynamic>{};
  }

  List<Map<String, dynamic>> _items(String key) {
    final raw = _workspace[key];
    return raw is List
        ? raw.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList()
        : [];
  }

  int _stat(String key) =>
      (num.tryParse(_object(_workspace['summary'])[key]?.toString() ?? '') ?? 0)
          .toInt();

  String _status(String value) => switch (value) {
    'active' => 'Activa',
    'pending' => 'Pendiente',
    'past_due' => 'En gracia',
    'suspended' => 'Suspendida',
    'canceled' => 'Cancelada',
    'paid' => 'Pagada',
    'confirmed' => 'Confirmado',
    'void' => 'Anulada',
    'critical' => 'Urgente',
    'warning' => 'Aviso',
    'info' => 'Informativa',
    _ => value.isEmpty ? 'Sin estado' : value,
  };

  Color _statusColor(String value) => switch (value) {
    'active' || 'paid' || 'confirmed' => _success,
    'pending' || 'past_due' || 'warning' => _amber,
    'suspended' || 'canceled' || 'void' || 'critical' => _danger,
    _ => _accent,
  };

  Widget _pill(String value) {
    final color = _statusColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(50),
        color: color.withValues(alpha: .12),
      ),
      child: Text(
        _status(value),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  List<MasterOption24N9> _options(String section, {String? filterStatus}) {
    final result = <MasterOption24N9>[];
    for (final item in _items(section)) {
      if (filterStatus != null && item['status'] != filterStatus) {
        continue;
      }
      final label = _txt(
        item['name'] ?? item['reference'] ?? item['title'] ?? item['id'],
      );
      result.add(
        MasterOption24N9(item['id'].toString(), '$label · #${item['id']}'),
      );
    }
    return result;
  }

  List<MasterField24N9> _fields(int section, {bool edit = false}) {
    final companies = _options('companies');
    final plans = _options('plans');
    final customers = _options('customers');
    final invoices = _items('invoices')
        .where((r) => r['status'] == 'pending')
        .map(
          (r) => MasterOption24N9(
            r['id'].toString(),
            '${_txt(r['reference'])} · ${_money(r['amount'])}',
          ),
        )
        .toList();
    const statuses = [
      MasterOption24N9('active', 'Activa'),
      MasterOption24N9('pending', 'Pendiente'),
      MasterOption24N9('suspended', 'Suspendida'),
      MasterOption24N9('canceled', 'Cancelada'),
    ];
    switch (section) {
      case 1:
        return [
          const MasterField24N9('name', 'Nombre comercial', required: true),
          if (!edit) ...[
            const MasterField24N9(
              'owner_name',
              'Nombre del administrador',
              required: true,
            ),
            const MasterField24N9(
              'owner_email',
              'Correo de inicio de sesión',
              required: true,
            ),
            const MasterField24N9(
              'owner_password',
              'Contraseña inicial segura',
              required: true,
              secret: true,
            ),
          ],
          MasterField24N9(
            'customer_id',
            'Cliente comercial',
            options: customers,
          ),
          MasterField24N9('plan_id', 'Plan contratado', options: plans),
          const MasterField24N9('due_date', 'Próximo vencimiento', date: true),
          if (edit)
            const MasterField24N9(
              'status',
              'Acceso de la empresa',
              options: statuses,
            ),
        ];
      case 2:
        return [
          const MasterField24N9(
            'name',
            'Nombre / razón social',
            required: true,
          ),
          const MasterField24N9('email', 'Correo de cobro'),
          const MasterField24N9('phone', 'Teléfono / WhatsApp'),
          const MasterField24N9('tax_id', 'RTN'),
          const MasterField24N9('notes', 'Notas comerciales', multiline: true),
          if (edit)
            const MasterField24N9(
              'is_active',
              'Estado del cliente',
              options: [
                MasterOption24N9('1', 'Activo'),
                MasterOption24N9('0', 'Archivado'),
              ],
            ),
        ];
      case 3:
        return [
          const MasterField24N9('name', 'Nombre del plan', required: true),
          const MasterField24N9(
            'monthly_price',
            'Precio mensual (L)',
            numeric: true,
          ),
          if (edit)
            const MasterField24N9(
              'is_active',
              'Disponibilidad del plan',
              options: [
                MasterOption24N9('1', 'Habilitado'),
                MasterOption24N9('0', 'Deshabilitado'),
              ],
            ),
        ];
      case 4:
        return [
          MasterField24N9(
            'customer_id',
            'Cliente comercial',
            options: customers,
          ),
          MasterField24N9('plan_id', 'Plan contratado', options: plans),
          const MasterField24N9('due_date', 'Fecha de vencimiento', date: true),
          const MasterField24N9(
            'status',
            'Estado de la suscripción',
            options: statuses,
          ),
          const MasterField24N9('notes', 'Observaciones', multiline: true),
        ];
      case 5:
        return [
          if (!edit)
            MasterField24N9(
              'company_id',
              'Empresa a facturar',
              required: true,
              options: companies,
            ),
          const MasterField24N9(
            'amount',
            'Importe (L)',
            required: true,
            numeric: true,
          ),
          const MasterField24N9(
            'due_date',
            'Fecha de pago',
            required: true,
            date: true,
          ),
          const MasterField24N9(
            'coverage_until',
            'Cobertura hasta',
            required: true,
            date: true,
          ),
          const MasterField24N9('notes', 'Concepto y notas', multiline: true),
        ];
      case 6:
        return [
          if (!edit)
            MasterField24N9(
              'invoice_id',
              'Factura pendiente',
              required: true,
              options: invoices,
            ),
          const MasterField24N9(
            'amount',
            'Importe recibido (L)',
            required: true,
            numeric: true,
          ),
          const MasterField24N9(
            'method',
            'Método de pago',
            required: true,
            options: [
              MasterOption24N9('transferencia', 'Transferencia bancaria'),
              MasterOption24N9('efectivo', 'Efectivo'),
              MasterOption24N9('deposito', 'Depósito'),
              MasterOption24N9('tarjeta', 'Tarjeta'),
              MasterOption24N9('otro', 'Otro'),
            ],
          ),
          const MasterField24N9('reference', 'Número de referencia'),
          const MasterField24N9('notes', 'Observaciones', multiline: true),
        ];
      case 7:
        return [
          MasterField24N9(
            'company_id',
            'Destinatario (vacío = todas)',
            options: companies,
          ),
          const MasterField24N9('title', 'Título del aviso', required: true),
          const MasterField24N9(
            'body',
            'Mensaje',
            required: true,
            multiline: true,
          ),
          const MasterField24N9(
            'severity',
            'Prioridad',
            options: [
              MasterOption24N9('info', 'Informativa'),
              MasterOption24N9('warning', 'Advertencia'),
              MasterOption24N9('critical', 'Urgente'),
            ],
          ),
          const MasterField24N9('starts_at', 'Visible desde (opcional)'),
          const MasterField24N9('expires_at', 'Caduca (opcional)'),
          if (edit)
            const MasterField24N9(
              'is_active',
              'Disponibilidad del aviso',
              options: [
                MasterOption24N9('1', 'Visible'),
                MasterOption24N9('0', 'Archivado'),
              ],
            ),
        ];
      default:
        return [];
    }
  }

  Map<String, dynamic> _initial(int section, Map<String, dynamic> row) {
    final initial = Map<String, dynamic>.from(row);
    if (section == 2 || section == 3 || section == 7) {
      initial['is_active'] = row['is_active'] == true || row['is_active'] == 1
          ? '1'
          : '0';
    }
    if (section == 1 || section == 4) {
      initial['customer_id'] = row['master_customer_id'];
      initial['plan_id'] = row['master_plan_id'];
      initial['status'] = row['stored_status'] ?? row['status'];
    }
    return initial;
  }

  Future<void> _newRecord() async {
    final section = _section;
    if (section == 0 || section == 4 || section == 8) {
      return;
    }
    final fields = _fields(section);
    final data = await showMasterForm24N9(
      context,
      title: 'Nuevo · ${_titles[section]}',
      fields: fields,
      planFeatures: section == 3,
    );
    if (data == null || !mounted) {
      return;
    }
    if (section == 7 && data['severity'] == null) {
      data['severity'] = 'info';
    }
    await _perform(
      'POST',
      _resources[section],
      data,
      'Registro creado correctamente.',
    );
  }

  Future<void> _editRecord(Map<String, dynamic> row) async {
    final section = _section;
    final data = await showMasterForm24N9(
      context,
      title: 'Editar · ${_titles[section]} #${row['id']}',
      fields: _fields(section, edit: true),
      initial: _initial(section, row),
      planFeatures: section == 3,
    );
    if (data == null || !mounted) {
      return;
    }
    // Evitar enviar null para campos con validación sometimes|string.
    data.removeWhere(
      (key, value) =>
          value == null &&
          ![
            'notes',
            'phone',
            'email',
            'tax_id',
            'monthly_price',
            'customer_id',
            'plan_id',
            'due_date',
            'company_id',
            'starts_at',
            'expires_at',
            'reference',
          ].contains(key),
    );
    // Una selección vacía significa desvincular, no el ID cero.
    final id = section == 4 ? row['company_id'] : row['id'];
    final endpoint = section == 4
        ? 'subscriptions-24n9/$id'
        : '${_resources[section]}/$id';
    await _perform('PATCH', endpoint, data, 'Cambios guardados correctamente.');
  }

  Future<bool> _confirm(
    String title,
    String question, {
    bool critical = false,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _panel,
        title: Text(title),
        content: Text(question, style: const TextStyle(color: _soft)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: critical
                ? FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF9C3545),
                  )
                : null,
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _deleteRecord(Map<String, dynamic> row) async {
    final section = _section;
    if (section == 8) {
      return;
    }
    final name = _txt(
      row['name'] ?? row['title'] ?? row['reference'] ?? row['id'],
    );
    if (!await _confirm(
      'Archivar o anular',
      '¿Confirmas archivar/anular "$name"? Los datos y movimientos históricos se conservarán.',
      critical: true,
    )) {
      return;
    }
    if (section == 4) {
      await _perform('PATCH', 'subscriptions-24n9/${row['company_id']}', {
        'status': 'canceled',
      }, 'Suscripción cancelada, sin borrar datos.');
    } else {
      await _perform(
        'DELETE',
        '${_resources[section]}/${row['id']}',
        null,
        'Registro archivado o anulado.',
      );
    }
  }

  Future<void> _confirmPayment(Map<String, dynamic> row) async {
    if (!await _confirm(
      'Verificación del pago',
      '¿Ya verificaste el ingreso real de ${_money(row['amount'])}? '
          'Una vez confirmado, este pago no podrá editarse y puede reactivar la suscripción.',
    )) {
      return;
    }
    await _perform(
      'POST',
      'payments/${row['id']}/confirm',
      {},
      'Pago confirmado. Estado de la suscripción actualizado.',
    );
  }

  Future<void> _perform(
    String method,
    String path,
    Map<String, dynamic>? data,
    String success,
  ) async {
    if (_processing) {
      return;
    }
    setState(() => _processing = true);
    try {
      await _call(method, path, data);
      await _load();
      _notice(success);
    } catch (e) {
      _notice(_cleanError(e), bad: true);
    } finally {
      if (mounted) {
        setState(() => _processing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.dark(useMaterial3: true);
    return Theme(
      data: dark.copyWith(
        scaffoldBackgroundColor: _bg,
        colorScheme: const ColorScheme.dark(
          primary: _accent,
          onPrimary: _bg,
          surface: _panel,
          onSurface: Colors.white,
          secondary: _success,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _accent,
            foregroundColor: _bg,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: _accent,
            side: const BorderSide(color: _line),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationThemeData(
          filled: true,
          fillColor: _panel2,
          labelStyle: const TextStyle(color: _soft),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 17,
          ),
          border: OutlineInputBorder(
            borderSide: const BorderSide(color: _line),
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: _line),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _bg,
        drawer: _token != null
            ? Drawer(
                backgroundColor: _panel,
                child: SafeArea(child: _navigation(compact: true)),
              )
            : null,
        body: SafeArea(child: _token == null ? _loginPage() : _officePage()),
      ),
    );
  }

  Widget _loginPage() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: _surface(
            padding: 28,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 66,
                  height: 66,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.admin_panel_settings_rounded,
                    color: _accent,
                    size: 35,
                  ),
                ),
                const SizedBox(height: 22),
                const Text(
                  'ADN MyCarWash',
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                const Text(
                  'CENTRO DE ADMINISTRACIÓN MAESTRA',
                  style: TextStyle(
                    color: _accent,
                    letterSpacing: 1.0,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Acceso exclusivo de ADN Publicidad. Ningún usuario de una empresa puede administrar otras cuentas.',
                  style: TextStyle(color: _soft, height: 1.4),
                ),
                const SizedBox(height: 26),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Correo maestro',
                    prefixIcon: Icon(Icons.alternate_email),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(
                    labelText: 'Contraseña maestra',
                    prefixIcon: Icon(Icons.lock_outline_rounded),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: _danger)),
                ],
                const SizedBox(height: 25),
                FilledButton.icon(
                  onPressed: _loggingIn ? null : _login,
                  icon: const Icon(Icons.login_rounded),
                  label: Text(
                    _loggingIn
                        ? 'Validando acceso…'
                        : 'Entrar a la administración',
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.maybePop(context),
                  child: const Text('Volver al inicio de MyCarWash'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _officePage() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 900;
        return Row(
          children: [
            if (desktop)
              SizedBox(width: 250, child: _navigation(compact: false)),
            Expanded(
              child: Column(
                children: [
                  _topBar(desktop),
                  if (_loading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        desktop ? 25 : 15,
                        20,
                        desktop ? 25 : 15,
                        35,
                      ),
                      child: _section == 0 ? _dashboard() : _recordsPage(),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _navigation({required bool compact}) {
    return Container(
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(right: BorderSide(color: _line)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 23, 16, 23),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .13),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(
                    Icons.water_drop_outlined,
                    color: _accent,
                    size: 23,
                  ),
                ),
                const SizedBox(width: 11),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADN MyCarWash',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'SOFTWARE · ADMIN',
                        style: TextStyle(
                          color: _accent,
                          fontSize: 9,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: _line),
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 19, 12, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'PANEL DE CONTROL',
                style: TextStyle(
                  color: _soft,
                  fontSize: 10,
                  letterSpacing: 1.5,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(11, 0, 11, 15),
              itemCount: _titles.length,
              itemBuilder: (context, index) {
                final selected = _section == index;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Material(
                    color: selected
                        ? _accent.withValues(alpha: .14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: ListTile(
                      dense: true,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      leading: Icon(
                        _icons[index],
                        size: 20,
                        color: selected ? _accent : _soft,
                      ),
                      title: Text(
                        _titles[index],
                        style: TextStyle(
                          color: selected ? Colors.white : _soft,
                          fontWeight: selected
                              ? FontWeight.w800
                              : FontWeight.w500,
                          fontSize: 13,
                        ),
                      ),
                      trailing: selected
                          ? const Icon(
                              Icons.chevron_right,
                              color: _accent,
                              size: 16,
                            )
                          : null,
                      onTap: () {
                        if (compact) {
                          Navigator.of(context).pop();
                        }
                        _navigate(index);
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1, color: _line),
          Padding(
            padding: const EdgeInsets.all(12),
            child: OutlinedButton.icon(
              onPressed: _logout,
              icon: const Icon(Icons.logout_rounded, size: 17),
              label: const Text('Cerrar sesión'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar(bool desktop) {
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
        color: _panel,
        border: Border(bottom: BorderSide(color: _line)),
      ),
      child: Row(
        children: [
          if (!desktop) ...[
            IconButton(
              tooltip: 'Abrir menú',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu_rounded, color: _accent),
            ),
            const SizedBox(width: 7),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _titles[_section],
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
                const Text(
                  'Centro de control · ADN Publicidad',
                  style: TextStyle(color: _soft, fontSize: 11),
                ),
              ],
            ),
          ),
          if (desktop)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: _success.withValues(alpha: .1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.shield_outlined, color: _success, size: 15),
                  SizedBox(width: 6),
                  Text(
                    'Cuenta maestra',
                    style: TextStyle(color: _success, fontSize: 11),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Actualizar información',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded, color: _accent),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _logout,
            icon: const Icon(Icons.logout_outlined, color: _soft),
          ),
        ],
      ),
    );
  }

  Widget _surface({required Widget child, double padding = 20}) {
    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: child,
    );
  }

  Widget _heading(String title, String subtitle, {Widget? action}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 19),
      child: Wrap(
        spacing: 18,
        runSpacing: 12,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(color: _soft, fontSize: 12),
              ),
            ],
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _dashboard() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          'Resumen general',
          'Ingresos, suscripciones, vencimientos y riesgos de todas tus empresas',
          action: OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.sync_rounded, size: 17),
            label: const Text('Actualizar'),
          ),
        ),
        LayoutBuilder(
          builder: (context, limits) {
            final columns = limits.maxWidth >= 1150
                ? 4
                : limits.maxWidth >= 620
                ? 2
                : 1;
            final gap = 13.0;
            final width = (limits.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: 13,
              children: [
                SizedBox(
                  width: width,
                  child: _statCard(
                    'Empresas registradas',
                    '${_stat('companies_total')}',
                    Icons.apartment,
                    _accent,
                    'Cuentas del sistema',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _statCard(
                    'Acceso habilitado',
                    '${_stat('companies_active')}',
                    Icons.verified_user_outlined,
                    _success,
                    'Empresas operativas',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _statCard(
                    'En gracia',
                    '${_stat('in_grace')}',
                    Icons.hourglass_bottom,
                    _amber,
                    '4 días tras vencimiento',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _statCard(
                    'Sin acceso',
                    '${_stat('companies_suspended')}',
                    Icons.lock_clock_outlined,
                    _danger,
                    'Suspendidas / pendientes',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _statCard(
                    'Cobrado este mes',
                    _money(_object(_workspace['summary'])['income_month']),
                    Icons.account_balance_wallet_outlined,
                    _success,
                    'Pagos confirmados',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _statCard(
                    'Facturas por cobrar',
                    _money(
                      _object(_workspace['summary'])['open_invoices_amount'],
                    ),
                    Icons.receipt_long,
                    _amber,
                    'Monto de facturas pendientes',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _statCard(
                    'Pagos por verificar',
                    '${_stat('payments_to_review')}',
                    Icons.fact_check_outlined,
                    _accent,
                    'Revisión manual requerida',
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _statCard(
                    'Próximos vencimientos',
                    '${_stat('due_soon')}',
                    Icons.event_busy_outlined,
                    _amber,
                    'Dentro de 7 días',
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 19),
        LayoutBuilder(
          builder: (context, limits) {
            final wide = limits.maxWidth >= 840;
            final chart = _revenueChart();
            final alerts = _riskPanel();
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: chart),
                      const SizedBox(width: 14),
                      Expanded(flex: 2, child: alerts),
                    ],
                  )
                : Column(children: [chart, const SizedBox(height: 14), alerts]);
          },
        ),
        const SizedBox(height: 17),
        LayoutBuilder(
          builder: (context, limits) {
            final wide = limits.maxWidth >= 840;
            final due = _duePanel();
            final recent = _activityPanel();
            return wide
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: due),
                      const SizedBox(width: 14),
                      Expanded(child: recent),
                    ],
                  )
                : Column(children: [due, const SizedBox(height: 14), recent]);
          },
        ),
      ],
    );
  }

  Widget _statCard(
    String title,
    String value,
    IconData icon,
    Color color,
    String sub,
  ) {
    return _surface(
      padding: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: _soft,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 7),
          Text(sub, style: const TextStyle(color: _soft, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _revenueChart() {
    final values = _items('income_months');
    double maximum = 0;
    for (final point in values) {
      final amount = (num.tryParse(point['amount'].toString()) ?? 0).toDouble();
      if (amount > maximum) {
        maximum = amount;
      }
    }
    if (maximum <= 0) {
      maximum = 1;
    }
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bar_chart_rounded, color: _accent, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Ingresos de los últimos 6 meses',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Únicamente pagos verificados y confirmados',
            style: TextStyle(color: _soft, fontSize: 11),
          ),
          const SizedBox(height: 22),
          SizedBox(
            height: 195,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final point in values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _money(point['amount']),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 9, color: _soft),
                          ),
                          const SizedBox(height: 7),
                          Container(
                            height:
                                8 +
                                125 *
                                    ((num.tryParse(
                                              point['amount'].toString(),
                                            ) ??
                                            0) /
                                        maximum),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [_accent, Color(0xFF166777)],
                              ),
                              borderRadius: BorderRadius.circular(7),
                            ),
                          ),
                          const SizedBox(height: 9),
                          Text(
                            _txt(point['month']).substring(5),
                            style: const TextStyle(color: _soft, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _riskPanel() {
    final risks = _items('at_risk');
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: _amber, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Atención prioritaria',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (risks.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Text(
                'Sin empresas en mora o suspendidas.',
                style: TextStyle(color: _soft),
              ),
            )
          else
            for (final item in risks.take(5))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 15,
                      backgroundColor: _panel2,
                      child: Icon(Icons.apartment, size: 16, color: _danger),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _txt(item['company_name']),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Vence: ${_txt(item['due_date'])}',
                            style: const TextStyle(color: _soft, fontSize: 10),
                          ),
                        ],
                      ),
                    ),
                    _pill(_txt(_object(item['billing'])['status'], 'pending')),
                  ],
                ),
              ),
          const SizedBox(height: 9),
          TextButton.icon(
            onPressed: () => _navigate(4),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Administrar suscripciones'),
          ),
        ],
      ),
    );
  }

  Widget _duePanel() {
    final due = _items('due_soon');
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.event_available_outlined, color: _accent, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Renovaciones próximas',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (due.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Text(
                'Sin vencimientos en los próximos 7 días.',
                style: TextStyle(color: _soft),
              ),
            )
          else
            for (final item in due.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      color: _amber,
                      size: 18,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _txt(item['company_name']),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Text(
                      _txt(item['due_date']),
                      style: const TextStyle(fontSize: 11, color: _soft),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  Widget _activityPanel() {
    final recent = _items('activity');
    return _surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.history_rounded, color: _accent, size: 20),
              SizedBox(width: 9),
              Expanded(
                child: Text(
                  'Últimos movimientos',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (recent.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 15),
              child: Text(
                'No hay movimientos registrados.',
                style: TextStyle(color: _soft),
              ),
            )
          else
            for (final item in recent.take(6))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 7),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: _success,
                      size: 17,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _txt(item['action']),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      _txt(item['target']),
                      style: const TextStyle(color: _soft, fontSize: 10),
                    ),
                  ],
                ),
              ),
          TextButton.icon(
            onPressed: () => _navigate(8),
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: const Text('Ver auditoría completa'),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _visibleRows() {
    if (_filter == 'Todas') {
      return _pageRows;
    }
    return _pageRows.where((row) {
      final billing = _object(row['billing']);
      final status = _txt(
        billing['status'] ?? row['stored_status'] ?? row['status'],
        '',
      );
      return _status(status) == _filter;
    }).toList();
  }

  Widget _recordsPage() {
    final section = _section;
    final records = _visibleRows();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _heading(
          _titles[section],
          _descriptions[section],
          action: section == 8 || section == 4
              ? null
              : FilledButton.icon(
                  onPressed: _processing ? null : _newRecord,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: Text('Crear ${section == 1 ? 'empresa' : 'registro'}'),
                ),
        ),
        _surface(
          padding: 14,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 12,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430, minWidth: 230),
                child: TextField(
                  controller: _search,
                  onChanged: _onSearch,
                  decoration: const InputDecoration(
                    hintText: 'Buscar por nombre, referencia o título...',
                    prefixIcon: Icon(Icons.search_rounded, color: _accent),
                  ),
                ),
              ),
              Text(
                '$_total registros',
                style: const TextStyle(color: _soft, fontSize: 12),
              ),
              OutlinedButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Actualizar'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        if (section == 1 ||
            section == 4 ||
            section == 5 ||
            section == 6 ||
            section == 7)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final label in const [
                  'Todas',
                  'Activa',
                  'Pendiente',
                  'En gracia',
                  'Suspendida',
                  'Cancelada',
                  'Pagada',
                  'Confirmado',
                  'Anulada',
                  'Aviso',
                  'Urgente',
                ])
                  Padding(
                    padding: const EdgeInsets.only(right: 7),
                    child: ChoiceChip(
                      selected: _filter == label,
                      label: Text(label),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() => _filter = label);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 13),
        if (_loadingRows) const LinearProgressIndicator(minHeight: 2),
        if (!_loadingRows && records.isEmpty)
          _surface(
            child: Column(
              children: [
                Icon(_icons[section], color: _accent, size: 39),
                const SizedBox(height: 12),
                const Text(
                  'No se encontraron registros',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Revisa la búsqueda o crea un nuevo registro.',
                  style: TextStyle(color: _soft),
                ),
              ],
            ),
          )
        else
          LayoutBuilder(
            builder: (context, limits) {
              final columns = limits.maxWidth >= 1150
                  ? 3
                  : limits.maxWidth >= 700
                  ? 2
                  : 1;
              final gap = 13.0;
              final width = (limits.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: 13,
                children: [
                  for (final record in records)
                    SizedBox(width: width, child: _recordCard(record)),
                ],
              );
            },
          ),
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Página anterior',
              onPressed: _page <= 1 ? null : () => _changePage(-1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              'Página $_page de $_lastPage',
              style: const TextStyle(color: _soft, fontSize: 12),
            ),
            IconButton(
              tooltip: 'Página siguiente',
              onPressed: _page >= _lastPage ? null : () => _changePage(1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }

  Widget _detail(String title, String value, {IconData? icon}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: _accent),
            const SizedBox(width: 9),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(color: _soft, fontSize: 10)),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> row) {
    final section = _section;
    final billing = _object(row['billing']);
    final title = switch (section) {
      1 || 2 || 3 => _txt(row['name']),
      4 => _txt(row['company_name']),
      5 => _txt(row['reference']),
      6 => 'Pago #${row['id']}',
      7 => _txt(row['title']),
      _ => _txt(row['action']),
    };
    final subtitle = switch (section) {
      1 => _txt(row['plan_name'], 'Sin plan asignado'),
      2 => 'Cliente comercial · #${row['id']}',
      3 => 'Plan comercial · #${row['id']}',
      4 =>
        '${_txt(row['plan_name'], 'Sin plan')} · Empresa #${row['company_id']}',
      5 => _txt(row['company_name'], 'Empresa #${row['company_id']}'),
      6 => _txt(row['company_name'], 'Factura #${row['master_invoice_id']}'),
      7 => _txt(row['company_name'], 'Todas las empresas'),
      _ => _txt(row['operator_name'], 'Operador maestro'),
    };
    final status = switch (section) {
      1 || 4 => _txt(billing['status'], 'pending'),
      2 || 3 =>
        row['is_active'] == true || row['is_active'] == 1
            ? 'active'
            : 'canceled',
      7 =>
        row['is_active'] == true || row['is_active'] == 1
            ? _txt(row['severity'], 'info')
            : 'canceled',
      8 => 'confirmed',
      _ => _txt(row['status'], 'pending'),
    };
    final details = <(String, String, IconData)>[];
    switch (section) {
      case 1:
        details.addAll([
          (
            'Cliente comercial',
            _txt(row['customer_name']),
            Icons.person_outline,
          ),
          (
            'Próximo pago',
            _txt(row['due_date'], 'Sin vencimiento'),
            Icons.event_outlined,
          ),
          (
            'Acceso de empleados',
            billing['allowed'] == true ? 'Habilitado' : 'Bloqueado',
            Icons.shield_outlined,
          ),
        ]);
      case 2:
        details.addAll([
          ('Correo', _txt(row['email']), Icons.email_outlined),
          ('Teléfono', _txt(row['phone']), Icons.call_outlined),
          ('RTN', _txt(row['tax_id']), Icons.badge_outlined),
        ]);
      case 3:
        details.addAll([
          ('Precio mensual', _money(row['monthly_price']), Icons.sell_outlined),
          ('Moneda', _txt(row['currency'], 'HNL'), Icons.currency_exchange),
          (
            'Módulos',
            'Configurar permisos desde Editar',
            Icons.widgets_outlined,
          ),
        ]);
      case 4:
        details.addAll([
          ('Cliente', _txt(row['customer_name']), Icons.person_outline),
          (
            'Vencimiento',
            _txt(row['due_date'], 'Sin fecha'),
            Icons.calendar_month_outlined,
          ),
          (
            'Período de gracia',
            '4 días después del vencimiento',
            Icons.hourglass_bottom,
          ),
        ]);
      case 5:
        details.addAll([
          ('Importe', _money(row['amount']), Icons.payments_outlined),
          (
            'Fecha límite',
            _txt(row['due_date']),
            Icons.calendar_month_outlined,
          ),
          (
            'Cobertura',
            _txt(row['coverage_until']),
            Icons.event_available_outlined,
          ),
        ]);
      case 6:
        details.addAll([
          ('Importe', _money(row['amount']), Icons.payments_outlined),
          ('Método', _txt(row['method']), Icons.account_balance_outlined),
          ('Referencia bancaria', _txt(row['reference']), Icons.tag_outlined),
        ]);
      case 7:
        details.addAll([
          ('Mensaje', _txt(row['body']), Icons.message_outlined),
          ('Publicado', _txt(row['created_at']), Icons.schedule_outlined),
        ]);
      case 8:
        details.addAll([
          (
            'Registro afectado',
            _txt(row['target']),
            Icons.bookmark_border_rounded,
          ),
          ('Fecha', _txt(row['created_at']), Icons.schedule_outlined),
        ]);
    }
    return _surface(
      padding: 17,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_icons[section], color: _accent, size: 21),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: _soft, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 5),
              _pill(status),
            ],
          ),
          const Divider(height: 29, color: _line),
          for (final item in details) _detail(item.$1, item.$2, icon: item.$3),
          if (section != 8) ...[
            const Divider(height: 22, color: _line),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                if ((section != 5 && section != 6) || status == 'pending')
                  OutlinedButton.icon(
                    onPressed: _processing ? null : () => _editRecord(row),
                    icon: const Icon(Icons.edit_outlined, size: 16),
                    label: const Text('Editar'),
                  ),
                if (section == 6 && status == 'pending')
                  FilledButton.icon(
                    onPressed: _processing ? null : () => _confirmPayment(row),
                    icon: const Icon(Icons.verified_rounded, size: 16),
                    label: const Text('Confirmar'),
                  ),
                if ((section != 6 && section != 5) || status == 'pending')
                  TextButton.icon(
                    onPressed: _processing ? null : () => _deleteRecord(row),
                    icon: const Icon(Icons.archive_outlined, size: 16),
                    label: Text(section == 4 ? 'Cancelar plan' : 'Archivar'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
