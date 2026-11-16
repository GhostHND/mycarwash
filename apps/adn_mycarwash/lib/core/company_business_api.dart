import 'dart:convert';

import 'package:http/http.dart' as http;

import 'mycarwash_session.dart';

class CompanyBusinessApiException implements Exception {
  const CompanyBusinessApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Reutiliza el cliente HTTP de Mi Empresa; no es propietario de él.
class CompanyBusinessApi {
  const CompanyBusinessApi(this.client);

  final http.Client client;

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!MyCarWashSession.isAuthenticated) {
      throw const CompanyBusinessApiException('La sesión no está activa.');
    }

    final companyId = MyCarWashSession.companyId;
    final url = Uri.parse(
      '${MyCarWashSession.apiBaseUrl}/companies/$companyId$path',
    ).replace(queryParameters: query);
    final headers = MyCarWashSession.headers;

    late http.Response response;
    try {
      final Future<http.Response> pending = switch (method) {
        'GET' => client.get(url, headers: headers),
        'POST' => client.post(
          url,
          headers: headers,
          body: jsonEncode(body ?? <String, dynamic>{}),
        ),
        'PATCH' => client.patch(
          url,
          headers: headers,
          body: jsonEncode(body ?? <String, dynamic>{}),
        ),
        'DELETE' => client.delete(url, headers: headers),
        _ => throw const CompanyBusinessApiException(
          'Método HTTP no admitido.',
        ),
      };
      response = await pending.timeout(const Duration(seconds: 20));
    } on CompanyBusinessApiException {
      rethrow;
    } catch (_) {
      throw const CompanyBusinessApiException(
        'No se pudo conectar con Laravel. Comprueba el servidor.',
      );
    }

    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Respuesta inesperada.');
      }
      data = decoded;
    } catch (_) {
      throw const CompanyBusinessApiException(
        'Laravel devolvió una respuesta inválida.',
      );
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        throw const CompanyBusinessApiException(
          'Tu sesión expiró. Vuelve a iniciar sesión.',
        );
      }
      if (response.statusCode == 403) {
        throw const CompanyBusinessApiException(
          'No tienes permiso para realizar esta operación.',
        );
      }
      final errors = data['errors'];
      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;
        if (first is List && first.isNotEmpty) {
          throw CompanyBusinessApiException(first.first.toString());
        }
      }
      throw CompanyBusinessApiException(
        (data['message'] ?? 'Error HTTP ${response.statusCode}').toString(),
      );
    }
    return data;
  }
}
