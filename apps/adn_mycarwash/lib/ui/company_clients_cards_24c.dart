import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';

/// Cuadrícula exclusiva de Clientes; las operaciones CRUD siguen en la página
/// existente. El tema procede de ThemeData (sin colores de marca incrustados).
class CompanyClientsCardGrid24C extends StatelessWidget {
  const CompanyClientsCardGrid24C({
    super.key,
    required this.rows,
    required this.accent,
    required this.onEdit,
    required this.onArchive,
  });

  final List<Map<String, dynamic>> rows;
  final Color accent;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onArchive;

  static String _value(Object? value, String fallback) {
    final text = (value ?? '').toString().trim();
    return text.isEmpty ? fallback : text;
  }

  Widget _detail(IconData icon, String value, Color muted) => Row(
    children: [
      Icon(icon, size: 15, color: muted),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: muted, fontSize: 12),
        ),
      ),
    ],
  );

  Widget _card(BuildContext context, Map<String, dynamic> row) {
    final scheme = Theme.of(context).colorScheme;
    final active = row['is_active'] != false && row['is_active'] != 0;
    final statusColor = active ? CompanyVisualTheme.legacy(const Color(0xFF1CB88D)) : scheme.error;
    final border = Color.lerp(accent, scheme.surface, 0.48)!;
    final name = _value(row['full_name'], 'Sin nombre');
    return Container(
      key: ValueKey('customer_card_${row['id']}'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: accent.withValues(alpha: 0.15),
                child: Icon(Icons.person_outline, color: accent, size: 22),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Tooltip(
                  message: name,
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 5),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.10),
                  border: Border.all(color: statusColor),
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  active ? '● Activo' : '● Inactivo',
                  style: TextStyle(color: statusColor, fontSize: 10),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: [
                    _detail(
                      Icons.phone_outlined,
                      _value(row['phone'], 'Sin teléfono registrado'),
                      scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    _detail(
                      Icons.badge_outlined,
                      _value(
                        row['identity_document'],
                        'Sin documento registrado',
                      ),
                      scheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(height: 42, width: 1, color: border),
              const SizedBox(width: 8),
              Text(
                'ID ${row['id'] ?? '—'}',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
              ),
            ],
          ),
          const Spacer(),
          Divider(color: border, height: 18),
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: _value(row['email'], 'Sin correo registrado'),
                  child: _detail(
                    Icons.email_outlined,
                    _value(row['email'], 'Sin correo registrado'),
                    scheme.onSurfaceVariant,
                  ),
                ),
              ),
              IconButton(
                key: ValueKey('customer_edit_${row['id']}'),
                tooltip: 'Editar cliente',
                onPressed: () => onEdit(row),
                icon: Icon(Icons.edit_outlined, color: accent, size: 19),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 35, minHeight: 35),
              ),
              IconButton(
                key: ValueKey('customer_archive_${row['id']}'),
                tooltip: 'Archivar cliente',
                onPressed: () => onArchive(row),
                icon: Icon(
                  Icons.archive_outlined,
                  color: scheme.error,
                  size: 19,
                ),
                visualDensity: VisualDensity.compact,
                constraints: const BoxConstraints(minWidth: 35, minHeight: 35),
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
      final columns = width >= 1000
          ? 3
          : width >= 640
          ? 2
          : 1;
      final gap = 14.0;
      final cardWidth = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final row in rows)
            SizedBox(width: cardWidth, height: 188, child: _card(context, row)),
        ],
      );
    },
  );
}
