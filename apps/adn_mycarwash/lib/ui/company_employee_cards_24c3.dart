import 'dart:typed_data';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/mycarwash_session.dart';

String staffValue(Object? value, [String fallback = 'No registrado']) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

/// Fotografía privada del empleado; no utiliza URL pública ni comparte empresas.
class CompanyEmployeePhoto24C3 extends StatefulWidget {
  const CompanyEmployeePhoto24C3({
    super.key,
    required this.client,
    required this.employeeId,
  });
  final http.Client client;
  final int employeeId;

  @override
  State<CompanyEmployeePhoto24C3> createState() =>
      _CompanyEmployeePhoto24C3State();
}

class _CompanyEmployeePhoto24C3State extends State<CompanyEmployeePhoto24C3> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyEmployeePhoto24C3 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.employeeId != widget.employeeId) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.employeeId;
    if (mounted) {
      setState(() {
        _loading = true;
        _bytes = null;
      });
    }
    try {
      final uri = Uri.parse(
        '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/employees/$id/file',
      );
      final response = await widget.client
          .get(uri, headers: MyCarWashSession.headers)
          .timeout(const Duration(seconds: 12));
      if (mounted && id == widget.employeeId) {
        setState(() {
          _bytes = response.statusCode == 200 && response.bodyBytes.isNotEmpty
              ? response.bodyBytes
              : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && id == widget.employeeId) {
        setState(() {
          _bytes = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 23,
          height: 23,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes == null) {
      return Center(
        child: Icon(
          Icons.person_outline,
          color: Theme.of(context).colorScheme.primary,
          size: 70,
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) =>
          const Center(child: Icon(Icons.person_outline, size: 58)),
    );
  }
}

class CompanyEmployeesGrid24C3 extends StatelessWidget {
  const CompanyEmployeesGrid24C3({
    super.key,
    required this.rows,
    required this.client,
    required this.onEdit,
    required this.onArchive,
    this.commissionsToday = const {},
  });
  final Map<int, String> commissionsToday;
  final List<Map<String, dynamic>> rows;
  final http.Client client;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onArchive;

  Widget _line(IconData icon, String label, String value, Color muted) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: muted),
            const SizedBox(width: 8),
            Text('$label: ', style: TextStyle(color: muted, fontSize: 14)),
            Expanded(
              child: Tooltip(
                message: value,
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: CompanyVisualTheme.text, fontSize: 14),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _card(BuildContext context, Map<String, dynamic> row) {
    final scheme = Theme.of(context).colorScheme;
    final id = int.tryParse('${row['id']}') ?? 0;
    final inactive = row['is_active'] == false || row['is_active'] == 0;
    final title = staffValue(row['full_name'], 'Sin nombre');
    const cargos = {
      'washer': 'Lavador',
      'supervisor': 'Supervisor',
      'cashier': 'Cajero',
      'manager': 'Administrador',
      'other': 'Otro',
    };
    final position = '${row['position'] ?? ''}';
    final role = cargos[position] ?? staffValue(row['position']);
    return Container(
      key: ValueKey('employee_card_$id'),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: scheme.primary.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: title,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: CompanyVisualTheme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(inactive ? 'Inactivo' : 'Activo',
                  style: TextStyle(color: inactive ? scheme.error :
                    CompanyVisualTheme.legacy(const Color(0xFF27CC9D)), fontSize: 14)),
                const SizedBox(height: 5),
                Text('Comisión hoy: L ${commissionsToday[id] ?? '0.00'}',
                  style: TextStyle(color: scheme.primary, fontSize: 12,
                    fontWeight: FontWeight.w700)),
              ]),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            height: 150,
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: id > 0
                ? CompanyEmployeePhoto24C3(
                    key: ValueKey('employee_photo_$id'),
                    client: client,
                    employeeId: id,
                  )
                : const Icon(Icons.person_outline, size: 70),
          ),
          const SizedBox(height: 11),
          _line(Icons.badge_outlined, 'Cargo', role, scheme.onSurfaceVariant),
          _line(
            Icons.phone_outlined,
            'Teléfono',
            staffValue(row['phone']),
            scheme.onSurfaceVariant,
          ),
          _line(
            Icons.credit_card_outlined,
            'Documento',
            staffValue(row['identity_document']),
            scheme.onSurfaceVariant,
          ),
          _line(
            Icons.mail_outline,
            'Correo',
            staffValue(row['email']),
            scheme.onSurfaceVariant,
          ),
          _line(
            Icons.event_available_outlined,
            'Ingreso',
            staffValue(row['hire_date']),
            scheme.onSurfaceVariant,
          ),
          _line(Icons.numbers_outlined, 'ID', '$id', scheme.onSurfaceVariant),
          Tooltip(
            message: staffValue(row['notes']),
            child: Text(
              'Observaciones: ${staffValue(row['notes'])}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
            ),
          ),
          const Spacer(),
          Divider(color: scheme.primary.withValues(alpha: .35)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: ValueKey('employee_edit_$id'),
                onPressed: () => onEdit(row),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 17,
                  color: scheme.primary,
                ),
                label: const Text('Editar'),
              ),
              IconButton(
                key: ValueKey('employee_archive_$id'),
                tooltip: 'Archivar empleado',
                onPressed: () => onArchive(row),
                icon: Icon(Icons.archive_outlined, color: scheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 1050
          ? 3
          : width >= 690
          ? 2
          : 1;
      const gap = 14.0;
      final w = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final row in rows)
            SizedBox(width: w, height: 542, child: _card(context, row)),
        ],
      );
    },
  );
}
