import 'dart:convert';

import 'package:adn_mycarwash/core/company_visual_theme.dart';
import 'package:adn_mycarwash/core/monitor_completion_queue_24n5.dart';
import 'package:adn_mycarwash/core/mycarwash_session.dart';
import 'package:adn_mycarwash/ui/company_wash_monitor_24b1.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('24N.5: inicio sin reproducir historial, eventos ordenados y sin duplicados', () {
    final queue = MonitorCompletionQueue24N5();
    queue.ingest([{'event_id': 4}, {'event_id': 3}]);
    expect(queue.initialized, true);
    expect(queue.takeNext(), isNull);
    queue.ingest([{'event_id': 4}, {'event_id': 6}, {'event_id': 5}]);
    expect(queue.takeNext()?['event_id'], 5);
    queue.ingest([{'event_id': 5}, {'event_id': 6}]);
    expect(queue.takeNext()?['event_id'], 6);
    expect(queue.takeNext(), isNull);
  });

  testWidgets('24N.5: panel temporal 10 s, encabezado y cola siempre presentes', (tester) async {
    MyCarWashSession.begin(accessToken: 'monitor-test', companyId: 1,
      apiBaseUrl: 'http://localhost:8000/api/v1');
    addTearDown(() { MyCarWashSession.clear(); CompanyVisualTheme.reset(); });
    await tester.binding.setSurfaceSize(const Size(1600, 980));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    int calls = 0;
    final client = MockClient((req) async {
      if (req.url.path.endsWith('/dashboard/monitor-24b2')) {
        calls++;
        return http.Response(jsonEncode({'data': {
          'active': [], 'active_total': 0,
          'slogan': 'Lavado de excelencia',
          'completion_events': calls <= 1 ? [] : [
            {'event_id': 101, 'order_id': 8, 'vehicle_id': 5,
             'brand': 'Honda', 'model': 'Civic', 'plate': 'HND1234',
             'service': 'Lavado General', 'bay': 'Puesto 2',
             'washers': ['David'], 'photo_enabled': false,
             'photo_on_kiosk': false}
          ],
        }}), 200, headers: {'content-type':'application/json'});
      }
      return http.Response('{}', 404);
    });
    addTearDown(client.close);
    await tester.pumpWidget(MaterialApp(home: Scaffold(
      body: SingleChildScrollView(child: CompanyWashMonitor24B1(client: client)),
    )));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Lavado terminado'), findsOneWidget);
    // El panel debe caber completo en el alto reducido de la prueba,
    // sin RenderFlex overflow ni otras excepciones de renderizado.
    expect(tester.takeException(), isNull);
    expect(find.text('Siguiente en cola'), findsOneWidget);
    expect(find.text('Lavado de excelencia'), findsOneWidget);
    await tester.pump(const Duration(seconds: 9));
    expect(find.text('Lavado terminado'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Lavado terminado'), findsNothing);
    expect(find.text('Siguiente en cola'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
