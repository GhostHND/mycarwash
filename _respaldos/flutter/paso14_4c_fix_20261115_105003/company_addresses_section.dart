import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';

class CompanyAddressesSection extends StatefulWidget {
  const CompanyAddressesSection({super.key, required this.client});

  final http.Client client;

  @override
  State<CompanyAddressesSection> createState() =>
      _CompanyAddressesSectionState();
}

class _CompanyAddressesSectionState extends State<CompanyAddressesSection> {
  static const turquoise = Color(0xFF0FA7B4);
  static const surface = Color(0xFF0A1519);
  static const border = Color(0xFF20343C);
  static const muted = Color(0xFF9BAEB6);

  static const fields = <String, String>{
    'type': 'Tipo de dirección',
    'country': 'País',
    'department': 'Departamento',
    'municipality': 'Municipio',
    'neighborhood': 'Colonia o barrio',
    'street': 'Calle o avenida',
    'building_number': 'Número o local',
    'postal_code': 'Código postal',
    'full_address': 'Dirección completa',
    'reference': 'Punto de referencia',
    'latitude': 'Latitud (opcional)',
    'longitude': 'Longitud (opcional)',
  };

  late final TextEditingController _search;
  Timer? _debounce;
  int _requestVersion = 0;
  int _page = 1;
  int _lastPage = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _addresses = [];

  CompanyBusinessApi get _api => CompanyBusinessApi(widget.client);

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _requestVersion++;
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_requestVersion;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _api.request(
        'GET',
        '/addresses',
        query: {
          'q': _search.text.trim(),
          'page': _page.toString(),
          'per_page': '10',
        },
      );
      if (!mounted || version != _requestVersion) return;
      final raw = response['data'];
      setState(() {
        _addresses = raw is List
            ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
        _page = int.tryParse((response['current_page'] ?? 1).toString()) ?? 1;
        _lastPage = int.tryParse((response['last_page'] ?? 1).toString()) ?? 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _requestVersion) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _onSearch(String value) {
    _debounce?.cancel();
    setState(() => _page = 1);
    _debounce = Timer(const Duration(milliseconds: 280), () {
      if (mounted) _load();
    });
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

  InputDecoration _decoration(String label) => InputDecoration(
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
  );

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final controllers = <String, TextEditingController>{
      for (final key in fields.keys)
        key: TextEditingController(
          text:
              (existing?[key] ??
                      (key == 'country'
                          ? 'Honduras'
                          : key == 'type'
                          ? 'principal'
                          : ''))
                  .toString(),
        ),
    };
    final formKey = GlobalKey<FormState>();
    bool primary =
        existing?['is_primary'] == true || existing?['is_primary'] == 1;
    final wasPrimary = primary;
    bool saving = false;
    String? dialogError;

    try {
      final changed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, updateDialog) => AlertDialog(
            backgroundColor: surface,
            title: Text(
              existing == null ? 'Nueva dirección' : 'Editar dirección',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final field in fields.entries) ...[
                        TextFormField(
                          key: ValueKey('address_${field.key}'),
                          controller: controllers[field.key],
                          maxLines:
                              const [
                                'full_address',
                                'reference',
                              ].contains(field.key)
                              ? 3
                              : 1,
                          keyboardType:
                              const [
                                'latitude',
                                'longitude',
                              ].contains(field.key)
                              ? const TextInputType.numberWithOptions(
                                  signed: true,
                                  decimal: true,
                                )
                              : TextInputType.text,
                          style: const TextStyle(color: Colors.white),
                          decoration: _decoration(field.value),
                          validator: (value) {
                            final text = (value ?? '').trim();
                            final key = field.key;
                            final max = switch (key) {
                              'type' => 40,
                              'country' => 100,
                              'department' || 'municipality' => 120,
                              'neighborhood' => 180,
                              'street' => 255,
                              'building_number' => 50,
                              'postal_code' => 30,
                              _ => 5000,
                            };
                            if (text.length > max) {
                              return 'Máximo $max caracteres.';
                            }
                            if ((key == 'type' || key == 'country') &&
                                text.isEmpty) {
                              return 'Este dato es obligatorio.';
                            }
                            if (key == 'latitude' || key == 'longitude') {
                              if (text.isEmpty) return null;
                              final number = double.tryParse(text);
                              if (number == null || !number.isFinite) {
                                return 'Introduce un número válido.';
                              }
                              final limit = key == 'latitude' ? 90 : 180;
                              if (number < -limit || number > limit) {
                                return 'Rango permitido: -$limit a $limit.';
                              }
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Dirección principal',
                          style: TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          wasPrimary
                              ? 'Para cambiar la principal, marca otra dirección.'
                              : 'Solo una dirección puede ser principal.',
                          style: const TextStyle(color: muted),
                        ),
                        activeThumbColor: turquoise,
                        value: primary,
                        onChanged: saving || wasPrimary
                            ? null
                            : (value) => updateDialog(() => primary = value),
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
                        final hasLocation =
                            const [
                              'full_address',
                              'street',
                              'neighborhood',
                              'municipality',
                            ].any(
                              (key) => controllers[key]!.text.trim().isNotEmpty,
                            );
                        if (!hasLocation) {
                          updateDialog(() {
                            dialogError = 'Indica al menos una ubicación.';
                          });
                          return;
                        }
                        updateDialog(() {
                          saving = true;
                          dialogError = null;
                        });
                        final data = <String, dynamic>{};
                        for (final entry in controllers.entries) {
                          final value = entry.value.text.trim();
                          if (entry.key == 'latitude' ||
                              entry.key == 'longitude') {
                            data[entry.key] = value.isEmpty
                                ? null
                                : double.parse(value);
                          } else {
                            data[entry.key] = value.isEmpty ? null : value;
                          }
                        }
                        data['is_primary'] = primary;
                        try {
                          if (existing == null) {
                            await _api.request(
                              'POST',
                              '/addresses',
                              body: data,
                            );
                          } else {
                            await _api.request(
                              'PATCH',
                              '/addresses/${existing['id']}',
                              body: data,
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
                child: Text(saving ? 'Guardando...' : 'Guardar dirección'),
              ),
            ],
          ),
        ),
      );
      if (changed == true && mounted) {
        _notify('Dirección guardada correctamente.');
        _page = 1;
        await _load();
      }
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: surface,
        title: const Text(
          'Eliminar dirección',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          '¿Eliminar la dirección ${item['id']}? Esta acción no se puede deshacer.',
          style: const TextStyle(color: muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB63D4A),
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _api.request('DELETE', '/addresses/${item['id']}');
      _notify('Dirección eliminada.');
      await _load();
      if (_addresses.isEmpty && _page > 1 && mounted) {
        _page--;
        await _load();
      }
    } catch (error) {
      _notify(error.toString(), error: true);
    }
  }

  String _description(Map<String, dynamic> item) {
    final full = (item['full_address'] ?? '').toString().trim();
    if (full.isNotEmpty) return full;
    return [
          item['street'],
          item['neighborhood'],
          item['municipality'],
          item['department'],
          item['country'],
        ]
        .map((value) => (value ?? '').toString().trim())
        .where((value) => value.isNotEmpty)
        .join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: surface,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 14,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Direcciones del negocio',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Ubicaciones, referencias y dirección principal.',
                    style: TextStyle(color: muted),
                  ),
                ],
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Nueva dirección'),
                style: FilledButton.styleFrom(backgroundColor: turquoise),
              ),
            ],
          ),
          const SizedBox(height: 21),
          TextField(
            controller: _search,
            onChanged: _onSearch,
            style: const TextStyle(color: Colors.white),
            decoration:
                _decoration(
                  'Buscar por municipio, colonia, calle, dirección o ID',
                ).copyWith(
                  prefixIcon: const Icon(Icons.search, color: turquoise),
                  suffixIcon: IconButton(
                    tooltip: 'Limpiar búsqueda',
                    icon: const Icon(Icons.close, color: muted),
                    onPressed: () {
                      _search.clear();
                      _onSearch('');
                    },
                  ),
                ),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(color: turquoise),
              ),
            )
          else if (_error != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_error!, style: const TextStyle(color: Color(0xFFFF8995))),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _load,
                  child: const Text('Reintentar'),
                ),
              ],
            )
          else if (_addresses.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: Text(
                  'No se encontraron direcciones.',
                  style: TextStyle(color: muted),
                ),
              ),
            )
          else
            for (final item in _addresses)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.place_outlined, color: turquoise),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${item['type'] ?? 'Dirección'}'
                            '${item['is_primary'] == true || item['is_primary'] == 1 ? ' · Principal' : ''}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _description(item),
                            style: const TextStyle(color: muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'ID ${item['id']}',
                            style: const TextStyle(color: muted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Editar dirección',
                      onPressed: () => _edit(item),
                      icon: const Icon(Icons.edit_outlined, color: turquoise),
                    ),
                    IconButton(
                      tooltip: 'Eliminar dirección',
                      onPressed: () => _delete(item),
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
                style: const TextStyle(color: muted),
              ),
              IconButton(
                tooltip: 'Página siguiente',
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
}
