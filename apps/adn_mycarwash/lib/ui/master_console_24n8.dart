import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Administración comercial propia de ADN. No utiliza MyCarWashSession.
class MasterConsole24N8 extends StatefulWidget {
  const MasterConsole24N8({super.key});

  @override
  State<MasterConsole24N8> createState() => _MasterConsole24N8State();
}

class _MasterConsole24N8State extends State<MasterConsole24N8> {
  static const _api = String.fromEnvironment(
    'MYCARWASH_API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8000/api/v1',
  );
  static const _bg = Color(0xFF050C0F);
  static const _card = Color(0xFF09262C);
  static const _border = Color(0xFF24515A);
  static const _accent = Color(0xFF00DCE5);

  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _token;
  String? _error;
  bool _busy = false;
  int _section = 0;
  Map<String, dynamic> _data = {};
  final _sections = const [
    'Empresas',
    'Clientes',
    'Planes',
    'Facturas',
    'Pagos',
    'Notificaciones',
  ];
  final _icons = const [
    Icons.apartment,
    Icons.people_alt_outlined,
    Icons.layers_outlined,
    Icons.receipt_long_outlined,
    Icons.payments_outlined,
    Icons.notifications_outlined,
  ];
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _call(
    String method,
    String path, [
    Map<String, dynamic>? payload,
  ]) async {
    final response = http.Request(method, Uri.parse('$_api/master/$path'));
    response.headers.addAll({
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (_token != null) 'Authorization': 'Bearer $_token',
    });
    if (payload != null) {
      response.body = jsonEncode(payload);
    }
    final client = http.Client();
    late final http.Response result;
    try {
      final sent = await client
          .send(response)
          .timeout(const Duration(seconds: 25));
      result = await http.Response.fromStream(sent);
    } finally {
      client.close();
    }
    Map<String, dynamic> body = {};
    try {
      body = Map<String, dynamic>.from(jsonDecode(result.body) as Map);
    } catch (_) {}
    if (result.statusCode < 200 || result.statusCode >= 300) {
      final validation = body['errors'];
      final msg = validation is Map && validation.isNotEmpty
          ? (validation.values.first is List
                ? (validation.values.first as List).first.toString()
                : validation.values.first.toString())
          : (body['message']?.toString() ?? 'Error HTTP ${result.statusCode}');
      throw Exception(msg);
    }
    return body;
  }

  Future<void> _login() async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final body = await _call('POST', 'auth/token', {
        'email': _email.text.trim().toLowerCase(),
        'password': _password.text,
      });
      _token = body['access_token']?.toString();
      if (_token == null || _token!.isEmpty) {
        throw Exception('El servidor no creó la sesión maestra.');
      }
      _password.clear();
      await _refresh();
    } catch (e) {
      _token = null;
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _refresh() async {
    final data = await _call('GET', 'overview');
    if (mounted) {
      setState(() => _data = data);
    }
  }

  List<Map<String, dynamic>> _rows(String key) {
    final list = _data[key];
    return list is List
        ? list
              .whereType<Map>()
              .map((x) => Map<String, dynamic>.from(x))
              .toList()
        : [];
  }

  String _value(dynamic value) => value == null ? '—' : value.toString();
  String _money(dynamic value) =>
      value == null ? 'Sin precio' : 'L ${_value(value)}';
  void _message(String msg, {bool bad = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: bad ? const Color(0xFF84242D) : _card,
      ),
    );
  }

  Future<bool> _confirm(String question) async =>
      (await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Confirmar operación'),
          content: Text(question),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Confirmar'),
            ),
          ],
        ),
      )) ??
      false;

  Future<void> _perform(
    String method,
    String path,
    Map<String, dynamic>? payload, {
    String success = 'Cambios guardados',
  }) async {
    try {
      await _call(method, path, payload);
      await _refresh();
      _message(success);
    } catch (e) {
      _message(e.toString(), bad: true);
    }
  }

  Future<Map<String, dynamic>?> _form(
    String title,
    List<_MasterField> fields, {
    Map<String, dynamic>? initial,
    Map<String, bool>? toggles,
  }) async {
    final controls = <String, TextEditingController>{};
    for (final field in fields) {
      controls[field.key] = TextEditingController(
        text: initial?[field.key]?.toString() ?? '',
      );
    }
    final checks = <String, bool>{...?toggles};
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: _card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: Text(title, style: const TextStyle(color: Colors.white)),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final field in fields)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextField(
                        controller: controls[field.key],
                        obscureText: field.secret,
                        keyboardType: field.number
                            ? const TextInputType.numberWithOptions(
                                decimal: true,
                              )
                            : TextInputType.text,
                        maxLines: field.multiline ? 3 : 1,
                        decoration: InputDecoration(
                          labelText: field.label,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  for (final entry in checks.entries)
                    SwitchListTile(
                      title: Text(
                        entry.key,
                        style: const TextStyle(color: Colors.white),
                      ),
                      activeThumbColor: _accent,
                      value: entry.value,
                      onChanged: (v) => setLocal(() => checks[entry.key] = v),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final out = <String, dynamic>{};
                for (final field in fields) {
                  final raw = controls[field.key]!.text.trim();
                  out[field.key] = field.number
                      ? (raw.isEmpty ? null : num.tryParse(raw))
                      : (raw.isEmpty ? null : raw);
                }
                if (checks.isNotEmpty) {
                  out['features'] = {
                    'operations': checks['Operaciones'] ?? false,
                    'monitor': checks['Monitor de lavado'] ?? false,
                    'marketing_site': checks['Sitio comercial'] ?? false,
                    'editor': checks['Editor Pro'] ?? false,
                  };
                }
                Navigator.pop(ctx, out);
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    for (final controller in controls.values) {
      controller.dispose();
    }
    return result;
  }

  List<_MasterField> _fieldsFor(String section, {bool editing = false}) {
    switch (section) {
      case 'Empresas':
        return editing
            ? [
                const _MasterField('name', 'Nombre de empresa'),
                const _MasterField(
                  'customer_id',
                  'ID del cliente comercial',
                  number: true,
                ),
                const _MasterField('plan_id', 'ID del plan', number: true),
                const _MasterField(
                  'due_date',
                  'Próximo vencimiento (AAAA-MM-DD)',
                ),
                const _MasterField(
                  'status',
                  'Estado: active, pending, suspended o canceled',
                ),
              ]
            : [
                const _MasterField('name', 'Nombre de la empresa'),
                const _MasterField('owner_name', 'Propietario / administrador'),
                const _MasterField('owner_email', 'Correo de acceso'),
                const _MasterField(
                  'owner_password',
                  'Contraseña del propietario',
                  secret: true,
                ),
                const _MasterField(
                  'customer_id',
                  'ID del cliente comercial',
                  number: true,
                ),
                const _MasterField('plan_id', 'ID del plan', number: true),
                const _MasterField(
                  'due_date',
                  'Fecha de vencimiento (AAAA-MM-DD)',
                ),
              ];
      case 'Clientes':
        return [
          const _MasterField('name', 'Nombre / razón social'),
          const _MasterField('email', 'Correo de cobro'),
          const _MasterField('phone', 'Teléfono'),
          const _MasterField('tax_id', 'RTN (opcional)'),
          const _MasterField('notes', 'Notas', multiline: true),
        ];
      case 'Planes':
        return [
          const _MasterField('name', 'Nombre del plan'),
          const _MasterField(
            'monthly_price',
            'Precio mensual en lempiras (configúralo)',
            number: true,
          ),
        ];
      case 'Facturas':
        return editing
            ? [
                const _MasterField('amount', 'Importe', number: true),
                const _MasterField('due_date', 'Vencimiento (AAAA-MM-DD)'),
                const _MasterField(
                  'coverage_until',
                  'Cobertura hasta (AAAA-MM-DD)',
                ),
                const _MasterField('notes', 'Notas', multiline: true),
              ]
            : [
                const _MasterField('company_id', 'ID de empresa', number: true),
                const _MasterField('amount', 'Importe', number: true),
                const _MasterField('due_date', 'Vencimiento (AAAA-MM-DD)'),
                const _MasterField(
                  'coverage_until',
                  'Cobertura hasta (AAAA-MM-DD)',
                ),
                const _MasterField('notes', 'Notas', multiline: true),
              ];
      case 'Pagos':
        return editing
            ? [
                const _MasterField('amount', 'Importe recibido', number: true),
                const _MasterField('method', 'Método de pago'),
                const _MasterField('reference', 'Referencia bancaria'),
                const _MasterField('notes', 'Notas', multiline: true),
              ]
            : [
                const _MasterField('invoice_id', 'ID de factura', number: true),
                const _MasterField('amount', 'Importe recibido', number: true),
                const _MasterField(
                  'method',
                  'Método de pago (transferencia, efectivo...)',
                ),
                const _MasterField('reference', 'Referencia bancaria'),
                const _MasterField('notes', 'Notas', multiline: true),
              ];
      default:
        return [
          const _MasterField(
            'company_id',
            'ID empresa (vacío = todas)',
            number: true,
          ),
          const _MasterField('title', 'Título'),
          const _MasterField('body', 'Mensaje', multiline: true),
          const _MasterField('severity', 'Tipo: info, warning o critical'),
        ];
    }
  }

  Map<String, bool> _toggles(Map<String, dynamic>? item) {
    final raw = item?['features'];
    Map<String, dynamic> features = {};
    if (raw is Map) {
      features = Map<String, dynamic>.from(raw);
    }
    if (raw is String) {
      try {
        features = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {}
    }
    return {
      'Operaciones': features['operations'] == true,
      'Monitor de lavado': features['monitor'] == true,
      'Sitio comercial': features['marketing_site'] == true,
      'Editor Pro': features['editor'] == true,
    };
  }

  Future<void> _newRecord() async {
    final name = _sections[_section];
    final fields = _fieldsFor(name);
    final data = await _form(
      'Nuevo registro · $name',
      fields,
      toggles: name == 'Planes' ? _toggles(null) : null,
    );
    if (data == null) {
      return;
    }
    if (name == 'Empresas' && data['owner_password'] == null) {
      _message('Define contraseña de propietario.', bad: true);
      return;
    }
    await _perform('POST', _endpoint(name), data, success: 'Registro creado.');
  }

  String _endpoint(String section) => switch (section) {
    'Empresas' => 'companies',
    'Clientes' => 'customers',
    'Planes' => 'plans',
    'Facturas' => 'invoices',
    'Pagos' => 'payments',
    _ => 'notices',
  };
  Future<void> _editRecord(Map<String, dynamic> row) async {
    final name = _sections[_section];
    final initial = Map<String, dynamic>.from(row);
    if (name == 'Empresas') {
      initial['customer_id'] = row['master_customer_id'];
      initial['plan_id'] = row['master_plan_id'];
      initial['status'] = row['stored_status'];
    }
    if (name == 'Pagos') {
      initial['reference'] = row['reference'];
    }
    final fields = _fieldsFor(name, editing: true);
    final changes = await _form(
      'Editar $name · #${row['id']}',
      fields,
      initial: initial,
      toggles: name == 'Planes' ? _toggles(row) : null,
    );
    if (changes == null) {
      return;
    }
    changes.removeWhere(
      (k, v) =>
          v == null &&
          !(k == 'due_date' ||
              k == 'notes' ||
              k == 'customer_id' ||
              k == 'plan_id'),
    );
    await _perform('PATCH', '${_endpoint(name)}/${row['id']}', changes);
  }

  Future<void> _deleteRecord(Map<String, dynamic> row) async {
    final name = _sections[_section];
    if (!await _confirm(
      '¿Archivar/anular ${_value(row['name'] ?? row['title'] ?? row['reference'] ?? row['id'])}? Se conserva el historial.',
    )) {
      return;
    }
    await _perform(
      'DELETE',
      '${_endpoint(name)}/${row['id']}',
      null,
      success: 'Registro archivado o anulado.',
    );
  }

  Future<void> _confirmPayment(Map<String, dynamic> row) async {
    if (!await _confirm(
      '¿Has verificado realmente el abono de ${_money(row['amount'])}? Confirmar puede reactivar la empresa cuando la factura quede cubierta.',
    )) {
      return;
    }
    await _perform(
      'POST',
      'payments/${row['id']}/confirm',
      {},
      success: 'Pago confirmado y suscripción recalculada.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(child: _token == null ? _loginScreen() : _mainScreen()),
    );
  }

  Widget _loginScreen() => Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Container(
          margin: const EdgeInsets.all(22),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: _card,
            border: Border.all(color: _border),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.admin_panel_settings, size: 52, color: _accent),
              const SizedBox(height: 16),
              const Text(
                'ADN MyCarWash · Control maestro',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Acceso exclusivo de ADN Publicidad. Las cuentas de empresas no tienen acceso.',
                style: TextStyle(color: Color(0xFFA5BAC0)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 25),
              TextField(
                controller: _email,
                decoration: const InputDecoration(labelText: 'Correo maestro'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _password,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(
                  labelText: 'Contraseña maestra',
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                ),
              const SizedBox(height: 25),
              FilledButton.icon(
                onPressed: _busy ? null : _login,
                icon: const Icon(Icons.lock_open),
                label: Text(
                  _busy ? 'Validando...' : 'Acceder al panel maestro',
                ),
              ),
              const SizedBox(height: 10),
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text('Volver a MyCarWash'),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _mainScreen() => Column(
    children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: _card,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        child: Row(
          children: [
            const Icon(Icons.admin_panel_settings, color: _accent, size: 32),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ADN MyCarWash',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                    ),
                  ),
                  Text(
                    'ADMINISTRACIÓN MAESTRA · ADN PUBLICIDAD',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 10,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Actualizar',
              onPressed: () async {
                try {
                  await _refresh();
                } catch (e) {
                  _message('$e', bad: true);
                }
              },
              icon: const Icon(Icons.refresh, color: _accent),
            ),
            IconButton(
              tooltip: 'Cerrar sesión',
              onPressed: () async {
                try {
                  await _call('POST', 'auth/logout', {});
                } catch (_) {}
                if (mounted) {
                  setState(() {
                    _token = null;
                    _data = {};
                  });
                }
              },
              icon: const Icon(Icons.logout, color: Colors.white),
            ),
          ],
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: List.generate(
              _sections.length,
              (i) => Padding(
                padding: const EdgeInsets.only(right: 7),
                child: ChoiceChip(
                  selected: i == _section,
                  avatar: Icon(
                    _icons[i],
                    size: 17,
                    color: i == _section ? Colors.black : _accent,
                  ),
                  label: Text(_sections[i]),
                  onSelected: (_) => setState(() => _section = i),
                  selectedColor: _accent,
                  backgroundColor: _card,
                  labelStyle: TextStyle(
                    color: i == _section ? Colors.black : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 6, 18, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 12,
                children: [
                  Text(
                    _sections[_section],
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _newRecord,
                    icon: const Icon(Icons.add),
                    label: Text('Nuevo · ${_sections[_section]}'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final count = constraints.maxWidth > 1100
                      ? 3
                      : constraints.maxWidth > 650
                      ? 2
                      : 1;
                  final gap = 14.0;
                  final width =
                      (constraints.maxWidth - gap * (count - 1)) / count;
                  final rows = _rows(_endpoint(_sections[_section]));
                  if (rows.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Sin registros. Crea uno desde Nuevo.'),
                    );
                  }
                  return Wrap(
                    spacing: gap,
                    runSpacing: 14,
                    children: [
                      for (final row in rows)
                        SizedBox(width: width, child: _recordCard(row)),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _recordCard(Map<String, dynamic> row) {
    final section = _sections[_section];
    String title = '';
    String subtitle = '';
    List<String> details = [];
    switch (section) {
      case 'Empresas':
        title = _value(row['name']);
        subtitle =
            'Empresa #${_value(row['id'])} · ${_value(row['plan_name'] ?? 'Sin plan')}';
        final billing = row['billing'] is Map
            ? Map<String, dynamic>.from(row['billing'] as Map)
            : <String, dynamic>{};
        details = [
          'Estado: ${_value(billing['status'])}',
          'Próximo vencimiento: ${_value(row['due_date'])}',
          'Cliente: ${_value(row['customer_name'])}',
          'Acceso: ${billing['allowed'] == true ? 'Habilitado' : 'Bloqueado'}',
        ];
        break;
      case 'Clientes':
        title = _value(row['name']);
        subtitle = 'Cliente comercial #${row['id']}';
        details = [
          'Correo: ${_value(row['email'])}',
          'Teléfono: ${_value(row['phone'])}',
          'Estado: ${row['is_active'] == true || row['is_active'] == 1 ? 'Activo' : 'Archivado'}',
        ];
        break;
      case 'Planes':
        title = _value(row['name']);
        subtitle = 'Plan #${row['id']}';
        details = [
          'Precio mensual: ${_money(row['monthly_price'])}',
          'Estado: ${row['is_active'] == true || row['is_active'] == 1 ? 'Habilitado' : 'Deshabilitado'}',
        ];
        break;
      case 'Facturas':
        title = _value(row['reference']);
        subtitle = 'Empresa #${row['company_id']}';
        details = [
          'Monto: ${_money(row['amount'])}',
          'Vence: ${_value(row['due_date'])}',
          'Cobertura hasta: ${_value(row['coverage_until'])}',
          'Estado: ${_value(row['status'])}',
        ];
        break;
      case 'Pagos':
        title = 'Pago #${row['id']}';
        subtitle = 'Factura #${row['master_invoice_id']}';
        details = [
          'Monto: ${_money(row['amount'])}',
          'Método: ${_value(row['method'])}',
          'Referencia: ${_value(row['reference'])}',
          'Estado: ${_value(row['status'])}',
        ];
        break;
      default:
        title = _value(row['title']);
        subtitle = 'Notificación #${row['id']}';
        details = [
          'Empresa: ${_value(row['company_id'] ?? 'Todas')}',
          'Importancia: ${_value(row['severity'])}',
          'Mensaje: ${_value(row['body'])}',
        ];
        break;
    }
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(color: _accent, fontSize: 12)),
          const Divider(height: 22, color: _border),
          for (final line in details)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                line,
                style: const TextStyle(color: Color(0xFFC4D6DB), fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              OutlinedButton.icon(
                onPressed: () => _editRecord(row),
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Editar'),
              ),
              if (section == 'Pagos' && row['status'] == 'pending')
                FilledButton.icon(
                  onPressed: () => _confirmPayment(row),
                  icon: const Icon(Icons.verified_outlined, size: 17),
                  label: const Text('Confirmar pago'),
                ),
              OutlinedButton.icon(
                onPressed: () => _deleteRecord(row),
                icon: const Icon(Icons.archive_outlined, size: 17),
                label: const Text('Archivar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MasterField {
  const _MasterField(
    this.key,
    this.label, {
    this.number = false,
    this.secret = false,
    this.multiline = false,
  });
  final String key, label;
  final bool number, secret, multiline;
}
