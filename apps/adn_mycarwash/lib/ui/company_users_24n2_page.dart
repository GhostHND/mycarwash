import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_visual_theme.dart';
import '../core/mycarwash_session.dart';

/// Accesos de empleados. La API Laravel valida permisos y pertenencia empresarial.
class CompanyUsers24N2Page extends StatefulWidget {
  const CompanyUsers24N2Page({super.key, this.client});
  final http.Client? client;

  @override
  State<CompanyUsers24N2Page> createState() => _CompanyUsers24N2PageState();
}

class _CompanyUsers24N2PageState extends State<CompanyUsers24N2Page> {
  late final http.Client _client;
  late final bool _ownsClient;
  bool _loading = true;
  bool _busy = false;
  bool _showRoles = false;
  String? _error;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _roles = [];
  List<Map<String, dynamic>> _employees = [];
  List<Map<String, dynamic>> _permissions = [];
  bool _manageUsers = false;
  bool _manageRoles = false;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _load();
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> _request(String method, String path, [Map<String, dynamic>? payload]) async {
    final url = Uri.parse('${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}$path');
    final headers = MyCarWashSession.headers;
    late http.Response response;
    if (method == 'GET') {
      response = await _client.get(url, headers: headers);
    } else if (method == 'POST') {
      response = await _client.post(url, headers: headers, body: jsonEncode(payload));
    } else if (method == 'PATCH') {
      response = await _client.patch(url, headers: headers, body: jsonEncode(payload));
    } else {
      response = await _client.delete(url, headers: headers);
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Respuesta inesperada del servidor.');
    if (response.statusCode >= 400) {
      var message = (decoded['message'] ?? 'Error ${response.statusCode}').toString();
      final errors = decoded['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) message = first.first.toString();
      }
      throw Exception(message);
    }
    return decoded;
  }

  List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await _request('GET', '/users');
      if (!mounted) return;
      setState(() {
        _users = _list(response['users']);
        _roles = _list(response['roles']);
        _employees = _list(response['available_employees']);
        _permissions = _list(response['permissions']);
        _manageUsers = response['can_manage_users'] == true;
        _manageRoles = response['can_manage_roles'] == true;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  Future<void> _perform(String method, String path, [Map<String, dynamic>? body]) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final response = await _request(method, path, body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${response['message'] ?? 'Guardado'}')));
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$error'), backgroundColor: CompanyVisualTheme.danger,
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label, filled: true, fillColor: CompanyVisualTheme.field,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: CompanyVisualTheme.card,
      border: Border.all(color: CompanyVisualTheme.border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );

  int? _toInt(dynamic value) => int.tryParse('$value');
  List<int> _assigned(Map<String, dynamic> user) {
    final roles = user['role_ids'];
    return roles is List ? roles.map(_toInt).whereType<int>().toList() : [];
  }

  String _roleName(Map<String, dynamic> user) {
    final ids = _assigned(user);
    return _roles.where((r) => ids.contains(_toInt(r['id'])))
        .map((r) => '${r['name']}').join(', ');
  }

  bool _isProtected(Map<String, dynamic> user) => _roles.any((role) =>
      role['is_system'] == true || role['is_system'] == 1
          ? _assigned(user).contains(_toInt(role['id'])) : false);

  Future<void> _userEditor([Map<String, dynamic>? user]) async {
    final editing = user != null;
    if (!editing && _employees.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Primero registra un empleado activo sin cuenta.')));
      return;
    }
    final form = GlobalKey<FormState>();
    int? employeeId = !editing ? _toInt(_employees.first['id']) : null;
    final editableRoles = _roles.where((r) => r['is_system'] != true && r['is_system'] != 1).toList();
    if (editableRoles.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Primero crea un rol de acceso limitado.')));
      return;
    }
    int? roleId = editing && _assigned(user).isNotEmpty ? _assigned(user).first : _toInt(editableRoles.first['id']);
    final email = TextEditingController(text: editing ? '${user['email']}' : '');
    final password = TextEditingController();
    var active = !editing || user['status'] == 'active';
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(editing ? 'Editar acceso de empleado' : 'Nueva cuenta de empleado'),
        content: SizedBox(width: 480, child: SingleChildScrollView(child: Form(
          key: form,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (!editing) ...[
              DropdownButtonFormField<int>(
                initialValue: employeeId,
                decoration: _decoration('Empleado'),
                items: _employees.map((e) => DropdownMenuItem<int>(
                  value: _toInt(e['id']), child: Text('${e['full_name']}'),
                )).toList(),
                onChanged: (v) => employeeId = v,
              ),
              const SizedBox(height: 14),
              TextFormField(controller: email, decoration: _decoration('Correo de acceso'),
                validator: (v) => v == null || !v.contains('@') ? 'Correo no válido' : null),
              const SizedBox(height: 14),
            ],
            DropdownButtonFormField<int>(
              initialValue: editableRoles.any((r) => _toInt(r['id']) == roleId) ? roleId : _toInt(editableRoles.first['id']),
              decoration: _decoration('Rol y permisos'),
              items: editableRoles.map((r) => DropdownMenuItem<int>(
                value: _toInt(r['id']), child: Text('${r['name']}'),
              )).toList(),
              onChanged: (v) => roleId = v,
            ),
            const SizedBox(height: 14),
            TextFormField(controller: password, obscureText: true,
              decoration: _decoration(editing ? 'Nueva contraseña (opcional)' : 'Contraseña inicial'),
              validator: (v) => (!editing || (v?.isNotEmpty ?? false)) && (v?.length ?? 0) < 10
                  ? 'Mínimo 10 caracteres' : null),
            if (editing) SwitchListTile(
              title: const Text('Cuenta activa'), value: active,
              onChanged: (v) => update(() => active = v),
            ),
          ]),
        ))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: _busy ? null : () {
            if (form.currentState!.validate() && roleId != null && (editing || employeeId != null)) {
              Navigator.pop(dialogContext, true);
            }
          }, child: const Text('Guardar cuenta')),
        ],
      )),
    );
    if (ok == true) {
      final payload = <String, dynamic>{'role_id': roleId};
      if (!editing) {
        payload.addAll({'employee_id': employeeId, 'email': email.text.trim(), 'password': password.text});
      } else {
        payload['status'] = active ? 'active' : 'inactive';
        if (password.text.isNotEmpty) payload['password'] = password.text;
      }
      await _perform(editing ? 'PATCH' : 'POST', editing ? '/users/${user['id']}' : '/users', payload);
    }
    email.dispose();
    password.dispose();
  }

  Future<void> _roleEditor([Map<String, dynamic>? role]) async {
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: role?['name']?.toString() ?? '');
    final chosen = <String>{};
    final existing = role?['permissions'];
    if (existing is List) chosen.addAll(existing.map((e) => '$e'));
    final options = _permissions.map((e) => '${e['code']}').toList();
    const labels = <String, String>{
      'dashboard': 'Panel general', 'washes': 'Lavados y órdenes',
      'schedule': 'Agenda y reservas', 'customers': 'Clientes y vehículos',
      'staff': 'Personal y turnos', 'inventory': 'Inventario y compras',
      'cash': 'Caja y bancos', 'sales': 'Ventas y cobros',
      'reports': 'Reportes', 'company': 'Mi empresa y configuración',
      'users': 'Usuarios',
    };
    const actionLabels = <String, String>{
      'view': 'Ver', 'create': 'Crear', 'edit': 'Editar / eliminar', 'execute': 'Ejecutar',
    };
    final ok = await showDialog<bool>(context: context,
      builder: (dialogContext) => StatefulBuilder(builder: (context, update) => AlertDialog(
        title: Text(role == null ? 'Crear rol de acceso' : 'Editar rol y permisos'),
        content: SizedBox(width: 610, height: 535, child: Form(
          key: form,
          child: Column(children: [
            TextFormField(controller: name, decoration: _decoration('Nombre del rol'),
              validator: (v) => v == null || v.trim().length < 3 ? 'Indica un nombre' : null),
            const SizedBox(height: 12),
            const Text('Elige exactamente lo que podrán consultar y realizar los empleados.'),
            const SizedBox(height: 10),
            Expanded(child: ListView(children: [
              for (final group in labels.entries) _panel(Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 10, runSpacing: 5, children: [
                    for (final action in actionLabels.entries)
                      if (options.contains('nav.${group.key}.${action.key}'))
                        FilterChip(
                          label: Text(action.value),
                          selected: chosen.contains('nav.${group.key}.${action.key}'),
                          onSelected: (yes) => update(() {
                            final code = 'nav.${group.key}.${action.key}';
                            if (yes) { chosen.add(code); } else { chosen.remove(code); }
                          }),
                        ),
                  ]),
                ],
              )),
            ])),
          ]),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () {
            if (form.currentState!.validate() && chosen.isNotEmpty) Navigator.pop(dialogContext, true);
          }, child: const Text('Guardar rol')),
        ],
      )),
    );
    if (ok == true) {
      await _perform(role == null ? 'POST' : 'PATCH',
        role == null ? '/roles' : '/roles/${role['id']}',
        {'name': name.text.trim(), 'permissions': chosen.toList()});
    }
    name.dispose();
  }

  Widget _userCard(Map<String, dynamic> user) => _panel(Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(children: [
        CircleAvatar(backgroundColor: CompanyVisualTheme.selected,
          child: Icon(Icons.person_outline_rounded, color: CompanyVisualTheme.icon)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${user['name']}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
            color: CompanyVisualTheme.heading)),
          Text('${user['email']}', overflow: TextOverflow.ellipsis,
            style: TextStyle(color: CompanyVisualTheme.muted, fontSize: 12)),
        ])),
        Icon(user['status'] == 'active' ? Icons.check_circle : Icons.block,
          color: user['status'] == 'active' ? CompanyVisualTheme.success : CompanyVisualTheme.danger),
      ]),
      const SizedBox(height: 14),
      Text('Empleado: ${user['employee_name'] ?? 'Sin vinculación (cuenta existente)'}'),
      const SizedBox(height: 6),
      Text('Rol: ${_roleName(user)}', style: TextStyle(color: CompanyVisualTheme.muted)),
      const SizedBox(height: 12),
      if (_manageUsers && !_isProtected(user)) Align(alignment: Alignment.centerRight,
        child: OutlinedButton.icon(onPressed: _busy ? null : () => _userEditor(user),
          icon: const Icon(Icons.manage_accounts_outlined), label: const Text('Administrar acceso'))),
      if (_isProtected(user)) Text('Cuenta protegida del sistema',
        style: TextStyle(color: CompanyVisualTheme.muted, fontSize: 12)),
    ],
  ));

  @override
  Widget build(BuildContext context) {
    final theme = CompanyVisualTheme.current.value;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: double.infinity, padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [theme.selected, theme.surface]),
          border: Border.all(color: theme.border), borderRadius: BorderRadius.circular(20),
        ),
        child: Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16, runSpacing: 12, children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ADMINISTRACIÓN DE ACCESOS', style: TextStyle(color: theme.primary, fontWeight: FontWeight.w800, fontSize: 11)),
              const SizedBox(height: 9),
              Text('Usuarios', style: TextStyle(color: theme.heading, fontSize: 29, fontWeight: FontWeight.w800)),
              const SizedBox(height: 5),
              Text('Cuentas de empleados, roles y permisos efectivos.', style: TextStyle(color: theme.muted)),
            ]),
            if (!_loading && _manageUsers && !_showRoles)
              FilledButton.icon(onPressed: _busy ? null : () => _userEditor(),
                icon: const Icon(Icons.person_add_alt_1_outlined), label: const Text('Nuevo usuario')),
            if (!_loading && _manageRoles && _showRoles)
              FilledButton.icon(onPressed: _busy ? null : () => _roleEditor(),
                icon: const Icon(Icons.add_moderator_outlined), label: const Text('Nuevo rol')),
          ])),
      const SizedBox(height: 17),
      Wrap(spacing: 10, children: [
        ChoiceChip(label: const Text('Cuentas de empleados'), selected: !_showRoles,
          onSelected: (_) => setState(() => _showRoles = false)),
        ChoiceChip(label: const Text('Roles y permisos'), selected: _showRoles,
          onSelected: (_) => setState(() => _showRoles = true)),
      ]),
      const SizedBox(height: 17),
      if (_loading) const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
      else if (_error != null) _panel(Column(children: [
        Text(_error!), const SizedBox(height: 12),
        OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
      ]))
      else if (!_showRoles) ...[
        Text('${_users.length} cuentas registradas', style: TextStyle(color: theme.muted)),
        const SizedBox(height: 13),
        if (_users.isEmpty) _panel(const Text('Todavía no hay cuentas vinculadas.')),
        LayoutBuilder(builder: (context, constraints) {
          final cols = constraints.maxWidth >= 900 ? 3 : constraints.maxWidth >= 560 ? 2 : 1;
          final width = (constraints.maxWidth - (cols - 1) * 14) / cols;
          return Wrap(spacing: 14, runSpacing: 14, children: [
            for (final user in _users) SizedBox(width: width, child: _userCard(user)),
          ]);
        }),
      ] else ...[
        for (final role in _roles) Padding(padding: const EdgeInsets.only(bottom: 12),
          child: _panel(Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 15, runSpacing: 12, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${role['name']}', style: TextStyle(color: theme.heading, fontWeight: FontWeight.w800, fontSize: 17)),
                Text((role['is_system'] == true || role['is_system'] == 1) ? 'Rol protegido' : 'Rol personalizado',
                    style: TextStyle(color: theme.muted)),
                Text('${(role['permissions'] is List ? (role['permissions'] as List).length : 0)} permisos granulares',
                    style: TextStyle(color: theme.muted, fontSize: 12)),
              ]),
              if (_manageRoles && role['is_system'] != true && role['is_system'] != 1)
                OutlinedButton.icon(onPressed: _busy ? null : () => _roleEditor(role),
                  icon: const Icon(Icons.tune), label: const Text('Editar permisos')),
            ]))),
      ],
    ]);
  }
}
