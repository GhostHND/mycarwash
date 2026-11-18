import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

class CompanyFiscalSection extends StatefulWidget {
  const CompanyFiscalSection({super.key, required this.client});

  final http.Client client;

  @override
  State<CompanyFiscalSection> createState() => _CompanyFiscalSectionState();
}

class _CompanyFiscalSectionState extends State<CompanyFiscalSection> {
  static const turquoise = Color(0xFF0FA7B4);
  static const surface = Color(0xFF0A1519);
  static const border = Color(0xFF20343C);
  static const muted = Color(0xFF9BAEB6);

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

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _load();
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
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
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

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: muted),
    filled: true,
    fillColor: const Color(0xFF111F25),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: border),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: turquoise),
      borderRadius: BorderRadius.circular(10),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFFE84657)),
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
      style: const TextStyle(color: Colors.white),
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
      return const Center(
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
            Text(_error!, style: const TextStyle(color: Color(0xFFFF8995))),
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
        gradient: const LinearGradient(
          colors: [Color(0xFF11242C), Color(0xFF0A171D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: const Color(0xFF2A414A)),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.verified_user_outlined, color: turquoise, size: 25),
                SizedBox(width: 11),
                Expanded(
                  child: Text(
                    'Datos fiscales',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
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
                title: const Text(
                  'Empresa exenta de impuestos',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
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
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
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
          ],
        ),
      ),
    );
  }
}
