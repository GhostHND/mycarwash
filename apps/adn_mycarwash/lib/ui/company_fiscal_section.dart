import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import 'company_pos_fiscal_settings_dialog.dart';

class CompanyFiscalSection extends StatefulWidget {
  const CompanyFiscalSection({super.key, required this.client});

  final http.Client client;

  @override
  State<CompanyFiscalSection> createState() => _CompanyFiscalSectionState();
}

class _CompanyFiscalSectionState extends State<CompanyFiscalSection> {
  static Color get turquoise => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get surface => CompanyVisualTheme.legacy(const Color(0xFF0A1519));
  static Color get border => CompanyVisualTheme.legacy(const Color(0xFF20343C));
  static Color get muted => CompanyVisualTheme.legacy(const Color(0xFF9BAEB6));

  static const fields = <String, String>{
    'legal_name': 'Razón social',
    'tax_id': 'RTN o identificación tributaria',
    'taxpayer_type': 'Tipo de contribuyente',
    'tax_regime': 'Régimen tributario',
    'tax_status': 'Estado tributario',
    'commercial_registration': 'Registro mercantil',
    'billing_email': 'Correo de facturación',
    'billing_phone': 'Teléfono de facturación',
    'fiscal_address': 'Dirección fiscal',
    'invoice_footer': 'Pie de factura',
    'fiscal_notes': 'Observaciones fiscales',
  };

  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {
    for (final key in fields.keys) key: TextEditingController(),
  };

  bool _loading = true;
  bool _saving = false;
  bool _taxExempt = false;
  String? _error;

  // La autorización CAI es de cada sucursal. Reutilizamos la misma API
  // que Smart POS; no se crea un registro fiscal paralelo.
  List<Map<String, dynamic>> _caiBranches = [];
  int? _caiBranchId;
  Map<String, dynamic>? _caiSettings;
  bool _caiBusy = false;
  String? _caiError;

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _load();
    _loadCaiBranches();
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.request('GET', '/settings/fiscal');
      if (!mounted) return;
      final fiscal = response['fiscal'];
      for (final entry in _controllers.entries) {
        entry.value.text = fiscal is Map
            ? (fiscal[entry.key] ?? '').toString()
            : '';
      }
      setState(() {
        _taxExempt =
            fiscal is Map &&
            (fiscal['is_tax_exempt'] == true || fiscal['is_tax_exempt'] == 1);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _notify(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? CompanyVisualTheme.legacy(const Color(0xFF9C3541))
            : CompanyVisualTheme.legacy(const Color(0xFF126F75)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    if (_saving || !_formKey.currentState!.validate()) return;
    final data = <String, dynamic>{};
    for (final entry in _controllers.entries) {
      final value = entry.value.text.trim();
      data[entry.key] = value.isEmpty ? null : value;
    }
    data['is_tax_exempt'] = _taxExempt;

    setState(() => _saving = true);
    try {
      final response = await _api.request(
        'PATCH',
        '/settings/fiscal',
        body: data,
      );
      if (!mounted) return;
      final fiscal = response['fiscal'];
      if (fiscal is Map) {
        for (final entry in _controllers.entries) {
          entry.value.text = (fiscal[entry.key] ?? '').toString();
        }
      }
      _notify('Datos fiscales guardados correctamente.');
    } catch (error) {
      _notify(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }


  int? _caiInt(dynamic value) => int.tryParse('${value ?? ''}');

  Future<void> _loadCaiBranches() async {
    if (_caiBusy) return;
    setState(() {
      _caiBusy = true;
      _caiError = null;
    });
    try {
      final response = await _api.request('GET', '/pos/options');
      final data = response['data'];
      if (data is! Map || data['branches'] is! List) {
        throw const FormatException('No se recibió el catálogo de sucursales.');
      }
      final branches = (data['branches'] as List)
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .where((item) => _caiInt(item['id']) != null)
          .toList();
      if (!mounted) return;
      final previous = _caiBranchId;
      final stillExists = branches.any((b) => _caiInt(b['id']) == previous);
      final current = stillExists
          ? previous
          : (branches.isNotEmpty ? _caiInt(branches.first['id']) : null);
      setState(() {
        _caiBranches = branches;
        _caiBranchId = current;
        _caiSettings = null;
        _caiBusy = false;
      });
      if (current != null) await _loadCaiSettings();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _caiError = 'No se pudo consultar las sucursales: $e';
        _caiBusy = false;
      });
    }
  }

  Future<void> _loadCaiSettings() async {
    final branchId = _caiBranchId;
    if (branchId == null) return;
    setState(() {
      _caiBusy = true;
      _caiError = null;
    });
    try {
      final response = await _api.request(
        'GET', '/pos/fiscal-settings',
        query: {'branch_id': '$branchId'},
      );
      if (!mounted || branchId != _caiBranchId) return;
      // H04.10.1: API CAI sin autorizacion es estado valido.
      final data = response['data'];
      if (data == null && response['available'] == false) {
        setState(() => _caiSettings = null);
      } else if (data is Map) {
        setState(() => _caiSettings = Map<String, dynamic>.from(data));
      } else {
        throw const FormatException('La API fiscal no devolvió un registro válido.');
      }
    } catch (e) {
      if (!mounted || branchId != _caiBranchId) return;
      setState(() => _caiError = 'No se pudo consultar la autorización: $e');
    } finally {
      if (mounted && branchId == _caiBranchId) {
        setState(() => _caiBusy = false);
      }
    }
  }

  Future<void> _editCaiSettings() async {
    final branchId = _caiBranchId;
    if (_caiBusy || branchId == null) return;
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CompanyPosFiscalSettingsDialog(
        api: _api, branchId: branchId,
      ),
    );
    if (!mounted) return;
    if (saved == true) {
      await _loadCaiSettings();
      _notify('Configuración CAI actualizada.');
    }
  }

  Widget _caiSection() {
    final hasCai = (_caiSettings?['cai'] ?? '').toString().trim().isNotEmpty;
    final available = _caiSettings?['available'] == true;
    final nextNumber = _caiSettings?['next_sequence'];
    final expiry = _caiSettings?['expires_on'];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CompanyVisualTheme.legacy(const Color(0xFF101F25)),
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(Icons.receipt_long_outlined, color: turquoise, size: 25),
              Text('Autorización de facturación CAI',
                style: TextStyle(color: CompanyVisualTheme.text,
                  fontSize: 18, fontWeight: FontWeight.w800)),
            ],
          ),
          const SizedBox(height: 7),
          Text('Consulta y modifica el CAI y rango autorizado de cada sucursal. '
               'Los comprobantes ya emitidos no deben renumerarse.',
            style: TextStyle(color: muted)),
          const SizedBox(height: 15),
          if (_caiBranches.isNotEmpty)
            DropdownButtonFormField<int>(
              value: _caiBranchId,
              isExpanded: true,
              dropdownColor: CompanyVisualTheme.legacy(const Color(0xFF172B33)),
              decoration: _decoration('Sucursal que emite facturas'),
              items: [
                for (final item in _caiBranches)
                  DropdownMenuItem<int>(
                    value: _caiInt(item['id']),
                    child: Text((item['name'] ?? 'Sucursal #${item['id']}').toString(),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: CompanyVisualTheme.text)),
                  ),
              ],
              onChanged: _caiBusy ? null : (id) {
                setState(() {
                  _caiBranchId = id;
                  _caiSettings = null;
                });
                _loadCaiSettings();
              },
            ),
          if (_caiBusy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(color: turquoise),
          ],
          if (_caiError != null) ...[
            const SizedBox(height: 10),
            SelectableText(_caiError!,
              style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995)))),
            TextButton.icon(
              onPressed: _caiBusy ? null : _loadCaiBranches,
              icon: const Icon(Icons.refresh),
              label: const Text('Reintentar consulta'),
            ),
          ],
          if (!_caiBusy && _caiError == null) ...[
            const SizedBox(height: 11),
            Text(
              _caiBranchId == null
                  ? 'No hay sucursales disponibles.'
                  : !hasCai
                      ? 'No hay un CAI registrado para esta sucursal.'
                      : 'CAI: ${_caiSettings!['cai']}  •  '
                        'Siguiente: ${nextNumber ?? 'No disponible'}  •  '
                        'Vencimiento: ${expiry ?? 'No disponible'}',
              style: TextStyle(color: CompanyVisualTheme.text,
                fontWeight: FontWeight.w600),
            ),
            if (hasCai && !available) ...[
              const SizedBox(height: 6),
              Text('La autorización no figura disponible para emitir facturas. '
                   'Revise su vigencia, rango y permisos antes de facturar.',
                style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFF5BD70)))),
            ],
          ],
          const SizedBox(height: 15),
          FilledButton.icon(
            key: const ValueKey('company_fiscal_edit_cai_button'),
            onPressed: (_caiBusy || _caiBranchId == null || _caiError != null)
                ? null : _editCaiSettings,
            icon: const Icon(Icons.edit_outlined),
            label: Text(hasCai ? 'Editar CAI y rangos' : 'Configurar autorización CAI'),
            style: FilledButton.styleFrom(
              backgroundColor: turquoise,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: TextStyle(color: muted),
    filled: true,
    fillColor: CompanyVisualTheme.legacy(const Color(0xFF111F25)),
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: border),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: turquoise),
      borderRadius: BorderRadius.circular(10),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: CompanyVisualTheme.legacy(const Color(0xFFE84657))),
      borderRadius: BorderRadius.circular(10),
    ),
  );

  Widget _field(String key, String label) {
    final longText = const [
      'fiscal_address',
      'invoice_footer',
      'fiscal_notes',
    ].contains(key);
    final maxLength = switch (key) {
      'legal_name' => 180,
      'tax_id' => 60,
      'taxpayer_type' || 'tax_status' => 100,
      'tax_regime' || 'commercial_registration' => 120,
      'billing_email' => 190,
      'billing_phone' => 40,
      _ => 5000,
    };
    return TextFormField(
      key: ValueKey('fiscal_$key'),
      controller: _controllers[key],
      maxLines: longText ? 3 : 1,
      keyboardType: key == 'billing_email'
          ? TextInputType.emailAddress
          : key == 'billing_phone'
          ? TextInputType.phone
          : TextInputType.text,
      style: TextStyle(color: CompanyVisualTheme.text),
      decoration: _decoration(label),
      validator: (input) {
        final value = (input ?? '').trim();
        if (value.length > maxLength) {
          return 'Máximo $maxLength caracteres.';
        }
        if (key == 'billing_email' &&
            value.isNotEmpty &&
            !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
          return 'Introduce un correo válido.';
        }
        return null;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: turquoise),
        ),
      );
    }

    if (_error != null) {
      return Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: surface,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_error!, style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995)))),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [CompanyVisualTheme.legacy(const Color(0xFF11242C)), CompanyVisualTheme.legacy(const Color(0xFF0A171D))],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF2A414A))),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_user_outlined, color: turquoise, size: 25),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Datos fiscales',
                    style: TextStyle(
                      color: CompanyVisualTheme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Información tributaria y de facturación de tu empresa. '
              'Solo se mostrará a los usuarios autorizados.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 22),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 700
                    ? (constraints.maxWidth - 14) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    for (final field in fields.entries)
                      SizedBox(
                        width: width,
                        child: _field(field.key, field.value),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Material(
              color: Colors.transparent,
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  'Empresa exenta de impuestos',
                  style: TextStyle(color: CompanyVisualTheme.text),
                ),
                subtitle: Text(
                  'Activa esta opción únicamente si corresponde a tu condición fiscal.',
                  style: TextStyle(color: muted),
                ),
                value: _taxExempt,
                activeThumbColor: turquoise,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _taxExempt = value),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: CompanyVisualTheme.text,
                      ),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Guardando...' : 'Guardar datos fiscales'),
              style: FilledButton.styleFrom(
                backgroundColor: turquoise,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 17,
                ),
              ),
            ),
            const SizedBox(height: 24),
            _caiSection(),
          ],
        ),
      ),
    );
  }
}
