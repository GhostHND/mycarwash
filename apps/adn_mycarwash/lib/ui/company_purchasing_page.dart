import 'dart:math';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// Bloque 23A: órdenes de compra y recepción real de artículos.
class CompanyPurchasingPage extends StatefulWidget {
  const CompanyPurchasingPage({super.key, this.client});
  final http.Client? client;

  @override
  State<CompanyPurchasingPage> createState() => _CompanyPurchasingPageState();
}

class _PurchaseDraftLine {
  const _PurchaseDraftLine(this.id, this.name, this.quantity, this.cost);
  final int id;
  final String name;
  final String quantity;
  final String cost;
}

class _CompanyPurchasingPageState extends State<CompanyPurchasingPage> {
  static Color get accent => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get panel => CompanyVisualTheme.legacy(const Color(0xFF102229));
  static Color get muted => CompanyVisualTheme.legacy(const Color(0xFFA7B8BF));
  late final http.Client client;
  late final bool ownsClient;
  CompanyBusinessApi get api => CompanyBusinessApi(client);
  bool loading = true;
  bool submitting = false;
  String? error;
  int? selectedBranch;
  int? selectedSupplier;
  Map<String, dynamic>? detail;
  List<Map<String, dynamic>> branches = [];
  List<Map<String, dynamic>> suppliers = [];
  List<Map<String, dynamic>> items = [];
  List<Map<String, dynamic>> orders = [];
  final List<_PurchaseDraftLine> draft = [];
  final notes = TextEditingController();
  final reference = TextEditingController();

  static List<Map<String, dynamic>> asList(dynamic value) => value is List
      ? value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : [];
  static int intVal(dynamic value) => int.tryParse('$value') ?? 0;
  static String money(dynamic value) => 'L ${value ?? '0.00'}';

  @override
  void initState() {
    super.initState();
    ownsClient = widget.client == null;
    client = widget.client ?? http.Client();
    load();
  }

  @override
  void dispose() {
    notes.dispose();
    reference.dispose();
    if (ownsClient) {
      client.close();
    }
    super.dispose();
  }

  Future<void> load() async {
    if (!mounted) {
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final options = await api.request('GET', '/purchasing/options');
      final response = await api.request('GET', '/purchasing/orders');
      if (!mounted) {
        return;
      }
      final data = Map<String, dynamic>.from(options['data'] as Map);
      setState(() {
        branches = asList(data['branches']);
        suppliers = asList(data['suppliers']);
        items = asList(data['items']);
        orders = asList(response['data']);
        if (!branches.any((e) => intVal(e['id']) == selectedBranch)) {
          selectedBranch = branches.isEmpty
              ? null
              : intVal(branches.first['id']);
        }
        if (!suppliers.any((e) => intVal(e['id']) == selectedSupplier)) {
          selectedSupplier = suppliers.isEmpty
              ? null
              : intVal(suppliers.first['id']);
        }
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'No se pudieron cargar las compras: $e';
          loading = false;
        });
      }
    }
  }

  void notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> addItem() async {
    if (items.isEmpty) {
      notice('Primero registra artículos en Inventario.');
      return;
    }
    int? choice = intVal(items.first['id']);
    final qty = TextEditingController(text: '1.000');
    final cost = TextEditingController(
      text: '${items.first['cost_price'] ?? '0.00'}',
    );
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: const Text('Agregar artículo a la orden'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: choice,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Artículo de inventario',
                      ),
                      items: [
                        for (final item in items)
                          DropdownMenuItem<int>(
                            value: intVal(item['id']),
                            child: Text(
                              '${item['sku']} · ${item['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) {
                        update(() => choice = v);
                        final item = items
                            .where((e) => intVal(e['id']) == v)
                            .firstOrNull;
                        if (item != null) {
                          cost.text = '${item['cost_price'] ?? '0.00'}';
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: qty,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Cantidad (3 decimales)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: cost,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Costo unitario HNL (2 decimales)',
                      ),
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
                  final id = choice;
                  if (id == null || draft.any((e) => e.id == id)) {
                    notice('Artículo ya incluido o selección inválida.');
                    return;
                  }
                  final q = double.tryParse(qty.text.trim());
                  final c = double.tryParse(cost.text.trim());
                  if (q == null ||
                      q <= 0 ||
                      c == null ||
                      c < 0 ||
                      !RegExp(r'^\d{1,11}(?:\.\d{1,3})?$')
                          .hasMatch(qty.text.trim()) ||
                      !RegExp(r'^\d{1,11}(?:\.\d{1,2})?$')
                          .hasMatch(cost.text.trim())) {
                    notice(
                      'Verifica cantidad y costo; máximo 3 y 2 decimales.',
                    );
                    return;
                  }
                  final item = items.firstWhere((e) => intVal(e['id']) == id);
                  setState(
                    () => draft.add(
                      _PurchaseDraftLine(
                        id,
                        '${item['name']}',
                        qty.text.trim(),
                        cost.text.trim(),
                      ),
                    ),
                  );
                  Navigator.pop(ctx);
                },
                child: const Text('Agregar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      qty.dispose();
      cost.dispose();
    }
  }

  Future<void> create() async {
    if (submitting ||
        selectedBranch == null ||
        selectedSupplier == null ||
        draft.isEmpty) {
      notice('Selecciona sucursal, proveedor y al menos un artículo.');
      return;
    }
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final response = await api.request(
        'POST',
        '/purchasing/orders',
        body: {
          'branch_id': selectedBranch,
          'supplier_id': selectedSupplier,
          'supplier_reference': reference.text.trim().isEmpty
              ? null
              : reference.text.trim(),
          'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
          'lines': [
            for (final line in draft)
              {
                'item_id': line.id,
                'quantity': line.quantity,
                'unit_cost': line.cost,
              },
          ],
        },
      );
      if (!mounted) {
        return;
      }
      final data = Map<String, dynamic>.from(response['data'] as Map);
      setState(() {
        draft.clear();
        reference.clear();
        notes.clear();
        detail = data;
      });
      notice('Orden creada correctamente. No se agregó stock hasta recibirla.');
      await load();
    } catch (e) {
      if (mounted) {
        setState(() => error = 'No se pudo registrar la orden: $e');
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  Future<void> inspect(int id) async {
    setState(() {
      submitting = true;
      error = null;
    });
    try {
      final response = await api.request('GET', '/purchasing/orders/$id');
      if (mounted) {
        setState(
          () => detail = Map<String, dynamic>.from(response['data'] as Map),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = 'No se pudo consultar la orden: $e');
      }
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  Future<void> cancelOrder() async {
    final snapshot = detail;
    if (snapshot == null || submitting) {
      return;
    }
    final header = Map<String, dynamic>.from(snapshot['order'] as Map);
    final id = intVal(header['id']);
    final approved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar orden sin recepciones'),
        content: const Text(
          'La orden quedará cancelada. No altera inventario ni caja.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancelar orden'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true) {
      return;
    }
    setState(() => submitting = true);
    try {
      await api.request('POST', '/purchasing/orders/$id/cancel');
      await inspect(id);
      await load();
      notice('Orden cancelada.');
    } catch (e) {
      notice('No se pudo cancelar: $e');
    } finally {
      if (mounted) {
        setState(() => submitting = false);
      }
    }
  }

  Future<void> receive() async {
    final snapshot = detail;
    if (snapshot == null) {
      return;
    }
    final order = Map<String, dynamic>.from(snapshot['order'] as Map);
    final orderId = intVal(order['id']);
    final lines = asList(snapshot['lines']);
    final inputs = <int, TextEditingController>{};
    for (final line in lines) {
      inputs[intVal(line['id'])] = TextEditingController(text: '0');
    }
    final supplierDoc = TextEditingController();
    // Se conserva la misma clave durante reintentos del diálogo.
    final key =
        'MCW-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';
    bool sending = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            title: Text('Recibir artículos · ${order['number']}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Registra solo lo que realmente llegó. Cero = no recibido.',
                      style: TextStyle(color: muted),
                    ),
                    const SizedBox(height: 12),
                    for (final line in lines) ...[
                      Text(
                        '${line['name_snapshot']} · pendiente: '
                        '${(double.tryParse('${line['ordered_quantity']}') ?? 0) - (double.tryParse('${line['received_quantity']}') ?? 0)}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 5),
                      TextField(
                        controller: inputs[intVal(line['id'])],
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Cantidad recibida',
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: supplierDoc,
                      decoration: const InputDecoration(
                        labelText: 'Documento del proveedor (opcional)',
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      'Al confirmar, el inventario aumentará inmediatamente. '
                      'No registres una entrada manual adicional.',
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: sending ? null : () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: sending
                    ? null
                    : () async {
                        final selected = <Map<String, dynamic>>[];
                        for (final line in lines) {
                          final id = intVal(line['id']);
                          final raw = inputs[id]!.text.trim();
                          if (raw.isEmpty || raw == '0' || raw == '0.000') {
                            continue;
                          }
                          if (!RegExp(r'^\d{1,11}(?:\.\d{1,3})?$')
                                  .hasMatch(raw) ||
                              (double.tryParse(raw) ?? 0) <= 0) {
                            notice(
                              'Cantidades inválidas: verifica hasta tres decimales.',
                            );
                            return;
                          }
                          selected.add({'order_line_id': id, 'quantity': raw});
                        }
                        if (selected.isEmpty) {
                          notice('Ingresa una cantidad mayor que cero.');
                          return;
                        }
                        update(() => sending = true);
                        try {
                          await api.request(
                            'POST',
                            '/purchasing/orders/$orderId/receive',
                            body: {
                              'idempotency_key': key,
                              'supplier_document':
                                  supplierDoc.text.trim().isEmpty
                                  ? null
                                  : supplierDoc.text.trim(),
                              'lines': selected,
                            },
                          );
                          if (!ctx.mounted) {
                            return;
                          }
                          Navigator.pop(ctx);
                          notice(
                            'Recepción registrada; inventario actualizado.',
                          );
                          await inspect(orderId);
                          await load();
                        } catch (e) {
                          if (ctx.mounted) {
                            update(() => sending = false);
                          }
                          notice(
                            'No se pudo recibir: $e. Revisa el historial antes de reintentar.',
                          );
                        }
                      },
                child: Text(sending ? 'Registrando...' : 'Confirmar recepción'),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final controller in inputs.values) {
        controller.dispose();
      }
      supplierDoc.dispose();
    }
  }

  Widget box(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: panel,
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF29444C))),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    final selected = detail;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1330),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Compras y recepciones',
              style: TextStyle(
                fontSize: 26,
                color: CompanyVisualTheme.text,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'Órdenes por sucursal · proveedores existentes · entradas auditadas',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 16),
            if (loading) LinearProgressIndicator(color: accent),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  error!,
                  style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF9BA7))),
                ),
              ),
            if (!loading) ...[
              box(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nueva orden de compra',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    LayoutBuilder(
                      builder: (ctx, bounds) {
                        final width = bounds.maxWidth;
                        final itemWidth = width < 620
                            ? width
                            : (width - 14) / 2;
                        return Wrap(
                          spacing: 14,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: itemWidth,
                              child: DropdownButtonFormField<int>(
                                key: ValueKey('branch_$selectedBranch'),
                                initialValue: selectedBranch,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Sucursal',
                                ),
                                items: [
                                  for (final branch in branches)
                                    DropdownMenuItem(
                                      value: intVal(branch['id']),
                                      child: Text(
                                        '${branch['name']}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) =>
                                    setState(() => selectedBranch = v),
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: DropdownButtonFormField<int>(
                                key: ValueKey('supplier_$selectedSupplier'),
                                initialValue: selectedSupplier,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Proveedor',
                                ),
                                items: [
                                  for (final supplier in suppliers)
                                    DropdownMenuItem(
                                      value: intVal(supplier['id']),
                                      child: Text(
                                        '${supplier['name']}',
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                ],
                                onChanged: (v) =>
                                    setState(() => selectedSupplier = v),
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: TextField(
                                controller: reference,
                                decoration: const InputDecoration(
                                  labelText:
                                      'Referencia del proveedor (opcional)',
                                ),
                              ),
                            ),
                            SizedBox(
                              width: itemWidth,
                              child: TextField(
                                controller: notes,
                                decoration: const InputDecoration(
                                  labelText: 'Observaciones (opcional)',
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 13),
                    for (final line in draft)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${line.name} · ${line.quantity} × L ${line.cost}',
                                style: const TextStyle(fontSize: 15),
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  setState(() => draft.remove(line)),
                              icon: const Icon(Icons.close),
                              tooltip: 'Retirar artículo',
                            ),
                          ],
                        ),
                      ),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        OutlinedButton.icon(
                          onPressed: addItem,
                          icon: const Icon(Icons.add),
                          label: const Text('Agregar artículo'),
                        ),
                        FilledButton.icon(
                          onPressed: submitting || draft.isEmpty
                              ? null
                              : create,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(
                            submitting ? 'Guardando...' : 'Crear orden',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Actualizar'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              LayoutBuilder(
                builder: (ctx, bounds) {
                  final wide = bounds.maxWidth >= 850;
                  final history = box(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Órdenes recientes',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 11),
                        if (orders.isEmpty)
                          Text(
                            'Aún no hay compras registradas.',
                            style: TextStyle(color: muted),
                          ),
                        // El ListTile requiere Material sobre la tarjeta decorada.
                        for (final order in orders)
                          Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(
                                '${order['number']} · ${money(order['total'])}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                '${order['status']} · ${order['created_at']}',
                                style: TextStyle(color: muted),
                              ),
                              trailing: Icon(
                                Icons.chevron_right,
                                color: accent,
                              ),
                              onTap: () => inspect(intVal(order['id'])),
                            ),
                          ),
                      ],
                    ),
                  );
                  final current = box(
                    selected == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Detalle de orden',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Selecciona una orden para ver recepciones y pendientes.',
                                style: TextStyle(color: muted),
                              ),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Orden ${((selected['order'] as Map)['number'])}',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Estado: ${((selected['order'] as Map)['status'])}',
                                style: TextStyle(color: muted),
                              ),
                              const Divider(height: 24),
                              for (final line in asList(selected['lines']))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 13),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${line['name_snapshot']}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Text(
                                        'Pedido ${line['ordered_quantity']} · recibido ${line['received_quantity']} · ${money(line['line_total'])}',
                                        style: TextStyle(
                                          color: muted,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              Text(
                                'Recepciones registradas: ${asList(selected['receipts']).length}',
                                style: TextStyle(color: muted),
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  if (['ORDERED', 'PARTIAL'].contains(
                                    '${(selected['order'] as Map)['status']}',
                                  ))
                                    FilledButton.icon(
                                      onPressed: submitting ? null : receive,
                                      icon: const Icon(
                                        Icons.inventory_2_outlined,
                                      ),
                                      label: const Text('Registrar recepción'),
                                    ),
                                  if ('${(selected['order'] as Map)['status']}' ==
                                      'ORDERED')
                                    OutlinedButton.icon(
                                      onPressed: submitting
                                          ? null
                                          : cancelOrder,
                                      icon: const Icon(Icons.cancel_outlined),
                                      label: const Text('Cancelar orden'),
                                    ),
                                ],
                              ),
                            ],
                          ),
                  );
                  if (!wide) {
                    return Column(
                      children: [history, const SizedBox(height: 14), current],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: history),
                      const SizedBox(width: 14),
                      Expanded(child: current),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Las órdenes no afectan caja ni existencias hasta confirmar una recepción. '
                'Las devoluciones, pagos a proveedores y correcciones requieren un procedimiento separado.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
