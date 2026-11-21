import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/mycarwash_session.dart';
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';

class CompanyNewOrderB25B extends StatefulWidget {
  const CompanyNewOrderB25B({super.key, required this.api, required this.options, this.existing});
  final CompanyBusinessApi api;
  final Future<Map<String, List<Map<String, dynamic>>>> options;
  final Map<String, dynamic>? existing;
  @override
  State<CompanyNewOrderB25B> createState() => _CompanyNewOrderB25BState();
}

class _ServiceLineB25B {
  int? serviceId;
  final name = TextEditingController();
  final price = TextEditingController();
  final percent = TextEditingController(text: '40');
  void dispose() { name.dispose(); price.dispose(); percent.dispose(); }
}

class _CompanyNewOrderB25BState extends State<CompanyNewOrderB25B> {
  static Color get accent => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get surface => CompanyVisualTheme.legacy(const Color(0xFF0A1519));
  static Color get border => CompanyVisualTheme.legacy(const Color(0xFF20343C));
  static Color get field => CompanyVisualTheme.legacy(const Color(0xFF111F25));
  final form = GlobalKey<FormState>();
  final notes = TextEditingController();
  final lines = <_ServiceLineB25B>[_ServiceLineB25B()];
  int? branchId, vehicleId, bayId, workerId;
  Map<String, dynamic>? selectedVehicle;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    final old = widget.existing;
    if (old == null) return;
    branchId = id(old['branch_id']);
    vehicleId = id(old['vehicle_id']);
    bayId = id(old['bay_id']);
    if (old['selected_vehicle_b25h'] is Map) selectedVehicle = Map<String, dynamic>.from(old['selected_vehicle_b25h'] as Map);
    notes.text = '${old['notes'] ?? ''}';
    final assignments = old['assignments'];
    if (assignments is List && assignments.isNotEmpty) {
      final primary = assignments.whereType<Map>().where((a) => a['is_primary'] == true || a['is_primary'] == 1);
      final first = primary.isNotEmpty ? primary.first : assignments.first;
      if (first is Map) workerId = id(first['employee_id']);
    }
    final saved = old['service_lines_b25'];
    if (saved is List && saved.isNotEmpty) {
      lines.first.dispose(); lines.clear();
      for (final item in saved.whereType<Map>()) {
        final line = _ServiceLineB25B();
        line.serviceId = id(item['service_id']);
        line.name.text = '${item['service_name'] ?? ''}';
        line.price.text = '${item['price'] ?? '0'}';
        line.percent.text = '${item['commission_percent'] ?? '40'}';
        lines.add(line);
      }
    } else {
      lines.first.serviceId = id(old['service_id']);
      lines.first.price.text = '${old['quoted_price'] ?? '0'}';
      lines.first.name.text = '${old['service_name'] ?? ''}';
    }
  }
  String? error;
  @override
  void dispose() {
    notes.dispose();
    for (final line in lines) { line.dispose(); }
    super.dispose();
  }
  int? id(dynamic value) => int.tryParse('$value');
  Map<String, dynamic>? find(List<Map<String, dynamic>> rows, int? key) {
    for (final row in rows) { if (id(row['id']) == key) return row; }
    return null;
  }
  double priceFor(Map<String, dynamic> service, Map<String, dynamic>? vehicle) {
    final type = '${vehicle?['vehicle_type'] ?? ''}'.toLowerCase().trim();
    if ('${service['name'] ?? ''}'.trim().toLowerCase() == 'otro' || '${service['name'] ?? ''}'.trim().toLowerCase() == 'otros servicios') {
      return double.tryParse('${service['price']}') ?? 0;
    }
    final tariffs = service['vehicle_prices'];
    if (tariffs is List && type.isNotEmpty) {
      for (final tariff in tariffs) {
        if (tariff is Map && '${tariff['vehicle_type'] ?? ''}'.toLowerCase().trim() == type) {
          return double.tryParse('${tariff['price']}') ?? 0;
        }
      }
    }
    return double.tryParse('${service['price']}') ?? 0;
  }
  InputDecoration decoration(String label) => InputDecoration(
    labelText: label, filled: true, fillColor: field,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
  );
  Widget selector(String label, int? selected, List<Map<String, dynamic>> rows,
      String Function(Map<String, dynamic>) labelFor, ValueChanged<int?> change,
      {bool isRequired = true}) {
    return DropdownButtonFormField<int>(
      initialValue: selected, isExpanded: true, dropdownColor: surface,
      decoration: decoration(label),
      items: [if (!isRequired) const DropdownMenuItem<int>(value: null, child: Text('Sin asignar')),
        ...rows.map((e) => DropdownMenuItem<int>(value: id(e['id']), child: Text(labelFor(e), overflow: TextOverflow.ellipsis)))],
      onChanged: saving ? null : (v) => setState(() => change(v)),
      validator: (v) => isRequired && v == null ? 'Selecciona una opción' : null,
    );
  }
  Widget serviceRow(_ServiceLineB25B line, int index, Map<String, List<Map<String, dynamic>>> data) {
    final services = data['services'] ?? [];
    final vehicle = selectedVehicle ?? find(data['vehicles'] ?? [], vehicleId);
    final price = double.tryParse(line.price.text.replaceAll(',', '.')) ?? 0;
    final pct = double.tryParse(line.percent.text.replaceAll(',', '.')) ?? 0;
    final selectedService = find(services, line.serviceId);
    final isOther = ['otro', 'otros servicios'].contains(
      '${selectedService?['name'] ?? ''}'.trim().toLowerCase());
    return Container(
      margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: field, border: Border.all(color: border), borderRadius: BorderRadius.circular(14)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('SERVICIO ${index + 1}', style: TextStyle(color: accent, fontWeight: FontWeight.w700))),
          if (index > 0) IconButton(tooltip: 'Eliminar servicio extra', icon: const Icon(Icons.close_rounded),
            onPressed: saving ? null : () => setState(() { lines.removeAt(index); line.dispose(); })),
        ]),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, size) {
          final wide = size.maxWidth >= 490;
          final service = DropdownButtonFormField<int>(
            key: ValueKey('service-$index-${line.serviceId}'),
            initialValue: line.serviceId, isExpanded: true, dropdownColor: surface,
            decoration: decoration('Servicio'),
            items: services.map((item) => DropdownMenuItem<int>(
              value: id(item['id']), child: Text('${item['name']}', overflow: TextOverflow.ellipsis))).toList(),
            onChanged: saving ? null : (value) => setState(() {
              line.serviceId = value;
              final chosen = find(services, value);
              if (chosen != null) {
                line.name.text = ['otro', 'otros servicios'].contains(
                    '${chosen['name']}'.trim().toLowerCase()) ? '' : '${chosen['name']}';
                line.price.text = ['otro', 'otros servicios'].contains(
                    '${chosen['name']}'.trim().toLowerCase())
                    ? '' : priceFor(chosen, vehicle).toStringAsFixed(2);
              }
            }),
            validator: (value) => value == null ? 'Selecciona un servicio' : null,
          );
          final amount = TextFormField(
            controller: line.price, decoration: decoration('Precio (L)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final parsed = double.tryParse((v ?? '').replaceAll(',', '.'));
              return parsed == null || !parsed.isFinite || parsed < (isOther ? 0.01 : 0) || parsed > 9999999999.99 ||
                  !RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(v ?? '') ? 'Precio no válido' : null;
            },
          );
          final percent = TextFormField(
            controller: line.percent, decoration: decoration('Comisión (%)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final parsed = double.tryParse((v ?? '').replaceAll(',', '.'));
              return parsed == null || !parsed.isFinite || parsed < 0 || parsed > 100 ||
                  !RegExp(r'^\d+(?:[.,]\d{1,2})?$').hasMatch(v ?? '') ? 'Porcentaje no válido' : null;
            },
          );
          if (wide) {
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 5, child: service), const SizedBox(width: 8),
              Expanded(flex: 3, child: amount), const SizedBox(width: 8),
              Expanded(flex: 3, child: percent),
            ]);
          }
          return Column(children: [service, const SizedBox(height: 8),
            Row(children: [Expanded(child: amount), const SizedBox(width: 8), Expanded(child: percent)])]);
        }),
        if (isOther) ...[
          const SizedBox(height: 9),
          TextFormField(controller: line.name,
            decoration: decoration('Descripción del trabajo (factura y recibo)'),
            validator: (v) {
              final name = (v ?? '').trim();
              if (name.isEmpty || ['otros servicios', 'otro'].contains(name.toLowerCase())) {
                return 'Escribe el nombre real del trabajo';
              }
              if (name.length > 150) return 'Máximo 150 caracteres';
              return null;
            }),
        ],
        const SizedBox(height: 8),
        Text('Comisión prevista: L ${(price * pct / 100).toStringAsFixed(2)}',
          style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
      ]),
    );
  }
  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    if (branchId == null || vehicleId == null) { setState(() => error = 'Selecciona sucursal y vehículo'); return; }
    if (lines.first.serviceId == null) { setState(() => error = 'Selecciona el servicio principal del catálogo.'); return; }
    setState(() { saving = true; error = null; });
    try {
      await widget.api.request(widget.existing == null ? 'POST' : 'PATCH',
        widget.existing == null ? '/workflow/orders' : '/workflow/orders/${widget.existing!['id']}', body: {
        'branch_id': branchId, 'vehicle_id': vehicleId, 'bay_id': bayId,
        'primary_employee_id': workerId,
        'service_id': lines.first.serviceId,
        'notes': notes.text.trim().isEmpty ? null : notes.text.trim(),
        'service_lines_b25': lines.map((l) => {
          'service_id': l.serviceId,
          'service_name': l.name.text.trim(),
          'price': double.parse(l.price.text.replaceAll(',', '.')),
          'commission_percent': double.parse(l.percent.text.replaceAll(',', '.')),
        }).toList(),
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) { if (mounted) setState(() => error = '$e'); }
    finally { if (mounted) setState(() => saving = false); }
  }
  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: surface,
    title: Text(widget.existing == null ? 'Nueva orden de lavado' : 'Editar orden de lavado'),
    content: SizedBox(width: 720, child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: widget.options, builder: (context, snapshot) {
        if (snapshot.hasError) return Text('${snapshot.error}');
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: accent));
        final data = snapshot.data!;
        final branches = data['branches'] ?? [];
        if (branchId == null && branches.length == 1) branchId = id(branches.first['id']);
        final vehicles = data['vehicles'] ?? [];
        final bays = data['bays'] ?? [];
        final services = data['services'] ?? [];
        final washers = (data['employees'] ?? []).where((employee) =>
          (employee['position'] == 'washer' || employee['position'] == 'supervisor') &&
          (employee['is_active'] == true || employee['is_active'] == 1 || employee['is_active'] == '1')).toList();
        return Form(key: form, child: SizedBox(height: 530, child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (branches.length > 1) ...[
              selector('Sucursal', branchId, branches, (r) => '${r['name']}', (v) => branchId = v),
              const SizedBox(height: 10),
            ] else if (branches.length == 1) ...[
              Text('Sucursal: ${branches.first['name']}', style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
            ],
            OutlinedButton.icon(
              onPressed: saving ? null : () async {
                final chosen = await showDialog<Map<String, dynamic>>(
                  context: context,
                  builder: (ctx) => _VehiclePickerB25H(api: widget.api),
                );
                if (chosen == null || !mounted) return;
                setState(() {
                  vehicleId = id(chosen['id']); selectedVehicle = chosen;
                  for (final line in lines) {
                    if (line.serviceId == null) continue;
                    final service = find(services, line.serviceId);
                    if (service != null && widget.existing == null &&
                        !['otro', 'otros servicios'].contains(
                          '${service['name'] ?? ''}'.trim().toLowerCase())) {
                      line.price.text = priceFor(service, chosen).toStringAsFixed(2);
                    }
                  }
                });
              },
              icon: Icon(Icons.directions_car_outlined, color: accent),
              label: Text(vehicleId == null ? 'Buscar y seleccionar vehículo' :
                'Vehículo: ${selectedVehicle?['plate'] ?? find(vehicles, vehicleId)?['plate'] ?? widget.existing?['plate'] ?? 'Seleccionado'} · Cambiar',
                maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(height: 10),
            selector('Puesto de lavado', bayId, bays, (r) => '${r['name']}', (v) => bayId = v, isRequired: false),
            const SizedBox(height: 10),
            selector('Lavador principal (opcional · comisión habitual)', workerId,
              washers, (r) => '${r['full_name']}',
              (value) {
                workerId = value;
                final employee = find(washers, value);
                final pct = double.tryParse('${employee?['commission_percent'] ?? 40}') ?? 40;
                for (final line in lines) { line.percent.text = pct.toStringAsFixed(2); }
              }, isRequired: false),
            const SizedBox(height: 16),
            ...List.generate(lines.length, (index) => serviceRow(lines[index], index, data)),
            OutlinedButton.icon(onPressed: saving || lines.length >= 20 ? null : () => setState(() => lines.add(_ServiceLineB25B()..percent.text =
                (double.tryParse('${find(washers, workerId)?['commission_percent'] ?? 40}') ?? 40).toStringAsFixed(2))),
              icon: const Icon(Icons.add_circle_outline), label: const Text('Agregar servicio extra')),
            const SizedBox(height: 12),
            TextFormField(controller: notes, decoration: decoration('Observaciones'), maxLines: 2),
            const SizedBox(height: 14),
            Text('Total a cobrar: L ${lines.fold<double>(0, (sum, line) => sum + (double.tryParse(line.price.text.replaceAll(',', '.')) ?? 0)).toStringAsFixed(2)}',
              style: TextStyle(color: accent, fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('Comisión prevista: L ${lines.fold<double>(0, (sum, line) => sum + (double.tryParse(line.price.text.replaceAll(',', '.')) ?? 0) * (double.tryParse(line.percent.text.replaceAll(',', '.')) ?? 0) / 100).toStringAsFixed(2)}',
              style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
            const Text('Comisión estimada; la liquidación requiere asistencia válida y trabajo completado.',
              style: TextStyle(fontSize: 11)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
          ]),
        )));
      },
    )),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Guardando...' : (widget.existing == null ? 'Crear orden' : 'Guardar cambios')))],
  );
}


/// B25H: selector paginado. Nunca carga cientos de vehículos en un Dropdown.
class _VehiclePickerB25H extends StatefulWidget {
  const _VehiclePickerB25H({required this.api});
  final CompanyBusinessApi api;
  @override
  State<_VehiclePickerB25H> createState() => _VehiclePickerB25HState();
}

class _VehiclePickerB25HState extends State<_VehiclePickerB25H> {
  final search = TextEditingController();
  int page = 1;
  int totalPages = 1;
  bool loading = true;
  String? error;
  List<Map<String, dynamic>> vehicles = [];
  int sequence = 0;
  Timer? debounce;

  @override
  void initState() { super.initState(); load(); }
  @override
  void dispose() { sequence++; debounce?.cancel(); search.dispose(); super.dispose(); }

  Future<void> load() async {
    final seq = ++sequence;
    setState(() { loading = true; error = null; });
    try {
      final response = await widget.api.request('GET', '/vehicles', query: {
        'q': search.text.trim(), 'page': '$page', 'per_page': '20',
      });
      if (!mounted || seq != sequence) return;
      setState(() {
        vehicles = ((response['data'] as List?) ?? [])
            .whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList();
        totalPages = int.tryParse('${response['last_page'] ?? 1}') ?? 1;
        loading = false;
      });
    } catch (e) {
      if (mounted && seq == sequence) setState(() { error = '$e'; loading = false; });
    }
  }
  Future<Widget> photo(int id) async {
    final url = Uri.parse('${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/vehicles/$id/file');
    try {
      final result = await http.get(url, headers: MyCarWashSession.headers)
          .timeout(const Duration(seconds: 6));
      if (result.statusCode == 200 && result.headers['content-type']?.startsWith('image/') == true) {
        return Image.memory(result.bodyBytes, width: 76, height: 64, fit: BoxFit.cover);
      }
    } catch (_) { /* Fotografía opcional */ }
    return const Icon(Icons.directions_car_outlined, size: 35);
  }
  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: CompanyVisualTheme.card,
    child: SizedBox(width: 770, height: 620, child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Seleccionar vehículo', style: TextStyle(
            color: CompanyVisualTheme.text, fontSize: 22, fontWeight: FontWeight.bold))),
          IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        const SizedBox(height: 10),
        TextField(controller: search,
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search),
            hintText: 'Buscar por placa, marca, modelo, color o tipo de vehículo', border: OutlineInputBorder()),
          onSubmitted: (_) { page = 1; load(); },
          onChanged: (_) {
            debounce?.cancel();
            debounce = Timer(const Duration(milliseconds: 320), () {
              if (mounted) { page = 1; load(); }
            });
          },
        ),
        const SizedBox(height: 12),
        Expanded(child: loading ? const Center(child: CircularProgressIndicator())
          : error != null ? Center(child: Text(error!))
          : vehicles.isEmpty ? const Center(child: Text('No se encontraron vehículos.'))
          : ListView.separated(
            itemCount: vehicles.length, separatorBuilder: (_, _) => const SizedBox(height: 7),
            itemBuilder: (ctx, index) {
              final v = vehicles[index];
              final id = int.tryParse('${v['id']}') ?? 0;
              return Card(child: InkWell(onTap: () => Navigator.pop(context, v),
                child: Padding(padding: const EdgeInsets.all(9), child: Row(children: [
                  SizedBox(width: 82, height: 68, child: FutureBuilder<Widget>(
                    future: photo(id), builder: (ctx, snap) => snap.data ?? const Icon(Icons.car_repair))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${v['brand'] ?? ''} ${v['model'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Placa: ${v['plate'] ?? 'Sin placa'} · ${v['vehicle_type'] ?? 'Tipo no registrado'}'),
                    Text('Color: ${v['color'] ?? 'No registrado'} · Año: ${v['year'] ?? 'No registrado'}'),
                  ])),
                  const Icon(Icons.chevron_right),
                ]))));
            },
          )),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(onPressed: page <= 1 || loading ? null : () { page--; load(); }, icon: const Icon(Icons.chevron_left)),
          Text('Página $page de $totalPages'),
          IconButton(onPressed: page >= totalPages || loading ? null : () { page++; load(); }, icon: const Icon(Icons.chevron_right)),
        ]),
      ]),
    )),
  );
}
