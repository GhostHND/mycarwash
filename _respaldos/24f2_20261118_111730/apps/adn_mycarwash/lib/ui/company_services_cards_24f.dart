import 'package:flutter/material.dart';

class CompanyServicesCards24F extends StatelessWidget {
  const CompanyServicesCards24F({
    super.key,
    required this.records,
    required this.onEdit,
    required this.onArchive,
    required this.onPrices,
  });
  final List<Map<String, dynamic>> records;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onArchive;
  final void Function(Map<String, dynamic>) onPrices;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final cols = constraints.maxWidth >= 1050
          ? 3
          : constraints.maxWidth >= 650
          ? 2
          : 1;
      const gap = 14.0;
      final width = (constraints.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final r in records)
            SizedBox(
              width: width,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.local_car_wash_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${r['name'] ?? 'Servicio'}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 17,
                            ),
                          ),
                        ),
                        Text(
                          r['is_active'] == false || r['is_active'] == 0
                              ? 'Inactivo'
                              : 'Activo',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('${r['description'] ?? ''}'),
                    const SizedBox(height: 8),
                    Text('Duración: ${r['duration_minutes'] ?? '-'} min'),
                    Text('Precio base: L ${r['price'] ?? '-'}'),
                    const Divider(),
                    const Text(
                      'Precios por tipo de vehículo',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if ((r['vehicle_prices'] as List?)?.isNotEmpty == true)
                      for (final p in (r['vehicle_prices'] as List))
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Expanded(child: Text('${p['vehicle_type']}')),
                              Text('L ${p['price']}'),
                            ],
                          ),
                        )
                    else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Usa precio base hasta configurar tarifas'),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      children: [
                        TextButton.icon(
                          onPressed: () => onPrices(r),
                          icon: const Icon(Icons.payments_outlined),
                          label: const Text('Tarifas'),
                        ),
                        IconButton(
                          tooltip: 'Editar servicio',
                          onPressed: () => onEdit(r),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Archivar servicio',
                          onPressed: () => onArchive(r),
                          icon: const Icon(Icons.archive_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
