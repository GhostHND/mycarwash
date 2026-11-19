import 'package:flutter/material.dart';

/// Paleta por empresa. Cambiarla repinta MaterialApp y los controles conectados.
class CompanyPalette {
  const CompanyPalette(this.colors);
  final Map<String, Color> colors;

  Color get primary => colors['primary_color'] ?? const Color(0xFF00DCE5);
  Color get secondary => colors['secondary_color'] ?? const Color(0xFF0B292F);
  Color get accent => colors['accent_color'] ?? const Color(0xFF00DCE5);
  Color get background => colors['background_color'] ?? const Color(0xFF050C0F);
  Color get surface => colors['surface_color'] ?? const Color(0xFF071B20);
  Color get card => colors['card_color'] ?? const Color(0xFF071F23);
  Color get border => colors['border_color'] ?? const Color(0xFF17434B);
  Color get field => colors['field_color'] ?? const Color(0xFF16343D);
  Color get text => colors['text_color'] ?? const Color(0xFFF4F7F8);
  Color get muted => colors['muted_text_color'] ?? const Color(0xFFA5B6BB);
  Color get sidebar => colors['sidebar_color'] ?? const Color(0xFF061115);
  Color get button => colors['button_color'] ?? const Color(0xFF00DCE5);
  Color get icon => colors['icon_color'] ?? const Color(0xFF00DCE5);
  Color get heading => colors['heading_color'] ?? const Color(0xFFF4F7F8);
  Color get hover => colors['hover_color'] ?? const Color(0xFF10383F);
  Color get selected => colors['selected_color'] ?? const Color(0xFF10454D);
  Color get success => colors['success_color'] ?? const Color(0xFF00D99A);
  Color get warning => colors['warning_color'] ?? const Color(0xFFF59E0B);
  Color get danger => colors['danger_color'] ?? const Color(0xFFEC488A);
}

class CompanyVisualTheme {
  CompanyVisualTheme._();

  static const defaults = <String, String>{
    'primary_color': '#00DCE5',
    'secondary_color': '#0B292F',
    'accent_color': '#00DCE5',
    'background_color': '#050C0F',
    'surface_color': '#071B20',
    'card_color': '#071F23',
    'border_color': '#17434B',
    'field_color': '#16343D',
    'text_color': '#F4F7F8',
    'muted_text_color': '#A5B6BB',
    'sidebar_color': '#061115',
    'button_color': '#00DCE5',
    'icon_color': '#00DCE5',
    'heading_color': '#F4F7F8',
    'hover_color': '#10383F',
    'selected_color': '#10454D',
    'success_color': '#00D99A',
    'warning_color': '#F59E0B',
    'danger_color': '#EC488A',
  };

  static Color parse(String? hex, Color fallback) {
    if (hex == null || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return fallback;
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  static Map<dynamic, dynamic>? normalize(Map<dynamic, dynamic>? input) {
    if (input == null) return null;
    final values = Map<dynamic, dynamic>.from(input);
    final legacy = (int.tryParse('${values['visual_theme_version'] ?? 0}') ?? 0) < 2;
    if (legacy &&
        '${values['background_color'] ?? ''}'.toUpperCase() == '#FFFFFF' &&
        '${values['surface_color'] ?? ''}'.toUpperCase() == '#F5F7F8' &&
        '${values['text_color'] ?? ''}'.toUpperCase() == '#1D1D1B') {
      for (final key in ['background_color', 'surface_color', 'text_color',
        'muted_text_color', 'sidebar_color']) {
        values[key] = defaults[key];
      }
    }
    return values;
  }

  static CompanyPalette fromMap(Map<dynamic, dynamic>? input) {
    input = normalize(input);
    final values = <String, Color>{};
    for (final entry in defaults.entries) {
      final fallback = parse(entry.value, Colors.white);
      values[entry.key] = parse(input?[entry.key]?.toString(), fallback);
    }
    return CompanyPalette(Map.unmodifiable(values));
  }

  static final ValueNotifier<CompanyPalette> current = ValueNotifier(fromMap(null));

  static void load(Map<dynamic, dynamic>? saved) => current.value = fromMap(saved);
  static void reset() => current.value = fromMap(null);
  static Color get primary => current.value.primary;
  static Color get secondary => current.value.secondary;
  static Color get accent => current.value.accent;
  static Color get background => current.value.background;
  static Color get surface => current.value.surface;
  static Color get card => current.value.card;
  static Color get border => current.value.border;
  static Color get field => current.value.field;
  static Color get text => current.value.text;
  static Color get muted => current.value.muted;
  static Color get sidebar => current.value.sidebar;
  static Color get button => current.value.button;
  static Color get icon => current.value.icon;
  static Color get heading => current.value.heading;
  static Color get hover => current.value.hover;
  static Color get selected => current.value.selected;
  static Color get success => current.value.success;
  static Color get warning => current.value.warning;
  static Color get danger => current.value.danger;

  /// Mapea los colores heredados a los tonos de la empresa.
  /// Preserva alpha y agrupa colores de superficie, borde y texto.
  static Color legacy(Color source) {
    final v = current.value;
    final alpha = source.a;
    final r = (source.r * 255).round();
    final g = (source.g * 255).round();
    final b = (source.b * 255).round();
    final brightness = (r * 299 + g * 587 + b * 114) / 1000;
    Color result;
    if ((r - g).abs() < 26 && (g - b).abs() < 30 && brightness >= 190) {
      result = v.text;
    } else if (r < 45 && g < 65 && b < 78) {
      result = brightness < 17 ? v.background : brightness < 29 ? v.surface : brightness < 41 ? v.card : v.border;
    } else if (g > r * 1.24 && b > r * 1.25 && brightness > 75) {
      result = v.primary;
    } else if (b > r && (b - r) > 12 && brightness < 175) {
      result = v.muted;
    } else if (r > 120 && g < r * .75) {
      result = v.danger;
    } else {
      return source;
    }
    return result.withValues(alpha: alpha);
  }
}
