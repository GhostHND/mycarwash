import 'package:flutter/material.dart';

import '../core/mycarwash_session.dart';
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
    required this.onReceiveReservation,
    required this.onPreassignReservation,
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

  final OrderAction onReceiveReservation;
  final OrderAction onPreassignReservation;
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
                  Text(title, style: TextStyle(fontSize: 12, color: faded)),
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
                  Text('Importe', style: TextStyle(color: faded, fontSize: 11)),
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

  // 24N.7.2: tarjetas de reservas con la misma reticula que las ordenes.
  Widget _reservationInfo(IconData icon, String title, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: accent, size: 17),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(color: faded, fontSize: 11)),
              const SizedBox(height: 3),
              Text(
                value,
                softWrap: true,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reservationVehiclePhoto(dynamic rawId) {
    final vehicleId = int.tryParse('${rawId ?? ''}');
    final placeholder = Center(
      child: Icon(Icons.directions_car_outlined, color: faded, size: 43),
    );
    return Container(
      width: 116,
      height: 101,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFF102B32),
        border: Border.all(color: line.withValues(alpha: 0.75)),
        borderRadius: BorderRadius.circular(13),
      ),
      child:
          vehicleId == null ||
              vehicleId <= 0 ||
              !MyCarWashSession.isAuthenticated
          ? placeholder
          : Image.network(
              '${MyCarWashSession.apiBaseUrl}/companies/'
              '${MyCarWashSession.companyId}/media/vehicles/$vehicleId/file',
              headers: MyCarWashSession.headers,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (context, error, stackTrace) => placeholder,
            ),
    );
  }

  Widget _reservationCard(Map<String, dynamic> row) {
    final received = row['received'] == true;
    final date = '${row['local_date'] ?? ''}';
    final time = '${row['local_time'] ?? ''}';
    final now = DateTime.now();
    final todayString =
        '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    final isToday = date == todayString;
    final code = _value(row['booking_code'], 'Reserva sin código');
    final vehicle = _value(row['vehicle_label'], 'Vehículo sin identificar');
    final plate = _value(row['plate'], 'Sin placa');
    final client = _value(row['client_name'], 'No registrado');
    final service = _value(row['service_name'], 'Servicio no disponible');
    final duration = int.tryParse('${row['estimated_minutes'] ?? ''}');
    final bay = _value(row['bay_name'], 'Sin asignar');
    final washer = _value(
      row['proposed_employee_name'],
      'Pendiente de asignar',
    );
    final orderId = int.tryParse('${row['order_id'] ?? ''}');
    final statusColor = received ? const Color(0xFF35D9A0) : accent;
    final amount = double.tryParse('${row['quoted_price'] ?? ''}');
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: ink,
        border: Border.all(color: line),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
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
                  horizontal: 11,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Text(
                  received ? 'Recibido' : 'Reservado',
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reservationVehiclePhoto(row['vehicle_id']),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vehicle,
                      softWrap: true,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: accent),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.badge_outlined, size: 15, color: accent),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              plate,
                              softWrap: true,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          Divider(color: line, height: 1),
          const SizedBox(height: 12),
          _reservationInfo(
            Icons.calendar_month_outlined,
            'Fecha y hora',
            '$date · $time',
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _reservationInfo(
                  Icons.person_outline,
                  'Cliente',
                  client,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _reservationInfo(
                  Icons.local_car_wash_outlined,
                  'Servicio',
                  duration == null ? service : '$service · $duration min',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _reservationInfo(
                  Icons.garage_outlined,
                  'Bahía / Puesto',
                  bay,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _reservationInfo(
                  Icons.engineering_outlined,
                  'Lavador previsto',
                  washer,
                ),
              ),
            ],
          ),
          if (amount != null) ...[
            const SizedBox(height: 9),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'L ${amount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: accent,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          const SizedBox(height: 13),
          Divider(color: line, height: 1),
          const SizedBox(height: 12),
          if (received && orderId != null)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                key: ValueKey('reserved_view_order_$orderId'),
                onPressed: () => onDetail({'id': orderId}),
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: Text('Ver orden #$orderId'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(color: line),
                ),
              ),
            )
          else if (received)
            Text(
              'Vehículo recibido · Orden vinculada',
              textAlign: TextAlign.center,
              style: TextStyle(color: faded, fontSize: 12),
            )
          else ...[
            if (isToday)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey('reserved_receive_${row['id']}'),
                  onPressed: () => onReceiveReservation(row),
                  icon: const Icon(Icons.car_rental_outlined, size: 18),
                  label: const Text('Vehículo recibido'),
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: ink,
                  ),
                ),
              ),
            if (isToday && row['proposed_employee_id'] == null) ...[
              const SizedBox(height: 7),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: ValueKey('reserved_assign_${row['id']}'),
                  onPressed: () => onPreassignReservation(row),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                  label: const Text('Asignar lavador previsto'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: accent,
                    side: BorderSide(color: line),
                  ),
                ),
              ),
            ],
            if (!isToday)
              Text(
                'La recepción se habilita el día de la cita.',
                textAlign: TextAlign.center,
                style: TextStyle(color: faded, fontSize: 12),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filters = <String, String>{
      'TODAS': 'Todas',
      'RESERVADAS': 'Reservadas',
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
          'Órdenes, vehículos recibidos y reservas confirmadas.',
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
              label: const Text('Nueva orden / Reserva'),
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
        else if (filter == 'RESERVADAS')
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1080
                  ? 3
                  : constraints.maxWidth >= 680
                  ? 2
                  : 1;
              const spacing = 12.0;
              final cardWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Reservas del día seleccionado. Recibir un vehículo crea una sola orden en Nuevas.',
                      style: TextStyle(color: faded, fontSize: 12),
                    ),
                  ),
                  Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: [
                      for (final row in orders)
                        SizedBox(
                          width: cardWidth,
                          child: _reservationCard(row),
                        ),
                    ],
                  ),
                ],
              );
            },
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
