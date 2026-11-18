import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

enum InventoryModule { categories, suppliers, items, movements }

class _InventoryField {
  const _InventoryField(
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

class CompanyInventoryPage extends StatefulWidget {
  const CompanyInventoryPage({super.key, required this.module, this.client});
  final InventoryModule module;
  final http.Client? client;

  @override
  State<CompanyInventoryPage> createState() => _CompanyInventoryPageState();
}

class _CompanyInventoryPageState extends State<CompanyInventoryPage> {
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
    InventoryModule.categories => 'categories',
    InventoryModule.suppliers => 'suppliers',
    InventoryModule.items => 'items',
    InventoryModule.movements => 'movements',
  };
  String get _path => '/inventory/$_resource';
  String get _title => switch (widget.module) {
    InventoryModule.categories => 'Categorías de inventario',
    InventoryModule.suppliers => 'Proveedores',
    InventoryModule.items => 'Productos e insumos',
    InventoryModule.movements => 'Movimientos de existencias',
  };
  String get _single => switch (widget.module) {
    InventoryModule.categories => 'categoría',
    InventoryModule.suppliers => 'proveedor',
    InventoryModule.items => 'producto',
    InventoryModule.movements => 'movimiento',
  };
  String get _description => switch (widget.module) {
    InventoryModule.categories =>
      'Clasifica los productos y materiales del autolavado.',
    InventoryModule.suppliers =>
      'Contactos y datos de abastecimiento por empresa.',
    InventoryModule.items => 'Catálogo de insumos y existencias consolidadas.',
    InventoryModule.movements =>
      'Entradas y salidas por sucursal con trazabilidad.',
  };

  List<_InventoryField> get _fields => switch (widget.module) {
    InventoryModule.categories => const [
      _InventoryField('name', 'Nombre de la categoría', mandatory: true),
      _InventoryField('description', 'Descripción', multiline: true),
    ],
    InventoryModule.suppliers => const [
      _InventoryField('name', 'Nombre del proveedor', mandatory: true),
      _InventoryField('tax_id', 'RTN / Identificación fiscal'),
      _InventoryField('phone', 'Teléfono'),
      _InventoryField('email', 'Correo electrónico'),
      _InventoryField('address', 'Dirección'),
      _InventoryField('notes', 'Notas', multiline: true),
    ],
    InventoryModule.items => const [
      _InventoryField('sku', 'Código SKU', mandatory: true),
      _InventoryField('name', 'Nombre del producto', mandatory: true),
      _InventoryField(
        'unit',
        'Unidad de medida',
        mandatory: true,
        option: 'units',
      ),
      _InventoryField('category_id', 'Categoría', option: 'categories'),
      _InventoryField('supplier_id', 'Proveedor', option: 'suppliers'),
      _InventoryField('min_stock', 'Existencia mínima', number: true),
      _InventoryField('cost_price', 'Costo unitario (L)', number: true),
      _InventoryField('sale_price', 'Precio de venta (L)', number: true),
      _InventoryField('description', 'Descripción', multiline: true),
    ],
    InventoryModule.movements => const [
      _InventoryField(
        'branch_id',
        'Sucursal',
        mandatory: true,
        option: 'branches',
      ),
      _InventoryField('item_id', 'Producto', mandatory: true, option: 'items'),
      _InventoryField(
        'movement_type',
        'Tipo de movimiento',
        mandatory: true,
        option: 'direction',
      ),
      _InventoryField('quantity', 'Cantidad', mandatory: true, number: true),
      _InventoryField('reference', 'Referencia o comprobante'),
      _InventoryField('notes', 'Observaciones', multiline: true),
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
  void didUpdateWidget(covariant CompanyInventoryPage oldWidget) {
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
    if (field == 'items') {
      return '${row['sku']} · ${row['name']} (${row['unit']})';
    }
    return '${row['name'] ?? row['id']}';
  }

  List<DropdownMenuItem<String>> _choices(
    _InventoryField field,
    Map<String, dynamic> options,
  ) {
    if (field.option == 'units') {
      const units = [
        'unidad',
        'litro',
        'ml',
        'galon',
        'kg',
        'g',
        'metro',
        'paquete',
      ];
      return [
        for (final unit in units)
          DropdownMenuItem<String>(value: unit, child: Text(unit)),
      ];
    }
    if (field.option == 'direction') {
      return const [
        DropdownMenuItem(value: 'IN', child: Text('Entrada de inventario (+)')),
        DropdownMenuItem(value: 'OUT', child: Text('Salida de inventario (−)')),
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
      final response = await _api.request('GET', '/inventory/options');
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
                      (field.key == 'unit'
                          ? 'unidad'
                          : ['min_stock', 'cost_price'].contains(field.key)
                          ? '0'
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
                                          widget.module ==
                                              InventoryModule.movements &&
                                          (field.key == 'branch_id' ||
                                              field.key == 'item_id'))
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
                            key: ValueKey('inventory_${field.key}'),
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
                              if (field.key == 'quantity' &&
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
                    if (widget.module != InventoryModule.movements)
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
                          if (f.number && f.key != 'sale_price') {
                            continue;
                          }
                          data[f.key] = null;
                        } else if (f.option != null &&
                            !['units', 'direction'].contains(f.option)) {
                          data[f.key] = int.parse(v);
                        } else {
                          data[f.key] = v;
                        }
                      }
                      if (widget.module != InventoryModule.movements) {
                        data['is_active'] = active;
                      }
                      if (existing != null &&
                          widget.module == InventoryModule.movements) {
                        data.remove('branch_id');
                        data.remove('item_id');
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
          'Se conservará el historial correspondiente.',
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

  // 24I: tarjetas de altura natural y ancho proporcional al contenido.
  String _cardValue(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null || '$value'.trim().isEmpty) return '';
    return '$value'.trim();
  }

  Widget _cardDetail(String label, String value, {Color? valueColor}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 5,
        runSpacing: 2,
        children: [
          Text('$label:', style: const TextStyle(fontSize: 12, color: _muted)),
          Text(
            value,
            style: TextStyle(fontSize: 13, color: valueColor ?? Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _inventoryCard(Map<String, dynamic> row) {
    final isMovement = widget.module == InventoryModule.movements;
    final active = row['is_active'] != false && '${row['is_active']}' != '0';
    final title = switch (widget.module) {
      InventoryModule.categories => _cardValue(row, 'name'),
      InventoryModule.suppliers => _cardValue(row, 'name'),
      InventoryModule.items => _cardValue(row, 'name'),
      InventoryModule.movements =>
        _cardValue(row, 'movement_type') == 'IN'
            ? 'Entrada de inventario'
            : 'Salida de inventario',
    };
    final icon = switch (widget.module) {
      InventoryModule.categories => Icons.category_outlined,
      InventoryModule.suppliers => Icons.local_shipping_outlined,
      InventoryModule.items => Icons.inventory_2_outlined,
      InventoryModule.movements => Icons.swap_horiz_outlined,
    };
    final details = <Widget>[
      if (widget.module == InventoryModule.categories)
        _cardDetail('Descripción', _cardValue(row, 'description')),
      if (widget.module == InventoryModule.suppliers) ...[
        _cardDetail('RTN', _cardValue(row, 'tax_id')),
        _cardDetail('Teléfono', _cardValue(row, 'phone')),
        _cardDetail('Correo', _cardValue(row, 'email')),
        _cardDetail('Dirección', _cardValue(row, 'address')),
        _cardDetail('Notas', _cardValue(row, 'notes')),
      ],
      if (widget.module == InventoryModule.items) ...[
        _cardDetail('SKU', _cardValue(row, 'sku')),
        _cardDetail('Categoría', _cardValue(row, 'category_name')),
        _cardDetail('Proveedor', _cardValue(row, 'supplier_name')),
        _cardDetail(
          'Existencia',
          '${row['stock_total'] ?? '0'} ${row['unit'] ?? ''}',
        ),
        _cardDetail('Mínimo', _cardValue(row, 'min_stock')),
        _cardDetail(
          'Costo',
          _cardValue(row, 'cost_price').isEmpty ? '' : 'L ${row['cost_price']}',
        ),
        _cardDetail(
          'Precio de venta',
          _cardValue(row, 'sale_price').isEmpty ? '' : 'L ${row['sale_price']}',
          valueColor: _turquoise,
        ),
        _cardDetail('Descripción', _cardValue(row, 'description')),
      ],
      if (isMovement) ...[
        _cardDetail(
          'Producto',
          _cardValue(row, 'item_name').isEmpty
              ? _cardValue(row, 'item_id')
              : _cardValue(row, 'item_name'),
        ),
        _cardDetail('Cantidad', _cardValue(row, 'quantity')),
        _cardDetail(
          'Sucursal',
          _cardValue(row, 'branch_name').isEmpty
              ? _cardValue(row, 'branch_id')
              : _cardValue(row, 'branch_name'),
        ),
        _cardDetail('Referencia', _cardValue(row, 'reference')),
        _cardDetail('Observaciones', _cardValue(row, 'notes')),
      ],
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF112229),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _turquoise.withValues(alpha: 0.65)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: _turquoise, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title.isEmpty ? 'Registro ${row['id']}' : title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              if (!isMovement)
                Text(
                  active ? 'Activo' : 'Inactivo',
                  style: TextStyle(
                    fontSize: 11,
                    color: active ? const Color(0xFF52D5A0) : _muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'ID ${row['id']}',
            style: const TextStyle(fontSize: 11, color: _muted),
          ),
          ...details,
          const SizedBox(height: 10),
          const Divider(color: _border, height: 1),
          const SizedBox(height: 4),
          Wrap(
            spacing: 2,
            runSpacing: 0,
            children: [
              if (isMovement)
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
                onPressed: () => _edit(row),
                icon: const Icon(Icons.edit_outlined, color: _turquoise),
              ),
              IconButton(
                tooltip: 'Eliminar',
                onPressed: () => _delete(row),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Color(0xFFE84657),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inventoryCards() => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      // Categorías son más compactas que proveedores y productos.
      final minWidth = switch (widget.module) {
        InventoryModule.categories => 240.0,
        InventoryModule.suppliers => 335.0,
        InventoryModule.items => 330.0,
        InventoryModule.movements => 300.0,
      };
      const spacing = 12.0;
      final columns = ((width + spacing) / (minWidth + spacing)).floor().clamp(
        1,
        4,
      );
      final cardWidth = (width - spacing * (columns - 1)) / columns;
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        crossAxisAlignment: WrapCrossAlignment.start,
        children: [
          for (final row in _rows)
            SizedBox(width: cardWidth, child: _inventoryCard(row)),
        ],
      );
    },
  );

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
          _inventoryCards(),
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
