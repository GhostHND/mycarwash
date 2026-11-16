import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/mycarwash_session.dart';
import '../core/business_identity.dart';
import 'business_identity_editor.dart';
import 'company_fiscal_section.dart';
import 'company_addresses_section.dart';

class CompanySettingsPage extends StatefulWidget {
  const CompanySettingsPage({super.key, this.client});

  final http.Client? client;

  @override
  State<CompanySettingsPage> createState() => _CompanySettingsPageState();
}

class _CompanySettingsPageState extends State<CompanySettingsPage> {
  static const turquoise = Color(0xFF0FA7B4);
  static const surface = Color(0xFF0A1519);
  static const border = Color(0xFF20343C);
  static const muted = Color(0xFF9BAEB6);

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
    'text_color': 'Texto',
    'muted_text_color': 'Texto secundario',
    'sidebar_color': 'Menú lateral',
    'button_color': 'Botones',
    'success_color': 'Éxito',
    'warning_color': 'Advertencia',
    'danger_color': 'Error',
  };

  static const defaultColors = <String, String>{
    'primary_color': '#0FA7B4',
    'secondary_color': '#1D1D1B',
    'accent_color': '#ED7E24',
    'background_color': '#FFFFFF',
    'surface_color': '#F5F7F8',
    'text_color': '#1D1D1B',
    'muted_text_color': '#64748B',
    'sidebar_color': '#1D1D1B',
    'button_color': '#0FA7B4',
    'success_color': '#16A34A',
    'warning_color': '#F59E0B',
    'danger_color': '#DC2626',
  };

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
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
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

      for (final entry in _colors.entries) {
        entry.value.text = branding is Map
            ? (branding[entry.key] ?? defaultColors[entry.key]).toString()
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

      await BusinessIdentity.refresh(client: _client);
      _notify('Identidad visual empresarial guardada en MySQL.');
    } catch (error) {
      _notify(error.toString(), error: true);
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
                style: const TextStyle(color: Colors.white),
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
                          style: const TextStyle(color: Colors.white),
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
                          style: const TextStyle(color: Colors.white),
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
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Etiqueta'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: person,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Persona de contacto'),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: department,
                          style: const TextStyle(color: Colors.white),
                          decoration: _inputDecoration('Departamento'),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          title: const Text(
                            'Contacto principal',
                            style: TextStyle(color: Colors.white),
                          ),
                          value: isPrimary,
                          activeThumbColor: turquoise,
                          onChanged: saving
                              ? null
                              : (value) =>
                                    updateDialog(() => isPrimary = value),
                        ),
                        SwitchListTile(
                          title: const Text(
                            'Visible públicamente',
                            style: TextStyle(color: Colors.white),
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
                              style: const TextStyle(color: Color(0xFFFF8995)),
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
          title: const Text(
            'Eliminar contacto',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '¿Eliminar "${contact['value']}"? Esta acción no se puede deshacer.',
            style: const TextStyle(color: muted),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB63D4A),
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
      labelStyle: const TextStyle(color: muted),
      filled: true,
      fillColor: const Color(0xFF111F25),
      enabledBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: border),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: turquoise),
        borderRadius: BorderRadius.circular(10),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE84657)),
        borderRadius: BorderRadius.circular(10),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: Color(0xFFE84657)),
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
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
      style: const TextStyle(color: Colors.white),
      decoration: _inputDecoration(label),
    );
  }

  Widget _profileSection() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Información general',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Completa los datos de tu negocio. Los cambios se guardan en MySQL.',
            style: TextStyle(color: muted),
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
                  for (final entry in profileLabels.entries)
                    SizedBox(
                      width: width,
                      child: _field(entry.key, entry.value),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
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
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.save_outlined),
      label: Text(_saving ? 'Guardando...' : label),
      style: FilledButton.styleFrom(
        backgroundColor: turquoise,
        foregroundColor: Colors.white,
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
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contactos',
                    style: TextStyle(
                      color: Colors.white,
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
            style: const TextStyle(color: Colors.white),
            decoration:
                _inputDecoration(
                  'Buscar por ID, nombre, teléfono, correo o departamento',
                ).copyWith(
                  prefixIcon: const Icon(Icons.search, color: turquoise),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Limpiar búsqueda',
                          icon: const Icon(Icons.close, color: muted),
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
            const Center(
              child: Padding(
                padding: EdgeInsets.all(22),
                child: CircularProgressIndicator(color: turquoise),
              ),
            )
          else if (_contactsError != null)
            Text(
              _contactsError!,
              style: const TextStyle(color: Color(0xFFFF8995)),
            )
          else if (_contacts.isEmpty)
            const Padding(
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
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.contact_phone_outlined, color: turquoise),
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
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            '${contact['value']} · ${contact['type']} · ID ${contact['id']}',
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                          if ((contact['department'] ?? '')
                              .toString()
                              .isNotEmpty)
                            Text(
                              contact['department'].toString(),
                              style: const TextStyle(
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
                      icon: const Icon(Icons.edit_outlined, color: turquoise),
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      onPressed: () => _deleteContact(contact),
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFE84657),
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
                style: const TextStyle(color: muted),
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

  Widget _brandingSection() {
    final primary = _parseColor(_colors['primary_color']!.text, turquoise);

    final sidebar = _parseColor(
      _colors['sidebar_color']!.text,
      const Color(0xFF1D1D1B),
    );

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Identidad visual de tu negocio',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
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
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Image.asset(
                    'assets/branding/logo_adn.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ADN MyCarWash',
                        style: TextStyle(
                          color: Colors.white,
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
          const Text(
            'Vista previa de marca. El cambio global del tema se integrará después.',
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: _colors[entry.key],
                              style: const TextStyle(color: Colors.white),
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
                style: const TextStyle(color: Colors.white),
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
                style: const TextStyle(color: Colors.white),
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
            title: const Text(
              'Interfaz compacta',
              style: TextStyle(color: Colors.white),
            ),
            value: _compactMode,
            activeThumbColor: turquoise,
            onChanged: (value) => setState(() => _compactMode = value),
          ),
          SwitchListTile(
            title: const Text(
              'Mostrar nombre comercial',
              style: TextStyle(color: Colors.white),
            ),
            value: _showBusinessName,
            activeThumbColor: turquoise,
            onChanged: (value) => setState(() => _showBusinessName = value),
          ),
          const SizedBox(height: 14),
          _saveButton(
            label: 'Guardar identidad visual',
            onPressed: _saveBranding,
          ),
        ],
      ),
    );
  }

  Widget _tab(String title, IconData icon, int index) {
    final active = _section == index;

    return InkWell(
      onTap: () => _changeSection(index),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13),
        decoration: BoxDecoration(
          color: active ? turquoise.withValues(alpha: 0.16) : surface,
          border: Border.all(color: active ? turquoise : border),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 19, color: active ? turquoise : muted),
            const SizedBox(width: 9),
            Text(
              title,
              style: TextStyle(
                color: active ? Colors.white : muted,
                fontWeight: active ? FontWeight.w800 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ADN PUBLICIDAD · SOFTWARE',
          style: TextStyle(
            color: turquoise,
            fontSize: 11,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 13),
        const Text(
          'Mi Empresa',
          style: TextStyle(
            fontSize: 31,
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 7),
        Text(_companyName, style: const TextStyle(color: muted)),
        const SizedBox(height: 23),
        if (_loading)
          const Center(
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
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8995))),
                const SizedBox(height: 15),
                OutlinedButton(
                  onPressed: _loadSettings,
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          )
        else ...[
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _tab('Información', Icons.business_outlined, 0),
              _tab('Contactos', Icons.contacts_outlined, 1),
              _tab('Identidad visual', Icons.palette_outlined, 2),
              _tab('Datos fiscales', Icons.receipt_long_outlined, 3),
              _tab('Direcciones', Icons.place_outlined, 4),
            ],
          ),
          const SizedBox(height: 19),
          if (_section == 0) _profileSection(),
          if (_section == 1) _contactSection(),
          if (_section == 2) _brandingSection(),
          if (_section == 3) CompanyFiscalSection(client: _client),
          if (_section == 4) CompanyAddressesSection(client: _client),
          const SizedBox(height: 20),
          const Row(
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
