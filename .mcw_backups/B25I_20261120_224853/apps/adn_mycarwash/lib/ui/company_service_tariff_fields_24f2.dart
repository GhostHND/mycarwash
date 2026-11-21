import 'package:flutter/material.dart';

/// Borrador de tarifas dentro del formulario de alta/edición de servicios.
/// No modifica datos hasta que se guarda el servicio.
class ServiceVehicleTariffDraft24F2 {
  ServiceVehicleTariffDraft24F2(List<dynamic> existing) {
    for (final type in defaultTypes) {
      controllers[type] = TextEditingController();
    }
    for (final row in existing) {
      if (row is! Map) {
        continue;
      }
      final type = '${row['vehicle_type'] ?? ''}'.trim();
      if (type.isEmpty) {
        continue;
      }
      controllers.putIfAbsent(type, () => TextEditingController());
      enabled.add(type);
      controllers[type]!.text = '${row['price'] ?? ''}';
    }
  }

  static const defaultTypes = <String>[
    'Turismo',
    'Pickup',
    'SUV',
    'Camioneta',
    'Motocicleta',
    'Microbús',
    'Camión',
  ];

  final Map<String, TextEditingController> controllers = {};
  final Set<String> enabled = {};
  bool saving = false;

  List<Map<String, dynamic>> validatedPrices() {
    final values = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final type in controllers.keys) {
      if (!enabled.contains(type)) {
        continue;
      }
      final name = type.trim();
      final value = controllers[type]!.text.trim();
      if (name.isEmpty || name.length > 60 || !seen.add(name.toLowerCase())) {
        throw FormatException('Categoría inválida o repetida: $type');
      }
      if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(value)) {
        throw FormatException(
          'Indica un precio válido para $type (máximo 2 decimales).',
        );
      }
      final number = double.tryParse(value);
      if (number == null ||
          !number.isFinite ||
          number < 0 ||
          number > 9999999999.99) {
        throw FormatException('Precio inválido para $type.');
      }
      values.add({'vehicle_type': name, 'price': number});
    }
    return values;
  }

  void dispose() {
    for (final item in controllers.values) {
      item.dispose();
    }
  }
}

class CompanyServiceTariffFields24F2 extends StatefulWidget {
  const CompanyServiceTariffFields24F2({super.key, required this.draft});
  final ServiceVehicleTariffDraft24F2 draft;

  @override
  State<CompanyServiceTariffFields24F2> createState() =>
      _CompanyServiceTariffFields24F2State();
}

class _CompanyServiceTariffFields24F2State
    extends State<CompanyServiceTariffFields24F2> {
  final _newCategory = TextEditingController();

  @override
  void dispose() {
    _newCategory.dispose();
    super.dispose();
  }

  void _addCategory() {
    final name = _newCategory.text.trim();
    if (name.isEmpty || name.length > 60) {
      return;
    }
    final duplicate = widget.draft.controllers.keys.any(
      (type) => type.toLowerCase() == name.toLowerCase(),
    );
    if (duplicate) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('La categoría ya existe. Actívala en la lista.'),
        ),
      );
      return;
    }
    setState(() {
      widget.draft.controllers[name] = TextEditingController();
      widget.draft.enabled.add(name);
      _newCategory.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 24),
        const Text(
          'Precios por tipo de vehículo',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Activa las categorías que atenderá este servicio y escribe el precio de cada una. Las desactivadas no se cobrarán con tarifa específica.',
        ),
        const SizedBox(height: 10),
        for (final entry in widget.draft.controllers.entries) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              border: Border.all(color: color.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    entry.key,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  value: widget.draft.enabled.contains(entry.key),
                  onChanged: (value) => setState(() {
                    if (value) {
                      widget.draft.enabled.add(entry.key);
                    } else {
                      widget.draft.enabled.remove(entry.key);
                    }
                  }),
                ),
                if (widget.draft.enabled.contains(entry.key))
                  TextFormField(
                    key: ValueKey('service_tariff_${entry.key}'),
                    controller: entry.value,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Precio de ${entry.key} (L)',
                      prefixText: 'L ',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    validator: (value) {
                      if (!widget.draft.enabled.contains(entry.key)) {
                        return null;
                      }
                      final raw = (value ?? '').trim();
                      if (!RegExp(r'^\d+(?:\.\d{1,2})?$').hasMatch(raw)) {
                        return 'Introduce un precio válido, máximo 2 decimales.';
                      }
                      final n = double.tryParse(raw);
                      if (n == null ||
                          !n.isFinite ||
                          n < 0 ||
                          n > 9999999999.99) {
                        return 'Precio fuera del rango permitido.';
                      }
                      return null;
                    },
                  ),
              ],
            ),
          ),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newCategory,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'Otra categoría registrada',
                  hintText: 'Ej. Furgoneta',
                  border: OutlineInputBorder(),
                  counterText: '',
                ),
                onSubmitted: (_) => _addCategory(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Agregar categoría',
              onPressed: _addCategory,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
        const SizedBox(height: 5),
        const Text(
          'El tipo debe coincidir con el registrado en el vehículo. Una categoría sin tarifa activa no tendrá precio específico.',
        ),
      ],
    );
  }
}
