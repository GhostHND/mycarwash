import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

enum CashModule { registers, sessions, categories, movements }

class _CashField {
  const _CashField(
    this.key,
    this.name, {
    this.mandatory = false,
    this.option,
    this.multiline = false,
    this.number = false,
  });
  final String key;
  final String name;
  final bool mandatory;
  final String? option;
  final bool multiline;
  final bool number;
}

class CompanyCashPage extends StatefulWidget {
  const CompanyCashPage({super.key, required this.module, this.client});
  final CashModule module;
  final http.Client? client;

  @override
  State<CompanyCashPage> createState() => _CompanyCashPageState();
}

class _CompanyCashPageState extends State<CompanyCashPage> {
  static const Color _turquoise = Color(0xFF0FA7B4);
  static const Color _muted = Color(0xFF9BAEB6);
  static const Color _border = Color(0xFF20343C);
  static const Color _surface = Color(0xFF0A1519);

  late final http.Client _client;
  late final bool _ownsClient;
  final _search = TextEditingController();
  Timer? _debounce;
  int _version = 0;
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  String get _resource => switch (widget.module) {
    CashModule.registers => 'registers',
    CashModule.sessions => 'sessions',
    CashModule.categories => 'categories',
    CashModule.movements => 'movements',
  };
  String get _path => '/cash/$_resource';
  String get _title => switch (widget.module) {
    CashModule.registers => 'Cajas registradoras',
    CashModule.sessions => 'Sesiones y cierres de caja',
    CashModule.categories => 'Categorías de egresos',
    CashModule.movements => 'Movimientos de efectivo',
  };
  String get _single => switch (widget.module) {
    CashModule.registers => 'caja',
    CashModule.sessions => 'sesión',
    CashModule.categories => 'categoría',
    CashModule.movements => 'movimiento',
  };
  String get _description => switch (widget.module) {
    CashModule.registers => 'Puntos de cobro manual por sucursal. Moneda: HNL.',
    CashModule.sessions => 'Aperturas, conteos y cierres de efectivo, sin alterar cierres históricos.',
    CashModule.categories => 'Clasifica los egresos manuales de efectivo.',
    CashModule.movements => 'Entradas y salidas manuales por sesión, auditadas. No son pagos de ventas.',
  };

  List<_CashField> get _fields => switch (widget.module) {
    CashModule.registers => const [
      _CashField('branch_id', 'Sucursal', mandatory: true, option: 'branches'),
      _CashField('code', 'Código de caja', mandatory: true),
      _CashField('name', 'Nombre de caja', mandatory: true),
      _CashField('notes', 'Observaciones', multiline: true),
    ],
    CashModule.categories => const [
      _CashField('name', 'Nombre de la categoría', mandatory: true),
      _CashField('description', 'Descripción', multiline: true),
    ],
    CashModule.sessions => const [
      _CashField(
        'register_id',
        'Caja registradora',
        mandatory: true,
        option: 'registers',
      ),
      _CashField(
        'opening_cash',
        'Fondo inicial (L)',
        mandatory: true,
        number: true,
      ),
      _CashField(
        'notes',
        'Observaciones / motivo de diferencia',
        multiline: true,
      ),
      _CashField(
        'status',
        'Estado de la sesión',
        mandatory: true,
        option: 'status',
      ),
      _CashField(
        'counted_cash',
        'Efectivo contado al cierre (L)',
        number: true,
      ),
    ],
    CashModule.movements => const [
      _CashField(
        'session_id',
        'Sesión abierta',
        mandatory: true,
        option: 'sessions',
      ),
      _CashField(
        'direction',
        'Movimiento',
        mandatory: true,
        option: 'direction',
      ),
      _CashField('amount', 'Monto (L)', mandatory: true, number: true),
      _CashField(
        'expense_category_id',
        'Categoría (obligatoria para egresos)',
        option: 'categories',
      ),
      _CashField('reference', 'Número o referencia'),
      _CashField('notes', 'Motivo / observaciones', multiline: true),
    ],
  };

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyCashPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      _search.clear();
      _page = 1;
      _load();
    }
  }

  @override
  void dispose() {
    _version++;
    _debounce?.cancel();
    _search.dispose();
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_version;
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
      if (!mounted || version != _version) {
        return;
      }
      final raw = result['data'];
      setState(() {
        _rows = raw is List
            ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
        _page = int.tryParse('${result['current_page'] ?? 1}') ?? 1;
        _pages = int.tryParse('${result['last_page'] ?? 1}') ?? 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _version) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _searchChanged(String value) {
    _debounce?.cancel();
    _page = 1;
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _load();
      }
    });
  }

  void _notice(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted),
    filled: true,
    fillColor: const Color(0xFF111F25),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: _border),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: _turquoise),
      borderRadius: BorderRadius.circular(10),
    ),
  );

  static String _label(String field, Map<String, dynamic> row) {
    if (field == 'sessions') {
      return 'Sesión ${row['id']} · Caja ${row['register_id']}';
    }
    return '${row['name'] ?? row['id']}';
  }

  List<DropdownMenuItem<String>> _choices(
    _CashField field,
    Map<String, dynamic> options,
  ) {
    if (field.option == 'status') {
      return const [
        DropdownMenuItem(value: 'OPEN', child: Text('Abierta')),
        DropdownMenuItem(
          value: 'CLOSED',
          child: Text('Cerrar definitivamente'),
        ),
      ];
    }
    if (field.option == 'direction') {
      return const [
        DropdownMenuItem(value: 'IN', child: Text('Ingreso de efectivo (+)')),
        DropdownMenuItem(value: 'OUT', child: Text('Egreso de efectivo (−)')),
      ];
    }
    final raw = options[field.option];
    if (raw is! List) {
      return [];
    }
    return raw.whereType<Map>().map((row) {
      final map = Map<String, dynamic>.from(row);
      return DropdownMenuItem<String>(
        value: '${row['id']}',
        child: Text(
          _label(field.option!, map),
          overflow: TextOverflow.ellipsis,
        ),
      );
    }).toList();
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    Map<String, dynamic> options;
    try {
      final response = await _api.request('GET', '/cash/options');
      options = Map<String, dynamic>.from(response['data'] as Map);
    } catch (error) {
      _notice('No se pudo cargar el formulario: $error', error: true);
      return;
    }
    if (!mounted) {
      return;
    }
    final fields = _fields;
    final controllers = <String, TextEditingController>{
      for (final field in fields)
        field.key: TextEditingController(
          text:
              (existing?[field.key] ??
                      (field.key == 'status'
                          ? 'OPEN'
                          : ['opening_cash', 'amount'].contains(field.key)
                          ? '0.00'
                          : ''))
                  .toString(),
        ),
    };
    final key = GlobalKey<FormState>();
    var active =
        existing == null ||
        existing['is_active'] == true ||
        existing['is_active'] == 1;
    var saving = false;
    String? dialogError;
    // Evita liberar controladores mientras sigue montado el Overlay.
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          backgroundColor: _surface,
          title: Text(
            existing == null ? 'Nuevo $_single' : 'Editar $_single',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final field in fields) ...[
                      Builder(
                        builder: (context) {
                          if (field.option != null) {
                            final values = _choices(field, options);
                            final current = controllers[field.key]!.text;
                            final selected =
                                values.any((e) => e.value == current)
                                ? current
                                : null;
                            return DropdownButtonFormField<String>(
                              key: ValueKey('${field.key}:$selected'),
                              initialValue: selected,
                              isExpanded: true,
                              dropdownColor: _surface,
                              decoration: _decoration(field.name),
                              items: [
                                if (!field.mandatory)
                                  const DropdownMenuItem(
                                    value: '',
                                    child: Text('Sin asignar'),
                                  ),
                                ...values,
                              ],
                              onChanged:
                                  saving ||
                                      (existing != null &&
                                          ((widget.module ==
                                                      CashModule.movements &&
                                                  field.key == 'session_id') ||
                                              (widget.module ==
                                                      CashModule.sessions &&
                                                  field.key == 'register_id')))
                                  ? null
                                  : (value) {
                                      controllers[field.key]!.text =
                                          value ?? '';
                                      update(() {});
                                    },
                              validator: (value) =>
                                  field.mandatory &&
                                      (value == null || value.isEmpty)
                                  ? 'Selecciona una opción.'
                                  : null,
                            );
                          }
                          return TextFormField(
                            key: ValueKey('cash_${field.key}'),
                            controller: controllers[field.key],
                            enabled: !saving,
                            keyboardType: field.number
                                ? const TextInputType.numberWithOptions(
                                    decimal: true,
                                  )
                                : TextInputType.text,
                            maxLines: field.multiline ? 3 : 1,
                            style: const TextStyle(color: Colors.white),
                            decoration: _decoration(field.name),
                            validator: (value) {
                              final v = (value ?? '').trim();
                              if (field.mandatory && v.isEmpty) {
                                return 'Este campo es obligatorio.';
                              }
                              if (field.number &&
                                  v.isNotEmpty &&
                                  double.tryParse(v) == null) {
                                return 'Escribe una cantidad numérica.';
                              }
                              if (field.number &&
                                  v.isNotEmpty &&
                                  (double.tryParse(v) ?? -1) < 0) {
                                return 'La cantidad no puede ser negativa.';
                              }
                              if (field.key == 'amount' &&
                                  v.isNotEmpty &&
                                  (double.tryParse(v) ?? 0) <= 0) {
                                return 'Cantidad mayor que cero.';
                              }
                              return null;
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 13),
                    ],
                    if (widget.module == CashModule.registers ||
                        widget.module == CashModule.categories)
                      SwitchListTile(
                        title: const Text('Activo'),
                        value: active,
                        activeThumbColor: _turquoise,
                        onChanged: saving
                            ? null
                            : (v) => update(() => active = v),
                      ),
                    if (dialogError != null)
                      Text(
                        dialogError!,
                        style: const TextStyle(color: Color(0xFFFF8995)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: saving
                  ? null
                  : () async {
                      if (key.currentState?.validate() != true) {
                        return;
                      }
                      update(() {
                        saving = true;
                        dialogError = null;
                      });
                      final data = <String, dynamic>{};
                      for (final f in fields) {
                        final v = controllers[f.key]!.text.trim();
                        if (v.isEmpty) {
                          if (f.number) {
                            data[f.key] = null;
                            continue;
                          }
                          data[f.key] = null;
                        } else if (f.option != null &&
                            !['status', 'direction'].contains(f.option)) {
                          data[f.key] = int.parse(v);
                        } else {
                          data[f.key] = v;
                        }
                      }
                      if (widget.module == CashModule.registers ||
                          widget.module == CashModule.categories) {
                        data['is_active'] = active;
                      }
                      if (existing != null &&
                          widget.module == CashModule.movements) {
                        data.remove('session_id');
                      }
                      if (existing != null &&
                          widget.module == CashModule.sessions) {
                        data.remove('register_id');
                      }
                      try {
                        await _api.request(
                          existing == null ? 'POST' : 'PATCH',
                          existing == null ? _path : '$_path/${existing['id']}',
                          body: data,
                        );
                        if (dialogContext.mounted) {
                          Navigator.pop(dialogContext, true);
                        }
                      } catch (error) {
                        if (dialogContext.mounted) {
                          update(() {
                            saving = false;
                            dialogError = error.toString();
                          });
                        }
                      }
                    },
              icon: const Icon(Icons.save_outlined),
              style: FilledButton.styleFrom(backgroundColor: _turquoise),
              label: Text(saving ? 'Guardando...' : 'Guardar $_single'),
            ),
          ],
        ),
      ),
    );
    try {
      final changed = await Navigator.of(
        context,
        rootNavigator: true,
      ).push<bool>(route);
      await route.completed;
      if (changed == true && mounted) {
        _notice('Registro guardado.');
        _page = 1;
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
      final result = await _api.request('GET', '$_path/${row['id']}');
      if (!mounted) {
        return;
      }
      final info = Map<String, dynamic>.from(result['data'] as Map);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: _surface,
          title: Text('Detalle de $_single'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in info.entries)
                    if (![
                      'created_at',
                      'updated_at',
                      'deleted_at',
                    ].contains(f.key))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 9),
                        child: Text('${f.key}: ${f.value ?? '—'}'),
                      ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      _notice(error.toString(), error: true);
    }
  }

  Future<void> _history(Map<String, dynamic> row) async {
    try {
      final response = await _api.request('GET', '$_path/${row['id']}/history');
      if (!mounted) {
        return;
      }
      final records = response['data'] as List? ?? [];
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: _surface,
          title: const Text('Historial del movimiento'),
          content: SizedBox(
            width: 510,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final event in records)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${event['action']} · ${event['occurred_at']} · Usuario ${event['actor_user_id']}',
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (error) {
      _notice(error.toString(), error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Eliminar $_single'),
        content: Text(
          '¿Confirmas eliminar el registro ${row['id']}? '
          'El sistema rechazará eliminaciones con operaciones históricas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await _api.request('DELETE', '$_path/${row['id']}');
      if (!mounted) {
        return;
      }
      _notice('Registro eliminado de los activos.');
      await _load();
      if (_rows.isEmpty && _page > 1 && mounted) {
        _page--;
        await _load();
      }
    } catch (error) {
      _notice(error.toString(), error: true);
    }
  }

  Future<void> _closeSession(Map<String, dynamic> row) async {
    if (row['status'] != 'OPEN') {
      return;
    }
    final counted = TextEditingController();
    final reason = TextEditingController();
    bool saving = false;
    String? failure;
    try {
      final answer = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            backgroundColor: _surface,
            title: const Text('Cerrar caja'),
            content: SizedBox(
              width: 450,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Caja: ${row['register_name'] ?? row['register_id']}'),
                  Text(
                    'Efectivo esperado: L ${row['expected_current'] ?? row['opening_cash']}',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const ValueKey('cash_close_counted'),
                    controller: counted,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: _decoration('Efectivo contado en L'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reason,
                    maxLines: 3,
                    decoration: _decoration(
                      'Observaciones y diferencias de caja',
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'El cierre es definitivo y no se puede editar.',
                    style: TextStyle(color: _muted),
                  ),
                  if (failure != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        failure!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('cash_close_confirm'),
                onPressed: saving
                    ? null
                    : () async {
                        update(() {
                          saving = true;
                          failure = null;
                        });
                        try {
                          await _api.request(
                            'PATCH',
                            '/cash/sessions/${row['id']}',
                            body: {
                              'status': 'CLOSED',
                              'counted_cash': counted.text.trim(),
                              'notes': reason.text.trim().isEmpty
                                  ? null
                                  : reason.text.trim(),
                            },
                          );
                          if (dialog.mounted) {
                            Navigator.pop(dialog, true);
                          }
                        } catch (error) {
                          if (dialog.mounted) {
                            update(() {
                              saving = false;
                              failure = '$error';
                            });
                          }
                        }
                      },
                child: Text(
                  saving ? 'Cerrando...' : 'Confirmar cierre de caja',
                ),
              ),
            ],
          ),
        ),
      );
      if (answer == true && mounted) {
        _notice('Caja cerrada. Se conservará el cierre y su historial.');
        await _load();
      }
    } finally {
      counted.dispose();
      reason.dispose();
    }
  }

  String _summary(Map<String, dynamic> row) => switch (widget.module) {
    CashModule.registers =>
      '${row['code']} · ${row['name']} · ${row['branch_name'] ?? ''}',
    CashModule.categories => '${row['name'] ?? 'Categoría'}',
    CashModule.sessions =>
      '${row['register_name'] ?? row['register_id']} · ${row['status']} · '
          'Efectivo esperado: L ${row['expected_current'] ?? row['opening_cash']}',
    CashModule.movements =>
      '${row['direction'] == 'IN' ? 'Ingreso' : 'Egreso'} · '
          'L ${row['amount']} · ${row['register_name'] ?? row['session_id']}',
  };

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: _border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(_description, style: const TextStyle(color: _muted)),
              ],
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: Text('Nuevo $_single'),
              style: FilledButton.styleFrom(backgroundColor: _turquoise),
            ),
          ],
        ),
        const SizedBox(height: 19),
        TextField(
          controller: _search,
          onChanged: _searchChanged,
          decoration: _decoration(
            'Buscar registros',
          ).copyWith(prefixIcon: const Icon(Icons.search, color: _turquoise)),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(color: _turquoise)),
          )
        else if (_error != null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_error!, style: const TextStyle(color: Color(0xFFFF8995))),
              OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
            ],
          )
        else if (_rows.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text('No hay registros.', style: TextStyle(color: _muted)),
            ),
          )
        else
          for (final row in _rows)
            Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined, color: _turquoise),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _summary(row),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'ID ${row['id']}',
                          style: const TextStyle(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (widget.module == CashModule.sessions &&
                      row['status'] == 'OPEN')
                    FilledButton.icon(
                      key: ValueKey('cash_close_${row['id']}'),
                      onPressed: () => _closeSession(row),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Cerrar caja'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _turquoise,
                      ),
                    ),
                  if (widget.module == CashModule.movements)
                    IconButton(
                      tooltip: 'Historial',
                      onPressed: () => _history(row),
                      icon: const Icon(Icons.history, color: _muted),
                    ),
                  IconButton(
                    tooltip: 'Consultar',
                    onPressed: () => _details(row),
                    icon: const Icon(Icons.visibility_outlined, color: _muted),
                  ),
                  IconButton(
                    tooltip: 'Editar',
                    onPressed:
                        widget.module == CashModule.sessions &&
                            row['status'] == 'CLOSED'
                        ? null
                        : () => _edit(row),
                    icon: const Icon(Icons.edit_outlined, color: _turquoise),
                  ),
                  IconButton(
                    tooltip: 'Eliminar',
                    onPressed:
                        widget.module == CashModule.sessions &&
                            row['status'] == 'CLOSED'
                        ? null
                        : () => _delete(row),
                    icon: const Icon(
                      Icons.delete_outline,
                      color: Color(0xFFE84657),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Página anterior',
              onPressed: _loading || _page <= 1
                  ? null
                  : () {
                      _page--;
                      _load();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              'Página $_page de $_pages',
              style: const TextStyle(color: _muted),
            ),
            IconButton(
              tooltip: 'Página siguiente',
              onPressed: _loading || _page >= _pages
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
