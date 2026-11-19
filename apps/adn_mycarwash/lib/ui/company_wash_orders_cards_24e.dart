import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';

typedef OrderAction = void Function(Map<String, dynamic> order);

class CompanyWashOrdersCards24E extends StatelessWidget {
  const CompanyWashOrdersCards24E({
    super.key,
    required this.orders,
    required this.summary,
    required this.loading,
    required this.error,
    required this.search,
    required this.filter,
    required this.page,
    required this.pages,
    required this.onSearch,
    required this.onFilter,
    required this.onCreate,
    required this.onRefresh,
    required this.onPage,
    required this.onEdit,
    required this.onDetail,
    required this.onDelete,
    required this.onAdvance,
    required this.onAssign,
    required this.selectedDate,
    required this.onDate,
  });

  final List<Map<String, dynamic>> orders;
  final Map<String, dynamic> summary;
  final bool loading;
  final String? error;
  final TextEditingController search;
  final String filter;
  final int page;
  final int pages;
  final ValueChanged<String> onSearch;
  final ValueChanged<String> onFilter;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;
  final ValueChanged<int> onPage;
  final OrderAction onEdit;
  final OrderAction onDetail;
  final OrderAction onDelete;
  final OrderAction onAdvance;
  final OrderAction onAssign;
  final String? selectedDate;
  final ValueChanged<String?> onDate;

  static Color get accent => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get ink => CompanyVisualTheme.legacy(const Color(0xFF07161B));
  static Color get line => CompanyVisualTheme.legacy(const Color(0xFF26525B));
  static Color get faded => CompanyVisualTheme.legacy(const Color(0xFF9DB5BD));

  String _status(String status) => switch (status) {
    'EN_ESPERA' => 'Nueva',
    'ASIGNADO' => 'En espera',
    'EN_PROCESO' => 'En proceso',
    'TERMINADO' => 'Terminada',
    'ENTREGADO' => 'Entregada',
    'CANCELADO' => 'Cancelada',
    _ => status,
  };

  Color _statusColor(String status) => switch (status) {
    'EN_ESPERA' => CompanyVisualTheme.legacy(const Color(0xFF48B7F1)),
    'ASIGNADO' => CompanyVisualTheme.legacy(const Color(0xFFF5BB43)),
    'EN_PROCESO' => accent,
    'TERMINADO' => CompanyVisualTheme.legacy(const Color(0xFF25D49A)),
    'ENTREGADO' => CompanyVisualTheme.legacy(const Color(0xFF77C79B)),
    'CANCELADO' => CompanyVisualTheme.legacy(const Color(0xFFE47B82)),
    _ => faded,
  };

  String _value(dynamic v, [String empty = 'No registrado']) =>
      v == null || '$v'.trim().isEmpty ? empty : '$v';

  Widget _panel({required Widget child, EdgeInsets? padding}) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: ink,
      border: Border.all(color: line),
      borderRadius: BorderRadius.circular(17),
    ),
    child: child,
  );

  Widget _kpi(String title, dynamic count, String status, IconData icon) {
    final color = _statusColor(status);
    return InkWell(
      onTap: () => onFilter(status),
      borderRadius: BorderRadius.circular(13),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: filter == status ? color.withValues(alpha: 0.12) : ink,
          border: Border.all(color: filter == status ? color : line),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 12, color: faded),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: color,
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(icon, color: color, size: 24),
          ],
        ),
      ),
    );
  }

  Widget _tiny(String label, dynamic value, {bool alignRight = false}) =>
      Column(
        crossAxisAlignment: alignRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(color: faded, fontSize: 11)),
          const SizedBox(height: 3),
          Text(
            _value(value),
            textAlign: alignRight ? TextAlign.end : TextAlign.start,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      );

  Widget _card(Map<String, dynamic> order) {
    final state = '${order['status'] ?? ''}';
    final colors = _statusColor(state);
    final washers = order['washer_names'] is List
        ? (order['washer_names'] as List).map((value) => '$value').join(', ')
        : '';
    final raw = order['quoted_price'];
    final money = double.tryParse('$raw');
    final code = _value(order['tracking_code']);
    final allowed = ['ASIGNADO', 'EN_PROCESO', 'TERMINADO'].contains(state);
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ink,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: code,
                  child: Text(
                    code,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: faded, fontSize: 11),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: colors.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  _status(state),
                  style: TextStyle(
                    color: colors,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.directions_car_outlined, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _value(
                        order['vehicle_label'],
                        'Vehículo no identificado',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Placa: ${_value(order['plate'], 'Sin placa')}',
                      style: TextStyle(color: faded, fontSize: 12),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Ver detalle',
                onPressed: () => onDetail(order),
                icon: Icon(Icons.visibility_outlined, color: accent),
              ),
              IconButton(
                tooltip: 'Editar',
                onPressed: () => onEdit(order),
                icon: Icon(Icons.edit_outlined, color: accent),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: line),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _tiny('Cliente', order['client_name'])),
              const SizedBox(width: 10),
              Expanded(
                child: _tiny(
                  'Servicio',
                  order['service_name'],
                  alignRight: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _tiny(
                  'Lavador(es) · ${_value(order['bay_name'], 'Sin bahía')}',
                  washers.isEmpty ? 'Por asignar' : washers,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Importe',
                    style: TextStyle(color: faded, fontSize: 11),
                  ),
                  Text(
                    money == null
                        ? 'Sin importe'
                        : 'L ${money.toStringAsFixed(2)}',
                    style: TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          if (state == 'EN_ESPERA' || state == 'ASIGNADO')
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: ValueKey('quick_assign_${order['id']}'),
                onPressed: () => onAssign(order),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                label: const Text('Asignar lavador'),
              ),
            ),
          Divider(color: line),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Cambiar estado',
                  style: TextStyle(color: faded, fontSize: 12),
                ),
              ),
              if (state == 'EN_ESPERA' || state == 'ASIGNADO')
                IconButton(
                  tooltip: 'Cancelar orden',
                  onPressed: () => onDelete(order),
                  icon: const Icon(
                    Icons.archive_outlined,
                    color: Colors.redAccent,
                    size: 19,
                  ),
                ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: allowed ? () => onAdvance(order) : null,
              icon: Icon(
                state == 'TERMINADO'
                    ? Icons.payments_outlined
                    : Icons.arrow_forward,
                size: 18,
              ),
              label: Text(switch (state) {
                'ASIGNADO' => 'Iniciar lavado',
                'EN_PROCESO' => 'Terminar lavado',
                'TERMINADO' => 'Cobrar y entregar',
                _ => _status(state),
              }),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: line),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filters = <String, String>{
      'TODAS': 'Todas',
      'EN_ESPERA': 'Nuevas',
      'ASIGNADO': 'En espera',
      'EN_PROCESO': 'En proceso',
      'TERMINADO': 'Terminadas',
      'ENTREGADO': 'Entregadas',
      'CANCELADO': 'Canceladas',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'ADN PUBLICIDAD · SOFTWARE',
          style: TextStyle(color: accent, fontSize: 11),
        ),
        const SizedBox(height: 8),
        const Text(
          'Órdenes de lavado',
          style: TextStyle(fontSize: 29, fontWeight: FontWeight.w800),
        ),
        Text(
          'Control y seguimiento del estado de cada vehículo.',
          style: TextStyle(color: faded),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              key: const ValueKey('workflow_create'),
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Nueva orden'),
            ),
            OutlinedButton.icon(
              onPressed: loading ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              label: const Text('Actualizar'),
            ),
          ],
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final kpiColumns = constraints.maxWidth >= 850 ? 4 : 2;
            final w =
                (constraints.maxWidth - 10 * (kpiColumns - 1)) / kpiColumns;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                SizedBox(
                  width: w,
                  child: _kpi(
                    'Nuevas',
                    summary['new'] ?? '—',
                    'EN_ESPERA',
                    Icons.add_circle_outline,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _kpi(
                    'En espera',
                    summary['waiting'] ?? '—',
                    'ASIGNADO',
                    Icons.schedule,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _kpi(
                    'En proceso',
                    summary['active'] ?? '—',
                    'EN_PROCESO',
                    Icons.water_drop_outlined,
                  ),
                ),
                SizedBox(
                  width: w,
                  child: _kpi(
                    'Terminadas',
                    summary['finished'] ?? '—',
                    'TERMINADO',
                    Icons.check_circle_outline,
                  ),
                ),
              ],
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(
            _value(summary['scope'], 'Todas las sucursales · Historial'),
            style: TextStyle(fontSize: 11, color: faded),
          ),
        ),
        TextField(
          controller: search,
          onChanged: onSearch,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.search, color: accent),
            hintText: 'Buscar por cliente, placa, vehículo u orden...',
            filled: true,
            fillColor: ink,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(13)),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('orders_filter_day_24h'),
              onPressed: () async {
                final today = DateTime.now();
                final date = await showDatePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(today.year + 5, 12, 31),
                  initialDate: selectedDate == null
                      ? today
                      : DateTime.tryParse(selectedDate!) ?? today,
                  helpText: 'Selecciona el día de las órdenes',
                );
                if (date != null) {
                  final yyyy = date.year.toString().padLeft(4, '0');
                  final mm = date.month.toString().padLeft(2, '0');
                  final dd = date.day.toString().padLeft(2, '0');
                  onDate('$yyyy-$mm-$dd');
                }
              },
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(
                selectedDate == null ? 'Filtrar por día' : 'Día: $selectedDate',
              ),
            ),
            if (selectedDate != null)
              TextButton.icon(
                key: const ValueKey('orders_clear_day_24h'),
                onPressed: () => onDate(null),
                icon: const Icon(Icons.close),
                label: const Text('Todos los días'),
              ),
          ],
        ),
        Wrap(
          spacing: 6,
          runSpacing: 5,
          children: filters.entries
              .map(
                (e) => ChoiceChip(
                  label: Text(e.value),
                  selected: filter == e.key,
                  onSelected: (_) => onFilter(e.key),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 14),
        if (loading)
          Center(
            child: Padding(
              padding: EdgeInsets.all(30),
              child: CircularProgressIndicator(color: accent),
            ),
          )
        else if (error != null)
          _panel(
            child: Column(
              children: [
                Text(error!, style: const TextStyle(color: Colors.redAccent)),
                TextButton(
                  onPressed: onRefresh,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          )
        else if (orders.isEmpty)
          _panel(
            child: const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Sin registros para mostrar.'),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final effectiveColumns = constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: orders.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: effectiveColumns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  mainAxisExtent: 393,
                ),
                itemBuilder: (_, i) => _card(orders[i]),
              );
            },
          ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Página anterior',
              onPressed: page <= 1 ? null : () => onPage(page - 1),
              icon: const Icon(Icons.chevron_left),
            ),
            Text('Página $page de $pages'),
            IconButton(
              tooltip: 'Página siguiente',
              onPressed: page >= pages ? null : () => onPage(page + 1),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    );
  }
}
