import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/main.dart';

void main() {
  testWidgets('El inicio muestra MyCarWash y mantiene login inactivo', (
    tester,
  ) async {
    await tester.pumpWidget(const MyCarWashApp());

    expect(find.textContaining('MyCarWash'), findsWidgets);
    final loginButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Ingresar'),
    );
    expect(loginButton.onPressed, isNull);
    expect(find.textContaining('API y MySQL'), findsOneWidget);
  });

  testWidgets('La vista previa permite abrir el resumen administrativo', (
    tester,
  ) async {
    await tester.pumpWidget(const MyCarWashApp());

    final preview = find.text('Ver vista previa del dashboard');
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    await tester.pumpAndSettle();

    expect(find.text('Resumen general'), findsOneWidget);
    expect(find.text('Lavados activos'), findsOneWidget);
    expect(find.text('Aún no hay operaciones para mostrar'), findsOneWidget);
  });
}
