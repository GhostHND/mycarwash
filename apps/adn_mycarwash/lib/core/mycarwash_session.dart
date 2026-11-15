class MyCarWashSession {
  MyCarWashSession._();

  static String? _accessToken;
  static String? _apiBaseUrl;
  static int? _companyId;

  static bool get isAuthenticated => _accessToken != null && _companyId != null;

  static int get companyId {
    final id = _companyId;

    if (id == null) {
      throw StateError('No hay empresa autenticada.');
    }

    return id;
  }

  static String get apiBaseUrl {
    final url = _apiBaseUrl;

    if (url == null) {
      throw StateError('La sesion no esta activa.');
    }

    return url;
  }

  static Map<String, String> get headers {
    final token = _accessToken;

    if (token == null) {
      throw StateError('No existe una sesion autenticada.');
    }

    return {
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static void begin({
    required String accessToken,
    required int companyId,
    required String apiBaseUrl,
  }) {
    if (accessToken.isEmpty || companyId <= 0 || apiBaseUrl.isEmpty) {
      throw ArgumentError('Datos de sesion invalidos.');
    }

    _accessToken = accessToken;
    _companyId = companyId;
    _apiBaseUrl = apiBaseUrl;
  }

  static void clear() {
    _accessToken = null;
    _companyId = null;
    _apiBaseUrl = null;
  }
}
