import 'package:flutter_test/flutter_test.dart';
import 'package:adn_mycarwash/ui/company_pos_template_designer.dart';

void main() {
  test('zoom positivo y negativo en pasos de 25 por ciento', () {
    expect(posPreviewNextZoom(1.0, increase: true), 1.25);
    expect(posPreviewNextZoom(1.25, increase: true), 1.50);
    expect(posPreviewNextZoom(1.50, increase: false), 1.25);
    expect(posPreviewNextZoom(1.25, increase: false), 1.00);
  });

  test('zoom respeta limites de 50 a 500 por ciento', () {
    expect(posPreviewNextZoom(0.5, increase: false), 0.5);
    expect(posPreviewNextZoom(5.0, increase: true), 5.0);
    expect(posPreviewNextZoom(99.0, increase: true), 5.0);
    expect(posPreviewNextZoom(-99.0, increase: false), 0.5);
  });

  test('ajustar conserva el calculo automatico en 100 por ciento', () {
    final fitted = posPreviewFittedWidth(
      paper: '80MM',
      qrEnabled: true,
      viewportWidth: 760,
      viewportHeight: 480,
    );
    expect(posPreviewZoomedWidth(fittedWidth: fitted, zoom: 1.0), fitted);
    expect(
      posPreviewZoomedWidth(fittedWidth: fitted, zoom: 2.0),
      closeTo(2.0 * fitted, 1e-6),
    );
    expect(
      posPreviewZoomedWidth(fittedWidth: fitted, zoom: 0.5),
      closeTo(0.5 * fitted, 1e-6),
    );
  });

  test('zoom es visual y no cambia el formato de papel', () {
    final fittedA4 = posPreviewFittedWidth(
      paper: 'A4',
      qrEnabled: false,
      viewportWidth: 710,
      viewportHeight: 480,
    );
    expect(
      posPreviewZoomedWidth(fittedWidth: fittedA4, zoom: 1.25),
      greaterThan(fittedA4),
    );
    expect(
      posPreviewZoomedWidth(fittedWidth: fittedA4, zoom: 99.0),
      closeTo(5.0 * fittedA4, 1e-6),
    );
  });
}
