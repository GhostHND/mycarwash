import 'package:flutter/material.dart';

class CompanyWorkflowCards24F extends StatelessWidget {
  const CompanyWorkflowCards24F({
    super.key,
    required this.module,
    required this.records,
    required this.onEdit,
    required this.onArchive,
  });
  final String module;
  final List<Map<String, dynamic>> records;
  final void Function(Map<String, dynamic>) onEdit;
  final void Function(Map<String, dynamic>) onArchive;
  String text(
    Map<String, dynamic> r,
    String k, [
    String fallback = 'No registrado',
  ]) {
    final v = '${r[k] ?? ''}'.trim();
    return v.isEmpty ? fallback : v;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, size) {
      final columns = size.maxWidth >= 1100
          ? 3
          : size.maxWidth >= 650
          ? 2
          : 1;
      const gap = 14.0;
      final width = (size.maxWidth - (columns - 1) * gap) / columns;
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
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.7),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          module == 'bays'
                              ? Icons.garage_outlined
                              : module == 'queue'
                              ? Icons.schedule
                              : Icons.people_alt_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            module == 'bays'
                                ? text(r, 'name')
                                : module == 'queue'
                                ? text(r, 'vehicle_label')
                                : text(r, 'employee_name'),
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (module != 'queue')
                          IconButton(
                            tooltip: 'Editar',
                            onPressed: () => onEdit(r),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                        if (module != 'queue')
                          IconButton(
                            tooltip: 'Archivar o liberar',
                            onPressed: () => onArchive(r),
                            icon: const Icon(Icons.archive_outlined),
                          ),
                      ],
                    ),
                    const Divider(),
                    if (module == 'bays') ...[
                      Text('Código: ${text(r, 'code')}'),
                      Text('Sucursal: ${text(r, 'branch_id')}'),
                      Text(
                        'Estado: ${r['is_active'] == false || r['is_active'] == 0 ? 'Inactivo' : 'Activo'}',
                      ),
                      Text('Notas: ${text(r, 'notes')}'),
                    ] else if (module == 'assignments') ...[
                      Text('Orden: ${text(r, 'order_id')}'),
                      Text('Empleado: ${text(r, 'employee_name')}'),
                      Text('Función: ${text(r, 'function')}'),
                      Text(
                        'Principal: ${r['is_primary'] == true || r['is_primary'] == 1 ? 'Sí' : 'No'}',
                      ),
                      Text(
                        'Estado: ${r['is_active'] == false || r['is_active'] == 0 ? 'Liberado' : 'Activo'}',
                      ),
                      Text('Asignado: ${text(r, 'assigned_at')}'),
                    ] else ...[
                      Text('Orden: ${text(r, 'tracking_code')}'),
                      Text('Estado: ${text(r, 'status')}'),
                      Text('Servicio: ${text(r, 'service_name')}'),
                      Text('Importe: L ${text(r, 'quoted_price')}'),
                    ],
                  ],
                ),
              ),
            ),
        ],
      );
    },
  );
}
