import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/company_wash_orders_cards_24e.dart';

void main() {
  testWidgets('24N.7.2: reserva usa tarjeta y conserva acciones de recepcion', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final today = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${today.year}-${two(today.month)}-${two(today.day)}';
    var received = 0;
    var assigned = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyWashOrdersCards24E(
              orders: [
                {
                  'id': 10,
                  'booking_code': 'RSV-TEST-01',
                  'vehicle_label': 'Toyota Tacoma',
                  'plate': 'PQN2906',
                  'client_name': 'Cliente de prueba',
                  'service_name': 'Lavado General',
                  'estimated_minutes': 40,
                  'quoted_price': 450,
                  'local_date': date,
                  'local_time': '11:00',
                  'bay_name': 'Puesto 3',
                  'proposed_employee_name': null,
                  'proposed_employee_id': null,
                  'received': false,
                },
              ],
              summary: const {},
              loading: false,
              error: null,
              search: TextEditingController(),
              filter: 'RESERVADAS',
              page: 1,
              pages: 1,
              selectedDate: date,
              onSearch: (_) {},
              onFilter: (_) {},
              onCreate: () {},
              onRefresh: () {},
              onPage: (_) {},
              onEdit: (_) {},
              onDetail: (_) {},
              onDelete: (_) {},
              onAdvance: (_) {},
              onAssign: (_) {},
              onDate: (_) {},
              onReceiveReservation: (_) => received++,
              onPreassignReservation: (_) => assigned++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Toyota Tacoma'), findsOneWidget);
    expect(find.text('PQN2906'), findsOneWidget);
    expect(find.text('Lavado General · 40 min'), findsOneWidget);
    await tester.ensureVisible(find.text('Vehículo recibido'));
    await tester.tap(find.text('Vehículo recibido'));
    expect(received, 1);
    await tester.ensureVisible(find.text('Asignar lavador previsto'));
    await tester.tap(find.text('Asignar lavador previsto'));
    expect(assigned, 1);
    expect(tester.takeException(), isNull);
  });
}
