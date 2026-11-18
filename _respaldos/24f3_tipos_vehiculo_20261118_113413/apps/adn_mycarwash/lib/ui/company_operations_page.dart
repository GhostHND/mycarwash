import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import 'company_media_photo_dialog.dart';
import 'company_services_cards_24f.dart';
import 'company_service_tariff_fields_24f2.dart';
import 'company_clients_cards_24c.dart';
import 'company_vehicle_cards_24c2.dart';
import 'company_vehicle_photo_form_24c2.dart';
import 'company_employee_cards_24c3.dart';
import 'company_employee_photo_form_24c3.dart';
import '../core/business_identity.dart';

enum OperationsCatalog { clients, vehicles, employees, services }

class _FieldSpec {
  const _FieldSpec(
    this.key,
    this.label, {
    this.required = false,
    this.numeric = false,
    this.multiline = false,
  });

  final String key;
  final String label;
  final bool required;
  final bool numeric;
  final bool multiline;
}

class CompanyOperationsPage extends StatefulWidget {
  const CompanyOperationsPage({super.key, required this.catalog, this.client});

  final OperationsCatalog catalog;
  final http.Client? client;

  @override
  State<CompanyOperationsPage> createState() => _CompanyOperationsPageState();
}

class _CompanyOperationsPageState extends State<CompanyOperationsPage> {
  static const _turquoise = Color(0xFF0FA7B4);
  static const _surface = Color(0xFF0A1519);
  static const _border = Color(0xFF20343C);
  static const _muted = Color(0xFF9BAEB6);

  late final http.Client _client;
  late final bool _ownsClient;
  final _search = TextEditingController();
  Timer? _debounce;
  int _version = 0;
  int _page = 1;
  int _pages = 1;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = [];

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);

  String get _path => switch (widget.catalog) {
    OperationsCatalog.clients => '/clients',
    OperationsCatalog.vehicles => '/vehicles',
    OperationsCatalog.employees => '/employees',
    OperationsCatalog.services => '/services',
  };

  String get _title => switch (widget.catalog) {
    OperationsCatalog.clients => 'Clientes',
    OperationsCatalog.vehicles => 'Vehículos',
    OperationsCatalog.employees => 'Empleados',
    OperationsCatalog.services => 'Servicios de lavado',
  };

  String get _singular => switch (widget.catalog) {
    OperationsCatalog.clients => 'cliente',
    OperationsCatalog.vehicles => 'vehículo',
    OperationsCatalog.employees => 'empleado',
    OperationsCatalog.services => 'servicio',
  };

  IconData get _icon => switch (widget.catalog) {
    OperationsCatalog.clients => Icons.people_outline,
    OperationsCatalog.vehicles => Icons.directions_car_outlined,
    OperationsCatalog.employees => Icons.badge_outlined,
    OperationsCatalog.services => Icons.local_car_wash_outlined,
  };

  List<_FieldSpec> get _fields => switch (widget.catalog) {
    OperationsCatalog.clients => const [
      _FieldSpec('full_name', 'Nombre completo', required: true),
      _FieldSpec('identity_document', 'Documento de identidad'),
      _FieldSpec('phone', 'Teléfono'),
      _FieldSpec('email', 'Correo electrónico'),
      _FieldSpec('address', 'Dirección', multiline: true),
      _FieldSpec('notes', 'Observaciones', multiline: true),
    ],
    OperationsCatalog.vehicles => const [
      _FieldSpec('plate', 'Placa'),
      _FieldSpec('brand', 'Marca'),
      _FieldSpec('model', 'Modelo'),
      _FieldSpec('color', 'Color'),
      _FieldSpec('year', 'Año', numeric: true),
      _FieldSpec('vehicle_type', 'Tipo de vehículo'),
      _FieldSpec('notes', 'Observaciones', multiline: true),
    ],
    OperationsCatalog.employees => const [
      _FieldSpec('full_name', 'Nombre completo', required: true),
      _FieldSpec('identity_document', 'Documento de identidad'),
      _FieldSpec('phone', 'Teléfono'),
      _FieldSpec('email', 'Correo electrónico'),
      _FieldSpec('hire_date', 'Fecha de ingreso (AAAA-MM-DD)'),
      _FieldSpec('notes', 'Observaciones', multiline: true),
    ],
    OperationsCatalog.services => const [
      _FieldSpec('name', 'Nombre del servicio', required: true),
      _FieldSpec('description', 'Descripción', multiline: true),
      _FieldSpec(
        'price',
        'Precio en moneda del negocio',
        required: true,
        numeric: true,
      ),
      _FieldSpec(
        'duration_minutes',
        'Duración estimada (minutos)',
        required: true,
        numeric: true,
      ),
    ],
  };

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyOperationsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      _search.clear();
      _page = 1;
      _load();
    }
  }

  @override
  void dispose() {
    _version++;
    _debounce?.cancel();
    _search.dispose();
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final version = ++_version;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _api.request(
        'GET',
        _path,
        query: {
          'q': _search.text.trim(),
          'page': '$_page',
          'per_page':
              widget.catalog == OperationsCatalog.clients ||
                  widget.catalog == OperationsCatalog.employees
              ? '6'
              : '10',
        },
      );
      if (!mounted || version != _version) {
        return;
      }
      final data = result['data'];
      setState(() {
        _rows = data is List
            ? data
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
            : [];
        _page = int.tryParse('${result['current_page'] ?? 1}') ?? 1;
        _pages = int.tryParse('${result['last_page'] ?? 1}') ?? 1;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || version != _version) {
        return;
      }
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _onSearch(String text) {
    _debounce?.cancel();
    _page = 1;
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) {
        _load();
      }
    });
  }

  void _notify(String text, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
      ),
    );
  }

  InputDecoration _decoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: const TextStyle(color: _muted),
    filled: true,
    fillColor: const Color(0xFF111F25),
    enabledBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: _border),
      borderRadius: BorderRadius.circular(10),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: _turquoise),
      borderRadius: BorderRadius.circular(10),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: const BorderSide(color: Color(0xFFE84657)),
      borderRadius: BorderRadius.circular(10),
    ),
  );

  Future<Map<String, dynamic>?> _selectClient() async {
    Future<Map<String, dynamic>> pending = _api.request(
      'GET',
      '/clients',
      query: {'q': '', 'per_page': '30'},
    );
    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          backgroundColor: _surface,
          title: const Text(
            'Seleccionar cliente',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 510,
            height: 430,
            child: Column(
              children: [
                TextField(
                  key: const ValueKey('operations_client_search'),
                  style: const TextStyle(color: Colors.white),
                  decoration: _decoration(
                    'Buscar cliente por nombre o documento',
                  ),
                  onChanged: (text) {
                    update(() {
                      pending = _api.request(
                        'GET',
                        '/clients',
                        query: {'q': text.trim(), 'per_page': '30'},
                      );
                    });
                  },
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: FutureBuilder<Map<String, dynamic>>(
                    future: pending,
                    builder: (context, snapshot) {
                      if (snapshot.connectionState != ConnectionState.done) {
                        return const Center(
                          child: CircularProgressIndicator(color: _turquoise),
                        );
                      }
                      if (snapshot.hasError) {
                        return Text(
                          '${snapshot.error}',
                          style: const TextStyle(color: Colors.redAccent),
                        );
                      }
                      final records = snapshot.data?['data'];
                      final items = records is List
                          ? records.whereType<Map>().toList()
                          : <Map>[];
                      if (items.isEmpty) {
                        return const Center(
                          child: Text(
                            'No se encontraron clientes.',
                            style: TextStyle(color: _muted),
                          ),
                        );
                      }
                      return ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final client = Map<String, dynamic>.from(
                            items[index],
                          );
                          if (client['is_active'] == false ||
                              client['is_active'] == 0) {
                            return const SizedBox.shrink();
                          }
                          return ListTile(
                            title: Text(
                              '${client['full_name'] ?? ''}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            subtitle: Text(
                              '${client['identity_document'] ?? ''}',
                              style: const TextStyle(color: _muted),
                            ),
                            onTap: () =>
                                Navigator.of(dialogContext).pop(client),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancelar'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit([Map<String, dynamic>? existing]) async {
    final form = GlobalKey<FormState>();
    final controllers = <String, TextEditingController>{
      for (final field in _fields)
        field.key: TextEditingController(
          text: (existing?[field.key] ?? '').toString(),
        ),
    };
    bool active =
        existing == null ||
        existing['is_active'] == true ||
        existing['is_active'] == 1;
    String position = (existing?['position'] ?? 'washer').toString();
    const positions = {
      'washer': 'Lavador',
      'supervisor': 'Supervisor',
      'cashier': 'Cajero',
      'manager': 'Administrador',
      'other': 'Otro',
    };
    if (!positions.containsKey(position)) {
      position = 'other';
    }
    int? clientId = int.tryParse('${existing?['client_id'] ?? ''}');
    String clientName = (existing?['client_name'] ?? '').toString();
    bool saving = false;
    String? dialogError;
    bool didChange = false;
    final serviceTariffDraft24F2 = ServiceVehicleTariffDraft24F2(
      existing?['vehicle_prices'] is List
          ? existing!['vehicle_prices'] as List<dynamic>
          : <dynamic>[],
    );
    int? persistedServiceId24F2 = int.tryParse('${existing?['id'] ?? ''}');
    final photoDraft24C2 = CompanyVehiclePhotoDraft24C2();
    final photoDraft24C3 = CompanyEmployeePhotoDraft24C3();
    int? persistedEmployeeId24C3 = int.tryParse('${existing?['id'] ?? ''}');
    int? persistedVehicleId24C2 = int.tryParse('${existing?['id'] ?? ''}');

    try {
      final route = DialogRoute<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            backgroundColor: _surface,
            title: Text(
              existing == null ? 'Nuevo $_singular' : 'Editar $_singular',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 550,
              child: SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.catalog == OperationsCatalog.vehicles) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                clientId == null
                                    ? 'Cliente: pendiente de seleccionar'
                                    : 'Cliente: $clientName (ID $clientId)',
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                            TextButton.icon(
                              key: const ValueKey('operations_choose_client'),
                              onPressed: saving
                                  ? null
                                  : () async {
                                      final selected = await _selectClient();
                                      if (selected != null &&
                                          dialogContext.mounted) {
                                        update(() {
                                          clientId = int.tryParse(
                                            '${selected['id']}',
                                          );
                                          clientName =
                                              '${selected['full_name'] ?? ''}';
                                          dialogError = null;
                                        });
                                      }
                                    },
                              icon: const Icon(Icons.person_search_outlined),
                              label: const Text('Seleccionar'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.catalog == OperationsCatalog.vehicles) ...[
                        CompanyVehiclePhotoField24C2(
                          client: _client,
                          vehicleId: int.tryParse('${existing?['id'] ?? ''}'),
                          draft: photoDraft24C2,
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.catalog == OperationsCatalog.employees) ...[
                        CompanyEmployeePhotoField24C3(
                          client: _client,
                          employeeId: int.tryParse('${existing?['id'] ?? ''}'),
                          draft: photoDraft24C3,
                        ),
                        const SizedBox(height: 12),
                      ],
                      for (final field in _fields) ...[
                        TextFormField(
                          key: ValueKey('operations_${field.key}'),
                          controller: controllers[field.key],
                          enabled: !saving,
                          maxLines: field.multiline ? 3 : 1,
                          keyboardType: field.numeric
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : TextInputType.text,
                          style: const TextStyle(color: Colors.white),
                          decoration: _decoration(field.label),
                          validator: (text) {
                            final value = (text ?? '').trim();
                            if (field.required && value.isEmpty) {
                              return 'Campo obligatorio.';
                            }
                            if (field.key == 'price') {
                              final n = double.tryParse(value);
                              if (n == null || !n.isFinite || n < 0) {
                                return 'Precio inválido.';
                              }
                              if (!RegExp(r'^\d+(?:\.\d{1,2})?$')
                                  .hasMatch(value)) {
                                return 'Máximo dos decimales.';
                              }
                            }
                            if (field.key == 'duration_minutes' &&
                                (int.tryParse(value) == null ||
                                    int.parse(value) < 1 ||
                                    int.parse(value) > 1440)) {
                              return 'Entre 1 y 1440 minutos.';
                            }
                            if (field.key == 'year' &&
                                value.isNotEmpty &&
                                (int.tryParse(value) == null ||
                                    int.parse(value) < 1900 ||
                                    int.parse(value) >
                                        DateTime.now().year + 1)) {
                              return 'Año no válido.';
                            }
                            if (field.key == 'email' &&
                                value.isNotEmpty &&
                                !value.contains('@')) {
                              return 'Correo no válido.';
                            }
                            if (field.key == 'hire_date' &&
                                value.isNotEmpty &&
                                !RegExp(r'^\d{4}-\d{2}-\d{2}$')
                                    .hasMatch(value)) {
                              return 'Usa AAAA-MM-DD.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.catalog == OperationsCatalog.employees) ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey('operations_position_$position'),
                          initialValue: position,
                          isExpanded: true,
                          dropdownColor: _surface,
                          style: const TextStyle(color: Colors.white),
                          decoration: _decoration('Cargo'),
                          items: positions.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: saving
                              ? null
                              : (v) {
                                  if (v != null) {
                                    update(() => position = v);
                                  }
                                },
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (widget.catalog == OperationsCatalog.services) ...[
                        CompanyServiceTariffFields24F2(
                          draft: serviceTariffDraft24F2,
                        ),
                        const SizedBox(height: 12),
                      ],
                      Material(
                        color: Colors.transparent,
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text(
                            'Activo',
                            style: TextStyle(color: Colors.white),
                          ),
                          value: active,
                          activeThumbColor: _turquoise,
                          onChanged: saving
                              ? null
                              : (v) => update(() => active = v),
                        ),
                      ),
                      if (dialogError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            dialogError!,
                            style: const TextStyle(color: Colors.redAccent),
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
                key: const ValueKey('operations_save'),
                onPressed: saving
                    ? null
                    : () async {
                        if (!form.currentState!.validate()) {
                          return;
                        }
                        if (widget.catalog == OperationsCatalog.vehicles &&
                            clientId == null) {
                          update(
                            () => dialogError =
                                'Debes seleccionar un cliente activo.',
                          );
                          return;
                        }
                        final payload = <String, dynamic>{'is_active': active};
                        for (final field in _fields) {
                          final text = controllers[field.key]!.text.trim();
                          if (field.key == 'price') {
                            payload[field.key] = double.parse(text);
                          } else if (field.key == 'duration_minutes' ||
                              field.key == 'year') {
                            payload[field.key] = text.isEmpty
                                ? null
                                : int.parse(text);
                          } else {
                            payload[field.key] = text.isEmpty ? null : text;
                          }
                        }
                        if (widget.catalog == OperationsCatalog.vehicles) {
                          payload['client_id'] = clientId;
                        }
                        if (widget.catalog == OperationsCatalog.employees) {
                          payload['position'] = position;
                        }
                        update(() {
                          saving = true;
                          dialogError = null;
                        });
                        try {
                          // Si se creó el registro pero falló la foto, el reintento
                          // no debe duplicar el vehículo.
                          final saved24C2 =
                              widget.catalog == OperationsCatalog.services &&
                                  existing == null &&
                                  persistedServiceId24F2 != null
                              ? <String, dynamic>{
                                  'data': {'id': persistedServiceId24F2},
                                }
                              : existing == null &&
                                    widget.catalog ==
                                        OperationsCatalog.employees &&
                                    persistedEmployeeId24C3 != null
                              ? <String, dynamic>{
                                  'data': {'id': persistedEmployeeId24C3},
                                }
                              : widget.catalog == OperationsCatalog.vehicles &&
                                    existing == null &&
                                    persistedVehicleId24C2 != null
                              ? <String, dynamic>{
                                  'data': {'id': persistedVehicleId24C2},
                                }
                              : await _api.request(
                                  existing == null ? 'POST' : 'PATCH',
                                  existing == null
                                      ? _path
                                      : '$_path/${existing['id']}',
                                  body: payload,
                                );
                          if (widget.catalog == OperationsCatalog.services) {
                            final resultData = saved24C2['data'];
                            final serviceId = int.tryParse(
                              '${resultData is Map ? resultData['id'] : existing?['id']}',
                            );
                            if (serviceId == null) {
                              throw Exception(
                                'No se obtuvo el ID del servicio.',
                              );
                            }
                            persistedServiceId24F2 = serviceId;
                            final prices = serviceTariffDraft24F2
                                .validatedPrices();
                            await _api.request(
                              'PATCH',
                              '/services/$serviceId/vehicle-prices',
                              body: {'prices': prices},
                            );
                          }
                          if (widget.catalog == OperationsCatalog.vehicles) {
                            final data24C2 = saved24C2['data'];
                            final savedId24C2 = int.tryParse(
                              '${data24C2 is Map ? data24C2['id'] : existing?['id']}',
                            );
                            if (savedId24C2 == null) {
                              throw Exception(
                                'El servidor no devolvió el ID del vehículo.',
                              );
                            }
                            persistedVehicleId24C2 = savedId24C2;
                            await photoDraft24C2.save(_client, savedId24C2);
                          }
                          if (widget.catalog == OperationsCatalog.employees) {
                            final data24C3 = saved24C2['data'];
                            final savedId24C3 = int.tryParse(
                              '${data24C3 is Map ? data24C3['id'] : existing?['id']}',
                            );
                            if (savedId24C3 == null) {
                              throw Exception(
                                'El servidor no devolvió el ID del empleado.',
                              );
                            }
                            persistedEmployeeId24C3 = savedId24C3;
                            await photoDraft24C3.save(_client, savedId24C3);
                          }
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(true);
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            update(() {
                              saving = false;
                              dialogError = error.toString();
                            });
                          }
                        }
                      },
                style: FilledButton.styleFrom(backgroundColor: _turquoise),
                child: Text(saving ? 'Guardando...' : 'Guardar'),
              ),
            ],
          ),
        ),
      );
      didChange =
          await Navigator.of(context, rootNavigator: true).push<bool>(route) ??
          false;
      await route.completed;
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      serviceTariffDraft24F2.dispose();
    }
    if (didChange && mounted) {
      _notify('Registro guardado correctamente.');
      _page = 1;
      await _load();
    }
  }

  Future<void> _delete(Map<String, dynamic> item) async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _surface,
        title: Text(
          'Archivar $_singular',
          style: const TextStyle(color: Colors.white),
        ),
        content: const Text(
          'El registro se archivará y dejará de aparecer en el listado. Esta acción no elimina su historial.',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) {
      return;
    }
    try {
      await _api.request('DELETE', '$_path/${item['id']}');
      _notify('Registro archivado.');
      if (_rows.length == 1 && _page > 1) {
        _page--;
      }
      await _load();
    } catch (error) {
      _notify(error.toString(), error: true);
    }
  }

  String _rowTitle(Map<String, dynamic> row) => switch (widget.catalog) {
    OperationsCatalog.clients => '${row['full_name'] ?? ''}',
    OperationsCatalog.vehicles =>
      '${row['plate'] ?? 'Sin placa'} · ${row['brand'] ?? ''} ${row['model'] ?? ''}',
    OperationsCatalog.employees => '${row['full_name'] ?? ''}',
    OperationsCatalog.services => '${row['name'] ?? ''}',
  };

  String _rowDetail(Map<String, dynamic> row) => switch (widget.catalog) {
    OperationsCatalog.clients =>
      '${row['phone'] ?? 'Sin teléfono'} · ${row['identity_document'] ?? 'Sin documento'}',
    OperationsCatalog.vehicles =>
      'Cliente: ${row['client_name'] ?? 'No disponible'} · ${row['color'] ?? 'Sin color'}',
    OperationsCatalog.employees =>
      '${row['position'] ?? 'washer'} · ${row['phone'] ?? 'Sin teléfono'}',
    OperationsCatalog.services =>
      'Precio: ${row['price'] ?? '0'} · ${row['duration_minutes'] ?? '?'} min',
  };

  Widget _panel(Widget child) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(22),
    decoration: BoxDecoration(
      color: _surface,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(16),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ADN PUBLICIDAD · SOFTWARE',
          style: TextStyle(
            color: _turquoise,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 12),
        if (widget.catalog == OperationsCatalog.clients ||
            widget.catalog == OperationsCatalog.vehicles ||
            widget.catalog == OperationsCatalog.employees)
          ValueListenableBuilder<BusinessIdentityData>(
            valueListenable: BusinessIdentity.current,
            builder: (context, identity, _) => Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    _title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 31,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(width: 1, height: 65, color: _border),
                const SizedBox(width: 15),
                SizedBox(
                  width: 140,
                  height: 75,
                  child: identity.logoBytes == null
                      ? Center(
                          child: Text(
                            identity.companyName.isEmpty
                                ? 'Mi empresa'
                                : identity.companyName,
                            maxLines: 2,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      : Image.memory(
                          identity.logoBytes!,
                          fit: BoxFit.contain,
                          gaplessPlayback: true,
                        ),
                ),
              ],
            ),
          ),
        if (widget.catalog != OperationsCatalog.clients &&
            widget.catalog != OperationsCatalog.vehicles &&
            widget.catalog != OperationsCatalog.employees)
          Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 31,
              fontWeight: FontWeight.w800,
            ),
          ),
        const SizedBox(height: 8),
        const Text(
          'Administración del negocio · Datos vinculados a la empresa activa.',
          style: TextStyle(color: _muted),
        ),
        const SizedBox(height: 22),
        _panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('operations_new'),
                    onPressed: () => _edit(),
                    style: FilledButton.styleFrom(backgroundColor: _turquoise),
                    icon: const Icon(Icons.add),
                    label: Text('Nuevo $_singular'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Actualizar'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                key: const ValueKey('operations_search'),
                controller: _search,
                onChanged: _onSearch,
                style: const TextStyle(color: Colors.white),
                decoration: _decoration('Buscar en $_title').copyWith(
                  prefixIcon: const Icon(Icons.search, color: _turquoise),
                  suffixIcon: IconButton(
                    onPressed: () {
                      _search.clear();
                      _onSearch('');
                    },
                    icon: const Icon(Icons.close, color: _muted),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(25),
                    child: CircularProgressIndicator(color: _turquoise),
                  ),
                )
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.redAccent))
              else if (_rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text(
                      'No hay $_title registrados.',
                      style: const TextStyle(color: _muted),
                    ),
                  ),
                )
              else if (widget.catalog == OperationsCatalog.clients)
                CompanyClientsCardGrid24C(
                  rows: _rows,
                  accent: Theme.of(context).colorScheme.primary,
                  onEdit: _edit,
                  onArchive: _delete,
                )
              else if (widget.catalog == OperationsCatalog.vehicles)
                CompanyVehiclesGrid24C2(
                  rows: _rows,
                  client: _client,
                  onEdit: _edit,
                  onArchive: _delete,
                )
              else if (widget.catalog == OperationsCatalog.employees)
                CompanyEmployeesGrid24C3(
                  rows: _rows,
                  client: _client,
                  onEdit: _edit,
                  onArchive: _delete,
                )
              else if (widget.catalog == OperationsCatalog.services)
                CompanyServicesCards24F(
                  records: _rows,
                  onEdit: (record) => _edit(record),
                  onArchive: (record) => _delete(record),
                )
              else
                for (final record in _rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: const Color(0xFF111F25),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(_icon, color: _turquoise),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _rowTitle(record),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _rowDetail(record),
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'ID ${record['id']} · ${record['is_active'] == false || record['is_active'] == 0 ? 'Inactivo' : 'Activo'}',
                                    style: const TextStyle(
                                      color: _muted,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.catalog == OperationsCatalog.employees)
                              IconButton(
                                tooltip: 'Fotografía',
                                icon: const Icon(
                                  Icons.photo_camera_outlined,
                                  color: _turquoise,
                                ),
                                onPressed: () async {
                                  await showDialog<void>(
                                    context: context,
                                    builder: (_) => CompanyMediaPhotoDialog(
                                      client: _client,
                                      kind:
                                          widget.catalog ==
                                              OperationsCatalog.vehicles
                                          ? 'vehicles'
                                          : 'employees',
                                      recordId: int.parse('${record['id']}'),
                                      title: _rowTitle(record),
                                    ),
                                  );
                                  if (mounted) _load();
                                },
                              ),
                            IconButton(
                              tooltip: 'Editar',
                              icon: const Icon(
                                Icons.edit_outlined,
                                color: _turquoise,
                              ),
                              onPressed: () => _edit(record),
                            ),
                            IconButton(
                              tooltip: 'Archivar',
                              icon: const Icon(
                                Icons.archive_outlined,
                                color: Color(0xFFE84657),
                              ),
                              onPressed: () => _delete(record),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              const SizedBox(height: 13),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    tooltip: 'Página anterior',
                    icon: const Icon(Icons.chevron_left),
                    onPressed: _loading || _page <= 1
                        ? null
                        : () {
                            _page--;
                            _load();
                          },
                  ),
                  Text(
                    'Página $_page de $_pages',
                    style: const TextStyle(color: _muted),
                  ),
                  IconButton(
                    tooltip: 'Página siguiente',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: _loading || _page >= _pages
                        ? null
                        : () {
                            _page++;
                            _load();
                          },
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
