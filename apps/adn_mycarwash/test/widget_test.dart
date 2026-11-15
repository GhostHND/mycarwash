import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/main.dart';

void main() {
  testWidgets('El login mantiene la identidad ADN MyCarWash', (tester) async {
    await tester.pumpWidget(const MyCarWashApp());

    expect(find.text('Bienvenido de nuevo'), findsOneWidget);
    expect(find.text('ACCESO PRIVADO'), findsOneWidget);
    expect(find.textContaining('ADN MyCarWash'), findsWidgets);
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('No permite iniciar sesion con campos vacios', (tester) async {
    await tester.pumpWidget(const MyCarWashApp());

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Iniciar sesión'),
    );

    expect(button.onPressed, isNull);
    expect(find.text('Ver vista previa del dashboard'), findsNothing);
  });

  testWidgets('El formulario permite escribir credenciales', (tester) async {
    await tester.pumpWidget(const MyCarWashApp());

    final fields = find.byType(TextField);

    await tester.enterText(fields.at(0), 'eduardo@adn.com');
    await tester.enterText(fields.at(1), 'ClaveTemporal');

    await tester.pump();

    final button = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Iniciar sesión'),
    );

    expect(button.onPressed, isNotNull);
  });
}
