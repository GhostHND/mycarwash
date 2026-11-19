import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

/// Confirma cobro y entrega como una sola transacción del backend.
class CompanySaleCheckoutDialog extends StatefulWidget {
  const CompanySaleCheckoutDialog({
    super.key,
    required this.order,
    required this.client,
  });
  final Map<String, dynamic> order;
  final http.Client client;

  @override
  State<CompanySaleCheckoutDialog> createState() =>
      _CompanySaleCheckoutDialogState();
}

class _CompanySaleCheckoutDialogState extends State<CompanySaleCheckoutDialog> {
  static Color get accent => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get surface => CompanyVisualTheme.legacy(const Color(0xFF0A1519));

  final _finalPrice = TextEditingController(text: '0.00');
  final _reason = TextEditingController();
  final _reference = TextEditingController();
  late final Future<List<Map<String, dynamic>>> _lookups;
  int? _method;
  int? _session;
  int? _bank;
  bool _saving = false;
  String? _error;
  String _price = '0.00';
  int _pendingCount = 0;

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _lookups = _fetch();
  }

  Future<List<Map<String, dynamic>>> _fetch() async {
    final results = await Future.wait([
      _api.request('GET', '/sales/options'),
      _api.request('GET', '/sales/quote/${widget.order['id']}'),
    ]);
    final data = results[0]['data'] as Map? ?? {};
    final quote = results[1]['data'] as Map? ?? {};
    final existing = quote['payments'] as List? ?? [];
    if (mounted) {
      setState(() {
        _price = '${quote['price'] ?? widget.order['quoted_price'] ?? '0.00'}';
        _finalPrice.text = '${quote['total'] ?? _price}';
        _reason.text = '${quote['discount_reason'] ?? ''}';
        _pendingCount = existing.length;
      });
    }
    return [
      {'kind': 'methods', 'rows': data['methods'] ?? []},
      {'kind': 'sessions', 'rows': data['sessions'] ?? []},
      {'kind': 'banks', 'rows': data['banks'] ?? []},
    ];
  }

  @override
  void dispose() {
    _finalPrice.dispose();
    _reason.dispose();
    _reference.dispose();
    super.dispose();
  }

  int? _money(String text) {
    if (!RegExp(r'^(?:0|[1-9][0-9]{0,9})(?:\.[0-9]{1,2})?$')
        .hasMatch(text.trim())) {
      return null;
    }
    final pieces = text.trim().split('.');
    return int.parse(pieces[0]) * 100 +
        int.parse((pieces.length > 1 ? pieces[1] : '').padRight(2, '0'));
  }

  String _display(int cents) =>
      '${cents ~/ 100}.${(cents % 100).toString().padLeft(2, '0')}';

  String? _channel(List<Map<String, dynamic>> options) {
    final methods =
        options.firstWhere((o) => o['kind'] == 'methods')['rows'] as List;
    for (final method in methods.whereType<Map>()) {
      if ('${method['id']}' == '$_method') {
        return '${method['channel']}';
      }
    }
    return null;
  }

  Future<void> _confirm() async {
    final original = _money(_price);
    final finalPrice = _money(_finalPrice.text);
    if (original == null || finalPrice == null || finalPrice > original) {
      setState(
        () => _error = 'Precio final inválido: debe estar entre L 0.00 y el precio de lista.',
      );
      return;
    }
    final discount = original - finalPrice;
    if (discount > 0 && _reason.text.trim().length < 3) {
      setState(() => _error = 'Indica el motivo del descuento autorizado.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = <String, dynamic>{
        'expected_version': widget.order['version'],
        'discount_amount': _display(discount),
        'discount_reason': discount > 0 ? _reason.text.trim() : null,
      };
      if (_pendingCount == 0 && discount < original) {
        payload['payment_method_id'] = _method;
        payload['cash_session_id'] = _session;
        payload['bank_account_id'] = _bank;
        payload['reference'] = _reference.text.trim().isEmpty
            ? null
            : _reference.text.trim();
      }
      await _api.request(
        'POST',
        '/sales/checkout/${widget.order['id']}',
        body: payload,
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$error';
        });
      }
    }
  }

  InputDecoration _dec(String text) => InputDecoration(
    labelText: text,
    filled: true,
    fillColor: CompanyVisualTheme.legacy(const Color(0xFF112127)),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
  );

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: surface,
    title: const Text('Cobrar y entregar vehículo'),
    content: SizedBox(
      width: 530,
      child: SingleChildScrollView(
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _lookups,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Text(
                '${snapshot.error}',
                style: const TextStyle(color: Colors.redAccent),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final options = snapshot.data!;
            final cents = _money(_price) ?? 0;
            final due = _money(_finalPrice.text) ?? 0;
            final discount = cents - due;
            final methods =
                (options.firstWhere((o) => o['kind'] == 'methods')['rows']
                        as List)
                    .whereType<Map>()
                    .toList();
            final sessions =
                (options.firstWhere((o) => o['kind'] == 'sessions')['rows']
                        as List)
                    .whereType<Map>()
                    .where(
                      (v) =>
                          '${v['branch_id']}' == '${widget.order['branch_id']}',
                    )
                    .toList();
            final banks =
                (options.firstWhere((o) => o['kind'] == 'banks')['rows']
                        as List)
                    .whereType<Map>()
                    .where(
                      (v) =>
                          '${v['branch_id']}' == '${widget.order['branch_id']}',
                    )
                    .toList();
            final channel = _channel(options);
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '${widget.order['tracking_code']} · ${widget.order['vehicle_label'] ?? ''}',
                ),
                const SizedBox(height: 12),
                Text(
                  'Precio normal: L $_price',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _finalPrice,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: _dec('Precio final acordado (L)'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                if (discount > 0)
                  TextField(
                    controller: _reason,
                    decoration: _dec('Motivo de descuento'),
                    maxLength: 255,
                  ),
                Text(
                  'Descuento aplicado: L ${_display(discount < 0 ? 0 : discount)}',
                ),
                const SizedBox(height: 5),
                Text(
                  'Total a cobrar: L ${_display(due)}',
                  style: TextStyle(
                    fontSize: 20,
                    color: accent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                if (_pendingCount > 0)
                  Text(
                    'Esta orden tiene $_pendingCount cobro(s) pendiente(s). Se confirmarán tal como están registrados.',
                  )
                else if (due > 0) ...[
                  DropdownButtonFormField<int>(
                    initialValue: _method,
                    isExpanded: true,
                    decoration: _dec('Medio de pago'),
                    dropdownColor: surface,
                    items: methods
                        .map(
                          (v) => DropdownMenuItem<int>(
                            value: int.tryParse('${v['id']}'),
                            child: Text('${v['name']} (${v['channel']})'),
                          ),
                        )
                        .toList(),
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _method = value;
                            _session = null;
                            _bank = null;
                          }),
                  ),
                  const SizedBox(height: 12),
                  if (channel == 'CASH')
                    DropdownButtonFormField<int>(
                      initialValue: _session,
                      isExpanded: true,
                      decoration: _dec('Caja abierta'),
                      dropdownColor: surface,
                      items: sessions
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: int.tryParse('${s['id']}'),
                              child: Text('${s['name']} · Sesión ${s['id']}'),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _session = v),
                    ),
                  if (channel == 'BANK') ...[
                    DropdownButtonFormField<int>(
                      initialValue: _bank,
                      isExpanded: true,
                      decoration: _dec('Cuenta bancaria receptora'),
                      dropdownColor: surface,
                      items: banks
                          .map(
                            (b) => DropdownMenuItem<int>(
                              value: int.tryParse('${b['id']}'),
                              child: Text('${b['alias']} · ${b['bank_name']}'),
                            ),
                          )
                          .toList(),
                      onChanged: _saving
                          ? null
                          : (v) => setState(() => _bank = v),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _reference,
                      decoration: _dec('Referencia de transferencia'),
                    ),
                  ],
                ],
                const SizedBox(height: 10),
                if (_error != null)
                  Text(
                    _error!,
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                Text(
                  'El cobro se registrará una sola vez al confirmar la entrega.',
                  style: TextStyle(fontSize: 12, color: CompanyVisualTheme.legacy(const Color(0xFF9BAEB6))),
                ),
              ],
            );
          },
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancelar'),
      ),
      FilledButton.icon(
        key: const ValueKey('sales_checkout_confirm'),
        onPressed: _saving ? null : _confirm,
        icon: const Icon(Icons.check_circle_outline),
        label: Text(_saving ? 'Confirmando...' : 'Cobrar y entregar'),
      ),
    ],
  );
}
