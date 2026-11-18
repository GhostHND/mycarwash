import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// 24K: Caja y bancos. Solo APIs de la empresa autenticada, sin datos ficticios.
class CompanyFinanceHub24K extends StatefulWidget {
  const CompanyFinanceHub24K({
    super.key,
    required this.section,
    required this.onNavigate,
    this.client,
  });

  /// cash, banks, reconciliations
  final String section;
  final ValueChanged<String> onNavigate;
  final http.Client? client;

  @override
  State<CompanyFinanceHub24K> createState() => _CompanyFinanceHub24KState();
}

class _CompanyFinanceHub24KState extends State<CompanyFinanceHub24K> {
  static const Color bg = Color(0xFF080F12);
  static const Color surface = Color(0xFF0C1A1E);
  static const Color panel = Color(0xFF0E2227);
  static const Color border = Color(0xFF1D383F);
  static const Color accent = Color(0xFF0FA7B4);
  static const Color cyan = Color(0xFF00DCE5);
  static const Color green = Color(0xFF00D99A);
  static const Color red = Color(0xFFE84657);
  static const Color muted = Color(0xFF9DB0B6);

  late final http.Client _client;
  late final bool _owned;
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);

  String _period = 'day';
  DateTime _date = DateTime.now();
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _data;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _owned = widget.client == null;
    _client = widget.client ?? http.Client();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyFinanceHub24K oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    if (_owned) {
      _client.close();
    }
    super.dispose();
  }

  String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];

  String _money(dynamic v) =>
      v == null ? 'Sin saldo inicial' : 'L ${v.toString()}';

  String _periodLabel() => switch (_period) {
    'day' => 'Día',
    'week' => 'Semana',
    _ => 'Mes',
  };

  void _snack(String text, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? const Color(0xFF913340)
            : const Color(0xFF126E73),
      ),
    );
  }

  Future<void> _load() async {
    final serial = ++_epoch;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final reply = await _api.request(
        'GET',
        '/finance/overview',
        query: {'period': _period, 'date': _iso(_date)},
      );
      if (!mounted || serial != _epoch) {
        return;
      }
      final raw = reply['data'];
      setState(() {
        _data = raw is Map ? Map<String, dynamic>.from(raw) : {};
        _busy = false;
      });
    } catch (error) {
      if (!mounted || serial != _epoch) {
        return;
      }
      setState(() {
        _error = '$error';
        _busy = false;
      });
    }
  }

  Future<void> _execute(
    String method,
    String path,
    Map<String, dynamic> body,
    String message,
  ) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.request(method, path, body: body);
      if (!mounted) {
        return;
      }
      _snack(message);
      await _load();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _busy = false);
      _snack('$error', error: true);
    }
  }

  InputDecoration _input(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: muted),
    filled: true,
    fillColor: panel,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(11)),
  );

  /// Devuelve valores solo después de confirmar; descarta controladores tras la ruta.
  Future<Map<String, String>?> _fieldsDialog({
    required String title,
    required Map<String, String> fields,
    String submit = 'Confirmar',
  }) async {
    final inputs = <String, TextEditingController>{
      for (final entry in fields.entries)
        entry.key: TextEditingController(text: entry.value),
    };
    final route = DialogRoute<Map<String, String>>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => AlertDialog(
        backgroundColor: surface,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in inputs.entries) ...[
                  TextField(
                    controller: entry.value,
                    decoration: _input(entry.key),
                    maxLines: entry.key == 'Observaciones' ? 3 : 1,
                  ),
                  const SizedBox(height: 13),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent),
            onPressed: () => Navigator.pop(dialog, {
              for (final e in inputs.entries) e.key: e.value.text.trim(),
            }),
            child: Text(submit),
          ),
        ],
      ),
    );
    try {
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push(route);
      await route.completed;
      return result;
    } finally {
      for (final c in inputs.values) {
        c.dispose();
      }
    }
  }

  Future<void> _cashOpen(Map<String, dynamic> cash) async {
    final d = await _fieldsDialog(
      title: 'Abrir caja · ${cash['name']}',
      fields: {'Fondo inicial (L)': '0.00', 'Observaciones': ''},
      submit: 'Abrir caja',
    );
    if (d == null) {
      return;
    }
    await _execute('POST', '/cash/sessions', {
      'register_id': cash['id'],
      'opening_cash': d['Fondo inicial (L)'],
      'notes': d['Observaciones'],
    }, 'Caja abierta correctamente.');
  }

  Future<void> _cashClose(Map<String, dynamic> cash) async {
    final d = await _fieldsDialog(
      title: 'Cerrar caja · ${cash['name']}',
      fields: {'Efectivo contado (L)': '', 'Observaciones': ''},
      submit: 'Confirmar cierre',
    );
    if (d == null) {
      return;
    }
    await _execute('PATCH', '/cash/sessions/${cash['session_id']}', {
      'status': 'CLOSED',
      'counted_cash': d['Efectivo contado (L)'],
      'notes': d['Observaciones'],
    }, 'Cierre de caja registrado.');
  }

  Future<void> _initializeBank(Map<String, dynamic> bank) async {
    final d = await _fieldsDialog(
      title: 'Saldo inicial · ${bank['alias']}',
      fields: {
        'Saldo inicial (L)': '0.00',
        'Fecha inicial (AAAA-MM-DD)': _iso(_date),
      },
      submit: 'Registrar saldo inicial',
    );
    if (d == null) {
      return;
    }
    await _execute('POST', '/finance/banks/${bank['id']}/initialize', {
      'opening_balance': d['Saldo inicial (L)'],
      'effective_date': d['Fecha inicial (AAAA-MM-DD)'],
    }, 'Saldo inicial registrado. No se podrá sustituir después.');
  }

  Future<void> _bankMovement(
    Map<String, dynamic> bank,
    String direction,
  ) async {
    final d = await _fieldsDialog(
      title:
          '${direction == 'IN' ? 'Ingreso' : 'Egreso'} bancario · ${bank['alias']}',
      fields: {
        'Monto (L)': '',
        'Fecha (AAAA-MM-DD)': _iso(_date),
        'Referencia': '',
        'Observaciones': '',
      },
      submit: 'Registrar movimiento',
    );
    if (d == null) {
      return;
    }
    final key =
        '${bank['id']}-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(0x7fffffff)}';
    await _execute('POST', '/finance/banks/${bank['id']}/entries', {
      'direction': direction,
      'amount': d['Monto (L)'],
      'posted_date': d['Fecha (AAAA-MM-DD)'],
      'reference': d['Referencia'],
      'notes': d['Observaciones'],
      'idempotency_key': key,
    }, 'Movimiento bancario registrado.');
  }

  Future<void> _bankOpenClosing(Map<String, dynamic> bank) async {
    await _execute('POST', '/finance/banks/${bank['id']}/closings/open', {
      'period': _period,
      'date': _iso(_date),
    }, 'Cuadre de ${_periodLabel().toLowerCase()} abierto.');
  }

  Future<void> _bankCloseClosing(Map<String, dynamic> bank) async {
    final d = await _fieldsDialog(
      title: 'Cerrar cuadre · ${bank['alias']}',
      fields: {'Saldo confirmado por banco (L)': '', 'Observaciones': ''},
      submit: 'Registrar cuadre',
    );
    if (d == null) {
      return;
    }
    final closing = bank['closing'];
    if (closing is! Map) {
      _snack('Abre primero el cuadre bancario.', error: true);
      return;
    }
    await _execute(
      'POST',
      '/finance/banks/${bank['id']}/closings/${closing['id']}/close',
      {
        'counted_balance': d['Saldo confirmado por banco (L)'],
        'notes': d['Observaciones'],
      },
      'Cuadre bancario cerrado y auditado.',
    );
  }

  Future<void> _bankHistory(Map<String, dynamic> bank) async {
    try {
      final reply = await _api.request(
        'GET',
        '/finance/banks/${bank['id']}/entries',
      );
      if (!mounted) {
        return;
      }
      final events = _maps(reply['data']);
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          backgroundColor: surface,
          title: Text('Historial bancario · ${bank['alias']}'),
          content: SizedBox(
            width: 500,
            height: 340,
            child: events.isEmpty
                ? const Center(child: Text('Sin ajustes manuales registrados.'))
                : ListView.builder(
                    itemCount: events.length,
                    itemBuilder: (context, i) {
                      final r = events[i];
                      return ListTile(
                        dense: true,
                        title: Text(
                          '${r['direction'] == 'IN' ? '+' : '−'} ${_money(r['amount'])}',
                        ),
                        subtitle: Text('${r['posted_date']} · ${r['notes']}'),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      _snack('$error', error: true);
    }
  }

  Future<void> _newBank() async {
    try {
      final response = await _api.request('GET', '/sales/options');
      if (!mounted) {
        return;
      }
      final raw = response['data'];
      final branches = raw is Map
          ? _maps(raw['branches'])
          : <Map<String, dynamic>>[];
      if (branches.isEmpty) {
        _snack('No hay sucursales activas disponibles.', error: true);
        return;
      }
      final alias = TextEditingController();
      final bankName = TextEditingController();
      final last4 = TextEditingController();
      final notes = TextEditingController();
      var branch = int.tryParse('${branches.first['id']}') ?? 0;
      final route = DialogRoute<Map<String, dynamic>>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            backgroundColor: surface,
            title: const Text('Agregar cuenta bancaria'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: branch,
                      decoration: _input('Sucursal'),
                      isExpanded: true,
                      items: [
                        for (final option in branches)
                          DropdownMenuItem<int>(
                            value: int.tryParse('${option['id']}') ?? 0,
                            child: Text(
                              '${option['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          update(() => branch = value ?? branch),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: alias,
                      decoration: _input('Nombre de la cuenta'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: bankName,
                      decoration: _input('Banco'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: last4,
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      decoration: _input('Últimos 4 dígitos (opcional)'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      maxLines: 2,
                      decoration: _input('Observaciones (opcional)'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: accent),
                onPressed: () => Navigator.pop(dialog, <String, dynamic>{
                  'branch_id': branch,
                  'alias': alias.text.trim(),
                  'bank_name': bankName.text.trim(),
                  'account_last4': last4.text.trim().isEmpty
                      ? null
                      : last4.text.trim(),
                  'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                }),
                child: const Text('Crear cuenta'),
              ),
            ],
          ),
        ),
      );
      Map<String, dynamic>? data;
      try {
        data = await Navigator.of(context, rootNavigator: true).push(route);
        await route.completed;
      } finally {
        alias.dispose();
        bankName.dispose();
        last4.dispose();
        notes.dispose();
      }
      if (data == null || !mounted) {
        return;
      }
      await _execute('POST', '/sales/banks', data, 'Cuenta bancaria creada.');
    } catch (error) {
      _snack('$error', error: true);
    }
  }

  Future<void> _toggleBank(Map<String, dynamic> bank) async {
    final active = bank['is_active'] == true;
    await _execute(
      'PATCH',
      '/sales/banks/${bank['id']}',
      {'is_active': !active},
      active
          ? 'Cuenta desactivada sin perder su historial.'
          : 'Cuenta reactivada.',
    );
  }

  Future<void> _editBank(Map<String, dynamic> bank) async {
    final d = await _fieldsDialog(
      title: 'Editar cuenta · ${bank['alias']}',
      fields: {
        'Alias de la cuenta': '${bank['alias']}',
        'Banco': '${bank['bank_name']}',
        'Últimos 4 dígitos': '${bank['account_last4'] ?? ''}',
      },
      submit: 'Guardar cuenta',
    );
    if (d == null) {
      return;
    }
    await _execute('PATCH', '/sales/banks/${bank['id']}', {
      'alias': d['Alias de la cuenta'],
      'bank_name': d['Banco'],
      'account_last4': (d['Últimos 4 dígitos'] ?? '').isEmpty
          ? null
          : d['Últimos 4 dígitos'],
    }, 'Cuenta bancaria actualizada.');
  }

  Widget _container({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
    Color color = surface,
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }

  Widget _section(
    String eyebrow,
    String title,
    IconData icon, {
    Color tone = cyan,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 19, 0, 13),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              color: tone.withValues(alpha: .09),
            ),
            child: Icon(icon, color: tone, size: 19),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                eyebrow.toUpperCase(),
                style: TextStyle(
                  color: tone,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _metric(String title, String amount, IconData icon, Color tone) {
    return _container(
      color: tone.withValues(alpha: .045),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: tone),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 11, color: muted)),
          const SizedBox(height: 5),
          Text(
            amount,
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cards(List<Widget> content, {int maxColumns = 3}) => LayoutBuilder(
    builder: (context, c) {
      final cols = math.max(
        1,
        math.min(
          content.length,
          c.maxWidth < 600
              ? 1
              : c.maxWidth < 1000
              ? 2
              : maxColumns,
        ),
      );
      final width = math.max(0.0, (c.maxWidth - (cols - 1) * 12) / cols);
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final child in content) SizedBox(width: width, child: child),
        ],
      );
    },
  );

  Widget _line(String name, dynamic amount, {Color color = muted}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Text(name, style: const TextStyle(color: muted, fontSize: 12)),
        ),
        Flexible(
          child: Text(
            _money(amount),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _action(
    String label,
    IconData icon,
    VoidCallback? tap, {
    bool primary = false,
  }) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : tap,
      style: OutlinedButton.styleFrom(
        foregroundColor: primary ? bg : cyan,
        backgroundColor: primary ? cyan : null,
        side: const BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      ),
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 11)),
    );
  }

  Widget _bankCard(Map<String, dynamic> bank) {
    final closing = bank['closing'] is Map
        ? Map<String, dynamic>.from(bank['closing'] as Map)
        : null;
    final active = bank['is_active'] == true;
    final configured = bank['opening_set'] == true;
    return _container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.account_balance_rounded, color: cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${bank['bank_name']}',
                      maxLines: 2,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      '${bank['alias']} · ${bank['account_last4'] ?? 'Cuenta bancaria'}',
                      maxLines: 2,
                      style: const TextStyle(fontSize: 11, color: muted),
                    ),
                  ],
                ),
              ),
              if (widget.section == 'banks') ...[
                IconButton(
                  tooltip: 'Editar cuenta',
                  onPressed: _busy ? null : () => _editBank(bank),
                  icon: const Icon(Icons.edit_outlined, size: 18, color: cyan),
                ),
                IconButton(
                  tooltip: active ? 'Desactivar cuenta' : 'Activar cuenta',
                  onPressed: _busy ? null : () => _toggleBank(bank),
                  icon: Icon(
                    active
                        ? Icons.toggle_on_outlined
                        : Icons.toggle_off_outlined,
                    size: 22,
                    color: active ? green : muted,
                  ),
                ),
              ],
            ],
          ),
          const Divider(height: 24, color: border),
          _line('Cobros de ventas', bank['sales_in'], color: green),
          _line('Otros ingresos', bank['other_in'], color: green),
          _line('Egresos del período', bank['out'], color: red),
          _line('Movimiento neto', bank['net'], color: cyan),
          _line(
            'Traspasos internos recibidos',
            bank['transfer_in'],
            color: green,
          ),
          _line(
            'Traspasos internos enviados',
            bank['transfer_out'],
            color: red,
          ),
          const Divider(height: 22, color: border),
          const Text(
            'SALDO INTERNO CALCULADO',
            style: TextStyle(fontSize: 10, color: cyan, letterSpacing: 1),
          ),
          const SizedBox(height: 5),
          Text(
            _money(bank['estimated_balance']),
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
          if (!configured)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Registra un saldo inicial para calcular el saldo del banco.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ),
          if (closing != null) ...[
            const SizedBox(height: 12),
            Text(
              'Cuadre ${closing['status'] == 'CLOSED' ? 'cerrado' : 'abierto'} · ${_periodLabel().toLowerCase()}',
              style: TextStyle(
                color: closing['status'] == 'CLOSED' ? green : cyan,
                fontSize: 12,
              ),
            ),
            if (closing['status'] == 'CLOSED') ...[
              _line('Saldo informado', closing['counted']),
              _line('Diferencia de cierre', closing['difference'], color: red),
              if (closing['post_close_change'] == true)
                const Text(
                  'Aviso: existen movimientos posteriores al cierre. Revisa la conciliación.',
                  style: TextStyle(color: red, fontSize: 11),
                ),
            ],
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 0,
            children: [
              if (active && !configured)
                _action(
                  'Saldo inicial',
                  Icons.lock_open_outlined,
                  () => _initializeBank(bank),
                ),
              if (active && configured) ...[
                _action(
                  'Ingreso',
                  Icons.add_circle_outline,
                  () => _bankMovement(bank, 'IN'),
                ),
                _action(
                  'Egreso',
                  Icons.remove_circle_outline,
                  () => _bankMovement(bank, 'OUT'),
                ),
              ],
              if (active &&
                  configured &&
                  widget.section != 'reconciliations') ...[
                _action(
                  'Retirar a caja',
                  Icons.call_received_outlined,
                  () => _internalTransfer24K2(
                    'BANK_TO_CASH',
                    selectedBankId: int.tryParse('${bank['id']}'),
                  ),
                ),
                _action(
                  'Depositar desde caja',
                  Icons.call_made_outlined,
                  () => _internalTransfer24K2(
                    'CASH_TO_BANK',
                    selectedBankId: int.tryParse('${bank['id']}'),
                  ),
                ),
              ],
              _action(
                'Movimientos',
                Icons.history_rounded,
                () => _bankHistory(bank),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cashCard(Map<String, dynamic> cash) {
    final opened = cash['session_status'] == 'OPEN';
    final active = cash['is_active'] == true;
    return _container(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Caja física',
              style: TextStyle(
                color: cyan,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Row(
            children: [
              const Icon(Icons.point_of_sale_outlined, color: cyan),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${cash['name']}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                opened ? 'ABIERTA' : 'CERRADA',
                style: TextStyle(
                  color: opened ? green : muted,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const Divider(height: 24, color: border),
          _line('Ingresos del período', cash['in'], color: green),
          _line('Egresos del período', cash['out'], color: red),
          _line('Movimiento neto', cash['net'], color: cyan),
          _line(
            'Traspasos internos recibidos',
            cash['transfer_in'],
            color: green,
          ),
          _line(
            'Traspasos internos enviados',
            cash['transfer_out'],
            color: red,
          ),
          if (cash['session_id'] != null) ...[
            const Divider(height: 20, color: border),
            _line('Fondo inicial de sesión', cash['opening_cash']),
            _line(
              'Efectivo esperado de sesión',
              cash['expected_current'],
              color: cyan,
            ),
            if (cash['counted_cash'] != null)
              _line('Efectivo contado', cash['counted_cash']),
            if (cash['difference_cash'] != null)
              _line(
                'Diferencia de arqueo',
                cash['difference_cash'],
                color: red,
              ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 5,
            children: [
              if (active && !opened)
                _action(
                  'Abrir caja',
                  Icons.lock_open_outlined,
                  () => _cashOpen(cash),
                  primary: true,
                ),
              if (opened)
                _action(
                  'Cerrar caja',
                  Icons.lock_outline,
                  () => _cashClose(cash),
                  primary: true,
                ),
              _action(
                'Movimientos',
                Icons.history,
                () => widget.onNavigate('Movimientos de caja'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _internalTransfer24K2(
    String direction, {
    int? selectedBankId,
    int? selectedCashSessionId,
  }) async {
    if (_busy) {
      return;
    }
    final raw = _data ?? <String, dynamic>{};
    final banks = _maps(raw['banks'])
        .where((b) => b['is_active'] == true && b['opening_set'] == true)
        .toList();
    final cash = _maps(raw['cash'])
        .where(
          (c) =>
              c['is_active'] == true &&
              c['session_status'] == 'OPEN' &&
              c['session_id'] != null,
        )
        .toList();
    if (banks.isEmpty || cash.isEmpty) {
      _snack(
        'Se necesita una cuenta bancaria con saldo inicial y una sesión de caja abierta.',
        error: true,
      );
      return;
    }
    int bankId = selectedBankId ?? int.tryParse('${banks.first['id']}') ?? 0;
    int sessionId =
        selectedCashSessionId ??
        int.tryParse('${cash.first['session_id']}') ??
        0;
    final amount = TextEditingController();
    final reference = TextEditingController();
    final notes = TextEditingController();
    final isWithdrawal = direction == 'BANK_TO_CASH';
    final idempotency =
        'internal-transfer-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(0x7fffffff)}';
    Map<String, dynamic>? data;
    final route = DialogRoute<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          backgroundColor: surface,
          title: Text(
            isWithdrawal
                ? 'Retirar del banco hacia caja'
                : 'Depositar efectivo en banco',
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Traspaso interno: no es ingreso ni gasto del negocio.',
                    style: TextStyle(fontSize: 12, color: muted),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: bankId,
                    isExpanded: true,
                    decoration: _input('Cuenta bancaria'),
                    items: [
                      for (final b in banks)
                        DropdownMenuItem<int>(
                          value: int.tryParse('${b['id']}') ?? 0,
                          child: Text(
                            '${b['bank_name']} · ${b['alias']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        update(() => bankId = value ?? bankId),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: sessionId,
                    isExpanded: true,
                    decoration: _input('Caja abierta'),
                    items: [
                      for (final c in cash)
                        DropdownMenuItem<int>(
                          value: int.tryParse('${c['session_id']}') ?? 0,
                          child: Text(
                            '${c['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) =>
                        update(() => sessionId = value ?? sessionId),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _input('Importe a transferir (L)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reference,
                    decoration: _input('Referencia (opcional)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notes,
                    decoration: _input('Observaciones (opcional)'),
                    maxLines: 2,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () {
                final value = double.tryParse(amount.text.trim());
                if (value == null ||
                    value <= 0 ||
                    !RegExp(r'^\d+(?:\.\d{1,2})?$')
                        .hasMatch(amount.text.trim())) {
                  ScaffoldMessenger.of(dialog).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Introduce un importe válido mayor a cero.',
                      ),
                    ),
                  );
                  return;
                }
                Navigator.pop(dialog, {
                  'direction': direction,
                  'bank_account_id': bankId,
                  'cash_session_id': sessionId,
                  'amount': amount.text.trim(),
                  'reference': reference.text.trim().isEmpty
                      ? null
                      : reference.text.trim(),
                  'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
                  'idempotency_key': idempotency,
                });
              },
              child: const Text('Confirmar traspaso'),
            ),
          ],
        ),
      ),
    );
    try {
      data = await Navigator.of(context, rootNavigator: true).push(route);
      await route.completed;
    } finally {
      amount.dispose();
      reference.dispose();
      notes.dispose();
    }
    if (data == null || !mounted) {
      return;
    }
    await _execute(
      'POST',
      '/finance/transfers',
      data,
      'Traspaso registrado en ambas posiciones sin generar ingreso ni gasto.',
    );
  }

  Future<void> _transferHistory24K2() async {
    try {
      final r = await _api.request('GET', '/finance/transfers');
      if (!mounted) {
        return;
      }
      final rows = _maps(r['data']);
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          backgroundColor: surface,
          title: const Text('Historial de traspasos internos'),
          content: SizedBox(
            width: 570,
            height: 350,
            child: rows.isEmpty
                ? const Center(child: Text('No hay traspasos registrados.'))
                : ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) {
                      final item = rows[i];
                      final withdraw = item['direction'] == 'BANK_TO_CASH';
                      return ListTile(
                        dense: true,
                        leading: const Icon(Icons.swap_horiz, color: cyan),
                        title: Text(
                          '${withdraw ? 'Banco a caja' : 'Caja a banco'} · ${_money(item['amount'])}',
                        ),
                        subtitle: Text(
                          '${item['bank_alias']} · ${item['cash_name']} · ${item['transferred_at']}',
                        ),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      _snack('$error', error: true);
    }
  }

  Widget _reconciliationView24K2() {
    final d = _data ?? <String, dynamic>{};
    final closings = d['cash_closings'] is Map
        ? Map<String, dynamic>.from(d['cash_closings'] as Map)
        : <String, dynamic>{};
    final cash = _maps(d['cash']);
    final banks = _maps(d['banks']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _section(
          'Arqueo de efectivo',
          'Conteo contra caja',
          Icons.point_of_sale_outlined,
        ),
        _container(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cierres de caja del período: ${closings['count'] ?? 0}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              _line(
                'Diferencia acumulada de arqueos',
                closings['difference'] ?? '0.00',
                color: red,
              ),
              const Text(
                'El arqueo compara el efectivo contado físicamente con el esperado por la sesión. '
                'No crea movimientos ni altera ventas.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (cash.isEmpty)
          _container(child: const Text('Sin cajas registradoras.')),
        _cards([
          for (final c in cash)
            _container(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${c['name']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Sesión ${c['session_status'] ?? 'sin apertura'}',
                    style: const TextStyle(color: muted),
                  ),
                  _line(
                    'Efectivo esperado',
                    c['expected_current'],
                    color: cyan,
                  ),
                  if (c['counted_cash'] != null)
                    _line('Efectivo contado', c['counted_cash']),
                  if (c['difference_cash'] != null)
                    _line('Diferencia', c['difference_cash'], color: red),
                  const SizedBox(height: 8),
                  if (c['session_status'] == 'OPEN')
                    _action(
                      'Arqueo y cierre',
                      Icons.fact_check_outlined,
                      () => _cashClose(c),
                      primary: true,
                    ),
                ],
              ),
            ),
        ], maxColumns: 3),
        _section(
          'Conciliación bancaria',
          'Comparar con extracto bancario',
          Icons.account_balance_outlined,
        ),
        _container(
          child: const Text(
            'La conciliación compara el saldo interno con el extracto bancario. '
            'La diferencia no se registra como gasto ni como ingreso automáticamente.',
            style: TextStyle(color: muted, fontSize: 11),
          ),
        ),
        const SizedBox(height: 10),
        if (banks.isEmpty)
          _container(child: const Text('Sin cuentas bancarias.')),
        _cards([
          for (final bank in banks)
            _container(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${bank['bank_name']} · ${bank['alias']}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  _line(
                    'Saldo interno',
                    bank['estimated_balance'],
                    color: cyan,
                  ),
                  Text(
                    'Cuadre: ${bank['closing'] is Map ? bank['closing']['status'] : 'sin abrir'}',
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                  if (bank['closing'] is Map &&
                      bank['closing']['status'] == 'CLOSED') ...[
                    _line('Saldo informado', bank['closing']['counted']),
                    _line(
                      'Diferencia',
                      bank['closing']['difference'],
                      color: red,
                    ),
                  ],
                  const SizedBox(height: 8),
                  if (bank['is_active'] == true &&
                      bank['opening_set'] == true) ...[
                    if (bank['closing'] == null)
                      _action(
                        'Abrir conciliación',
                        Icons.lock_open_outlined,
                        () => _bankOpenClosing(bank),
                      ),
                    if (bank['closing'] is Map &&
                        bank['closing']['status'] == 'OPEN')
                      _action(
                        'Cerrar conciliación',
                        Icons.fact_check_outlined,
                        () => _bankCloseClosing(bank),
                        primary: true,
                      ),
                  ],
                ],
              ),
            ),
        ], maxColumns: 3),
      ],
    );
  }

  Widget _mainView() {
    if (widget.section == 'reconciliations') {
      return _reconciliationView24K2();
    }
    final d = _data ?? <String, dynamic>{};
    final totals = d['totals'] is Map
        ? Map<String, dynamic>.from(d['totals'] as Map)
        : <String, dynamic>{};
    final cash = _maps(d['cash']);
    final banks = _maps(d['banks']);
    if (widget.section == 'banks') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cards([
            _metric(
              'Cobros y otros ingresos bancarios',
              _money(totals['bank_in']),
              Icons.arrow_circle_up_outlined,
              green,
            ),
            _metric(
              'Egresos bancarios',
              _money(totals['bank_out']),
              Icons.arrow_circle_down_outlined,
              red,
            ),
          ], maxColumns: 2),
          _section(
            'Bancos',
            'Cuentas bancarias',
            Icons.account_balance_outlined,
          ),
          _action(
            'Agregar cuenta bancaria',
            Icons.add,
            _newBank,
            primary: true,
          ),
          const SizedBox(height: 10),
          if (banks.isEmpty)
            _container(
              child: const Text('No hay cuentas bancarias registradas.'),
            ),
          _cards([for (final b in banks) _bankCard(b)]),
          const SizedBox(height: 12),
          _action(
            'Historial de traspasos',
            Icons.swap_horiz_outlined,
            _transferHistory24K2,
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cards([
          _metric(
            'Ingresos en efectivo',
            _money(totals['cash_in']),
            Icons.arrow_circle_up_outlined,
            green,
          ),
          _metric(
            'Egresos en efectivo',
            _money(totals['cash_out']),
            Icons.arrow_circle_down_outlined,
            red,
          ),
          _metric(
            'Ingresos bancarios',
            _money(totals['bank_in']),
            Icons.account_balance_rounded,
            cyan,
          ),
          _metric(
            'Egresos bancarios',
            _money(totals['bank_out']),
            Icons.credit_card_outlined,
            red,
          ),
        ], maxColumns: 4),
        _section(
          'Control de tesorería',
          'Caja física y cuentas bancarias',
          Icons.account_balance_wallet_outlined,
        ),
        if (cash.isEmpty && banks.isEmpty)
          _container(child: const Text('No hay cajas ni cuentas bancarias.')),
        _cards([
          for (final c in cash) _cashCard(c),
          for (final b in banks) _bankCard(b),
        ], maxColumns: 3),
        const SizedBox(height: 12),
        _container(
          color: panel,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Traspasos internos',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'Retirar del banco hacia efectivo o depositar efectivo en el banco. '
                'No se consideran ventas, ingresos operativos ni gastos.',
                style: TextStyle(color: muted, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _action(
                    'Retirar banco → caja',
                    Icons.call_received_outlined,
                    () => _internalTransfer24K2('BANK_TO_CASH'),
                    primary: true,
                  ),
                  _action(
                    'Depositar caja → banco',
                    Icons.call_made_outlined,
                    () => _internalTransfer24K2('CASH_TO_BANK'),
                  ),
                  _action(
                    'Historial de traspasos',
                    Icons.history,
                    _transferHistory24K2,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _action(
              'Administrar cajas',
              Icons.settings_outlined,
              () => widget.onNavigate('Cajas registradoras'),
            ),
            _action(
              'Sesiones y cierres',
              Icons.calendar_month_outlined,
              () => widget.onNavigate('Sesiones de caja'),
            ),
            _action(
              'Categorías de egresos',
              Icons.category_outlined,
              () => widget.onNavigate('Categorías de egresos'),
            ),
            _action(
              'Arqueos y conciliaciones',
              Icons.fact_check_outlined,
              () => widget.onNavigate('Cuadres y arqueos'),
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        _container(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 15,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'CONTROL FINANCIERO',
                    style: TextStyle(
                      color: cyan,
                      fontSize: 10,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.section == 'banks'
                        ? 'Cuentas bancarias'
                        : widget.section == 'reconciliations'
                        ? 'Cuadres y conciliaciones'
                        : 'Caja y cuentas',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Text(
                    'Movimientos reales, aperturas, cierres y conciliaciones.',
                    style: TextStyle(color: muted, fontSize: 12),
                  ),
                ],
              ),
              _action('Actualizar', Icons.refresh, _load),
            ],
          ),
        ),
        const SizedBox(height: 14),
        _container(
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final p in ['day', 'week', 'month'])
                ChoiceChip(
                  label: Text(
                    p == 'day'
                        ? 'Día'
                        : p == 'week'
                        ? 'Semana'
                        : 'Mes',
                  ),
                  selected: _period == p,
                  onSelected: (_) {
                    setState(() => _period = p);
                    _load();
                  },
                ),
              _action(
                'Fecha: ${_iso(_date)}',
                Icons.calendar_month_outlined,
                () async {
                  final selected = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2100),
                  );
                  if (selected == null || !mounted) {
                    return;
                  }
                  setState(() => _date = selected);
                  await _load();
                },
              ),
              Text(
                '${_data?['from'] ?? '—'} al ${_data?['through'] ?? '—'}',
                style: const TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (_busy && _data == null)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Center(child: CircularProgressIndicator(color: cyan)),
          )
        else if (_error != null)
          _container(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No se pudieron cargar los datos: $_error',
                  style: const TextStyle(color: red),
                ),
                TextButton(onPressed: _load, child: const Text('Reintentar')),
              ],
            ),
          )
        else ...[
          if (_busy) const LinearProgressIndicator(color: cyan),
          const SizedBox(height: 14),
          _mainView(),
        ],
      ],
    ),
  );
}
