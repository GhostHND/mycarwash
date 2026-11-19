import 'package:geolocator/geolocator.dart';

/// Coordenadas temporales del dispositivo para el pronóstico MET Norway
/// servido y cacheado por Laravel. No se guardan en base de datos.
class MonitorDeviceWeather24N5 {
  const MonitorDeviceWeather24N5._();

  static Future<Map<String, String>?> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
          timeLimit: Duration(seconds: 8),
        ),
      ).timeout(const Duration(seconds: 10));
      final latitude = position.latitude;
      final longitude = position.longitude;
      if (!latitude.isFinite || !longitude.isFinite ||
          latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
        return null;
      }
      return <String, String>{
        'latitude': latitude.toStringAsFixed(4),
        'longitude': longitude.toStringAsFixed(4),
      };
    } catch (_) {
      // Contexto web HTTP, ubicación denegada o GPS no disponible:
      // la API usa las coordenadas que el negocio tenga configuradas.
      return null;
    }
  }
}
