import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// Smart POS 21A: venta de artículos, carrito, pagos mixtos e historial.
/// Los importes que se muestran en el carrito son indicativos; Laravel calcula
/// y verifica todos los importes, existencias y destinos al confirmar.
class CompanySmartPosPage extends StatefulWidget {
  const CompanySmartPosPage({
    super.key,
    this.client,
    this.initialHistory = false,
  });
  final http.Client? client;
  final bool initialHistory;

  @override
  State<CompanySmartPosPage> createState() => _CompanySmartPosPageState();
}

class _CompanySmartPosPageState extends State<CompanySmartPosPage> {
  static const _teal = Color(0xFF0FA7B4);
  static const _panel = Color(0xFF0D1A1F);
  static const _muted = Color(0xFF9CB1BB);
  late final http.Client _client;
  late final bool _ownsClient;
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  final _search = TextEditingController();
  final _discount = TextEditingController(text: '0.00');
  final _reason = TextEditingController();
  final _cash = TextEditingController();
  final _bank = TextEditingController();
  final _bankReference = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _saving = false;
  bool _history = false;
  String? _error;
  int _epoch = 0;
  int? _branchId;
  int? _cashSessionId;
  int? _bankAccountId;
  int? _cashMethodId;
  int? _bankMethodId;
  String? _checkoutKey;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _banks = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _sales = [];
  final Map<int, int> _cart = {};
  final Map<int, Map<String, dynamic>> _chosen = {};

  @override
  void initState() {
    super.initState();
    _history = widget.initialHistory;
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _search.addListener(_scheduleSearch);
    _loadOptions();
  }

  @override
  void dispose() {
    _epoch++;
    _debounce?.cancel();
    for (final field in [
      _search,
      _discount,
      _reason,
      _cash,
      _bank,
      _bankReference,
    ]) {
      field.dispose();
    }
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), _loadProducts);
  }

  static List<Map<String, dynamic>> _rows(dynamic raw) {
    if (raw is! List) {
      return [];
    }
    return raw
        .whereType<Map>()
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
  }

  int? _asInt(dynamic value) => int.tryParse('$value');
  int _cents(String? value) {
    final m = RegExp(r'^([0-9]+)(?:\.([0-9]{1,2}))?$')
        .firstMatch((value ?? '').trim());
    if (m == null) {
      return -1;
    }
    return (int.tryParse(m.group(1) ?? '') ?? 0) * 100 +
        int.parse((m.group(2) ?? '').padRight(2, '0'));
  }

  String _money(int cents) {
    if (cents < 0) {
      return '—';
    }
    return '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';
  }

  int get _subtotal {
    var result = 0;
    for (final entry in _cart.entries) {
      result +=
          (_cents('${_chosen[entry.key]?['sale_price'] ?? '0'}') * entry.value);
    }
    return result;
  }

  int get _total => _subtotal - _cents(_discount.text);

  void _message(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFF963A47)
            : const Color(0xFF126E75),
      ),
    );
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.request('GET', '/pos/options');
      final raw = Map<String, dynamic>.from(response['data'] as Map);
      final branches = _rows(raw['branches']);
      final methods = _rows(raw['methods']);
      if (!mounted) {
        return;
      }
      setState(() {
        _branches = branches;
        _sessions = _rows(raw['sessions']);
        _banks = _rows(raw['banks']);
        _cashMethodId = methods
            .where((x) => x['channel'] == 'CASH')
            .map((x) => _asInt(x['id']))
            .firstOrNull;
        _bankMethodId = methods
            .where((x) => x['channel'] == 'BANK')
            .map((x) => _asInt(x['id']))
            .firstOrNull;
        _branchId = branches.isNotEmpty ? _asInt(branches.first['id']) : null;
        _loading = false;
      });
      _chooseBranch(_branchId);
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _chooseBranch(int? branch) {
    final sessions = _sessions
        .where((x) => _asInt(x['branch_id']) == branch)
        .toList();
    final banks = _banks
        .where((x) => _asInt(x['branch_id']) == branch)
        .toList();
    setState(() {
      _branchId = branch;
      _cashSessionId = sessions.isNotEmpty
          ? _asInt(sessions.first['id'])
          : null;
      _bankAccountId = banks.isNotEmpty ? _asInt(banks.first['id']) : null;
      _cart.clear();
      _chosen.clear();
      _cash.clear();
      _bank.clear();
      _discount.text = '0.00';
      _reason.clear();
      _checkoutKey = null;
    });
    _loadProducts();
    if (_history) {
      _loadSales();
    }
  }

  Future<void> _loadProducts() async {
    final branch = _branchId;
    if (branch == null) {
      return;
    }
    final epoch = ++_epoch;
    try {
      final response = await _api.request(
        'GET',
        '/pos/products',
        query: {'branch_id': '$branch', 'q': _search.text.trim()},
      );
      if (!mounted || epoch != _epoch) {
        return;
      }
      setState(() => _products = _rows(response['data']));
    } catch (e) {
      if (!mounted || epoch != _epoch) {
        return;
      }
      _message('No se pudo cargar el catálogo: $e', error: true);
    }
  }

  Future<void> _loadSales() async {
    final branch = _branchId;
    if (branch == null) {
      return;
    }
    try {
      final response = await _api.request(
        'GET',
        '/pos/sales',
        query: {'branch_id': '$branch'},
      );
      if (!mounted) {
        return;
      }
      setState(() => _sales = _rows(response['data']));
    } catch (e) {
      _message('No se pudo cargar el historial: $e', error: true);
    }
  }

  void _add(Map<String, dynamic> item) {
    final id = _asInt(item['id']);
    if (id == null) {
      return;
    }
    final stock = double.tryParse('${item['stock']}') ?? 0;
    final next = (_cart[id] ?? 0) + 1;
    if (stock < next) {
      _message('Sin existencias suficientes.', error: true);
      return;
    }
    setState(() {
      _chosen[id] = item;
      _cart[id] = next;
      _checkoutKey = null;
    });
  }

  void _adjust(int id, int change) {
    final amount = (_cart[id] ?? 0) + change;
    final available = double.tryParse('${_chosen[id]?['stock'] ?? '0'}') ?? 0;
    if (amount > available) {
      _message('Existencias insuficientes.', error: true);
      return;
    }
    setState(() {
      if (amount <= 0) {
        _cart.remove(id);
        _chosen.remove(id);
      } else {
        _cart[id] = amount;
      }
      _checkoutKey = null;
    });
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF20353D)),
        ),
        child: child,
      );

  InputDecoration _dec(String name) => InputDecoration(
    labelText: name,
    border: const OutlineInputBorder(),
    isDense: true,
  );

  Widget _catalog() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Catálogo y existencias',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        TextField(
          key: const ValueKey('pos_search'),
          controller: _search,
          decoration: _dec('Buscar por nombre o SKU'),
        ),
        const SizedBox(height: 10),
        if (_products.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No hay productos con precio de venta.',
              style: TextStyle(color: _muted),
            ),
          ),
        for (final item in _products)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${item['name']}'),
              subtitle: Text(
                '${item['sku']} · Stock: ${item['stock']} ${item['unit']}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
              trailing: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    'L ${item['sale_price']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    tooltip: 'Agregar al carrito',
                    icon: const Icon(Icons.add_circle_outline),
                    color: _teal,
                    onPressed: (double.tryParse('${item['stock']}') ?? 0) >= 1
                        ? () => _add(item)
                        : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );

  Widget _cartPanel() {
    final sessionOptions = _sessions
        .where((x) => _asInt(x['branch_id']) == _branchId)
        .toList();
    final bankOptions = _banks
        .where((x) => _asInt(x['branch_id']) == _branchId)
        .toList();
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Carrito de venta',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_cart.isEmpty)
            const Text(
              'Agrega productos desde el catálogo.',
              style: TextStyle(color: _muted),
            ),
          for (final row in _cart.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${_chosen[row.key]?['name']}', maxLines: 2),
                        Text(
                          'L ${_chosen[row.key]?['sale_price']} c/u',
                          style: const TextStyle(fontSize: 12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _adjust(row.key, -1),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('${row.value}'),
                  IconButton(
                    onPressed: () => _adjust(row.key, 1),
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          const Divider(),
          Text('Subtotal: L ${_money(_subtotal)}'),
          const SizedBox(height: 10),
          TextField(
            controller: _discount,
            key: const ValueKey('pos_discount'),
            decoration: _dec('Descuento autorizado (L)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() => _checkoutKey = null),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            decoration: _dec('Motivo del descuento'),
            onChanged: (_) => _checkoutKey = null,
          ),
          const SizedBox(height: 12),
          Text(
            'Total: L ${_money(_total)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _teal,
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Cobrar mediante',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _cash.text = _money(_total);
              _bank.clear();
              _checkoutKey = null;
            }),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Todo efectivo'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => setState(() {
              _bank.text = _money(_total);
              _cash.clear();
              _checkoutKey = null;
            }),
            icon: const Icon(Icons.account_balance_outlined),
            label: const Text('Todo banco'),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('pos_cash_amount'),
            controller: _cash,
            decoration: _dec('Efectivo (L)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _checkoutKey = null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey("pos_cash_session_$_branchId"),
            initialValue: _cashSessionId,
            decoration: _dec('Caja abierta'),
            items: sessionOptions
                .map(
                  (x) => DropdownMenuItem<int>(
                    value: _asInt(x['id']),
                    child: Text('${x['name']}'),
                  ),
                )
                .toList(),
            onChanged: (x) => setState(() {
              _cashSessionId = x;
              _checkoutKey = null;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pos_bank_amount'),
            controller: _bank,
            decoration: _dec('Transferencia (L)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => _checkoutKey = null,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<int>(
            key: ValueKey("pos_bank_account_$_branchId"),
            initialValue: _bankAccountId,
            decoration: _dec('Cuenta bancaria'),
            items: bankOptions
                .map(
                  (x) => DropdownMenuItem<int>(
                    value: _asInt(x['id']),
                    child: Text('${x['alias']}'),
                  ),
                )
                .toList(),
            onChanged: (x) => setState(() {
              _bankAccountId = x;
              _checkoutKey = null;
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _bankReference,
            decoration: _dec('Referencia de transferencia'),
            onChanged: (_) => _checkoutKey = null,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('pos_checkout'),
            style: FilledButton.styleFrom(backgroundColor: _teal),
            onPressed: _saving || _cart.isEmpty ? null : _checkout,
            icon: const Icon(Icons.check_circle_outline),
            label: Text(
              _saving ? 'Registrando...' : 'Confirmar venta y cobrar',
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Comprobante interno no fiscal. No sustituye una factura autorizada.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _checkout() async {
    final branch = _branchId;
    if (branch == null || _cart.isEmpty || _total <= 0) {
      _message(
        'Selecciona sucursal y artículos con total positivo.',
        error: true,
      );
      return;
    }
    final discount = _cents(_discount.text);
    final cash = _cash.text.trim().isEmpty ? 0 : _cents(_cash.text);
    final bank = _bank.text.trim().isEmpty ? 0 : _cents(_bank.text);
    if (discount < 0 || cash < 0 || bank < 0 || cash + bank != _total) {
      _message('Los pagos deben sumar exactamente el total.', error: true);
      return;
    }
    if (discount > 0 && _reason.text.trim().length < 3) {
      _message('Indica el motivo del descuento.', error: true);
      return;
    }
    if ((cash > 0 && (_cashMethodId == null || _cashSessionId == null)) ||
        (bank > 0 && (_bankMethodId == null || _bankAccountId == null))) {
      _message(
        'Configura un medio de pago y una cuenta o caja abierta.',
        error: true,
      );
      return;
    }
    final paymentRows = <Map<String, dynamic>>[];
    if (cash > 0) {
      paymentRows.add({
        'payment_method_id': _cashMethodId,
        'cash_session_id': _cashSessionId,
        'amount': _money(cash),
      });
    }
    if (bank > 0) {
      paymentRows.add({
        'payment_method_id': _bankMethodId,
        'bank_account_id': _bankAccountId,
        'amount': _money(bank),
        'reference': _bankReference.text.trim(),
      });
    }
    _checkoutKey ??=
        'pos-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    setState(() => _saving = true);
    try {
      final response = await _api.request(
        'POST',
        '/pos/sales',
        body: {
          'branch_id': branch,
          'idempotency_key': _checkoutKey,
          'lines': _cart.entries
              .map((x) => {'item_id': x.key, 'quantity': x.value})
              .toList(),
          'discount_amount': _money(discount),
          'discount_reason': _reason.text.trim(),
          'payments': paymentRows,
        },
      );
      if (!mounted) {
        return;
      }
      final receipt = Map<String, dynamic>.from(response['data'] as Map);
      setState(() {
        _cart.clear();
        _chosen.clear();
        _checkoutKey = null;
        _discount.text = '0.00';
        _reason.clear();
        _cash.clear();
        _bank.clear();
        _bankReference.clear();
      });
      _loadProducts();
      await _showReceipt(receipt);
    } catch (e) {
      _message('No se confirmó la venta: $e', error: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  String _receiptText(Map<String, dynamic> sale) {
    final b = StringBuffer('ADN MyCarWash — COMPROBANTE NO FISCAL\n');
    b.writeln('Venta #${sale['id']} — ${sale['posted_at']}');
    b.writeln('--------------------------------------');
    for (final line in _rows(sale['lines'])) {
      b.writeln(
        '${line['name_snapshot']} x${line['quantity']}   L ${line['line_total']}',
      );
    }
    b.writeln('Subtotal: L ${sale['subtotal']}');
    b.writeln('Descuento: L ${sale['discount_amount']}');
    b.writeln('TOTAL: L ${sale['total']}');
    for (final payment in _rows(sale['payments'])) {
      b.writeln('${payment['channel']}: L ${payment['amount']}');
    }
    b.writeln('No constituye factura fiscal.');
    return b.toString();
  }

  Future<void> _showReceipt(Map<String, dynamic> receipt) async {
    final text = _receiptText(receipt);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Venta #${receipt['id']} confirmada'),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (context.mounted) {
                Navigator.of(context).pop();
              }
              _message('Comprobante copiado.');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  Future<void> _viewSale(int id) async {
    try {
      final response = await _api.request('GET', '/pos/sales/$id');
      if (!mounted) {
        return;
      }
      await _showReceipt(Map<String, dynamic>.from(response['data'] as Map));
    } catch (e) {
      _message('No se pudo consultar el comprobante: $e', error: true);
    }
  }

  Widget _historyPanel() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Historial de ventas',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(onPressed: _loadSales, icon: const Icon(Icons.refresh)),
          ],
        ),
        const SizedBox(height: 12),
        if (_sales.isEmpty)
          const Text(
            'No hay ventas registradas.',
            style: TextStyle(color: _muted),
          ),
        for (final sale in _sales)
          ListTile(
            title: Text('Venta #${sale['id']} · L ${sale['total']}'),
            subtitle: Text(
              '${sale['posted_at']} · ${sale['status']}',
              style: const TextStyle(color: _muted),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.receipt_long_outlined),
              tooltip: 'Consultar comprobante',
              onPressed: () => _viewSale(_asInt(sale['id']) ?? 0),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.redAccent)),
            TextButton(
              onPressed: _loadOptions,
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Smart POS',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 5),
        const Text(
          'Venta de artículos y accesorios · Inventario por sucursal',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 18),
        LayoutBuilder(
          builder: (context, head) {
            final branchSelector = DropdownButtonFormField<int>(
              initialValue: _branchId,
              decoration: _dec('Sucursal'),
              items: _branches
                  .map(
                    (x) => DropdownMenuItem<int>(
                      value: _asInt(x['id']),
                      child: Text('${x['name']}'),
                    ),
                  )
                  .toList(),
              onChanged: _chooseBranch,
            );
            final tabs = SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Nueva venta'),
                  icon: Icon(Icons.point_of_sale),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Historial'),
                  icon: Icon(Icons.history),
                ),
              ],
              selected: {_history},
              onSelectionChanged: (v) {
                setState(() => _history = v.first);
                if (_history) {
                  _loadSales();
                }
              },
            );
            if (head.maxWidth < 650) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [branchSelector, const SizedBox(height: 12), tabs],
              );
            }
            return Row(
              children: [
                Expanded(child: branchSelector),
                const SizedBox(width: 12),
                tabs,
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        if (_history)
          _historyPanel()
        else
          LayoutBuilder(
            builder: (context, bounds) {
              if (bounds.maxWidth < 880) {
                return Column(
                  children: [
                    _catalog(),
                    const SizedBox(height: 14),
                    _cartPanel(),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: _catalog()),
                  const SizedBox(width: 15),
                  Expanded(flex: 2, child: _cartPanel()),
                ],
              );
            },
          ),
      ],
    );
  }
}
