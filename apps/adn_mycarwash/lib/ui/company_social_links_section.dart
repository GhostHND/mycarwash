import 'dart:async';

import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

class CompanySocialLinksSection extends StatefulWidget {
  const CompanySocialLinksSection({super.key, required this.client});

  final http.Client client;

  @override
  State<CompanySocialLinksSection> createState() =>
      _CompanySocialLinksSectionState();
}

class _CompanySocialLinksSectionState extends State<CompanySocialLinksSection> {
  static Color get turquoise => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get surface => CompanyVisualTheme.legacy(const Color(0xFF0A1519));
  static Color get border => CompanyVisualTheme.legacy(const Color(0xFF20343C));
  static Color get muted => CompanyVisualTheme.legacy(const Color(0xFF9BAEB6));

  final _search = TextEditingController();
  Timer? _debounce;
  int _version = 0;
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _socials = [];

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _version++;
    _search.dispose();
    super.dispose();
  }

  InputDecoration _decor(String label) => InputDecoration(
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

  void _notice(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError
            ? CompanyVisualTheme.legacy(const Color(0xFF9C3541))
            : CompanyVisualTheme.legacy(const Color(0xFF126F75)),
      ),
    );
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.request(
        'GET',
        '/social-links',
        query: {'q': _search.text.trim(), 'page': '$_page', 'per_page': '10'},
      );
      if (!mounted || version != _version) return;
      final rows = response['data'];
      setState(() {
        _socials = rows is List
            ? rows
                  .whereType<Map>()
                  .map((r) => Map<String, dynamic>.from(r))
                  .toList()
            : [];
        _page = int.tryParse('${response['current_page'] ?? 1}') ?? 1;
        _lastPage = int.tryParse('${response['last_page'] ?? 1}') ?? 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _version) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    setState(() => _page = 1);
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load();
    });
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    var platform = (existing?['platform'] ?? '').toString();
    var username = (existing?['username'] ?? '').toString();
    var url = (existing?['url'] ?? '').toString();
    var sortOrder = (existing?['sort_order'] ?? 0).toString();
    var visible =
        existing == null ||
        existing['is_visible'] == true ||
        existing['is_visible'] == 1;
    var saving = false;
    String? error;
    final key = GlobalKey<FormState>();

    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, updateDialog) => AlertDialog(
          backgroundColor: surface,
          title: Text(
            existing == null ? 'Nueva red social' : 'Editar red social',
            style: TextStyle(color: CompanyVisualTheme.text),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Form(
                key: key,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      key: const ValueKey('social_platform'),
                      initialValue: platform,
                      enabled: !saving,
                      maxLength: 60,
                      style: TextStyle(color: CompanyVisualTheme.text),
                      decoration: _decor(
                        'Plataforma (instagram, facebook, tiktok...)',
                      ),
                      onChanged: (v) => platform = v.trim(),
                      validator: (v) =>
                          RegExp(r'^[a-z][a-z0-9_-]{0,59}$')
                              .hasMatch((v ?? '').trim())
                          ? null
                          : 'Usa minúsculas, números, _ o - (sin espacios).',
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('social_username'),
                      initialValue: username,
                      enabled: !saving,
                      maxLength: 150,
                      style: TextStyle(color: CompanyVisualTheme.text),
                      decoration: _decor('Usuario (opcional)'),
                      onChanged: (v) => username = v,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      key: const ValueKey('social_url'),
                      initialValue: url,
                      enabled: !saving,
                      maxLength: 600,
                      keyboardType: TextInputType.url,
                      style: TextStyle(color: CompanyVisualTheme.text),
                      decoration: _decor('URL completa (https://...)'),
                      onChanged: (v) => url = v.trim(),
                      validator: (v) {
                        final parsed = Uri.tryParse((v ?? '').trim());
                        if (parsed == null ||
                            !['https', 'http'].contains(parsed.scheme) ||
                            parsed.host.isEmpty) {
                          return 'Introduce un enlace http:// o https:// válido.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      initialValue: sortOrder,
                      enabled: !saving,
                      keyboardType: TextInputType.number,
                      style: TextStyle(color: CompanyVisualTheme.text),
                      decoration: _decor('Orden de visualización (0-100000)'),
                      onChanged: (v) => sortOrder = v.trim(),
                      validator: (v) {
                        final n = int.tryParse((v ?? '').trim());
                        return n != null && n >= 0 && n <= 100000
                            ? null
                            : 'Indica un entero entre 0 y 100000.';
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Visible públicamente',
                            style: TextStyle(color: CompanyVisualTheme.text),
                          ),
                        ),
                        Switch(
                          value: visible,
                          activeThumbColor: turquoise,
                          onChanged: saving
                              ? null
                              : (v) => updateDialog(() => visible = v),
                        ),
                      ],
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        error!,
                        style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995))),
                      ),
                    ],
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
              key: const ValueKey('social_save'),
              onPressed: saving
                  ? null
                  : () async {
                      if (!key.currentState!.validate()) return;
                      updateDialog(() {
                        saving = true;
                        error = null;
                      });
                      final payload = <String, dynamic>{
                        'platform': platform.trim(),
                        'username': username.trim().isEmpty
                            ? null
                            : username.trim(),
                        'url': url.trim(),
                        'is_visible': visible,
                        'sort_order': int.parse(sortOrder.trim()),
                      };
                      try {
                        await _api.request(
                          existing == null ? 'POST' : 'PATCH',
                          existing == null
                              ? '/social-links'
                              : '/social-links/${existing['id']}',
                          body: payload,
                        );
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(true);
                        }
                      } catch (e) {
                        if (dialogContext.mounted) {
                          updateDialog(() {
                            saving = false;
                            error = e.toString();
                          });
                        }
                      }
                    },
              style: FilledButton.styleFrom(backgroundColor: turquoise),
              child: Text(saving ? 'Guardando...' : 'Guardar red social'),
            ),
          ],
        ),
      ),
    );

    if (changed == true && mounted) {
      _notice('Red social guardada.');
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: surface,
        title: Text(
          'Eliminar red social',
          style: TextStyle(color: CompanyVisualTheme.text),
        ),
        content: Text(
          '¿Eliminar ${item['platform']}? Esta acción no se puede deshacer.',
          style: TextStyle(color: muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    try {
      await _api.request('DELETE', '/social-links/${item['id']}');
      _notice('Red social eliminada.');
      if (_socials.length == 1 && _page > 1) {
        _page--;
      }
      await _load();
    } catch (e) {
      _notice(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: [CompanyVisualTheme.legacy(const Color(0xFF11242C)), CompanyVisualTheme.legacy(const Color(0xFF0A171D))],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(19),
      border: Border.all(color: CompanyVisualTheme.legacy(const Color(0xFF2A414A))),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Redes sociales',
              style: TextStyle(
                fontSize: 20,
                color: CompanyVisualTheme.text,
                fontWeight: FontWeight.w800,
              ),
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva red social'),
              style: FilledButton.styleFrom(backgroundColor: turquoise),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text(
          'Enlaces y perfiles públicos del negocio.',
          style: TextStyle(color: muted),
        ),
        const SizedBox(height: 18),
        TextField(
          controller: _search,
          onChanged: _onSearch,
          style: TextStyle(color: CompanyVisualTheme.text),
          decoration: _decor('Buscar plataforma, usuario o enlace')
              .copyWith(prefixIcon: Icon(Icons.search, color: turquoise)),
        ),
        const SizedBox(height: 17),
        if (_loading)
          Center(child: CircularProgressIndicator(color: turquoise))
        else if (_error != null) ...[
          Text(_error!, style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995)))),
          TextButton(onPressed: _load, child: const Text('Reintentar redes')),
        ] else if (_socials.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 22),
            child: Text(
              'No se encontraron redes sociales.',
              style: TextStyle(color: muted),
            ),
          )
        else
          for (final social in _socials) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CompanyVisualTheme.legacy(const Color(0xFF12242C)),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color:
                      social['is_visible'] == true || social['is_visible'] == 1
                      ? turquoise.withValues(alpha: 0.40)
                      : CompanyVisualTheme.legacy(const Color(0xFF2A414A)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.public, color: turquoise),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${social['platform']} ${social['username'] == null ? '' : '· ${social['username']}'}',
                          style: TextStyle(
                            color: CompanyVisualTheme.text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        SelectableText(
                          '${social['url']}',
                          style: TextStyle(color: muted, fontSize: 12),
                        ),
                        Text(
                          social['is_visible'] == true ||
                                  social['is_visible'] == 1
                              ? 'Visible'
                              : 'Oculta',
                          style: TextStyle(color: muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Editar red social',
                    onPressed: () => _edit(social),
                    icon: Icon(Icons.edit_outlined, color: turquoise),
                  ),
                  IconButton(
                    tooltip: 'Eliminar red social',
                    onPressed: () => _delete(social),
                    icon: Icon(
                      Icons.delete_outline,
                      color: CompanyVisualTheme.legacy(const Color(0xFFE84657)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Página anterior de redes',
              onPressed: _loading || _page <= 1
                  ? null
                  : () {
                      _page--;
                      _load();
                    },
              icon: const Icon(Icons.chevron_left),
            ),
            Text(
              'Página $_page de $_lastPage',
              style: TextStyle(color: muted),
            ),
            IconButton(
              tooltip: 'Página siguiente de redes',
              onPressed: _loading || _page >= _lastPage
                  ? null
                  : () {
                      _page++;
                      _load();
                    },
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );
}
