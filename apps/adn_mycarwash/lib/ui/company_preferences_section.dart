import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import 'receipt_print_preview.dart';

/// Configuración del negocio, independiente de las preferencias del usuario.
class CompanyPreferencesSection extends StatefulWidget {
  const CompanyPreferencesSection({
    super.key,
    required this.client,
    this.companyName = 'Mi Empresa',
  });

  final http.Client client;
  final String companyName;

  @override
  State<CompanyPreferencesSection> createState() =>
      _CompanyPreferencesSectionState();
}

class _CompanyPreferencesSectionState extends State<CompanyPreferencesSection> {
  static const _turquoise = Color(0xFF0FA7B4);
  static const _surface = Color(0xFF0A1519);
  static const _border = Color(0xFF20343C);
  static const _muted = Color(0xFF9BAEB6);
  static const _path = '/settings/preferences';

  static const _dateFormats = <String, String>{
    'dd/MM/yyyy': 'Día / Mes / Año (15/11/2026)',
    'MM/dd/yyyy': 'Mes / Día / Año (11/15/2026)',
    'yyyy-MM-dd': 'Año - Mes - Día (2026-11-15)',
  };
  static const _timeFormats = <String, String>{
    '24h': '24 horas (17:30)',
    '12h': '12 horas (5:30 p. m.)',
  };
  static const _themes = <String, String>{
    'system': 'Usar tema del sistema',
    'light': 'Claro',
    'dark': 'Oscuro',
  };
  static const _paperSizes = <String, String>{
    'letter': 'Carta',
    'a4': 'A4',
    'thermal_80mm': 'Térmico 80 mm',
    'thermal_58mm': 'Térmico 58 mm',
  };

  final _formKey = GlobalKey<FormState>();
  final _locale = TextEditingController(text: 'es-HN');
  final _currency = TextEditingController(text: 'HNL');
  final _timezone = TextEditingController(text: 'America/Tegucigalpa');
  final _phoneCode = TextEditingController(text: '+504');
  final _decimals = TextEditingController(text: '2');
  final _footer = TextEditingController();

  String _dateFormat = 'dd/MM/yyyy';
  String _timeFormat = '24h';
  String _theme = 'system';
  String _paper = 'letter';
  bool _soundAlerts = true;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _loadVersion = 0;

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _loadVersion++;
    _locale.dispose();
    _currency.dispose();
    _timezone.dispose();
    _phoneCode.dispose();
    _decimals.dispose();
    _footer.dispose();
    super.dispose();
  }

  void _setFromServer(Map<String, dynamic> data) {
    _locale.text = (data['locale'] ?? 'es-HN').toString();
    _currency.text = (data['currency_code'] ?? 'HNL').toString();
    _timezone.text = (data['timezone'] ?? 'America/Tegucigalpa').toString();
    _phoneCode.text = (data['country_phone_code'] ?? '+504').toString();
    _decimals.text = (data['decimal_places'] ?? 2).toString();
    _footer.text = (data['receipt_footer'] ?? '').toString();
    final date = (data['date_format'] ?? 'dd/MM/yyyy').toString();
    final time = (data['time_format'] ?? '24h').toString();
    final theme = (data['default_theme'] ?? 'system').toString();
    final paper = (data['invoice_paper_size'] ?? 'letter').toString();
    _dateFormat = _dateFormats.containsKey(date) ? date : 'dd/MM/yyyy';
    _timeFormat = _timeFormats.containsKey(time) ? time : '24h';
    _theme = _themes.containsKey(theme) ? theme : 'system';
    _paper = _paperSizes.containsKey(paper) ? paper : 'letter';
    final alerts = data['enable_sound_alerts'];
    _soundAlerts = alerts == null || alerts == true || alerts == 1;
  }

  Future<void> _load() async {
    if (_saving) {
      return;
    }
    final version = ++_loadVersion;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.request('GET', _path);
      if (!mounted || version != _loadVersion) {
        return;
      }
      final data = response['preferences'];
      if (data is! Map) {
        throw const FormatException(
          'El servidor no devolvió las preferencias.',
        );
      }
      setState(() {
        _setFromServer(Map<String, dynamic>.from(data));
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _loadVersion) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _notify(String text, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    if (_loading || _saving) {
      return;
    }
    if (!_formKey.currentState!.validate()) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final payload = <String, dynamic>{
      'locale': _locale.text.trim(),
      'currency_code': _currency.text.trim(),
      'timezone': _timezone.text.trim(),
      'country_phone_code': _phoneCode.text.trim(),
      'decimal_places': int.parse(_decimals.text.trim()),
      'date_format': _dateFormat,
      'time_format': _timeFormat,
      'default_theme': _theme,
      'invoice_paper_size': _paper,
      'enable_sound_alerts': _soundAlerts,
      'receipt_footer': _footer.text.trim().isEmpty
          ? null
          : _footer.text.trim(),
    };
    try {
      final response = await _api.request('PATCH', _path, body: payload);
      if (!mounted) {
        return;
      }
      final data = response['preferences'];
      if (data is! Map) {
        throw const FormatException('La respuesta del servidor no es válida.');
      }
      setState(() => _setFromServer(Map<String, dynamic>.from(data)));
      _notify('Preferencias empresariales guardadas correctamente.');
    } catch (error) {
      _notify(error.toString(), error: true);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _decoration(String label, {String? hint, String? helper}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
      labelStyle: const TextStyle(color: _muted),
      hintStyle: const TextStyle(color: _muted),
      helperStyle: const TextStyle(color: _muted),
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
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE84657)),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE84657)),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget _field({
    required String keyName,
    required String label,
    required TextEditingController controller,
    String? hint,
    String? helper,
    String? Function(String?)? validator,
    TextInputType? keyboard,
    int maxLines = 1,
    int? maxLength,
  }) {
    return TextFormField(
      key: ValueKey(keyName),
      controller: controller,
      enabled: !_saving,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label, hint: hint, helper: helper),
      keyboardType: keyboard,
      maxLines: maxLines,
      maxLength: maxLength,
      validator: validator,
    );
  }

  Widget _select({
    required String keyName,
    required String label,
    required String value,
    required Map<String, String> values,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      key: ValueKey('$keyName:$value'),
      initialValue: value,
      isExpanded: true,
      dropdownColor: _surface,
      style: const TextStyle(color: Colors.white),
      decoration: _decoration(label),
      items: values.entries
          .map(
            (entry) => DropdownMenuItem<String>(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: _saving
          ? null
          : (next) {
              if (next != null) {
                setState(() => onChanged(next));
              }
            },
    );
  }

  Widget _group(String heading, List<Widget> fields) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: const Color(0xFF12242C),
        border: Border.all(color: const Color(0xFF2A414A)),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 5,
                height: 25,
                decoration: BoxDecoration(
                  color: _turquoise,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  heading,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 680
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final item in fields)
                    SizedBox(width: width, child: item),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Este dato es obligatorio.';
    }
    return null;
  }

  String? _validateLocale(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) {
      return requiredError;
    }
    if (!RegExp(r'^[a-z]{2}(?:-[A-Z]{2})?$').hasMatch(value!.trim())) {
      return 'Utiliza un idioma como es-HN o en-US.';
    }
    return null;
  }

  String? _validateCurrency(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) {
      return requiredError;
    }
    if (!RegExp(r'^[A-Z]{3}$').hasMatch(value!.trim())) {
      return 'Utiliza un código ISO de tres letras (ej. HNL).';
    }
    return null;
  }

  String? _validatePhone(String? value) {
    final requiredError = _required(value);
    if (requiredError != null) {
      return requiredError;
    }
    if (!RegExp(r'^\+[1-9][0-9]{0,5}$').hasMatch(value!.trim())) {
      return 'Utiliza un prefijo como +504.';
    }
    return null;
  }

  String? _validateDecimals(String? value) {
    final number = int.tryParse(value?.trim() ?? '');
    if (number == null || number < 0 || number > 4) {
      return 'Ingresa un entero entre 0 y 4.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF11242C), Color(0xFF0A171D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xFF2A414A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Preferencias empresariales',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Configuración general de este negocio. No modifica las '
            'preferencias personales ni la identidad oficial de ADN.',
            style: TextStyle(color: _muted),
          ),
          const SizedBox(height: 22),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(
                child: CircularProgressIndicator(color: _turquoise),
              ),
            )
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8995))),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Reintentar'),
                ),
              ],
            )
          else
            Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _group('Región e idioma', [
                    _field(
                      keyName: 'preferences_locale',
                      label: 'Idioma y región',
                      controller: _locale,
                      hint: 'es-HN',
                      validator: _validateLocale,
                    ),
                    _field(
                      keyName: 'preferences_currency',
                      label: 'Moneda (código ISO)',
                      controller: _currency,
                      hint: 'HNL',
                      validator: _validateCurrency,
                    ),
                    _field(
                      keyName: 'preferences_timezone',
                      label: 'Zona horaria (IANA)',
                      controller: _timezone,
                      hint: 'America/Tegucigalpa',
                      validator: _required,
                    ),
                    _field(
                      keyName: 'preferences_phone',
                      label: 'Prefijo telefónico',
                      controller: _phoneCode,
                      validator: _validatePhone,
                    ),
                  ]),
                  const SizedBox(height: 28),
                  _group('Formatos y apariencia', [
                    _select(
                      keyName: 'preferences_date',
                      label: 'Formato de fecha',
                      value: _dateFormat,
                      values: _dateFormats,
                      onChanged: (value) => _dateFormat = value,
                    ),
                    _select(
                      keyName: 'preferences_time',
                      label: 'Formato de hora',
                      value: _timeFormat,
                      values: _timeFormats,
                      onChanged: (value) => _timeFormat = value,
                    ),
                    _field(
                      keyName: 'preferences_decimals',
                      label: 'Cantidad de decimales (0 a 4)',
                      controller: _decimals,
                      keyboard: TextInputType.number,
                      validator: _validateDecimals,
                    ),
                    _select(
                      keyName: 'preferences_theme',
                      label: 'Tema predeterminado',
                      value: _theme,
                      values: _themes,
                      onChanged: (value) => _theme = value,
                    ),
                  ]),
                  const SizedBox(height: 28),
                  _group('Comprobantes y comunicaciones', [
                    _select(
                      keyName: 'preferences_paper',
                      label: 'Formato de papel de facturación',
                      value: _paper,
                      values: _paperSizes,
                      onChanged: (value) => _paper = value,
                    ),
                    _field(
                      keyName: 'preferences_footer',
                      label: 'Texto al pie del recibo (opcional)',
                      controller: _footer,
                      maxLines: 3,
                      maxLength: 2000,
                    ),
                  ]),
                  const SizedBox(height: 18),
                  AnimatedBuilder(
                    animation: Listenable.merge([
                      _footer,
                      _currency,
                      _decimals,
                    ]),
                    builder: (context, child) => ReceiptPrintPreview(
                      paper: _paper,
                      businessName: widget.companyName,
                      currencyCode: _currency.text,
                      decimalPlaces: int.tryParse(_decimals.text.trim()) ?? 2,
                      dateFormat: _dateFormat,
                      timeFormat: _timeFormat,
                      footer: _footer.text,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Material(
                    color: const Color(0xFF111F25),
                    borderRadius: BorderRadius.circular(10),
                    child: SwitchListTile(
                      key: const ValueKey('preferences_sound_alerts'),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                      ),
                      title: const Text(
                        'Alertas sonoras',
                        style: TextStyle(color: Colors.white),
                      ),
                      subtitle: const Text(
                        'Preferencia guardada; su aplicación a notificaciones '
                        'se integrará en una etapa posterior.',
                        style: TextStyle(color: _muted),
                      ),
                      activeThumbColor: _turquoise,
                      value: _soundAlerts,
                      onChanged: _saving
                          ? null
                          : (value) => setState(() => _soundAlerts = value),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    key: const ValueKey('preferences_save'),
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 17,
                            height: 17,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? 'Guardando...' : 'Guardar preferencias',
                    ),
                    style: FilledButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: _turquoise,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 17,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Los valores se guardan en MySQL para esta empresa. '
                    'Su aplicación global a impresión, moneda, tema y avisos '
                    'se implementará en etapas posteriores.',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
