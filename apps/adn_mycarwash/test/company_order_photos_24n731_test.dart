import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/company_wash_orders_cards_24e.dart';

void main() {
  testWidgets('24N.7.3.1: seis estados usan fotografia y mantienen acciones', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final states = <String>[
      'EN_ESPERA',
      'ASIGNADO',
      'EN_PROCESO',
      'TERMINADO',
      'ENTREGADO',
      'CANCELADO',
    ];
    final orders = <Map<String, dynamic>>[
      for (var i = 0; i < states.length; i++)
        {
          'id': i + 101,
          'status': states[i],
          'tracking_code': 'MCW-24N73-$i',
          'vehicle_id': i + 201,
          'vehicle_label': 'Toyota Tacoma doble cabina',
          'plate': 'PQN2906',
          'client_name': 'Cliente de prueba',
          'service_name': 'Lavado General',
          'quoted_price': 350,
          'bay_name': 'Puesto 2',
          'washer_names': <String>['Antonio'],
        },
    ];

    var views = 0;
    var edits = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: CompanyWashOrdersCards24E(
              orders: orders,
              summary: const {},
              loading: false,
              error: null,
              search: TextEditingController(),
              filter: 'TODAS',
              page: 1,
              pages: 1,
              selectedDate: null,
              onSearch: (_) {},
              onFilter: (_) {},
              onCreate: () {},
              onRefresh: () {},
              onPage: (_) {},
              onEdit: (_) => edits++,
              onDetail: (_) => views++,
              onDelete: (_) {},
              onAdvance: (_) {},
              onAssign: (_) {},
              onDate: (_) {},
              onReceiveReservation: (_) {},
              onPreassignReservation: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    for (var i = 0; i < states.length; i++) {
      expect(
        find.byKey(ValueKey('order_vehicle_photo_${i + 101}')),
        findsOneWidget,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byTooltip('Ver detalle').first);
    await tester.tap(find.byTooltip('Ver detalle').first);
    expect(views, 1);
    await tester.ensureVisible(find.byTooltip('Editar').first);
    await tester.tap(find.byTooltip('Editar').first);
    expect(edits, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('24N.7.3.1: tarjetas adaptables sin overflow en telefono', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final query = TextEditingController();
    addTearDown(query.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.3)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: CompanyWashOrdersCards24E(
                orders: [
                  {
                    'id': 888,
                    'status': 'ASIGNADO',
                    'tracking_code': 'MCW-24N731-LARGA-ORDEN-888',
                    'vehicle_id': 201,
                    'vehicle_label': 'Toyota Tacoma doble cabina',
                    'plate': 'PQN290612345',
                    'client_name': 'Cliente de prueba con nombre largo',
                    'service_name': 'Lavado Premium de larga duracion',
                    'quoted_price': 350,
                    'bay_name': 'Puesto 2',
                    'washer_names': ['Antonio', 'Carlos'],
                  },
                ],
                summary: const {},
                loading: false,
                error: null,
                search: query,
                filter: 'ASIGNADO',
                page: 1,
                pages: 1,
                selectedDate: null,
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
                onReceiveReservation: (_) {},
                onPreassignReservation: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('order_vehicle_photo_888')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
