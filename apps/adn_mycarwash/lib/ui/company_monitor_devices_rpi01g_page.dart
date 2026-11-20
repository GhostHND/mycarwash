import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';

/// Administracion de pantallas TV desde la SESION existente del propietario.
/// El backend valida membresia y rol owner en cada operacion.
class CompanyMonitorDevicesRpi01gPage extends StatefulWidget {
  const CompanyMonitorDevicesRpi01gPage({super.key});

  @override
  State<CompanyMonitorDevicesRpi01gPage> createState() =>
      _CompanyMonitorDevicesRpi01gPageState();
}

class _CompanyMonitorDevicesRpi01gPageState
    extends State<CompanyMonitorDevicesRpi01gPage> {
  final http.Client _client = http.Client();
  final TextEditingController _deviceName =
      TextEditingController(text: 'TV Lavados Raspberry Pi 3');
  final TextEditingController _branchId = TextEditingController(text: '1');
  List<Map<String, dynamic>> _devices = [];
  bool _busy = false;
  String? _error;
  String? _newKey;
  int? _newDeviceId;

  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  Color get _accent => CompanyVisualTheme.primary;
  Color get _surface => CompanyVisualTheme.card;
  Color get _border => CompanyVisualTheme.border;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _deviceName.dispose();
    _branchId.dispose();
    _client.close();
    super.dispose();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final json = await _api.request('GET', '/monitor-devices-rpi01c');
      final raw = json['data'];
      if (raw is! List) throw const FormatException('Listado de dispositivos inválido.');
      final rows = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
      if (mounted) setState(() => _devices = rows);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudieron consultar las pantallas: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _issue() async {
    if (_busy) return;
    final branch = int.tryParse(_branchId.text.trim());
    final name = _deviceName.text.trim();
    if (branch == null || branch <= 0 || name.length < 2 || name.length > 90) {
      setState(() => _error = 'Verifica el ID real de sucursal y el nombre de la pantalla.');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Vincular nueva pantalla'),
        content: Text('Se vinculará "$name" a la sucursal $branch. '
            'La clave se mostrará UNA SOLA VEZ y solo permite consultar el monitor. '
            'Comprueba que esta sucursal pertenece a tu empresa.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Vincular')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _busy = true; _error = null; _newKey = null; _newDeviceId = null; });
    try {
      final json = await _api.request('POST', '/monitor-devices-rpi01c',
          body: {'name': name, 'branch_id': branch});
      final key = json['device_key'];
      final id = json['id'];
      if (key is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(key) || id is! num) {
        throw const FormatException('El registro no entregó una clave e ID válidos. NO vuelvas a vincular sin revisar el listado.');
      }
      if (mounted) setState(() { _newKey = key; _newDeviceId = id.toInt(); });
      final list = await _api.request('GET', '/monitor-devices-rpi01c');
      final data = list['data'];
      if (mounted && data is List) {
        setState(() => _devices = data.whereType<Map>().map((r) => Map<String, dynamic>.from(r)).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se completó la vinculación: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revoke(Map<String, dynamic> device) async {
    if (_busy) return;
    final id = device['id'];
    if (id is! num) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revocar acceso de pantalla'),
        content: Text('¿Desactivar "${device['name'] ?? 'Pantalla'}"? '
            'La Raspberry dejará de obtener datos hasta recibir una nueva vinculación.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Revocar')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      await _api.request('DELETE', '/monitor-devices-rpi01c/${id.toInt()}');
      if (mounted) {
        setState(() => _devices = _devices.map((row) =>
            row['id'] == id ? {...row, 'is_active': false} : row).toList());
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo revocar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _active(Map<String, dynamic> row) => row['is_active'] == true ||
      row['is_active'] == 1 || row['is_active'] == '1';

  Widget _panel(Widget child) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: _surface,
      border: Border.all(color: _border),
      borderRadius: BorderRadius.circular(18),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.tv_outlined, color: _accent, size: 30),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Pantallas de monitoreo', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
            Text('Raspberry Pi 3 · Vista general de lavados · Solo lectura'),
          ])),
          IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar'),
        ]),
        const SizedBox(height: 18),
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Vincular nueva Raspberry', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          TextField(controller: _deviceName, maxLength: 90,
              decoration: const InputDecoration(labelText: 'Nombre del dispositivo')),
          const SizedBox(height: 8),
          TextField(controller: _branchId, keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'ID de sucursal',
                helperText: 'Utiliza el identificador real de la sucursal. Laravel verificará su pertenencia.')),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _busy ? null : _issue,
              icon: const Icon(Icons.add_link), label: const Text('Vincular Raspberry')),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
        ])),
        if (_newKey != null) ...[
          const SizedBox(height: 16),
          _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Clave creada — guardar ahora',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text('Dispositivo #${_newDeviceId ?? '-'} · Esta clave no se podrá recuperar después de cerrar esta vista.'),
            const SizedBox(height: 8),
            SelectableText(_newKey!, style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: () => Clipboard.setData(ClipboardData(text: _newKey!)),
                icon: const Icon(Icons.copy), label: const Text('Copiar clave para instalar en la Raspberry')),
            const Text('No envíes esta clave por chat, no la publiques ni la incorpores en una URL. '
              'Instálala en el archivo privado del dispositivo.', style: TextStyle(fontSize: 12)),
            TextButton(onPressed: () => setState(() { _newKey = null; _newDeviceId = null; }),
                child: const Text('Ya guardé la clave; ocultarla')),
          ])),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: SelectableText(_error!, style: TextStyle(color: CompanyVisualTheme.danger))),
        const SizedBox(height: 18),
        _panel(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Dispositivos registrados', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (_devices.isEmpty) const Text('No hay pantallas registradas o el listado no está disponible.'),
          for (final d in _devices) ...[
            const Divider(),
            ListTile(
              leading: Icon(Icons.tv, color: _accent),
              title: Text('${d['name'] ?? 'Pantalla'}'),
              subtitle: Text('ID ${d['id']} · Sucursal ${d['branch_id']} · '
                  '${_active(d) ? 'Activa' : 'Revocada'}\n'
                  'Última conexión: ${d['last_seen_at'] ?? 'Sin conexión registrada'}'),
              isThreeLine: true,
              trailing: _active(d)
                  ? OutlinedButton(onPressed: _busy ? null : () => _revoke(d), child: const Text('Revocar'))
                  : const Icon(Icons.block),
            ),
          ],
        ])),
      ],
    );
  }
}
