class MyCarWashSession {
  MyCarWashSession._();

  static String? _accessToken;
  static String? _apiBaseUrl;
  static int? _companyId;
  static Set<String> _permissions = {};
  static bool _legacyFullAccess = true;

  static bool canNav(String module, String action) =>
      _legacyFullAccess || _permissions.contains('nav.$module.$action');

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
    List<String> permissions = const [],
    bool legacyFullAccess = true,
  }) {
    if (accessToken.isEmpty || companyId <= 0 || apiBaseUrl.isEmpty) {
      throw ArgumentError('Datos de sesion invalidos.');
    }

    _accessToken = accessToken;
    _companyId = companyId;
    _apiBaseUrl = apiBaseUrl;
    _permissions = permissions.toSet();
    _legacyFullAccess = legacyFullAccess;
  }

  static void clear() {
    _accessToken = null;
    _companyId = null;
    _apiBaseUrl = null;
    _permissions = {};
    _legacyFullAccess = true;
  }
}
