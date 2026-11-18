import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'company_employee_cards_24c3.dart';

class CompanyStaffScheduleGrid24C3 extends StatelessWidget {
  const CompanyStaffScheduleGrid24C3({
    super.key,
    required this.rows,
    required this.roster,
    required this.client,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });
  final List<Map<String, dynamic>> rows;
  final bool roster;
  final http.Client client;
  final ValueChanged<Map<String, dynamic>> onView;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;
  static const days = [
    'Domingo',
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
  ];
  String _value(Object? value, [String fallback = 'No registrado']) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Widget _line(IconData icon, String label, String value, Color accent) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, color: accent, size: 17),
            const SizedBox(width: 9),
            Expanded(
              child: Tooltip(
                message: '$label: $value',
                child: Text(
                  '$label: $value',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
  Widget _card(BuildContext context, Map<String, dynamic> row) {
    final scheme = Theme.of(context).colorScheme;
    final id = int.tryParse('${row['id']}') ?? 0;
    final employeeId = int.tryParse('${row['employee_id']}') ?? 0;
    final active = row['is_active'] != false && row['is_active'] != 0;
    final day = int.tryParse('${row['day_of_week']}');
    final weekday = day != null && day >= 0 && day < 7
        ? days[day]
        : 'No registrado';
    return Container(
      key: ValueKey('staff_schedule_card_$id'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: scheme.primary.withValues(alpha: .7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                roster ? Icons.badge_outlined : Icons.schedule_outlined,
                color: scheme.primary,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  roster
                      ? _value(row['employee_name'], 'Empleado ID $employeeId')
                      : _value(row['name']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                active ? 'Activo' : 'Inactivo',
                style: TextStyle(
                  fontSize: 11,
                  color: active ? const Color(0xFF27CC9D) : scheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (roster) ...[
            SizedBox(
              height: 120,
              width: double.infinity,
              child: employeeId > 0
                  ? CompanyEmployeePhoto24C3(
                      client: client,
                      employeeId: employeeId,
                    )
                  : Icon(Icons.person_outline, size: 74, color: scheme.primary),
            ),
            const SizedBox(height: 11),
            _line(
              Icons.schedule_outlined,
              'Turno',
              _value(row['shift_name'], 'Turno ID ${_value(row['shift_id'])}'),
              scheme.primary,
            ),
            _line(
              Icons.today_outlined,
              'Desde',
              _value(row['effective_from']),
              scheme.primary,
            ),
            _line(
              Icons.event_outlined,
              'Hasta',
              _value(row['effective_to'], 'Indefinido'),
              scheme.primary,
            ),
          ] else ...[
            const SizedBox(height: 20),
            Center(
              child: Icon(
                Icons.calendar_month_outlined,
                size: 60,
                color: scheme.primary,
              ),
            ),
            const SizedBox(height: 22),
            _line(
              Icons.calendar_today_outlined,
              'Día',
              weekday,
              scheme.primary,
            ),
            _line(
              Icons.login_outlined,
              'Entrada',
              _value(row['starts_at']),
              scheme.primary,
            ),
            _line(
              Icons.logout_outlined,
              'Salida',
              _value(row['ends_at']),
              scheme.primary,
            ),
            _line(
              Icons.store_outlined,
              'Sucursal',
              _value(row['branch_name'], 'ID ${_value(row['branch_id'])}'),
              scheme.primary,
            ),
          ],
          Tooltip(
            message: _value(row['notes']),
            child: Text(
              'Observaciones: ${_value(row['notes'])}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ),
          const Spacer(),
          Divider(color: scheme.primary.withValues(alpha: .35)),
          Row(
            children: [
              Text(
                'ID $id',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Detalle',
                onPressed: () => onView(row),
                icon: const Icon(Icons.visibility_outlined),
              ),
              IconButton(
                tooltip: 'Editar',
                onPressed: () => onEdit(row),
                icon: Icon(Icons.edit_outlined, color: scheme.primary),
              ),
              IconButton(
                tooltip: 'Archivar',
                onPressed: () => onDelete(row),
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
            SizedBox(
              width: w,
              height: roster ? 420 : 380,
              child: _card(context, row),
            ),
        ],
      );
    },
  );
}
