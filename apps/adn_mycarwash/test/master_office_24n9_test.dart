import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/master_form_24n9.dart';
import 'package:adn_mycarwash/ui/master_office_24n9.dart';

void main() {
  testWidgets('24N.9: login maestro es responsive y sin desbordamientos', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MasterOffice24N9()));
    expect(find.text('ADN MyCarWash'), findsOneWidget);
    expect(find.text('CENTRO DE ADMINISTRACIÓN MAESTRA'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('24N.9: los formularios validan campos obligatorios', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () => showMasterForm24N9(
                  context,
                  title: 'Crear cliente comercial',
                  fields: const [
                    MasterField24N9(
                      'name',
                      'Nombre / razón social',
                      required: true,
                    ),
                  ],
                ),
                child: const Text('Crear'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Crear'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Este dato es obligatorio'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
