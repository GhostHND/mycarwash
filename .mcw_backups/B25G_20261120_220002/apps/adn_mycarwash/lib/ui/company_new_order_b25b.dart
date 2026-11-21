import 'package:flutter/material.dart';
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';

class CompanyNewOrderB25B extends StatefulWidget {
  const CompanyNewOrderB25B({super.key, required this.api, required this.options});
  final CompanyBusinessApi api;
  final Future<Map<String, List<Map<String, dynamic>>>> options;
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
  int? branchId, vehicleId, bayId;
  bool saving = false;
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
      value: selected, isExpanded: true, dropdownColor: surface,
      decoration: decoration(label),
      items: [if (!isRequired) const DropdownMenuItem<int>(value: null, child: Text('Sin asignar')),
        ...rows.map((e) => DropdownMenuItem<int>(value: id(e['id']), child: Text(labelFor(e), overflow: TextOverflow.ellipsis)))],
      onChanged: saving ? null : (v) => setState(() => change(v)),
      validator: (v) => isRequired && v == null ? 'Selecciona una opción' : null,
    );
  }
  Widget serviceRow(_ServiceLineB25B line, int index, Map<String, List<Map<String, dynamic>>> data) {
    final services = data['services'] ?? [];
    final vehicle = find(data['vehicles'] ?? [], vehicleId);
    final price = double.tryParse(line.price.text.replaceAll(',', '.')) ?? 0;
    final pct = double.tryParse(line.percent.text.replaceAll(',', '.')) ?? 0;
    final selectedService = find(services, line.serviceId);
    final isOther = line.serviceId == null || '${selectedService?['name'] ?? ''}'.trim().toLowerCase() == 'otro';
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
        DropdownButtonFormField<int>(
          value: line.serviceId, isExpanded: true, dropdownColor: surface,
          decoration: decoration('Servicio'),
          items: [const DropdownMenuItem<int>(value: null, child: Text('Otro · escribir nombre manual')),
            ...services.map((s) => DropdownMenuItem<int>(value: id(s['id']),
              child: Text('${s['name']}', overflow: TextOverflow.ellipsis)))],
          onChanged: saving ? null : (value) => setState(() {
            line.serviceId = value;
            if (value != null) {
              final service = find(services, value)!;
              line.name.text = '${service['name']}'.trim().toLowerCase() == 'otro' ? '' : '${service['name']}';
              line.price.text = priceFor(service, vehicle).toStringAsFixed(2);
            } else { line.name.clear(); line.price.clear(); }
          }),
        ),
        if (isOther) ...[const SizedBox(height: 9), TextFormField(
          controller: line.name, decoration: decoration('Nombre del servicio Otro'),
          validator: (v) => (v ?? '').trim().isEmpty ? 'Escribe el nombre del servicio' : null,
        )],
        const SizedBox(height: 9),
        Row(children: [
          Expanded(child: TextFormField(controller: line.price,
            decoration: decoration('Precio L'), keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            validator: (v) { final n = double.tryParse((v ?? '').replaceAll(',', '.'));
              return n == null || n < 0 || n > 9999999999.99 ? 'Precio no válido' : null; },
          )),
          const SizedBox(width: 10),
          Expanded(child: TextFormField(controller: line.percent,
            decoration: decoration('Comisión %'), keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            validator: (v) { final n = double.tryParse((v ?? '').replaceAll(',', '.'));
              return n == null || n < 0 || n > 100 ? 'Porcentaje no válido' : null; },
          )),
        ]),
        const SizedBox(height: 8),
        Text('Comisión prevista: L ${(price * pct / 100).toStringAsFixed(2)}',
          style: TextStyle(color: accent, fontWeight: FontWeight.w600)),
      ]),
    );
  }
  Future<void> save() async {
    if (!(form.currentState?.validate() ?? false)) return;
    if (branchId == null || vehicleId == null) { setState(() => error = 'Selecciona sucursal y vehículo'); return; }
    if (lines.first.serviceId == null) { setState(() => error = 'El primer servicio debe ser del catálogo. Puedes usar Otro en las filas adicionales.'); return; }
    setState(() { saving = true; error = null; });
    try {
      await widget.api.request('POST', '/workflow/orders', body: {
        'branch_id': branchId, 'vehicle_id': vehicleId, 'bay_id': bayId,
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
    title: const Text('Nueva orden de lavado'),
    content: SizedBox(width: 720, child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
      future: widget.options, builder: (context, snapshot) {
        if (snapshot.hasError) return Text('${snapshot.error}');
        if (!snapshot.hasData) return Center(child: CircularProgressIndicator(color: accent));
        final data = snapshot.data!;
        final branches = data['branches'] ?? [];
        final vehicles = data['vehicles'] ?? [];
        final bays = data['bays'] ?? [];
        final services = data['services'] ?? [];
        return Form(key: form, child: SizedBox(height: 530, child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            selector('Sucursal', branchId, branches, (r) => '${r['name']}', (v) => branchId = v),
            const SizedBox(height: 10),
            selector('Vehículo', vehicleId, vehicles, (r) => '${r['plate'] ?? 'Sin placa'} · ${r['brand'] ?? ''} ${r['model'] ?? ''}',
              (v) { vehicleId = v; for (final line in lines) { if (line.serviceId != null) {
                final service = find(services, line.serviceId); if (service != null) line.price.text = priceFor(service, find(vehicles, v)).toStringAsFixed(2);
              } } }),
            const SizedBox(height: 10),
            selector('Puesto de lavado', bayId, bays, (r) => '${r['name']}', (v) => bayId = v, isRequired: false),
            const SizedBox(height: 16),
            ...List.generate(lines.length, (index) => serviceRow(lines[index], index, data)),
            OutlinedButton.icon(onPressed: saving || lines.length >= 20 ? null : () => setState(() => lines.add(_ServiceLineB25B())),
              icon: const Icon(Icons.add_circle_outline), label: const Text('Agregar servicio extra')),
            const SizedBox(height: 12),
            TextFormField(controller: notes, decoration: decoration('Observaciones'), maxLines: 2),
            const SizedBox(height: 14),
            Text('Total de servicios: L ${lines.fold<double>(0, (sum, line) => sum + (double.tryParse(line.price.text.replaceAll(',', '.')) ?? 0)).toStringAsFixed(2)}',
              style: TextStyle(color: accent, fontSize: 18, fontWeight: FontWeight.w700)),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
          ]),
        )));
      },
    )),
    actions: [TextButton(onPressed: saving ? null : () => Navigator.of(context).pop(false), child: const Text('Cancelar')),
      FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Guardando...' : 'Crear orden'))],
  );
}
