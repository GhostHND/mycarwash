import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';

import '../core/company_business_api.dart';

/// Cobro guiado del Smart POS. No registra importes hasta obtener confirmación
/// del servidor. El servidor recalcula precios, inventario, pagos y cambio.
class CompanyPosCheckoutDialog extends StatefulWidget {
  const CompanyPosCheckoutDialog({
    super.key,
    required this.api,
    this.washOrderId,
    this.washExpectedVersion,
    this.washCustomerId,
    this.washCustomerName,
    required this.branchId,
    required this.lines,
    required this.subtotalCents,
    required this.discountCents,
    required this.discountReason,
    required this.documentType,
    required this.sessions,
    required this.banks,
    required this.cashMethodId,
    required this.bankMethodId,
  });

  final CompanyBusinessApi api;
  final int? washOrderId;
  final int? washExpectedVersion;
  final int? washCustomerId;
  final String? washCustomerName;
  final int branchId;
  final List<Map<String, dynamic>> lines;
  final int subtotalCents;
  final int discountCents;
  final String discountReason;
  final String documentType;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> banks;
  final int? cashMethodId;
  final int? bankMethodId;

  @override
  State<CompanyPosCheckoutDialog> createState() =>
      _CompanyPosCheckoutDialogState();
}

class _CompanyPosCheckoutDialogState extends State<CompanyPosCheckoutDialog> {
  static Color get teal => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get surface => CompanyVisualTheme.legacy(const Color(0xFF0D1A1F));
  static Color get muted => CompanyVisualTheme.legacy(const Color(0xFFA3B8C0));
  final _search = TextEditingController();
  final _fullName = TextEditingController();
  final _document = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _cashApplied = TextEditingController();
  final _tendered = TextEditingController();
  final _bankReference = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _customers = [];
  String _customerMode = 'CONSUMER';
  String _paymentMode = 'CASH';
  int? _customerId;
  int? _sessionId;
  int? _bankId;
  String? _error;
  String? _status;
  String? _attemptKey;
  bool _saving = false;
  bool _searching = false;
  int _searchVersion = 0;

  int get _net => widget.subtotalCents - widget.discountCents;
  int get _tax =>
      widget.documentType == 'FISCAL_INVOICE' ? (_net * 15 + 50) ~/ 100 : 0;
  int get _total => _net + _tax;
  int? _integer(dynamic value) => int.tryParse('$value');
  String _amount(int cents) =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  int _parseMoney(String value) {
    final match = RegExp(r'^(?:0|[1-9][0-9]*)(?:\.[0-9]{1,2})?$')
        .firstMatch(value.trim());
    if (match == null) return -1;
    final parts = value.trim().split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null || whole > 999999999) return -1;
    return whole * 100 +
        int.parse((parts.length == 2 ? parts[1] : '').padRight(2, '0'));
  }

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessions.isEmpty
        ? null
        : _integer(widget.sessions.first['id']);
    _bankId = widget.banks.isEmpty ? null : _integer(widget.banks.first['id']);
    if (widget.cashMethodId == null && widget.bankMethodId != null) {
      _paymentMode = 'BANK';
    }
    if (widget.washOrderId != null) {
      _customerMode = 'EXISTING';
      _customerId = widget.washCustomerId;
    }
    _setPaymentMode(_paymentMode, refresh: false);
    if (widget.washOrderId == null) {
      _searchCustomers('');
    }
  }

  @override
  void dispose() {
    _searchVersion++;
    _debounce?.cancel();
    for (final controller in [
      _search,
      _fullName,
      _document,
      _phone,
      _email,
      _address,
      _cashApplied,
      _tendered,
      _bankReference,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _edited() {
    // Mantener la clave de idempotencia durante toda esta venta: si una solicitud
    // llegó al servidor pero se perdió la respuesta, un reintento no podrá
    // registrar la misma operación dos veces, incluso tras editar el formulario.
    if (_error != null) setState(() => _error = null);
  }

  void _setPaymentMode(String value, {bool refresh = true}) {
    _paymentMode = value;
    final cashDue = switch (value) {
      'BANK' => 0,
      'MIXED' => _total ~/ 2,
      _ => _total,
    };
    _cashApplied.text = _amount(cashDue);
    _tendered.text = _amount(cashDue);
    _edited();
    if (refresh) setState(() {});
  }

  Future<void> _searchCustomers(String text) async {
    final version = ++_searchVersion;
    setState(() => _searching = true);
    try {
      final response = await widget.api.request(
        'GET',
        '/pos/customers',
        query: {'q': text.trim()},
      );
      if (!mounted || version != _searchVersion) return;
      final raw = response['data'];
      setState(() {
        _customers = raw is List
            ? raw
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
            : [];
        _searching = false;
      });
    } catch (e) {
      if (!mounted || version != _searchVersion) return;
      setState(() {
        _searching = false;
        _error = 'No se pudo buscar clientes: $e';
      });
    }
  }

  InputDecoration _input(String label, {String? helper, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        helperText: helper,
        prefixIcon: icon == null ? null : Icon(icon, size: 19),
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      );

  Widget _heading(String title, String subtitle, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: teal, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 17,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _customerSection() => widget.washOrderId != null
      ? ListTile(
          leading: Icon(Icons.person_outline, color: teal),
          title: Text(widget.washCustomerName ?? 'Propietario del vehículo'),
          subtitle: const Text('Cliente vinculado a la orden (no modificable)'),
        )
      : Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heading(
              'Datos del comprador',
              'Selecciona cómo identificar esta venta.',
              Icons.person_outline,
            ),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                for (final option in const [
                  ('CONSUMER', 'Consumidor final'),
                  ('EXISTING', 'Cliente registrado'),
                  ('NEW', 'Cliente nuevo'),
                ])
                  ChoiceChip(
                    label: Text(option.$2),
                    selected: _customerMode == option.$1,
                    selectedColor: teal.withValues(alpha: .22),
                    onSelected: (_) {
                      _edited();
                      setState(() => _customerMode = option.$1);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_customerMode == 'CONSUMER')
              Text(
                'Venta sin datos personales. El comprobante mostrará «Consumidor final».',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            if (_customerMode == 'EXISTING') ...[
              TextField(
                controller: _search,
                decoration: _input(
                  'Buscar por nombre, identidad o teléfono',
                  icon: Icons.search,
                ),
                onChanged: (value) {
                  _edited();
                  _debounce?.cancel();
                  setState(() => _customerId = null);
                  _debounce = Timer(
                    const Duration(milliseconds: 320),
                    () => _searchCustomers(value),
                  );
                },
              ),
              const SizedBox(height: 8),
              if (_searching) const LinearProgressIndicator(minHeight: 2),
              DropdownButtonFormField<int>(
                key: ValueKey(
                  'pos_customers_${_searchVersion}_${_customerId ?? 0}',
                ),
                initialValue:
                    _customers.any((row) => _integer(row['id']) == _customerId)
                    ? _customerId
                    : null,
                isExpanded: true,
                decoration: _input('Cliente seleccionado'),
                items: _customers
                    .map(
                      (row) => DropdownMenuItem<int>(
                        value: _integer(row['id']),
                        child: Text(
                          '${row['full_name']} · ${row['identity_document'] ?? 'Sin documento'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _edited();
                  setState(() => _customerId = value);
                },
              ),
            ],
            if (_customerMode == 'NEW') ...[
              TextField(
                key: const ValueKey('pos_customer_name'),
                controller: _fullName,
                decoration: _input('Nombre completo *'),
                maxLength: 180,
                onChanged: (_) => _edited(),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: 270,
                    child: TextField(
                      controller: _document,
                      decoration: _input('Identidad o RTN (opcional)'),
                      maxLength: 50,
                      onChanged: (_) => _edited(),
                    ),
                  ),
                  SizedBox(
                    width: 270,
                    child: TextField(
                      controller: _phone,
                      decoration: _input('Teléfono (opcional)'),
                      maxLength: 40,
                      keyboardType: TextInputType.phone,
                      onChanged: (_) => _edited(),
                    ),
                  ),
                  SizedBox(
                    width: 270,
                    child: TextField(
                      controller: _email,
                      decoration: _input('Correo electrónico (opcional)'),
                      maxLength: 190,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) => _edited(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _address,
                decoration: _input('Dirección (opcional)'),
                maxLines: 2,
                onChanged: (_) => _edited(),
              ),
              const SizedBox(height: 5),
              Text(
                'Se registrará en Clientes únicamente cuando la venta sea confirmada.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
            ],
          ],
        );

  Widget _paymentSection() {
    final cashPart = _paymentMode == 'BANK'
        ? 0
        : _paymentMode == 'CASH'
        ? _total
        : _parseMoney(_cashApplied.text);
    final bankPart = _total - cashPart;
    final received = _parseMoney(_tendered.text);
    final change = received >= cashPart && cashPart >= 0
        ? received - cashPart
        : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _heading(
          'Forma de pago',
          'La confirmación registrará caja, banco e inventario una sola vez.',
          Icons.payments_outlined,
        ),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final option in const [
              ('CASH', 'Efectivo', Icons.payments_outlined),
              ('BANK', 'Transferencia', Icons.account_balance_outlined),
              ('MIXED', 'Pago mixto', Icons.call_split_outlined),
            ])
              ChoiceChip(
                avatar: Icon(option.$3, size: 16),
                label: Text(option.$2),
                selected: _paymentMode == option.$1,
                selectedColor: teal.withValues(alpha: .22),
                onSelected: (_) => _setPaymentMode(option.$1),
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_paymentMode == 'MIXED') ...[
          TextField(
            key: const ValueKey('pos_cash_split'),
            controller: _cashApplied,
            decoration: _input('Parte del total pagada en efectivo (L)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              _edited();
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Transferencia calculada: L ${bankPart >= 0 ? _amount(bankPart) : '—'}',
            style: TextStyle(color: teal, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
        ],
        if (_paymentMode != 'BANK') ...[
          DropdownButtonFormField<int>(
            key: const ValueKey('pos_dialog_cash_session'),
            initialValue: _sessionId,
            isExpanded: true,
            decoration: _input('Sesión de caja abierta'),
            items: widget.sessions
                .map(
                  (item) => DropdownMenuItem<int>(
                    value: _integer(item['id']),
                    child: Text('${item['name']}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              _edited();
              setState(() => _sessionId = value);
            },
          ),
          if (widget.sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text(
                'No hay caja abierta en esta sucursal. Abre una sesión en Caja y bancos.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('pos_cash_received'),
            controller: _tendered,
            decoration: _input('Efectivo recibido del cliente (L)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) {
              _edited();
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Monto a caja: L ${cashPart >= 0 ? _amount(cashPart) : '—'}',
              ),
              Text(
                'Cambio: L ${_amount(change)}',
                style: TextStyle(
                  color: teal,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_paymentMode != 'CASH') ...[
          DropdownButtonFormField<int>(
            key: const ValueKey('pos_dialog_bank'),
            initialValue: _bankId,
            isExpanded: true,
            decoration: _input('Cuenta bancaria receptora'),
            items: widget.banks
                .map(
                  (item) => DropdownMenuItem<int>(
                    value: _integer(item['id']),
                    child: Text('${item['alias']}'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              _edited();
              setState(() => _bankId = value);
            },
          ),
          if (widget.banks.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 7),
              child: Text(
                'No hay una cuenta bancaria activa en esta sucursal.',
                style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _bankReference,
            decoration: _input('Número de referencia o comprobante (opcional)'),
            maxLength: 120,
            onChanged: (_) => _edited(),
          ),
          const SizedBox(height: 5),
        ],
      ],
    );
  }

  // Este envoltorio cubre tambien la construccion del comprobante y de la
  // clave idempotente. Antes de 21A.6.3 los errores previos al POST quedaban
  // fuera del catch y el cajero no veia ninguna respuesta al pulsar el boton.
  Future<void> _confirm() async {
    if (_saving) {
      return;
    }
    setState(() {
      _error = null;
      _status = 'Validando datos y preparando el cobro...';
    });
    try {
      await _confirmInternal();
    } catch (error, stack) {
      debugPrint('ADN Smart POS: fallo antes o durante confirmacion: $error');
      debugPrintStack(stackTrace: stack);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _status = null;
        _error =
            'No se pudo iniciar o finalizar el cobro: $error. '
            'No vuelvas a confirmar sin revisar el historial de ventas.';
      });
    }
  }

  Future<void> _confirmInternal() async {
    String? error;
    if (_customerMode == 'EXISTING' && _customerId == null) {
      error = 'Selecciona un cliente registrado.';
    }
    if (_customerMode == 'NEW' && _fullName.text.trim().isEmpty) {
      error = 'El nombre del nuevo cliente es obligatorio.';
    }
    if (_customerMode == 'NEW' &&
        _email.text.trim().isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(_email.text.trim())) {
      error = 'El correo electrónico del cliente no es válido.';
    }
    final cashPart = _paymentMode == 'BANK'
        ? 0
        : _paymentMode == 'CASH'
        ? _total
        : _parseMoney(_cashApplied.text);
    final bankPart = _total - cashPart;
    final tendered = _paymentMode == 'BANK' ? 0 : _parseMoney(_tendered.text);
    if (cashPart < 0 ||
        bankPart < 0 ||
        (_paymentMode == 'MIXED' && (cashPart == 0 || bankPart == 0))) {
      error = 'El pago mixto debe tener importes positivos que sumen el total.';
    }
    if (cashPart > 0 && widget.cashMethodId == null) {
      error = 'Configura un medio de pago en efectivo.';
    }
    if (cashPart > 0 && _sessionId == null) {
      error = 'Abre una sesión de caja para cobrar en efectivo.';
    }
    if (bankPart > 0 && widget.bankMethodId == null) {
      error = 'Configura el medio de pago por transferencia.';
    }
    if (bankPart > 0 && _bankId == null) {
      error = 'Selecciona una cuenta bancaria activa.';
    }
    if (cashPart > 0 && tendered < cashPart) {
      error = 'El efectivo recibido no cubre el importe correspondiente.';
    }
    if (error != null) {
      setState(() {
        _error = error;
        _status = null;
      });
      return;
    }
    final payments = <Map<String, dynamic>>[];
    if (cashPart > 0) {
      payments.add({
        'payment_method_id': widget.cashMethodId,
        'cash_session_id': _sessionId,
        'amount': _amount(cashPart),
      });
    }
    if (bankPart > 0) {
      payments.add({
        'payment_method_id': widget.bankMethodId,
        'bank_account_id': _bankId,
        'amount': _amount(bankPart),
        'reference': _bankReference.text.trim(),
      });
    }
    // La clave es un identificador de reintentos, no un token de acceso.
    // Evitar Random.secure() aqui: en ciertos entornos Web su fuente criptografica
    // puede no estar disponible y antes lanzaba una excepcion silenciosa.
    _attemptKey ??=
        'pos-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(0x7fffffff)}';
    final body = <String, dynamic>{
      'branch_id': widget.branchId,
      'idempotency_key': _attemptKey,
      'lines': widget.lines,
      'discount_amount': _amount(widget.discountCents),
      'document_type': widget.documentType,
      'discount_reason': widget.discountReason,
      'customer_type': _customerMode,
      'cash_received': cashPart > 0 ? _amount(tendered) : null,
      'payments': payments,
    };
    if (widget.washOrderId != null) {
      body['wash_order_id'] = widget.washOrderId;
      body['wash_expected_version'] = widget.washExpectedVersion;
    }
    if (_customerMode == 'EXISTING') body['customer_id'] = _customerId;
    if (_customerMode == 'NEW') {
      body['customer'] = {
        'full_name': _fullName.text.trim(),
        'identity_document': _document.text.trim(),
        'phone': _phone.text.trim(),
        'email': _email.text.trim(),
        'address': _address.text.trim(),
      };
    }
    setState(() {
      _saving = true;
      _error = null;
      _status = 'Enviando venta al servidor. No cierres la ventana...';
    });
    try {
      final response = await widget.api
          .request('POST', '/pos/sales', body: body)
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      final raw = response['data'];
      if (raw is! Map) {
        throw const FormatException(
          'El servidor no devolvió el comprobante de la venta.',
        );
      }
      final receipt = Map<String, dynamic>.from(raw);
      final saleId = _integer(receipt['id']);
      if (saleId == null || saleId <= 0 || receipt['status'] != 'POSTED') {
        throw const FormatException(
          'El servidor no confirmó una venta publicada.',
        );
      }
      Navigator.of(context).pop(receipt);
    } on TimeoutException {
      if (!mounted) return;
      setState(
        () => _error =
            'El servidor no respondió en 30 segundos. El cobro podría haberse registrado. '
            'Cierra esta ventana y consulta Historial de ventas antes de repetirlo. '
            'Este formulario conserva la misma clave para proteger los reintentos.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error =
            'No se confirmó la venta: $e\n'
            'Comprueba la causa indicada y revisa Historial si hubo una interrupción.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
          _status = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .88;
    return Dialog(
      backgroundColor: surface,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 740, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 14),
              child: Row(
                children: [
                  Icon(Icons.point_of_sale, color: teal, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Finalizar venta',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Datos del cliente, pago y confirmación',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cancelar cobro',
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _customerSection(),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Divider(),
                    ),
                    _paymentSection(),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 20),
              child: Column(
                children: [
                  if (_status != null) ...[
                    Container(
                      key: const ValueKey('pos_confirm_status'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: teal.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        children: [
                          if (_saving) ...[
                            const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: Text(
                              _status!,
                              style: TextStyle(
                                color: CompanyVisualTheme.text,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (_error != null) ...[
                    Container(
                      key: const ValueKey('pos_payment_error'),
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: CompanyVisualTheme.legacy(const Color(0xFF502A32)),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.redAccent,
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 110),
                              child: SingleChildScrollView(
                                child: SelectableText(
                                  _error!,
                                  style: TextStyle(
                                    color: CompanyVisualTheme.text,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        widget.documentType == 'FISCAL_INVOICE'
                            ? 'TOTAL CON ISV 15%'
                            : 'TOTAL RECIBO',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'L ${_amount(_total)}',
                        style: TextStyle(
                          color: teal,
                          fontSize: 25,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Cancelar'),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        key: const ValueKey('pos_confirm_payment'),
                        style: FilledButton.styleFrom(
                          backgroundColor: teal,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 17,
                          ),
                        ),
                        onPressed: _saving ? null : _confirm,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.verified_outlined),
                        label: Text(
                          _saving ? 'Procesando...' : 'Confirmar y cobrar',
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
