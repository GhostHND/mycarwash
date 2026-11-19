import 'package:flutter/material.dart';

import 'company_visual_theme.dart';

/// La Vista general de lavados comparte la paleta global de la empresa.
/// No mantiene ni persiste un segundo editor de colores.
class CompanyMonitorColors24N27 {
  CompanyMonitorColors24N27._();

  static Color resolve(String token) {
    switch (token) {
      case 'primary_color':
        return CompanyVisualTheme.primary;
      case 'secondary_color':
        return CompanyVisualTheme.secondary;
      case 'accent_color':
        return CompanyVisualTheme.accent;
      case 'background_color':
        return CompanyVisualTheme.background;
      case 'surface_color':
        return CompanyVisualTheme.card;
      case 'text_color':
        return CompanyVisualTheme.text;
      case 'muted_text_color':
        return CompanyVisualTheme.muted;
      case 'sidebar_color':
        return CompanyVisualTheme.surface;
      case 'button_color':
        return CompanyVisualTheme.button;
      case 'success_color':
        return CompanyVisualTheme.success;
      case 'warning_color':
        return CompanyVisualTheme.warning;
      case 'danger_color':
        return CompanyVisualTheme.danger;
      case 'border_color':
        return CompanyVisualTheme.border;
      case 'queue_color':
        return CompanyVisualTheme.selected;
      default:
        throw ArgumentError.value(token, 'token', 'Color del monitor desconocido');
    }
  }
}
