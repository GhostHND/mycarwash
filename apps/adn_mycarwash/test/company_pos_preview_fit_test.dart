import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/company_pos_template_designer.dart';

void main() {
  test('ticket 80 mm con QR ajusta la pagina completa', () {
    const availableHeight = 440.0;
    final fitted = posPreviewFittedWidth(
      paper: '80MM',
      qrEnabled: true,
      viewportWidth: 810,
      viewportHeight: availableHeight,
    );
    expect(fitted, lessThan(175));
    expect(fitted * 281.0 / 80.0, lessThanOrEqualTo(availableHeight - 48));
  });

  test('ticket 58 mm se ajusta tambien con espacio reducido', () {
    const availableHeight = 355.0;
    final fitted = posPreviewFittedWidth(
      paper: '58MM',
      qrEnabled: true,
      viewportWidth: 380,
      viewportHeight: availableHeight,
    );
    expect(fitted * 281.0 / 58.0, lessThanOrEqualTo(availableHeight - 48));
  });

  test('A4 y Carta son proporcionales, sin cambiar el archivo PDF', () {
    for (final (paper, width, height) in [
      ('A4', 210.0, 297.0),
      ('LETTER', 215.9, 279.4),
    ]) {
      const availableHeight = 485.0;
      final fitted = posPreviewFittedWidth(
        paper: paper,
        qrEnabled: false,
        viewportWidth: 770,
        viewportHeight: availableHeight,
      );
      // La conversion de medidas del papel usa double; 1e-6 px solo
      // tolera redondeo binario, no admite desbordamientos perceptibles.
      expect(
        fitted * height / width,
        lessThanOrEqualTo(availableHeight - 48 + 1e-6),
      );
      expect(fitted, lessThan(390));
    }
  });

  test('se adapta al ancho y la altura del panel', () {
    final fitted = posPreviewFittedWidth(
      paper: 'A4',
      qrEnabled: false,
      viewportWidth: 260,
      viewportHeight: 300,
    );
    expect(fitted, lessThanOrEqualTo(228));
    expect(fitted * 297 / 210, lessThanOrEqualTo(252));
  });
}
