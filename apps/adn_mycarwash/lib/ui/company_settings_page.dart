import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/mycarwash_session.dart';
import '../core/business_identity.dart';
import 'business_identity_editor.dart';
import 'company_fiscal_section.dart';
import 'company_addresses_section.dart';
import 'company_schedule_section.dart';
import 'company_social_links_section.dart';
import 'company_preferences_section.dart';
import '../core/company_visual_theme.dart';

class CompanySettingsPage extends StatefulWidget {
  const CompanySettingsPage({super.key, this.client, this.initialSection = 0, this.configurationOnly = false});

  final http.Client? client;
  final int initialSection;
  final bool configurationOnly;

  @override
  State<CompanySettingsPage> createState() => _CompanySettingsPageState();
}

class _CompanySettingsPageState extends State<CompanySettingsPage> {
  static Color get turquoise => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get surface => CompanyVisualTheme.legacy(const Color(0xFF0A1519));
  static Color get border => CompanyVisualTheme.legacy(const Color(0xFF20343C));
  static Color get muted => CompanyVisualTheme.legacy(const Color(0xFF9BAEB6));

  static const profileLabels = <String, String>{
    'commercial_name': 'Nombre comercial',
    'business_category': 'Categoría del negocio',
    'business_type': 'Tipo de empresa',
    'slogan': 'Eslogan',
    'public_email': 'Correo público',
    'support_email': 'Correo de soporte',
    'website_url': 'Sitio web',
    'legal_representative': 'Representante legal',
    'registration_number': 'Número de registro',
    'founded_at': 'Fecha de fundación (AAAA-MM-DD)',
    'short_description': 'Descripción breve',
    'description': 'Descripción completa',
    'history': 'Historia',
    'mission': 'Misión',
    'vision': 'Visión',
    'business_values': 'Valores empresariales',
  };

  static const colorLabels = <String, String>{
    'primary_color': 'Principal',
    'secondary_color': 'Secundario',
    'accent_color': 'Acento',
    'background_color': 'Fondo',
    'surface_color': 'Superficies',
    'card_color': 'Tarjetas de todas las pantallas',
    'border_color': 'Contornos y divisiones',
    'field_color': 'Campos y formularios',
    'icon_color': 'Iconos',
    'heading_color': 'Encabezados',
    'hover_color': 'Al pasar el cursor',
    'selected_color': 'Elementos seleccionados',
    'text_color': 'Texto',
    'muted_text_color': 'Texto secundario',
    'sidebar_color': 'Menú lateral',
    'button_color': 'Botones',
    'success_color': 'Éxito',
    'warning_color': 'Advertencia',
    'danger_color': 'Error',
  };

  static const defaultColors = CompanyVisualTheme.defaults;

  late final http.Client _client;
  late final bool _ownsClient;

  final Map<String, TextEditingController> _profile = {};
  final Map<String, TextEditingController> _colors = {};

  final _search = TextEditingController();

  Timer? _debounce;

  int _section = 0;
  int _contactPage = 1;
  int _lastPage = 1;
  int _searchVersion = 0;

  bool _loading = true;
  bool _saving = false;
  bool _contactsLoading = false;
  bool _contactsLoaded = false;

  String? _error;
  String? _contactsError;
  String _companyName = 'Mi Empresa';

  String _buttonStyle = 'rounded';
  String _sidebarStyle = 'expanded';
  int _radius = 12;
  bool _compactMode = false;
  bool _showBusinessName = true;

  List<Map<String, dynamic>> _contacts = [];

  @override
  void initState() {
    super.initState();

    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _section = widget.configurationOnly ? 2 : 0;

    for (final key in profileLabels.keys) {
      _profile[key] = TextEditingController();
    }

    for (final key in colorLabels.keys) {
      _colors[key] = TextEditingController(text: defaultColors[key]);
    }

    _loadSettings();
  }

  @override
  void dispose() {
    _debounce?.cancel();

    for (final controller in _profile.values) {
      controller.dispose();
    }

    for (final controller in _colors.values) {
      controller.dispose();
    }

    _search.dispose();

    if (_ownsClient) {
      _client.close();
    }

    super.dispose();
  }

  Uri _url(String path, [Map<String, String>? query]) {
    final base = MyCarWashSession.apiBaseUrl;
    final companyId = MyCarWashSession.companyId;

    return Uri.parse('$base/companies/$companyId$path')
        .replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    if (!MyCarWashSession.isAuthenticated) {
      throw const _ApiFailure('La sesión no está activa.');
    }

    final uri = _url(path, query);
    final headers = MyCarWashSession.headers;

    late http.Response response;

    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers);
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          );
        case 'PATCH':
          response = await _client.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          );
        case 'DELETE':
          response = await _client.delete(uri, headers: headers);
        default:
          throw const _ApiFailure('Método HTTP no permitido.');
      }
    } on _ApiFailure {
      rethrow;
    } catch (_) {
      throw const _ApiFailure(
        'No se pudo conectar con Laravel. Comprueba el servidor.',
      );
    }

    dynamic decoded;

    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const _ApiFailure('El servidor devolvió una respuesta inválida.');
    }

    if (decoded is! Map<String, dynamic>) {
      throw const _ApiFailure('El formato de respuesta no es válido.');
    }

    if (response.statusCode >= 400) {
      if (response.statusCode == 401) {
        throw const _ApiFailure(
          'Tu sesión expiró. Cierra sesión e ingresa nuevamente.',
        );
      }

      if (response.statusCode == 403) {
        throw const _ApiFailure(
          'No tienes permiso para realizar esta operación.',
        );
      }

      final errors = decoded['errors'];

      if (errors is Map && errors.isNotEmpty) {
        final first = errors.values.first;

        if (first is List && first.isNotEmpty) {
          throw _ApiFailure(first.first.toString());
        }
      }

      throw _ApiFailure(
        (decoded['message'] ?? 'Error ${response.statusCode}').toString(),
      );
    }

    return decoded;
  }

  void _notify(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? CompanyVisualTheme.legacy(const Color(0xFF9C3541))
            : CompanyVisualTheme.legacy(const Color(0xFF126F75)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _loadSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await _request('GET', '/settings');

      if (!mounted) return;

      final company = data['company'];
      final profile = data['profile'];
      final branding = data['branding'];

      if (company is Map) {
        _companyName = (company['name'] ?? 'Mi Empresa').toString();
      }

      for (final entry in _profile.entries) {
        entry.value.text = profile is Map
            ? (profile[entry.key] ?? '').toString()
            : '';
      }

      final normalizedBranding = CompanyVisualTheme.normalize(branding is Map ? branding : null);
      for (final entry in _colors.entries) {
        entry.value.text = normalizedBranding is Map
            ? (normalizedBranding[entry.key] ?? defaultColors[entry.key]).toString()
            : defaultColors[entry.key]!;
      }

      if (branding is Map) {
        _buttonStyle = (branding['button_style'] ?? 'rounded').toString();
        _sidebarStyle = (branding['sidebar_style'] ?? 'expanded').toString();
        _radius =
            int.tryParse((branding['border_radius'] ?? 12).toString()) ?? 12;
        _compactMode =
            branding['compact_mode'] == true || branding['compact_mode'] == 1;
        _showBusinessName =
            branding['show_business_name'] == true ||
            branding['show_business_name'] == 1;
      }

      setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_saving) return;

    final payload = <String, dynamic>{};

    for (final entry in _profile.entries) {
      final value = entry.value.text.trim();
      payload[entry.key] = value.isEmpty ? null : value;
    }

    setState(() => _saving = true);

    try {
      await _request('PATCH', '/settings/profile', body: payload);

      await BusinessIdentity.refresh(client: _client);
      _notify('Información empresarial guardada en MySQL.');
    } catch (error) {
      _notify(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Color _parseColor(String value, Color fallback) {
    final color = value.trim();

    if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(color)) {
      return fallback;
    }

    return Color(int.parse('FF${color.substring(1)}', radix: 16));
  }

  Future<void> _saveBranding() async {
    if (_saving) return;

    final payload = <String, dynamic>{};

    for (final entry in _colors.entries) {
      final value = entry.value.text.trim();

      if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(value)) {
        _notify(
          'El color ${colorLabels[entry.key]} debe tener formato #RRGGBB.',
          error: true,
        );
        return;
      }

      payload[entry.key] = value.toUpperCase();
    }

    payload.addAll({
      'button_style': _buttonStyle,
      'sidebar_style': _sidebarStyle,
      'border_radius': _radius,
      'compact_mode': _compactMode,
      'show_business_name': _showBusinessName,
    });

    setState(() => _saving = true);

    try {
      await _request('PATCH', '/settings/branding', body: payload);

      final saved = await _request('GET', '/settings');
      final freshBrand = saved['branding'];
      CompanyVisualTheme.load(freshBrand is Map ? freshBrand : payload);
      await BusinessIdentity.refresh(client: _client);
      _notify('Identidad visual aplicada y guardada para todas las pantallas conectadas al tema.');
    } catch (error) {
      _notify(error.toString(), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Restaura SOLO la paleta de colores, sin modificar otros ajustes de empresa.
  /// Se almacena inmediatamente en MySQL mediante la API autorizada.
  Future<void> _restoreDefaultColors() async {
    if (_saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF071B20),
        title: const Text(
          'Restaurar colores por defecto',
          style: TextStyle(color: Color(0xFFF4F7F8)),
        ),
        content: const Text(
          'Se restaurarán los 19 colores azul oscuro y turquesa. '
          'No se modificarán el logotipo, los usuarios ni otras preferencias.',
          style: TextStyle(color: Color(0xFFA5B6BB)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            key: const ValueKey('admin_confirm_default_palette'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF00DCE5),
              foregroundColor: const Color(0xFF051318),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Restaurar colores'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);
    try {
      // La misma API de identidad visual valida permisos y persiste los 19 HEX.
      await _request(
        'PATCH',
        '/settings/branding',
        body: Map<String, dynamic>.from(CompanyVisualTheme.defaults),
      );
      final data = await _request('GET', '/settings');
      final branding = data['branding'];
      CompanyVisualTheme.load(branding is Map ? branding : CompanyVisualTheme.defaults);
      for (final entry in _colors.entries) {
        entry.value.text = CompanyVisualTheme.defaults[entry.key]!;
      }
      await BusinessIdentity.refresh(client: _client);
      if (mounted) {
        setState(() {});
        _notify('Paleta azul oscuro y turquesa restaurada y guardada.');
      }
    } catch (error) {
      _notify('No se pudieron restaurar los colores: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadContacts() async {
    final version = ++_searchVersion;

    setState(() {
      _contactsLoading = true;
      _contactsError = null;
    });

    try {
      final data = await _request(
        'GET',
        '/contacts',
        query: {'q': _search.text.trim(), 'page': _contactPage.toString()},
      );

      if (!mounted || version != _searchVersion) return;

      final rows = data['data'];

      setState(() {
        _contacts = rows is List
            ? rows
                  .whereType<Map>()
                  .map((row) => Map<String, dynamic>.from(row))
                  .toList()
            : [];

        _contactPage =
            int.tryParse((data['current_page'] ?? 1).toString()) ?? 1;

        _lastPage = int.tryParse((data['last_page'] ?? 1).toString()) ?? 1;

        _contactsLoaded = true;
        _contactsLoading = false;
      });
    } catch (error) {
      if (!mounted || version != _searchVersion) return;

      setState(() {
        _contactsError = error.toString();
        _contactsLoading = false;
      });
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    _contactPage = 1;

    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) _loadContacts();
    });
  }

  void _changeSection(int section) {
    setState(() => _section = section);

    if (section == 1 && !_contactsLoaded) {
      _loadContacts();
    }
  }

  Future<void> _editContact([Map<String, dynamic>? existing]) async {
    final formKey = GlobalKey<FormState>();

    final value = TextEditingController(
      text: (existing?['value'] ?? '').toString(),
    );

    final label = TextEditingController(
      text: (existing?['label'] ?? '').toString(),
    );

    final person = TextEditingController(
      text: (existing?['contact_person'] ?? '').toString(),
    );

    final department = TextEditingController(
      text: (existing?['department'] ?? '').toString(),
    );

    var type = (existing?['type'] ?? 'phone').toString();
    var isPrimary =
        existing?['is_primary'] == true || existing?['is_primary'] == 1;
    var isPublic =
        existing?['is_public'] == null ||
        existing?['is_public'] == true ||
        existing?['is_public'] == 1;

    var saving = false;
    String? dialogError;

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, updateDialog) {
            return AlertDialog(
              backgroundColor: surface,
              title: Text(
                existing == null ? 'Nuevo contacto' : 'Editar contacto',
                style: TextStyle(color: CompanyVisualTheme.text),
              ),
              content: SizedBox(
                width: 470,
                child: SingleChildScrollView(
                  child: Form(
                    key: formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: type,
                          dropdownColor: surface,
                          style: TextStyle(color: CompanyVisualTheme.text),
                          decoration: _inputDecoration('Tipo de contacto'),
                          items: const [
                            DropdownMenuItem(
                              value: 'phone',
                              child: Text('Teléfono'),
                            ),
                            DropdownMenuItem(
                              value: 'email',
                              child: Text('Correo electrónico'),
                            ),
                            DropdownMenuItem(
                              value: 'whatsapp',
                              child: Text('WhatsApp de contacto'),
                            ),
                            DropdownMenuItem(
                              value: 'other',
                              child: Text('Otro'),
                            ),
                          ],
                          onChanged: saving
                              ? null
                              : (next) {
                                  if (next != null) {
                                    updateDialog(() => type = next);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: value,
                          style: TextStyle(color: CompanyVisualTheme.text),
                          decoration: _inputDecoration('Número, correo o dato'),
                          validator: (text) {
                            if (text == null || text.trim().isEmpty) {
                              return 'Este dato es obligatorio.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: label,
                          style: TextStyle(color: CompanyVisualTheme.text),
                          decoration: _inputDecoration('Etiqueta'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: person,
                          style: TextStyle(color: CompanyVisualTheme.text),
                          decoration: _inputDecoration('Persona de contacto'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: department,
                          style: TextStyle(color: CompanyVisualTheme.text),
                          decoration: _inputDecoration('Departamento'),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          title: Text(
                            'Contacto principal',
                            style: TextStyle(color: CompanyVisualTheme.text),
                          ),
                          value: isPrimary,
                          activeThumbColor: turquoise,
                          onChanged: saving
                              ? null
                              : (value) =>
                                    updateDialog(() => isPrimary = value),
                        ),
                        SwitchListTile(
                          title: Text(
                            'Visible públicamente',
                            style: TextStyle(color: CompanyVisualTheme.text),
                          ),
                          value: isPublic,
                          activeThumbColor: turquoise,
                          onChanged: saving
                              ? null
                              : (value) => updateDialog(() => isPublic = value),
                        ),
                        if (dialogError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              dialogError!,
                              style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995))),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: saving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;

                          updateDialog(() {
                            saving = true;
                            dialogError = null;
                          });

                          try {
                            final payload = <String, dynamic>{
                              'type': type,
                              'value': value.text.trim(),
                              'label': label.text.trim(),
                              'contact_person': person.text.trim(),
                              'department': department.text.trim(),
                              'is_primary': isPrimary,
                              'is_public': isPublic,
                            };

                            if (existing == null) {
                              await _request(
                                'POST',
                                '/contacts',
                                body: payload,
                              );
                            } else {
                              await _request(
                                'PATCH',
                                '/contacts/${existing['id']}',
                                body: payload,
                              );
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop(true);
                            }
                          } catch (error) {
                            if (dialogContext.mounted) {
                              updateDialog(() {
                                dialogError = error.toString();
                                saving = false;
                              });
                            }
                          }
                        },
                  style: FilledButton.styleFrom(backgroundColor: turquoise),
                  child: Text(saving ? 'Guardando...' : 'Guardar'),
                ),
              ],
            );
          },
        );
      },
    );

    value.dispose();
    label.dispose();
    person.dispose();
    department.dispose();

    if (changed == true && mounted) {
      _notify('Contacto guardado correctamente.');
      await _loadContacts();
    }
  }

  Future<void> _deleteContact(Map<String, dynamic> contact) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: surface,
          title: Text(
            'Eliminar contacto',
            style: TextStyle(color: CompanyVisualTheme.text),
          ),
          content: Text(
            '¿Eliminar "${contact['value']}"? Esta acción no se puede deshacer.',
            style: TextStyle(color: muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: CompanyVisualTheme.legacy(const Color(0xFFB63D4A)),
              ),
              child: const Text('Eliminar'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    try {
      await _request('DELETE', '/contacts/${contact['id']}');
      _notify('Contacto eliminado.');
      await _loadContacts();
    } catch (error) {
      _notify(error.toString(), error: true);
    }
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: muted),
      filled: true,
      fillColor: CompanyVisualTheme.legacy(const Color(0xFF111F25)),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: turquoise),
        borderRadius: BorderRadius.circular(10),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: CompanyVisualTheme.legacy(const Color(0xFFE84657))),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: CompanyVisualTheme.legacy(const Color(0xFFE84657))),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [CompanyVisualTheme.legacy(const Color(0xFF102129)), CompanyVisualTheme.legacy(const Color(0xFF0B181E))],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF2A414A))),
        boxShadow: [
          BoxShadow(
            color: CompanyVisualTheme.legacy(const Color(0x18000000)),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _field(String key, String label) {
    final longText = [
      'description',
      'history',
      'mission',
      'vision',
      'business_values',
      'short_description',
    ].contains(key);

    return TextField(
      controller: _profile[key],
      maxLines: longText ? 3 : 1,
      style: TextStyle(color: CompanyVisualTheme.text),
      decoration: _inputDecoration(label),
    );
  }

  Widget _profileGroup24N(
    String title,
    String description,
    IconData icon,
    List<String> keys,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: CompanyVisualTheme.legacy(const Color(0xFF12242C)),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF2A414A))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: turquoise.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: turquoise, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: CompanyVisualTheme.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: TextStyle(color: muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 17),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 680
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final key in keys)
                    SizedBox(
                      width: width,
                      child: _field(key, profileLabels[key]!),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _profileSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Información general',
            style: TextStyle(
              color: CompanyVisualTheme.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            'Organiza los datos comerciales, los canales de contacto y la presentación del negocio.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 18),
          _profileGroup24N(
            'Datos del establecimiento',
            'Información principal del negocio',
            Icons.business_outlined,
            [
              'commercial_name',
              'business_category',
              'business_type',
              'slogan',
              'founded_at',
            ],
          ),
          const SizedBox(height: 14),
          _profileGroup24N(
            'Contacto y representación',
            'Datos públicos y administrativos',
            Icons.mail_outline,
            [
              'public_email',
              'support_email',
              'website_url',
              'legal_representative',
              'registration_number',
            ],
          ),
          const SizedBox(height: 14),
          _profileGroup24N(
            'Identidad y trayectoria',
            'Contenido descriptivo para presentar tu empresa',
            Icons.description_outlined,
            [
              'short_description',
              'description',
              'history',
              'mission',
              'vision',
              'business_values',
            ],
          ),
          const SizedBox(height: 20),
          _saveButton(
            label: 'Guardar información empresarial',
            onPressed: _saveProfile,
          ),
        ],
      ),
    );
  }

  Widget _saveButton({required String label, required VoidCallback onPressed}) {
    return FilledButton.icon(
      onPressed: _saving ? null : onPressed,
      icon: _saving
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CompanyVisualTheme.text,
              ),
            )
          : const Icon(Icons.save_outlined),
      label: Text(_saving ? 'Guardando...' : label),
      style: FilledButton.styleFrom(
        backgroundColor: turquoise,
        foregroundColor: const Color(0xFF051318),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
      ),
    );
  }

  Widget _contactSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contactos',
                    style: TextStyle(
                      color: CompanyVisualTheme.text,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Teléfonos, correos y responsables del negocio.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _editContact(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo contacto'),
                style: FilledButton.styleFrom(backgroundColor: turquoise),
              ),
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _search,
            onChanged: _onSearch,
            style: TextStyle(color: CompanyVisualTheme.text),
            decoration:
                _inputDecoration(
                  'Buscar por ID, nombre, teléfono, correo o departamento',
                ).copyWith(
                  prefixIcon: Icon(Icons.search, color: turquoise),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          icon: Icon(Icons.close, color: muted),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                            _onSearch('');
                          },
                        ),
                ),
          ),
          const SizedBox(height: 18),
          if (_contactsLoading)
            Center(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: CircularProgressIndicator(color: turquoise),
              ),
            )
          else if (_contactsError != null)
            Text(
              _contactsError!,
              style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995))),
            )
          else if (_contacts.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'No se encontraron contactos.',
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            for (final contact in _contacts)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: CompanyVisualTheme.legacy(const Color(0xFF12242C)),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF2A414A))),
                ),
                child: Row(
                  children: [
                    Icon(Icons.contact_phone_outlined, color: turquoise),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            (contact['contact_person'] ??
                                    contact['label'] ??
                                    'Contacto')
                                .toString(),
                            style: TextStyle(
                              color: CompanyVisualTheme.text,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${contact['value']} · ${contact['type']} · ID ${contact['id']}',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                          if ((contact['department'] ?? '')
                              .toString()
                              .isNotEmpty)
                            Text(
                              contact['department'].toString(),
                              style: TextStyle(
                                color: muted,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      onPressed: () => _editContact(contact),
                      icon: Icon(Icons.edit_outlined, color: turquoise),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteContact(contact),
                      icon: Icon(
                        Icons.delete_outline,
                        color: CompanyVisualTheme.legacy(const Color(0xFFE84657)),
                      ),
                    ),
                  ],
                ),
              ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                tooltip: 'Página anterior',
                onPressed: _contactsLoading || _contactPage <= 1
                    ? null
                    : () {
                        _contactPage--;
                        _loadContacts();
                      },
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                'Página $_contactPage de $_lastPage',
                style: TextStyle(color: muted),
              ),
              IconButton(
                tooltip: 'Página siguiente',
                onPressed: _contactsLoading || _contactPage >= _lastPage
                    ? null
                    : () {
                        _contactPage++;
                        _loadContacts();
                      },
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _chooseColor(String key) async {
    var hsv = HSVColor.fromColor(_parseColor(_colors[key]!.text, turquoise));
    final selected = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: Text('Color: ${colorLabels[key]}'),
          content: SizedBox(
            width: 370,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 65, decoration: BoxDecoration(
                color: hsv.toColor(), borderRadius: BorderRadius.circular(13),
              )),
              const SizedBox(height: 12),
              const Text('Tono'),
              Slider(value: hsv.hue, max: 360, onChanged: (v) => change(() => hsv = hsv.withHue(v))),
              const Text('Saturación'),
              Slider(value: hsv.saturation, onChanged: (v) => change(() => hsv = hsv.withSaturation(v))),
              const Text('Brillo'),
              Slider(value: hsv.value, onChanged: (v) => change(() => hsv = hsv.withValue(v))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, hsv.toColor()), child: const Text('Usar color')),
          ],
        ),
      ),
    );
    if (selected == null || !mounted) return;
    final hex = selected.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
    setState(() => _colors[key]!.text = '#$hex');
  }

  Widget _brandingSection() {
    final primary = _parseColor(_colors['primary_color']!.text, turquoise);

    final sidebar = _parseColor(
      _colors['sidebar_color']!.text,
      CompanyVisualTheme.legacy(const Color(0xFF1D1D1B)),
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Identidad visual de todo el sistema',
            style: TextStyle(
              color: CompanyVisualTheme.text,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Personaliza los colores del negocio. La identidad oficial ADN no se modifica.',
            style: TextStyle(color: muted),
          ),
          const SizedBox(height: 22),
          Container(
            decoration: BoxDecoration(
              color: sidebar,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border),
            ),
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 55,
                  height: 55,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: CompanyVisualTheme.text,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/branding/logo_adn.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADN MyCarWash',
                        style: TextStyle(
                          color: CompanyVisualTheme.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Powered by ADN Publicidad',
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Previsualización de los colores en tarjetas, botones y superficies. Guarda para aplicar el tema.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
          const SizedBox(height: 22),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 14) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 14,
                runSpacing: 14,
                children: [
                  for (final entry in colorLabels.entries)
                    SizedBox(
                      width: width,
                      child: Row(
                        children: [
                          Container(
                            width: 35,
                            height: 35,
                            decoration: BoxDecoration(
                              color: _parseColor(
                                _colors[entry.key]!.text,
                                Colors.grey,
                              ),
                              border: Border.all(color: Colors.white24),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Elegir color para ${entry.value}',
                            onPressed: () => _chooseColor(entry.key),
                            icon: Icon(Icons.colorize_outlined, color: turquoise),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: TextField(
                              controller: _colors[entry.key],
                              style: TextStyle(color: CompanyVisualTheme.text),
                              decoration: _inputDecoration(entry.value),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          BusinessIdentityEditor(client: _client),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 12,
            children: [
              DropdownButton<String>(
                value: _buttonStyle,
                dropdownColor: surface,
                style: TextStyle(color: CompanyVisualTheme.text),
                items: const [
                  DropdownMenuItem(
                    value: 'rounded',
                    child: Text('Botones redondeados'),
                  ),
                  DropdownMenuItem(
                    value: 'square',
                    child: Text('Botones cuadrados'),
                  ),
                  DropdownMenuItem(
                    value: 'pill',
                    child: Text('Botones tipo píldora'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _buttonStyle = value);
                },
              ),
              DropdownButton<String>(
                value: _sidebarStyle,
                dropdownColor: surface,
                style: TextStyle(color: CompanyVisualTheme.text),
                items: const [
                  DropdownMenuItem(
                    value: 'expanded',
                    child: Text('Menú expandido'),
                  ),
                  DropdownMenuItem(
                    value: 'compact',
                    child: Text('Menú compacto'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _sidebarStyle = value);
                },
              ),
            ],
          ),
          SwitchListTile(
            title: Text(
              'Interfaz compacta',
              style: TextStyle(color: CompanyVisualTheme.text),
            ),
            value: _compactMode,
            activeThumbColor: turquoise,
            onChanged: (value) => setState(() => _compactMode = value),
          ),
          SwitchListTile(
            title: Text(
              'Mostrar nombre comercial',
              style: TextStyle(color: CompanyVisualTheme.text),
            ),
            value: _showBusinessName,
            activeThumbColor: turquoise,
            onChanged: (value) => setState(() => _showBusinessName = value),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _saveButton(
                label: 'Guardar identidad visual',
                onPressed: _saveBranding,
              ),
              OutlinedButton.icon(
                key: const ValueKey('admin_reset_palette_default'),
                onPressed: _saving ? null : _restoreDefaultColors,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Restaurar colores por defecto'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFF061115),
                  foregroundColor: const Color(0xFF00DCE5),
                  side: const BorderSide(color: Color(0xFF00DCE5)),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _tab(
    String title,
    String description,
    IconData icon,
    int index,
    double width,
  ) {
    final active = _section == index;
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _changeSection(index),
          borderRadius: BorderRadius.circular(15),
          child: Container(
            key: ValueKey('admin_tab_24n_$index'),
            constraints: const BoxConstraints(minHeight: 91),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: active
                    ? [
                        turquoise.withValues(alpha: 0.22),
                        CompanyVisualTheme.legacy(const Color(0xFF142D34)),
                      ]
                    : [CompanyVisualTheme.legacy(const Color(0xFF12232B)), CompanyVisualTheme.legacy(const Color(0xFF0E1B22))],
              ),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: active ? turquoise : CompanyVisualTheme.legacy(const Color(0xFF2A414A)),
                width: active ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: active
                        ? turquoise.withValues(alpha: 0.23)
                        : CompanyVisualTheme.legacy(const Color(0xFF21343D)),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    icon,
                    size: 21,
                    color: active ? turquoise : muted,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: CompanyVisualTheme.text,
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (active)
                  Padding(
                    padding: EdgeInsets.only(left: 4),
                    child: Icon(Icons.check_circle, size: 15, color: turquoise),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _hero24N() {
    return Container(
      key: const ValueKey('admin_hero_24n'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [CompanyVisualTheme.legacy(const Color(0xFF11313A)), CompanyVisualTheme.legacy(const Color(0xFF10232B)), CompanyVisualTheme.legacy(const Color(0xFF0B181E))],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF27616A))),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 18,
        runSpacing: 16,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ADN PUBLICIDAD · SOFTWARE',
                  style: TextStyle(
                    color: turquoise,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  widget.configurationOnly ? 'Configuración' : 'Mi Empresa',
                  style: TextStyle(
                    color: CompanyVisualTheme.text,
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _companyName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: CompanyVisualTheme.legacy(const Color(0xFFD8EAEC)),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  widget.configurationOnly ? 'Personalización y preferencias' : 'Información del negocio',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: turquoise.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: turquoise.withValues(alpha: 0.32)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.tune_outlined, size: 18, color: turquoise),
                const SizedBox(width: 8),
                Text(
                  widget.configurationOnly ? '2 áreas de configuración' : '6 áreas de empresa',
                  style: TextStyle(
                    color: CompanyVisualTheme.text,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navigation24N() {
    final choices = widget.configurationOnly
        ? <(String, String, IconData, int)>[
            ('Identidad visual', 'Colores, tarjetas y logotipo', Icons.palette_outlined, 2),
            ('Preferencias de sistema', 'Idioma, moneda, formatos e impresión', Icons.tune_outlined, 7),
          ]
        : <(String, String, IconData, int)>[
            ('Información', 'Datos comerciales', Icons.business_outlined, 0),
            ('Contactos', 'Teléfonos y correos', Icons.contacts_outlined, 1),
            ('Datos fiscales', 'Información tributaria', Icons.receipt_long_outlined, 3),
            ('Dirección', 'Sucursales y ubicación', Icons.place_outlined, 4),
            ('Horarios', 'Apertura y excepciones', Icons.schedule_outlined, 5),
            ('Redes sociales', 'Presencia digital', Icons.public_outlined, 6),
          ];
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth;
      final columns = available >= 1060 ? 3 : available >= 700 ? 2 : 1;
      final width = (available - (columns - 1) * 12) / columns;
      return Wrap(
        key: const ValueKey('admin_sections_24n'),
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final item in choices) _tab(item.$1, item.$2, item.$3, item.$4, width),
        ],
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _hero24N(),
        const SizedBox(height: 20),
        if (_loading)
          Center(
            child: Padding(
              padding: EdgeInsets.all(48),
              child: CircularProgressIndicator(color: turquoise),
            ),
          )
        else if (_error != null)
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!, style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995)))),
                const SizedBox(height: 15),
                OutlinedButton(
                  onPressed: _loadSettings,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          )
        else ...[
          Text(
            'ADMINISTRACIÓN DEL NEGOCIO',
            style: TextStyle(
              color: turquoise,
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          _navigation24N(),
          const SizedBox(height: 17),
          Row(
            children: [
              Icon(Icons.edit_outlined, size: 17, color: turquoise),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Edita cada área por separado y utiliza su botón Guardar para confirmar los cambios.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
              Text(
                '${widget.configurationOnly ? (_section == 2 ? 1 : 2) : ([0,1,3,4,5,6].indexOf(_section) + 1)} / ${widget.configurationOnly ? 2 : 6}',
                style: TextStyle(
                  color: turquoise,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          if (_section == 0) _profileSection(),
          if (_section == 1) _contactSection(),
          if (_section == 2) _brandingSection(),
          if (_section == 3) CompanyFiscalSection(client: _client),
          if (_section == 4) CompanyAddressesSection(client: _client),
          if (_section == 5) CompanyScheduleSection(client: _client),
          if (_section == 6) CompanySocialLinksSection(client: _client),
          if (_section == 7)
            CompanyPreferencesSection(
              client: _client,
              companyName: _companyName,
            ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.lock_outline, color: muted, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'La identidad oficial de ADN MyCarWash permanece visible y protegida.',
                  style: TextStyle(color: muted, fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ApiFailure implements Exception {
  const _ApiFailure(this.message);

  final String message;

  @override
  String toString() => message;
}
