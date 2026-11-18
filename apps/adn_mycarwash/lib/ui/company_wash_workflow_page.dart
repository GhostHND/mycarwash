import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import 'company_sale_checkout_dialog.dart';
import 'company_service_price_label_24f4.dart';
import 'company_workflow_cards_24f.dart';
import 'company_wash_orders_cards_24e.dart';

enum WashModule { bays, orders, assignments, queue }

class CompanyWashWorkflowPage extends StatefulWidget {
  const CompanyWashWorkflowPage({
    super.key,
    required this.module,
    this.client,
    this.onCheckoutInPos,
  });

  final WashModule module;
  final http.Client? client;
  final ValueChanged<Map<String, dynamic>>? onCheckoutInPos;

  @override
  State<CompanyWashWorkflowPage> createState() =>
      _CompanyWashWorkflowPageState();
}

class _CompanyWashWorkflowPageState extends State<CompanyWashWorkflowPage> {
  static const _turquoise = Color(0xFF0FA7B4);
  static const _muted = Color(0xFF9BAEB6);
  static const _surface = Color(0xFF0A1519);
  static const _border = Color(0xFF20343C);

  late final http.Client _client;
  late final bool _ownsClient;
  final _search = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];
  int _page = 1;
  int _pages = 1;
  int _version = 0;
  String _ordersFilter24E = 'TODAS';
  Map<String, dynamic> _ordersSummary24E = {};

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  String get _resource => switch (widget.module) {
    WashModule.bays => 'bays',
    WashModule.orders => 'orders',
    WashModule.assignments => 'assignments',
    WashModule.queue => 'queue',
  };
  String get _title => switch (widget.module) {
    WashModule.bays => 'Puestos de lavado',
    WashModule.orders => 'Órdenes de lavado',
    WashModule.assignments => 'Asignaciones de lavadores',
    WashModule.queue => 'Cola operativa',
  };
  String get _path => '/workflow/$_resource';

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyWashWorkflowPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.module != widget.module) {
      _page = 1;
      _search.clear();
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
      Map<String, dynamic> result;
      if (widget.module == WashModule.orders) {
        result = await _api.request(
          'GET',
          '/workflow/orders-board-24e',
          query: {
            'q': _search.text.trim(),
            'status': _ordersFilter24E,
            'page': '$_page',
            'per_page': '9',
          },
        );
      } else if (widget.module == WashModule.queue) {
        final b = await _api.request('GET', '/workflow/branches');
        final branches = (b['data'] as List?)?.whereType<Map>().toList() ?? [];
        if (branches.isEmpty) {
          if (!mounted || version != _version) {
            return;
          }
          setState(() {
            _rows = [];
            _loading = false;
            _error = 'Esta empresa no tiene una sucursal activa.';
          });
          return;
        }
        result = await _api.request(
          'GET',
          '/workflow/queue',
          query: {'branch_id': '${branches.first['id']}'},
        );
      } else {
        result = await _api.request(
          'GET',
          _path,
          query: {'q': _search.text.trim(), 'page': '$_page', 'per_page': '10'},
        );
      }
      if (!mounted || version != _version) {
        return;
      }
      final list = result['data'];
      setState(() {
        _rows = list is List
            ? list
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : [];
        if (widget.module == WashModule.orders) {
          _ordersSummary24E = result['summary'] is Map
              ? Map<String, dynamic>.from(result['summary'] as Map)
              : <String, dynamic>{};
        }
        _page = int.tryParse('${result['current_page'] ?? 1}') ?? 1;
        _pages = int.tryParse('${result['last_page'] ?? 1}') ?? 1;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || version != _version) {
        return;
      }
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _onSearch(String value) {
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
      ),
    );
  }

  InputDecoration _decor(String text) => InputDecoration(
    labelText: text,
    filled: true,
    fillColor: const Color(0xFF111F25),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  Future<List<Map<String, dynamic>>> _lookup(String path) async {
    final result = await _api.request(
      'GET',
      path,
      query: {if (path != '/workflow/branches') 'per_page': '50'},
    );
    final list = result['data'];
    return list is List
        ? list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
        : [];
  }

  Future<Map<String, List<Map<String, dynamic>>>> _options() async {
    final all = await Future.wait([
      _lookup('/workflow/branches'),
      _lookup('/vehicles'),
      _lookup('/services'),
      _lookup('/employees'),
      _lookup('/workflow/bays'),
      _lookup('/workflow/orders'),
    ]);
    return {
      'branches': all[0],
      'vehicles': all[1],
      'services': all[2],
      'employees': all[3],
      'bays': all[4],
      'orders': all[5],
    };
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    if (widget.module == WashModule.queue) {
      return;
    }
    final form = GlobalKey<FormState>();
    final name = TextEditingController(text: '${existing?['name'] ?? ''}');
    final code = TextEditingController(text: '${existing?['code'] ?? ''}');
    final notes = TextEditingController(text: '${existing?['notes'] ?? ''}');
    final function = TextEditingController(
      text: '${existing?['function'] ?? 'lavado'}',
    );
    bool active =
        existing?['is_active'] != false && existing?['is_active'] != 0;
    bool primary =
        existing?['is_primary'] == true || existing?['is_primary'] == 1;
    int? branch = int.tryParse('${existing?['branch_id'] ?? ''}');
    int? vehicle = int.tryParse('${existing?['vehicle_id'] ?? ''}');
    int? service = int.tryParse('${existing?['service_id'] ?? ''}');
    int? bay = int.tryParse('${existing?['bay_id'] ?? ''}');
    int? order = int.tryParse('${existing?['order_id'] ?? ''}');
    int? employee = int.tryParse('${existing?['employee_id'] ?? ''}');
    bool busy = false;
    String? error;
    final lookup = _options();
    try {
      final route = DialogRoute<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (ctx, update) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              existing == null
                  ? 'Nuevo registro · $_title'
                  : 'Editar · $_title',
            ),
            content: SizedBox(
              width: 580,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                    future: lookup,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.all(30),
                            child: CircularProgressIndicator(color: _turquoise),
                          ),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text(
                          '${snapshot.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        );
                      }
                      final maps = snapshot.data!;
                      Widget choice({
                        required String title,
                        required String listName,
                        required int? value,
                        required ValueChanged<int?> setValue,
                        required String Function(Map<String, dynamic>) label,
                        bool requiredField = true,
                      }) {
                        final options = maps[listName]!
                            .where(
                              (e) =>
                                  e['is_active'] != false &&
                                  e['is_active'] != 0,
                            )
                            .toList();
                        final safe =
                            options.any(
                              (e) => int.tryParse('${e['id']}') == value,
                            )
                            ? value
                            : null;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('workflow_${listName}_$safe'),
                            initialValue: safe,
                            isExpanded: true,
                            dropdownColor: _surface,
                            decoration: _decor(title),
                            items: options
                                .map(
                                  (e) => DropdownMenuItem<int>(
                                    value: int.tryParse('${e['id']}'),
                                    child: Text(
                                      label(e),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: busy
                                ? null
                                : (v) => update(() => setValue(v)),
                            validator: (v) => requiredField && v == null
                                ? 'Selecciona una opción.'
                                : null,
                          ),
                        );
                      }

                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (widget.module == WashModule.bays) ...[
                            if (existing == null)
                              choice(
                                title: 'Sucursal',
                                listName: 'branches',
                                value: branch,
                                setValue: (v) => branch = v,
                                label: (e) => '${e['name']}',
                              ),
                            TextFormField(
                              controller: name,
                              decoration: _decor('Nombre del puesto'),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Obligatorio.'
                                  : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: code,
                              decoration: _decor('Código de puesto'),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Obligatorio.'
                                  : null,
                            ),
                            SwitchListTile(
                              title: const Text('Activo'),
                              value: active,
                              onChanged: busy
                                  ? null
                                  : (v) => update(() => active = v),
                            ),
                          ],
                          if (widget.module == WashModule.orders) ...[
                            if (existing == null) ...[
                              choice(
                                title: 'Sucursal',
                                listName: 'branches',
                                value: branch,
                                setValue: (v) => branch = v,
                                label: (e) => '${e['name']}',
                              ),
                              choice(
                                title: 'Vehículo',
                                listName: 'vehicles',
                                value: vehicle,
                                setValue: (v) => vehicle = v,
                                label: (e) =>
                                    '${e['plate'] ?? 'Sin placa'} · ${e['brand'] ?? ''} ${e['model'] ?? ''}',
                              ),
                              choice(
                                title: 'Servicio',
                                listName: 'services',
                                value: service,
                                setValue: (v) => service = v,
                                label: (e) => servicePriceLabel24F4(
                                  e,
                                  vehicle,
                                  maps['vehicles']!,
                                ),
                              ),
                            ],
                            choice(
                              title: 'Puesto de lavado (opcional)',
                              listName: 'bays',
                              value: bay,
                              setValue: (v) => bay = v,
                              label: (e) => '${e['name']} (${e['code']})',
                              requiredField: false,
                            ),
                          ],
                          if (widget.module == WashModule.assignments) ...[
                            if (existing == null) ...[
                              choice(
                                title: 'Orden de lavado',
                                listName: 'orders',
                                value: order,
                                setValue: (v) => order = v,
                                label: (e) =>
                                    '${e['tracking_code']} · ${e['status']}',
                              ),
                              choice(
                                title: 'Lavador',
                                listName: 'employees',
                                value: employee,
                                setValue: (v) => employee = v,
                                label: (e) =>
                                    '${e['full_name']} · ${e['position']}',
                              ),
                            ],
                            TextFormField(
                              controller: function,
                              decoration: _decor('Función en el lavado'),
                              validator: (v) => (v ?? '').trim().isEmpty
                                  ? 'Obligatorio.'
                                  : null,
                            ),
                            SwitchListTile(
                              title: const Text('Lavador principal'),
                              value: primary,
                              onChanged: busy
                                  ? null
                                  : (v) => update(() => primary = v),
                            ),
                          ],
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: notes,
                            maxLines: 3,
                            decoration: _decor('Observaciones (opcional)'),
                          ),
                          if (error != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                error!,
                                style: const TextStyle(color: Colors.redAccent),
                              ),
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
                onPressed: busy
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                key: const ValueKey('workflow_save'),
                onPressed: busy
                    ? null
                    : () async {
                        if (!(form.currentState?.validate() ?? false)) {
                          return;
                        }
                        final payload = <String, dynamic>{
                          'notes': notes.text.trim().isEmpty
                              ? null
                              : notes.text.trim(),
                        };
                        if (widget.module == WashModule.bays) {
                          payload.addAll({
                            'name': name.text.trim(),
                            'code': code.text.trim(),
                            'is_active': active,
                          });
                          if (existing == null) {
                            payload['branch_id'] = branch;
                          }
                        } else if (widget.module == WashModule.orders) {
                          payload['bay_id'] = bay;
                          if (existing == null) {
                            payload.addAll({
                              'branch_id': branch,
                              'vehicle_id': vehicle,
                              'service_id': service,
                            });
                          }
                        } else {
                          payload.addAll({
                            'function': function.text.trim(),
                            'is_primary': primary,
                          });
                          if (existing == null) {
                            payload.addAll({
                              'order_id': order,
                              'employee_id': employee,
                            });
                          }
                        }
                        update(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await _api.request(
                            existing == null ? 'POST' : 'PATCH',
                            existing == null
                                ? _path
                                : '$_path/${existing['id']}',
                            body: payload,
                          );
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            update(() {
                              busy = false;
                              error = '$e';
                            });
                          }
                        }
                      },
                child: Text(busy ? 'Guardando...' : 'Guardar'),
              ),
            ],
          ),
        ),
      );
      final result = await Navigator.of(
        context,
        rootNavigator: true,
      ).push<bool>(route);
      await route.completed;
      if (result == true && mounted) {
        _notice('Cambios guardados.');
        _load();
      }
    } finally {
      name.dispose();
      code.dispose();
      notes.dispose();
      function.dispose();
    }
  }

  Future<void> _delete(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.module == WashModule.orders
              ? 'Cancelar orden'
              : 'Archivar o liberar',
        ),
        content: const Text(
          'Esta operación conservará el historial. ¿Continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) {
      return;
    }
    try {
      await _api.request('DELETE', '$_path/${row['id']}');
      _notice('Operación completada.');
      _load();
    } catch (e) {
      _notice('$e', error: true);
    }
  }

  Future<void> _advance(Map<String, dynamic> row) async {
    final next = switch ('${row['status']}') {
      'ASIGNADO' => 'EN_PROCESO',
      'EN_PROCESO' => 'TERMINADO',
      'TERMINADO' => 'ENTREGADO',
      _ => null,
    };
    if (next == null) {
      return;
    }
    if (next == 'ENTREGADO' && widget.onCheckoutInPos != null) {
      widget.onCheckoutInPos!(row);
      return;
    }
    if (next == 'ENTREGADO') {
      final completed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialog) =>
            CompanySaleCheckoutDialog(order: row, client: _client),
      );
      if (completed == true && mounted) {
        _notice('Cobro registrado y vehículo entregado.');
        _load();
      }
      return;
    }
    try {
      await _api.request(
        'POST',
        '$_path/${row['id']}/transition',
        body: {'to_status': next, 'expected_version': row['version']},
      );
      _notice('Orden actualizada: $next');
      _load();
    } catch (e) {
      _notice('$e', error: true);
      _load();
    }
  }

  String _display(Map<String, dynamic> row) => switch (widget.module) {
    WashModule.bays => '${row['code']} · ${row['name']}',
    WashModule.orders ||
    WashModule.queue => '${row['tracking_code']} · ${row['vehicle_label']}',
    WashModule.assignments =>
      '${row['employee_name']} · Orden ${row['order_id']}',
  };

  String _detail(Map<String, dynamic> row) => switch (widget.module) {
    WashModule.bays =>
      'Sucursal ${row['branch_id']} · ${row['is_active'] == false ? 'Inactivo' : 'Activo'}',
    WashModule.orders || WashModule.queue =>
      '${row['service_name']} · ${row['status']} · ${row['quoted_price']}',
    WashModule.assignments =>
      '${row['function']} · ${row['is_active'] == false || row['is_active'] == 0 ? 'Liberado' : 'Activo'}',
  };

  Widget _ordersBoard24E() => CompanyWashOrdersCards24E(
    orders: _rows,
    summary: _ordersSummary24E,
    loading: _loading,
    error: _error,
    search: _search,
    filter: _ordersFilter24E,
    page: _page,
    pages: _pages,
    onSearch: _onSearch,
    onFilter: (state) {
      if (state == _ordersFilter24E) return;
      setState(() {
        _ordersFilter24E = state;
        _page = 1;
      });
      _load();
    },
    onCreate: () => _edit(),
    onRefresh: _load,
    onPage: (newPage) {
      _page = newPage;
      _load();
    },
    onEdit: (order) => _edit(order),
    onDetail: (order) => _orderDetail24E(order),
    onDelete: (order) => _delete(order),
    onAdvance: (order) => _advance(order),
  );

  Future<void> _orderDetail24E(Map<String, dynamic> order) async {
    final code = '${order['tracking_code'] ?? ''}';
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Orden $code'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Cliente: ${order['client_name'] ?? 'Sin cliente'}'),
                Text('Vehículo: ${order['vehicle_label'] ?? ''}'),
                Text('Placa: ${order['plate'] ?? 'Sin placa'}'),
                Text('Servicio: ${order['service_name'] ?? ''}'),
                Text('Bahía: ${order['bay_name'] ?? 'Sin bahía'}'),
                Text('Estado real: ${order['status'] ?? ''}'),
                Text('Inicio: ${order['started_at'] ?? 'Sin iniciar'}'),
                Text(
                  'Finalización: ${order['completed_at'] ?? 'Sin terminar'}',
                ),
                Text('Importe cotizado: L ${order['quoted_price'] ?? ''}'),
                const SizedBox(height: 12),
                FutureBuilder<Map<String, dynamic>>(
                  future: _api.request(
                    'GET',
                    '/workflow/orders/${order['id']}/history',
                  ),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.hasError) {
                      return Text('Historial no disponible: ${snapshot.error}');
                    }
                    final events = snapshot.data?['data'];
                    if (events is! List || events.isEmpty) {
                      return const Text('Sin eventos de historial.');
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Historial',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        for (final event in events.whereType<Map>())
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              '${event['from_status'] ?? 'Inicio'} → ${event['to_status']}',
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.module == WashModule.orders
      ? _ordersBoard24E()
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  _title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.module != WashModule.queue)
                  FilledButton.icon(
                    key: const ValueKey('workflow_create'),
                    onPressed: () => _edit(),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo registro'),
                  ),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_outlined),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (widget.module != WashModule.queue)
              TextField(
                controller: _search,
                onChanged: _onSearch,
                decoration: _decor('Buscar'),
              ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              width: double.infinity,
              decoration: BoxDecoration(
                color: _surface,
                border: Border.all(color: _border),
                borderRadius: BorderRadius.circular(14),
              ),
              child: _loading
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: CircularProgressIndicator(color: _turquoise),
                      ),
                    )
                  : _error != null
                  ? Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    )
                  : _rows.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('Sin registros para mostrar.')),
                    )
                  : widget.module == WashModule.bays ||
                        widget.module == WashModule.assignments ||
                        widget.module == WashModule.queue
                  ? CompanyWorkflowCards24F(
                      module: _resource,
                      records: _rows,
                      onEdit: (record) => _edit(record),
                      onArchive: (record) => _delete(record),
                    )
                  : Column(
                      children: [
                        for (final row in _rows) ...[
                          ListTile(
                            leading: const Icon(
                              Icons.local_car_wash_outlined,
                              color: _turquoise,
                            ),
                            title: Text(
                              _display(row),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              _detail(row),
                              style: const TextStyle(color: _muted),
                            ),
                            trailing: widget.module == WashModule.queue
                                ? null
                                : Wrap(
                                    spacing: 0,
                                    children: [
                                      if (widget.module == WashModule.orders &&
                                          [
                                            'ASIGNADO',
                                            'EN_PROCESO',
                                            'TERMINADO',
                                          ].contains('${row['status']}'))
                                        IconButton(
                                          tooltip: row['status'] == 'TERMINADO'
                                              ? 'Cobrar y entregar'
                                              : 'Avanzar estado',
                                          onPressed: () => _advance(row),
                                          icon: const Icon(
                                            Icons.play_circle_outline,
                                            color: _turquoise,
                                          ),
                                        ),
                                      IconButton(
                                        tooltip: 'Editar',
                                        onPressed: () => _edit(row),
                                        icon: const Icon(
                                          Icons.edit_outlined,
                                          color: _turquoise,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip:
                                            widget.module == WashModule.orders
                                            ? 'Cancelar'
                                            : 'Archivar o liberar',
                                        onPressed: () => _delete(row),
                                        icon: const Icon(
                                          Icons.archive_outlined,
                                          color: Colors.redAccent,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          const Divider(color: _border),
                        ],
                        if (widget.module != WashModule.queue)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                onPressed: _page <= 1
                                    ? null
                                    : () {
                                        _page--;
                                        _load();
                                      },
                                icon: const Icon(Icons.chevron_left),
                              ),
                              Text('Página $_page / $_pages'),
                              IconButton(
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
            ),
          ],
        );
}
