import 'dart:async';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import 'company_product_photo_24j.dart';
import 'company_pos_checkout_dialog.dart';
import 'company_pos_fiscal_settings_dialog.dart';
import 'company_pos_printing.dart';

/// Smart POS 21A: venta de artículos, carrito, pagos mixtos e historial.
/// Los importes que se muestran en el carrito son indicativos; Laravel calcula
/// y verifica todos los importes, existencias y destinos al confirmar.
class CompanySmartPosPage extends StatefulWidget {
  const CompanySmartPosPage({
    super.key,
    this.client,
    this.initialHistory = false,
    this.initialWashOrderId,
    this.onWashSaleCompleted,
  });
  final http.Client? client;
  final bool initialHistory;
  final int? initialWashOrderId;
  final VoidCallback? onWashSaleCompleted;

  @override
  State<CompanySmartPosPage> createState() => _CompanySmartPosPageState();
}

class _CompanySmartPosPageState extends State<CompanySmartPosPage> {
  static Color get _teal => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get _panel => CompanyVisualTheme.legacy(const Color(0xFF0D1A1F));
  static Color get _muted => CompanyVisualTheme.legacy(const Color(0xFF9CB1BB));
  late final http.Client _client;
  late final bool _ownsClient;
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  final _search = TextEditingController();
  final _discount = TextEditingController(text: '0.00');
  final _reason = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _history = false;
  String _documentType = 'RECEIPT';
  Map<String, dynamic>? _fiscalAuthorization;
  bool _fiscalLoading = false;
  String? _error;
  int _epoch = 0;
  int? _branchId;
  int? _cashMethodId;
  int? _bankMethodId;
  List<Map<String, dynamic>> _branches = [];
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _banks = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _sales = [];
  final Map<int, int> _cart = {};
  final Map<int, Map<String, dynamic>> _chosen = {};
  Map<String, dynamic>? _wash;

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
    for (final field in [_search, _discount, _reason]) {
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
    var result = _wash == null ? 0 : _cents('${_wash!['price']}');
    for (final entry in _cart.entries) {
      result +=
          (_cents('${_chosen[entry.key]?['sale_price'] ?? '0'}') * entry.value);
    }
    return result;
  }

  int get _net => _subtotal - _cents(_discount.text);
  int get _tax => _documentType == 'FISCAL_INVOICE' && _net > 0
      ? (_net * 15 + 50) ~/ 100
      : 0;
  int get _total => _net + _tax;
  bool get _fiscalReady => _fiscalAuthorization?['available'] == true;

  Future<void> _loadFiscalSettings() async {
    final branch = _branchId;
    if (branch == null) {
      return;
    }
    setState(() => _fiscalLoading = true);
    try {
      final response = await _api.request(
        'GET',
        '/pos/fiscal-settings',
        query: {'branch_id': '$branch'},
      );
      if (!mounted || _branchId != branch) {
        return;
      }
      final data = response['data'];
      setState(
        () => _fiscalAuthorization = data is Map
            ? Map<String, dynamic>.from(data)
            : null,
      );
    } catch (_) {
      if (mounted && _branchId == branch) {
        setState(() => _fiscalAuthorization = null);
      }
    } finally {
      if (mounted && _branchId == branch) {
        setState(() => _fiscalLoading = false);
      }
    }
  }

  Future<void> _configureFiscal() async {
    final branch = _branchId;
    if (branch == null) {
      return;
    }
    final done = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          CompanyPosFiscalSettingsDialog(api: _api, branchId: branch),
    );
    if (done == true && mounted) {
      await _loadFiscalSettings();
    }
  }

  void _message(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? CompanyVisualTheme.legacy(const Color(0xFF963A47))
            : CompanyVisualTheme.legacy(const Color(0xFF126E75)),
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
      Map<String, dynamic>? wash;
      if (widget.initialWashOrderId != null) {
        final washResponse = await _api.request(
          'GET',
          '/pos/wash/${widget.initialWashOrderId}',
        );
        if (washResponse['data'] is! Map) {
          throw const FormatException(
            'El servidor no devolvió la orden de lavado.',
          );
        }
        wash = Map<String, dynamic>.from(washResponse['data'] as Map);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _branches = branches;
        _wash = wash;
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
        _branchId = wash != null
            ? _asInt(wash['branch_id'])
            : (branches.isNotEmpty ? _asInt(branches.first['id']) : null);
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
    if (_wash != null && branch != _asInt(_wash!['branch_id'])) {
      _message(
        'Para cobrar este lavado conserva su sucursal original.',
        error: true,
      );
      return;
    }
    setState(() {
      _branchId = branch;
      _cart.clear();
      _chosen.clear();
      _discount.text = '0.00';
      _reason.clear();
      _documentType = 'RECEIPT';
      _fiscalAuthorization = null;
    });
    _loadProducts();
    _loadFiscalSettings();
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
      final raw = response['data'];
      setState(() => _sales = raw is Map ? _rows(raw['data']) : _rows(raw));
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
    });
  }

  Widget _card(Widget child, {EdgeInsets padding = const EdgeInsets.all(16)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: _panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF20353D))),
        ),
        child: child,
      );

  InputDecoration _dec(String name) => InputDecoration(
    labelText: name,
    border: const OutlineInputBorder(),
    isDense: true,
  );

  Widget _productTile(Map<String, dynamic> item) {
    final stock = double.tryParse('${item['stock']}') ?? 0;
    final available = stock >= 1;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CompanyVisualTheme.legacy(const Color(0xFF142329)),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF294047))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: CompanyProductPhotoView24J(
                  client: _client,
                  itemId: int.tryParse('${item['id']}'),
                  size: 46,
                  icon: Icons.shopping_bag_outlined,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Agregar al carrito',
                icon: const Icon(Icons.add_circle, size: 28),
                color: _teal,
                onPressed: available ? () => _add(item) : null,
              ),
            ],
          ),
          const SizedBox(height: 9),
          Text(
            '${item['name']}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
          ),
          const SizedBox(height: 3),
          Text(
            'SKU ${item['sku']}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  'L ${item['sale_price']}',
                  style: TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              Text(
                available ? '${item['stock']} ${item['unit']}' : 'Agotado',
                style: TextStyle(
                  color: available ? _muted : Colors.orangeAccent,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _catalog() => _card(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.inventory_2_outlined, color: _teal, size: 21),
            SizedBox(width: 9),
            Expanded(
              child: Text(
                'Productos en venta',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Catálogo vivo conectado con las existencias de la sucursal',
          style: TextStyle(color: _muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        TextField(
          key: const ValueKey('pos_search'),
          controller: _search,
          decoration: _dec('Buscar artículo por nombre o SKU')
              .copyWith(prefixIcon: Icon(Icons.search, color: _teal)),
        ),
        const SizedBox(height: 14),
        if (_products.isEmpty)
          Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No hay productos con precio de venta. Revisa Inventario.',
              style: TextStyle(color: _muted),
            ),
          ),
        if (_products.isNotEmpty)
          LayoutBuilder(
            builder: (context, bounds) {
              final cols = bounds.maxWidth >= 410 ? 2 : 1;
              final tileWidth = (bounds.maxWidth - (cols - 1) * 10) / cols;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in _products)
                    SizedBox(width: tileWidth, child: _productTile(item)),
                ],
              );
            },
          ),
      ],
    ),
  );

  Widget _cartPanel() {
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Carrito de venta',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          if (_wash != null) ...[
            ListTile(
              leading: Icon(Icons.local_car_wash_outlined, color: _teal),
              title: Text(
                'Lavado: ${_wash!['service_name']} · ${_wash!['vehicle_label']}',
              ),
              subtitle: Text(
                'Cliente: ${_wash!['customer_name']} · L ${_wash!['price']}',
              ),
              trailing: const Icon(Icons.lock_outline, size: 18),
            ),
            const Divider(),
          ],
          if (_cart.isEmpty && _wash == null)
            Text(
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
                          style: TextStyle(fontSize: 12, color: _muted),
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
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _reason,
            decoration: _dec('Motivo del descuento'),
          ),
          const SizedBox(height: 15),
          const Text(
            'Tipo de comprobante',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            key: const ValueKey('pos_document_type'),
            segments: const [
              ButtonSegment(
                value: 'RECEIPT',
                label: Text('Recibo'),
                icon: Icon(Icons.receipt_outlined),
              ),
              ButtonSegment(
                value: 'FISCAL_INVOICE',
                label: Text('Factura'),
                icon: Icon(Icons.description_outlined),
              ),
            ],
            selected: {_documentType},
            onSelectionChanged: (v) => setState(() => _documentType = v.first),
          ),
          if (_documentType == 'FISCAL_INVOICE') ...[
            const SizedBox(height: 10),
            Text(
              'ISV (15%): L ${_money(_tax)}',
              style: TextStyle(color: _muted),
            ),
            if (_fiscalLoading) const LinearProgressIndicator(),
            if (!_fiscalReady) ...[
              const SizedBox(height: 6),
              const Text(
                'Factura bloqueada: configure CAI, RTN y rango autorizado de la sucursal.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
              TextButton.icon(
                onPressed: _configureFiscal,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Configurar CAI fiscal'),
              ),
            ] else ...[
              const SizedBox(height: 5),
              Text(
                'CAI ${_fiscalAuthorization?['cai']} · siguiente #${_fiscalAuthorization?['next_sequence']}',
                style: TextStyle(color: _muted, fontSize: 11),
              ),
            ],
          ] else ...[
            const SizedBox(height: 5),
            Text(
              'Recibo interno sin valor fiscal; no agrega ISV al importe mostrado.',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Total: L ${_money(_total)}',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _teal,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: _teal.withValues(alpha: .3)),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: _teal),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Elige el cliente y la forma de pago en la siguiente pantalla. '
                    'Nada se cobra hasta confirmar la operación.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('pos_checkout'),
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed:
                  (_cart.isEmpty && _wash == null) ||
                      (_documentType == 'FISCAL_INVOICE' && !_fiscalReady)
                  ? null
                  : _openPaymentDialog,
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text('Continuar al cobro'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'La seleccion del documento no cambia las obligaciones tributarias del negocio.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Future<void> _openPaymentDialog() async {
    final branch = _branchId;
    final discount = _cents(_discount.text);
    if (branch == null || (_cart.isEmpty && _wash == null)) {
      _message('Selecciona sucursal y artículos.', error: true);
      return;
    }
    if (discount < 0 || discount >= _subtotal) {
      _message(
        'El descuento debe ser válido y menor que el subtotal.',
        error: true,
      );
      return;
    }
    if (discount > 0 && _reason.text.trim().length < 3) {
      _message('Explica el motivo del descuento.', error: true);
      return;
    }
    final availableSessions = _sessions
        .where((item) => _asInt(item['branch_id']) == branch)
        .toList();
    final availableBanks = _banks
        .where((item) => _asInt(item['branch_id']) == branch)
        .toList();
    final receipt = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompanyPosCheckoutDialog(
        api: _api,
        branchId: branch,
        washOrderId: _asInt(_wash?['order_id']),
        washExpectedVersion: _asInt(_wash?['version']),
        washCustomerId: _asInt(_wash?['customer_id']),
        washCustomerName: _wash?['customer_name']?.toString(),
        lines: _cart.entries
            .map(
              (entry) => <String, dynamic>{
                'item_id': entry.key,
                'quantity': entry.value,
              },
            )
            .toList(),
        subtotalCents: _subtotal,
        discountCents: discount,
        discountReason: _reason.text.trim(),
        documentType: _documentType,
        sessions: availableSessions,
        banks: availableBanks,
        cashMethodId: _cashMethodId,
        bankMethodId: _bankMethodId,
      ),
    );
    if (!mounted || receipt == null) return;
    setState(() {
      _cart.clear();
      _chosen.clear();
      _discount.text = '0.00';
      _reason.clear();
      _documentType = 'RECEIPT';
    });
    // Mostrar primero la confirmación; nunca bloquear el comprobante esperando
    // una actualización del catálogo que puede tardar o fallar por la red.
    await _showReceipt(receipt, afterSale: true);
    if (widget.initialWashOrderId != null) {
      _wash = null;
      widget.onWashSaleCompleted?.call();
    }
    if (!mounted) return;
    await _loadProducts();
    if (_history && mounted) await _loadSales();
  }

  String _receiptText(Map<String, dynamic> sale) {
    final invoice = sale['document_type'] == 'FISCAL_INVOICE';
    final b = StringBuffer(invoice ? 'FACTURA FISCAL\n' : 'RECIBO NO FISCAL\n');
    if (invoice) {
      b.writeln('Empresa: ${sale['fiscal_legal_name'] ?? ''}');
      b.writeln('RTN: ${sale['fiscal_rtn'] ?? ''}');
      b.writeln('Número: ${sale['fiscal_number'] ?? ''}');
      b.writeln('CAI: ${sale['fiscal_cai'] ?? ''}');
      b.writeln(
        'Rango: ${sale['fiscal_range_start'] ?? ''} a ${sale['fiscal_range_end'] ?? ''}',
      );
      b.writeln('Fecha límite: ${sale['fiscal_expires_on'] ?? ''}');
    }
    b.writeln('Venta #${sale['id']} — ${sale['posted_at']}');
    b.writeln('Cliente: ${sale['customer_name'] ?? 'Consumidor final'}');
    if ('${sale['customer_identity'] ?? ''}'.isNotEmpty) {
      b.writeln('Identidad/RTN: ${sale['customer_identity']}');
    }
    if ('${sale['customer_phone'] ?? ''}'.isNotEmpty) {
      b.writeln('Teléfono: ${sale['customer_phone']}');
    }
    if ('${sale['customer_email'] ?? ''}'.isNotEmpty) {
      b.writeln('Correo: ${sale['customer_email']}');
    }
    if ('${sale['customer_address'] ?? ''}'.isNotEmpty) {
      b.writeln('Dirección: ${sale['customer_address']}');
    }
    b.writeln('--------------------------------------');
    for (final line in _rows(sale['lines'])) {
      b.writeln(
        '${line['name_snapshot']} x${line['quantity']}   L ${line['line_total']}',
      );
    }
    b.writeln('Subtotal: L ${sale['subtotal']}');
    b.writeln('Descuento: L ${sale['discount_amount']}');
    if (invoice) {
      b.writeln('ISV 15%: L ${sale['tax_amount']}');
    }
    b.writeln('TOTAL: L ${sale['total']}');
    for (final payment in _rows(sale['payments'])) {
      b.writeln('${payment['channel']}: L ${payment['amount']}');
      if ('${payment['reference'] ?? ''}'.isNotEmpty) {
        b.writeln('Referencia: ${payment['reference']}');
      }
    }
    if (sale['cash_received'] != null) {
      b.writeln('Efectivo recibido: L ${sale['cash_received']}');
      b.writeln('Cambio entregado: L ${sale['change_given']}');
    }
    if (!invoice) {
      b.writeln('Documento interno sin valor fiscal.');
    }
    return b.toString();
  }

  Future<void> _showReceipt(
    Map<String, dynamic> receipt, {
    bool afterSale = false,
  }) async {
    final text = _receiptText(receipt);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          afterSale
              ? 'Venta #${receipt['id']} confirmada. ¿Desea imprimir el comprobante?'
              : 'Comprobante de venta #${receipt['id']}',
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 550),
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              _message('Comprobante copiado');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(afterSale ? 'No, finalizar' : 'Cerrar'),
          ),
          FilledButton.icon(
            key: const ValueKey('pos_print_receipt'),
            onPressed: () async {
              try {
                await CompanyPosPrinting.printSale(receipt);
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              } catch (e) {
                if (dialogContext.mounted) {
                  ScaffoldMessenger.of(dialogContext).showSnackBar(
                    SnackBar(content: Text('No se pudo imprimir: $e')),
                  );
                }
              }
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Sí, imprimir'),
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

  // 24L.1: Presentacion del historial, sin modificar el flujo de cobro.
  Widget _saleHistoryCard24L(Map<String, dynamic> sale) {
    final id = _asInt(sale['id']);
    final invoice = sale['document_type'] == 'FISCAL_INVOICE';
    final customer = '${sale['customer_name_snapshot'] ?? 'Consumidor final'}';
    final date = '${sale['posted_at'] ?? ''}'.trim();
    final state = '${sale['status'] ?? ''}'.trim();
    return Container(
      key: ValueKey<String>('pos_history_card_24l_${sale['id']}'),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: CompanyVisualTheme.legacy(const Color(0xFF12252B)),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF29434B))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: _teal, size: 19),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Venta #${sale['id']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  invoice ? 'Factura' : 'Recibo',
                  style: TextStyle(
                    color: _teal,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'L ${sale['total'] ?? '—'}',
            style: TextStyle(
              color: _teal,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          if (customer.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              customer,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ],
          if (date.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              date,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
          if (state.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(state, style: TextStyle(color: _muted, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: id == null ? null : () => _viewSale(id),
              icon: const Icon(Icons.visibility_outlined, size: 17),
              label: const Text('Consultar comprobante'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: BorderSide(color: CompanyVisualTheme.legacy(const Color(0xFF31545C))),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
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
          Text(
            'No hay ventas registradas.',
            style: TextStyle(color: _muted),
          ),
        LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 1050
                ? 4
                : bounds.maxWidth >= 780
                ? 3
                : bounds.maxWidth >= 520
                ? 2
                : 1;
            const gap = 10.0;
            final cardWidth = (bounds.maxWidth - (columns - 1) * gap) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final sale in _sales)
                  SizedBox(width: cardWidth, child: _saleHistoryCard24L(sale)),
              ],
            );
          },
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
        Text(
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
