import 'dart:convert';

import 'package:flutter/material.dart';

class MasterOption24N9 {
  const MasterOption24N9(this.value, this.label);
  final String value;
  final String label;
}

class MasterField24N9 {
  const MasterField24N9(
    this.key,
    this.title, {
    this.required = false,
    this.numeric = false,
    this.integer = false,
    this.secret = false,
    this.multiline = false,
    this.date = false,
    this.options,
  });
  final String key;
  final String title;
  final bool required;
  final bool numeric;
  final bool integer;
  final bool secret;
  final bool multiline;
  final bool date;
  final List<MasterOption24N9>? options;
}

Future<Map<String, dynamic>?> showMasterForm24N9(
  BuildContext context, {
  required String title,
  required List<MasterField24N9> fields,
  Map<String, dynamic>? initial,
  bool planFeatures = false,
}) {
  return showDialog<Map<String, dynamic>>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _MasterForm24N9(
      title: title,
      fields: fields,
      initial: initial ?? const <String, dynamic>{},
      planFeatures: planFeatures,
    ),
  );
}

class _MasterForm24N9 extends StatefulWidget {
  const _MasterForm24N9({
    required this.title,
    required this.fields,
    required this.initial,
    required this.planFeatures,
  });
  final String title;
  final List<MasterField24N9> fields;
  final Map<String, dynamic> initial;
  final bool planFeatures;

  @override
  State<_MasterForm24N9> createState() => _MasterForm24N9State();
}

class _MasterForm24N9State extends State<_MasterForm24N9> {
  static const accent = Color(0xFF07D5DB);
  static const background = Color(0xFF081D22);
  static const outline = Color(0xFF294E56);
  final _key = GlobalKey<FormState>();
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String> _selections = {};
  final Map<String, bool> _features = {};

  @override
  void initState() {
    super.initState();
    for (final field in widget.fields) {
      final value = widget.initial[field.key];
      if (field.options != null) {
        final key = value?.toString() ?? '';
        _selections[field.key] = field.options!.any((item) => item.value == key)
            ? key
            : '';
      } else {
        _controllers[field.key] = TextEditingController(
          text: field.secret ? '' : (value?.toString() ?? ''),
        );
      }
    }
    Map<String, dynamic> values = {};
    final raw = widget.initial['features'];
    if (raw is Map) {
      values = Map<String, dynamic>.from(raw);
    } else if (raw is String) {
      try {
        values = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      } catch (_) {
        values = {};
      }
    }
    for (final name in ['operations', 'monitor', 'marketing_site', 'editor']) {
      _features[name] =
          values[name] == true || (values.isEmpty && name == 'operations');
    }
  }

  @override
  void dispose() {
    for (final control in _controllers.values) {
      control.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(MasterField24N9 field) async {
    final value = _controllers[field.key]!.text;
    final parsed = DateTime.tryParse(value);
    final chosen = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: accent,
            surface: background,
          ),
        ),
        child: child!,
      ),
    );
    if (chosen != null && mounted) {
      _controllers[field.key]!.text =
          '${chosen.year.toString().padLeft(4, '0')}-${chosen.month.toString().padLeft(2, '0')}-${chosen.day.toString().padLeft(2, '0')}';
    }
  }

  String? _validate(MasterField24N9 field, String? input) {
    final value = (input ?? '').trim();
    if (field.required && value.isEmpty) {
      return 'Este dato es obligatorio';
    }
    if (value.isEmpty) {
      return null;
    }
    if (field.numeric && num.tryParse(value) == null) {
      return 'Introduce un importe válido';
    }
    if (field.integer && int.tryParse(value) == null) {
      return 'Selecciona un número entero';
    }
    if (field.date && !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      return 'Usa AAAA-MM-DD';
    }
    if (field.secret && value.length < 12) {
      return 'Mínimo 12 caracteres';
    }
    return null;
  }

  void _save() {
    if (!_key.currentState!.validate()) {
      return;
    }
    final output = <String, dynamic>{};
    for (final field in widget.fields) {
      String raw;
      if (field.options != null) {
        raw = _selections[field.key] ?? '';
      } else {
        raw = _controllers[field.key]!.text.trim();
      }
      if (raw.isEmpty) {
        output[field.key] = null;
      } else if (field.numeric) {
        output[field.key] = num.parse(raw);
      } else if (field.integer ||
          (field.options != null &&
              [
                'customer_id',
                'plan_id',
                'company_id',
                'invoice_id',
              ].contains(field.key))) {
        output[field.key] = int.parse(raw);
      } else if (field.key == 'is_active') {
        output[field.key] = raw == '1';
      } else {
        output[field.key] = raw;
      }
    }
    if (widget.planFeatures) {
      output['features'] = Map<String, bool>.from(_features);
    }
    Navigator.of(context).pop(output);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: outline),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.sizeOf(context).height * .86,
        ),
        child: Padding(
          padding: EdgeInsets.all(width < 600 ? 18 : 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune_rounded, color: accent, size: 26),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Los datos se guardan en la administración maestra.',
                style: TextStyle(color: Color(0xFF9CBBC0), fontSize: 12),
              ),
              const Divider(height: 28, color: outline),
              Flexible(
                child: Form(
                  key: _key,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final field in widget.fields) ...[
                          if (field.options != null)
                            DropdownButtonFormField<String>(
                              initialValue: _selections[field.key],
                              isExpanded: true,
                              dropdownColor: background,
                              decoration: InputDecoration(
                                labelText: field.title,
                                prefixIcon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  size: 20,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: '',
                                  child: Text('Seleccionar / sin asignar'),
                                ),
                                for (final option in field.options!)
                                  DropdownMenuItem(
                                    value: option.value,
                                    child: Text(
                                      option.label,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                              onChanged: (value) =>
                                  _selections[field.key] = value ?? '',
                              validator: (v) => _validate(field, v),
                            )
                          else
                            TextFormField(
                              controller: _controllers[field.key],
                              obscureText: field.secret,
                              maxLines: field.multiline ? 4 : 1,
                              keyboardType: field.numeric || field.integer
                                  ? const TextInputType.numberWithOptions(
                                      decimal: true,
                                    )
                                  : field.multiline
                                  ? TextInputType.multiline
                                  : TextInputType.text,
                              decoration: InputDecoration(
                                labelText: field.title,
                                suffixIcon: field.date
                                    ? IconButton(
                                        tooltip: 'Elegir fecha',
                                        onPressed: () => _pickDate(field),
                                        icon: const Icon(
                                          Icons.calendar_month_rounded,
                                          color: accent,
                                        ),
                                      )
                                    : null,
                              ),
                              validator: (v) => _validate(field, v),
                            ),
                          const SizedBox(height: 14),
                        ],
                        if (widget.planFeatures) ...[
                          const SizedBox(height: 4),
                          const Text(
                            'Habilitaciones del plan',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final feature in const [
                            ('operations', 'Operaciones y administración'),
                            ('monitor', 'Monitor Raspberry Pi'),
                            ('marketing_site', 'Sitio web comercial'),
                            ('editor', 'Editor modular Pro'),
                          ])
                            SwitchListTile.adaptive(
                              dense: true,
                              activeThumbColor: accent,
                              contentPadding: EdgeInsets.zero,
                              title: Text(feature.$2),
                              value: _features[feature.$1] ?? false,
                              onChanged: (v) =>
                                  setState(() => _features[feature.$1] = v),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 24, color: outline),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
