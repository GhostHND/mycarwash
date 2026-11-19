import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'mycarwash_session.dart';
import 'company_visual_theme.dart';

class BusinessIdentityData {
  const BusinessIdentityData({
    this.fontFamily = 'Inter',
    this.companyName = '',
    this.logoBytes,
  });

  final String fontFamily;
  final String companyName;
  final Uint8List? logoBytes;

  BusinessIdentityData copyWith({
    String? fontFamily,
    String? companyName,
    Uint8List? logoBytes,
    bool removeLogo = false,
  }) {
    return BusinessIdentityData(
      fontFamily: fontFamily ?? this.fontFamily,
      companyName: companyName ?? this.companyName,
      logoBytes: removeLogo ? null : logoBytes ?? this.logoBytes,
    );
  }
}

class BusinessIdentity {
  BusinessIdentity._();

  static const supportedFonts = <String>['Inter'];

  static final ValueNotifier<BusinessIdentityData> current = ValueNotifier(
    const BusinessIdentityData(),
  );

  static int _revision = 0;

  static void setFont(String font) {
    if (!supportedFonts.contains(font)) {
      throw ArgumentError.value(font, 'font', 'Fuente no permitida');
    }

    current.value = current.value.copyWith(fontFamily: font);
  }

  static void setLogoBytes(Uint8List? logo) {
    current.value = current.value.copyWith(
      logoBytes: logo,
      removeLogo: logo == null,
    );
  }

  static void reset() {
    _revision++;
    current.value = const BusinessIdentityData();
    CompanyVisualTheme.reset();
  }

  static Future<bool> refresh({http.Client? client}) async {
    if (!MyCarWashSession.isAuthenticated) return false;

    final revision = ++_revision;
    final companyId = MyCarWashSession.companyId;
    final baseUrl = MyCarWashSession.apiBaseUrl;
    final headers = MyCarWashSession.headers;

    final ownClient = client == null;
    final httpClient = client ?? http.Client();

    try {
      final url = '$baseUrl/companies/$companyId/${MyCarWashSession.isWasher ? 'washer/branding' : 'settings'}';

      final response = await httpClient
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) return false;

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) return false;

      final branding = decoded['branding'];
      final company = decoded['company'];
      final profile = decoded['profile'];

      var font = 'Inter';

      if (branding is Map) {
        font = (branding['font_family'] ?? 'Inter').toString();
      }

      if (!supportedFonts.contains(font)) {
        font = 'Inter';
      }

      var name = 'Mi Empresa';

      if (company is Map) {
        name = (company['name'] ?? name).toString();
      }

      if (profile is Map) {
        final commercialName = (profile['commercial_name'] ?? '')
            .toString()
            .trim();

        if (commercialName.isNotEmpty) {
          name = commercialName;
        }
      }

      Uint8List? logo;

      final storedPath = branding is Map
          ? (branding['business_logo_path'] ?? '').toString()
          : '';

      if (storedPath.isNotEmpty) {
        final logoResponse = await httpClient
            .get(Uri.parse('$baseUrl/companies/$companyId/settings/logo'), headers: headers)
            .timeout(const Duration(seconds: 15));

        if (logoResponse.statusCode == 200 &&
            logoResponse.bodyBytes.isNotEmpty &&
            logoResponse.bodyBytes.lengthInBytes <= 2 * 1024 * 1024) {
          logo = logoResponse.bodyBytes;
        }
      }

      if (revision != _revision ||
          !MyCarWashSession.isAuthenticated ||
          MyCarWashSession.companyId != companyId) {
        return false;
      }

      CompanyVisualTheme.load(branding is Map ? branding : null);
      current.value = BusinessIdentityData(
        fontFamily: font,
        companyName: name,
        logoBytes: logo,
      );

      return true;
    } catch (_) {
      return false;
    } finally {
      if (ownClient) httpClient.close();
    }
  }
}
