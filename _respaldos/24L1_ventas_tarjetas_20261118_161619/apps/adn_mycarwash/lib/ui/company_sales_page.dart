import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

enum SalesModule { banks, methods, discounts, payments }

class _SaleField {
  const _SaleField(
    this.key,
    this.label, {
    this.mandatory = false,
    this.option,
    this.number = false,
    this.notes = false,
  });
  final String key;
  final String label;
  final bool mandatory;
  final String? option;
  final bool number;
  final bool notes;
}

class CompanySalesPage extends StatefulWidget {
  const CompanySalesPage({super.key, required this.module, this.client});
  final SalesModule module;
  final http.Client? client;

  @override
  State<CompanySalesPage> createState() => _CompanySalesPageState();
}

class _CompanySalesPageState extends State<CompanySalesPage> {
  static const accent = Color(0xFF0FA7B4);
  static const surface = Color(0xFF0A1519);
  static const muted = Color(0xFF9BAEB6);
  static const border = Color(0xFF20343C);

  late final http.Client _client;
  late final bool _owned;
  final _search = TextEditingController();
  Timer? _debounce;
  int _page = 1;
  int _pages = 1;
  int _epoch = 0;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  String get _resource => widget.module.name;
  String get _path => '/sales/$_resource';
  String get _title => switch (widget.module) {
    SalesModule.banks => 'Cuentas bancarias',
    SalesModule.methods => 'Medios de pago',
    SalesModule.discounts => 'Descuentos de lavados',
    SalesModule.payments => 'Cobros de lavados',
  };
  String get _help => switch (widget.module) {
    SalesModule.banks => 'Cuentas de recepción por sucursal; no forman parte del efectivo de caja.',
    SalesModule.methods =>
      'Define efectivo o banco como canal para registrar cobros.',
    SalesModule.discounts =>
      'Descuento en lempiras autorizado para una orden terminada.',
    SalesModule.payments => 'Cobros pendientes editables; tras entregar quedan confirmados e inmutables.',
  };
  List<_SaleField> get _fields => switch (widget.module) {
    SalesModule.banks => const [
      _SaleField('branch_id', 'Sucursal', mandatory: true, option: 'branches'),
      _SaleField('alias', 'Nombre de la cuenta', mandatory: true),
      _SaleField('bank_name', 'Nombre del banco', mandatory: true),
      _SaleField('account_last4', 'Últimos 4 dígitos (opcional)'),
      _SaleField('notes', 'Notas', notes: true),
    ],
    SalesModule.methods => const [
      _SaleField('name', 'Nombre del medio', mandatory: true),
      _SaleField(
        'channel',
        'Canal de cobro',
        mandatory: true,
        option: 'channel',
      ),
      _SaleField('notes', 'Notas', notes: true),
    ],
    SalesModule.discounts => const [
      _SaleField(
        'order_id',
        'Orden terminada',
        mandatory: true,
        option: 'orders',
      ),
      _SaleField('amount', 'Descuento en L', mandatory: true, number: true),
      _SaleField('reason', 'Motivo del descuento', mandatory: true),
    ],
    SalesModule.payments => const [
      _SaleField(
        'order_id',
        'Orden terminada',
        mandatory: true,
        option: 'orders',
      ),
      _SaleField(
        'payment_method_id',
        'Medio de pago',
        mandatory: true,
        option: 'methods',
      ),
      _SaleField(
        'cash_session_id',
        'Sesión de caja (solo efectivo)',
        option: 'sessions',
      ),
      _SaleField(
        'bank_account_id',
        'Cuenta bancaria (solo banco)',
        option: 'banks',
      ),
      _SaleField(
        'amount',
        'Importe del cobro en L',
        mandatory: true,
        number: true,
      ),
      _SaleField('reference', 'Referencia / transferencia'),
      _SaleField('notes', 'Notas', notes: true),
    ],
  };

  @override
  void initState() {
    super.initState();
    _owned = widget.client == null;
    _client = widget.client ?? http.Client();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanySalesPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      _search.clear();
      _page = 1;
      _load();
    }
  }

  @override
  void dispose() {
    _epoch++;
    _debounce?.cancel();
    _search.dispose();
    if (_owned) {
      _client.close();
    }
    super.dispose();
  }

  InputDecoration _decor(String label) => InputDecoration(
    labelText: label,
    filled: true,
    fillColor: const Color(0xFF112127),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  void _notice(String text, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error
            ? const Color(0xFF993F49)
            : const Color(0xFF126F75),
      ),
    );
  }

  Future<void> _load() async {
    final epoch = ++_epoch;
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
      if (!mounted || epoch != _epoch) {
        return;
      }
      final records = result['data'];
      setState(() {
        _rows = records is List
            ? records
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : [];
        _page = int.tryParse('${result['current_page'] ?? 1}') ?? 1;
        _pages = int.tryParse('${result['last_page'] ?? 1}') ?? 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || epoch != _epoch) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  void _searchChanged(String _) {
    _debounce?.cancel();
    _page = 1;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _load();
      }
    });
  }

  String _optionTitle(String kind, Map record) => switch (kind) {
    'branches' => '${record['name']}',
    'orders' => '${record['tracking_code']} · L ${record['quoted_price']}',
    'banks' => '${record['alias']} · ${record['bank_name']}',
    'methods' => '${record['name']} (${record['channel']})',
    'sessions' => 'Caja ${record['name']} · Sesión ${record['id']}',
    _ => '${record['id']}',
  };

  Future<void> _edit([Map<String, dynamic>? original]) async {
    if (original != null &&
        widget.module == SalesModule.payments &&
        original['status'] == 'POSTED') {
      _notice('Un cobro confirmado no puede modificarse.', error: true);
      return;
    }
    final key = GlobalKey<FormState>();
    final fields = _fields;
    final controllers = {
      for (final field in fields)
        if (field.option == null)
          field.key: TextEditingController(
            text: '${original?[field.key] ?? ''}',
          ),
    };
    final choices = <String, int?>{
      for (final field in fields)
        if (field.option != null && field.option != 'channel')
          field.key: int.tryParse('${original?[field.key] ?? ''}'),
    };
    String? channel = original?['channel']?.toString();
    bool saving = false;
    bool active =
        original?['is_active'] != false && original?['is_active'] != 0;
    String? problem;
    final options = _api.request('GET', '/sales/options');
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            backgroundColor: surface,
            title: Text(
              original == null ? 'Nuevo · $_title' : 'Modificar · $_title',
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Form(
                  key: key,
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: options,
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        if (snapshot.hasError) {
                          return Text(
                            '${snapshot.error}',
                            style: const TextStyle(color: Colors.redAccent),
                          );
                        }
                        return const CircularProgressIndicator();
                      }
                      final source = snapshot.data!['data'] as Map? ?? {};
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final f in fields) ...[
                            if (f.option == 'channel')
                              DropdownButtonFormField<String>(
                                initialValue: channel,
                                isExpanded: true,
                                dropdownColor: surface,
                                decoration: _decor(f.label),
                                items: const [
                                  DropdownMenuItem(
                                    value: 'CASH',
                                    child: Text('Efectivo'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'BANK',
                                    child: Text('Banco / transferencia'),
                                  ),
                                ],
                                onChanged: saving
                                    ? null
                                    : (v) => update(() => channel = v),
                                validator: (v) => f.mandatory && v == null
                                    ? 'Selecciona una opción.'
                                    : null,
                              )
                            else if (f.option != null)
                              Builder(
                                builder: (context) {
                                  final rows =
                                      (source[f.option] as List?)
                                          ?.whereType<Map>()
                                          .toList() ??
                                      [];
                                  final current = choices[f.key];
                                  final valid =
                                      current != null &&
                                      rows.any(
                                        (row) => '${row['id']}' == '$current',
                                      );
                                  // Las referencias históricas se muestran, pero no se cambian.
                                  final view =
                                      (f.key == 'order_id' &&
                                          original != null) ||
                                      (f.key == 'branch_id' &&
                                          original != null);
                                  return DropdownButtonFormField<int>(
                                    initialValue: valid ? current : null,
                                    isExpanded: true,
                                    dropdownColor: surface,
                                    decoration: _decor(f.label),
                                    items: [
                                      if (!f.mandatory)
                                        const DropdownMenuItem<int>(
                                          value: null,
                                          child: Text('No aplica'),
                                        ),
                                      ...rows.map(
                                        (row) => DropdownMenuItem<int>(
                                          value: int.tryParse('${row['id']}'),
                                          child: Text(
                                            _optionTitle(f.option!, row),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),
                                    ],
                                    onChanged: saving || view
                                        ? null
                                        : (v) =>
                                              update(() => choices[f.key] = v),
                                    validator: (v) =>
                                        f.mandatory && v == null && !view
                                        ? 'Selecciona una opción.'
                                        : null,
                                  );
                                },
                              )
                            else
                              TextFormField(
                                controller: controllers[f.key],
                                maxLines: f.notes ? 3 : 1,
                                keyboardType: f.number
                                    ? const TextInputType.numberWithOptions(
                                        decimal: true,
                                      )
                                    : TextInputType.text,
                                decoration: _decor(f.label),
                                validator: (v) =>
                                    f.mandatory && (v ?? '').trim().isEmpty
                                    ? 'Obligatorio.'
                                    : null,
                              ),
                            const SizedBox(height: 12),
                          ],
                          if (widget.module == SalesModule.banks ||
                              widget.module == SalesModule.methods)
                            SwitchListTile(
                              title: const Text('Activo'),
                              value: active,
                              onChanged: saving
                                  ? null
                                  : (v) => update(() => active = v),
                            ),
                          if (problem != null)
                            Text(
                              problem!,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('sales_save'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!(key.currentState?.validate() ?? false)) {
                          return;
                        }
                        final payload = <String, dynamic>{};
                        for (final f in fields) {
                          if (f.key == 'branch_id' && original != null) {
                            continue;
                          }
                          if (f.key == 'order_id' && original != null) {
                            continue;
                          }
                          if (f.option == 'channel') {
                            payload[f.key] = channel;
                          } else if (f.option != null) {
                            payload[f.key] = choices[f.key];
                          } else {
                            final value = controllers[f.key]!.text.trim();
                            payload[f.key] = value.isEmpty ? null : value;
                          }
                        }
                        if (widget.module == SalesModule.banks ||
                            widget.module == SalesModule.methods) {
                          payload['is_active'] = active;
                        }
                        update(() {
                          saving = true;
                          problem = null;
                        });
                        try {
                          await _api.request(
                            original == null ? 'POST' : 'PATCH',
                            original == null
                                ? _path
                                : '$_path/${original['id']}',
                            body: payload,
                          );
                          if (dialog.mounted) {
                            Navigator.pop(dialog, true);
                          }
                        } catch (error) {
                          if (dialog.mounted) {
                            update(() {
                              saving = false;
                              problem = '$error';
                            });
                          }
                        }
                      },
                child: Text(saving ? 'Guardando...' : 'Guardar'),
              ),
            ],
          ),
        ),
      );
      if (result == true && mounted) {
        _notice('Registro guardado correctamente.');
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
      final response = await _api.request('GET', '$_path/${row['id']}');
      if (!mounted) {
        return;
      }
      final detail = response['data'] as Map? ?? {};
      await showDialog<void>(
        context: context,
        builder: (dialog) => AlertDialog(
          backgroundColor: surface,
          title: const Text('Detalle del registro'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final entry in detail.entries)
                    if (![
                      'created_at',
                      'updated_at',
                      'deleted_at',
                    ].contains(entry.key))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text('${entry.key}: ${entry.value ?? '—'}'),
                      ),
                ],
              ),
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
      _notice('$error', error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    if (widget.module == SalesModule.payments && row['status'] == 'POSTED') {
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: surface,
        title: const Text('Eliminar registro'),
        content: const Text(
          'Se archivará únicamente si no existen movimientos contables confirmados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true) {
      return;
    }
    try {
      await _api.request('DELETE', '$_path/${row['id']}');
      _notice('Registro archivado.');
      await _load();
    } catch (error) {
      _notice('$error', error: true);
    }
  }

  String _summary(Map<String, dynamic> row) => switch (widget.module) {
    SalesModule.banks =>
      '${row['alias']} · ${row['bank_name']} · Recibido L ${row['received_total']}',
    SalesModule.methods =>
      '${row['name']} · ${row['channel'] == 'CASH' ? 'Efectivo' : 'Banco'}',
    SalesModule.discounts =>
      '${row['tracking_code']} · Descuento L ${row['amount']}',
    SalesModule.payments =>
      '${row['tracking_code']} · L ${row['amount']} · ${row['status']}',
  };

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_help, style: const TextStyle(color: muted)),
              ],
            ),
            FilledButton.icon(
              key: const ValueKey('sales_new'),
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Nuevo registro'),
              style: FilledButton.styleFrom(backgroundColor: accent),
            ),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ],
        ),
        const SizedBox(height: 17),
        TextField(
          controller: _search,
          onChanged: _searchChanged,
          decoration: _decor('Buscar registros'),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(color: accent),
            ),
          )
        else if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.redAccent))
        else if (_rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Text('Sin registros para mostrar.'),
          )
        else
          for (final row in _rows)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 9),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _summary(row),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Consultar',
                    onPressed: () => _details(row),
                    icon: const Icon(Icons.visibility_outlined, color: muted),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed:
                        widget.module == SalesModule.payments &&
                            row['status'] == 'POSTED'
                        ? null
                        : () => _edit(row),
                    icon: const Icon(Icons.edit_outlined, color: accent),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed:
                        widget.module == SalesModule.payments &&
                            row['status'] == 'POSTED'
                        ? null
                        : () => _delete(row),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Colors.redAccent,
                    ),
                  ),
                ],
              ),
            ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Anterior',
              onPressed: _page <= 1
                  ? null
                  : () {
                      _page--;
                      _load();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              'Página $_page de $_pages',
              style: const TextStyle(color: muted),
            ),
            IconButton(
              tooltip: 'Siguiente',
              onPressed: _page >= _pages
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
