import 'dart:async';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';

import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';

/// Punto de asistencia autorizado. Solo el administrador puede solicitar
/// el desafío temporal: el escáner del lavador valida ese desafío en Laravel.
class CompanyAttendanceStation24N4 extends StatefulWidget {
  const CompanyAttendanceStation24N4({super.key, this.client});
  final http.Client? client;

  @override
  State<CompanyAttendanceStation24N4> createState() =>
      _CompanyAttendanceStation24N4State();
}

class _CompanyAttendanceStation24N4State
    extends State<CompanyAttendanceStation24N4> {
  late final http.Client _client;
  late final bool _ownsClient;
  late final CompanyBusinessApi _api;
  Timer? _timer;
  bool _loading = true;
  bool _fetching = false;
  String? _error;
  String _qr = '';
  String _manual = '';
  String _pointName = '';
  DateTime? _expiry;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _api = CompanyBusinessApi(_client);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      final remaining = _expiry?.difference(_now).inSeconds ?? 999;
      if (remaining <= 4 && !_fetching) _refresh();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final data = await _api.request('GET', '/attendance-points/station');
      if (!mounted) return;
      setState(() {
        _qr = (data['qr_payload'] ?? '').toString();
        _manual = (data['manual_code'] ?? '').toString();
        _pointName = (data['name'] ?? 'Punto de asistencia').toString();
        _expiry = DateTime.tryParse((data['expires_at'] ?? '').toString())?.toLocal();
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _qr = '';
        _manual = '';
        _expiry = null;
      });
    } finally {
      _fetching = false;
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = CompanyVisualTheme.primary;
    final foreground = CompanyVisualTheme.text;
    final remaining = (_expiry?.difference(_now).inSeconds ?? 0).clamp(0, 120);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(18),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 570),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Punto de asistencia QR', style: TextStyle(
                fontSize: 27, fontWeight: FontWeight.bold, color: foreground)),
              const SizedBox(height: 6),
              Text('Muestra este código en el punto físico del negocio. '
                  'El lavador lo escanea desde la aplicación de su teléfono.',
                  style: TextStyle(color: CompanyVisualTheme.muted)),
              const SizedBox(height: 20),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: CompanyVisualTheme.card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: CompanyVisualTheme.border),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    children: [
                      Icon(Icons.qr_code_2, color: accent, size: 34),
                      const SizedBox(height: 10),
                      Text(_pointName.isEmpty ? 'Asistencia del personal' : _pointName,
                          style: TextStyle(color: foreground, fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      const SizedBox(height: 16),
                      if (_loading) const CircularProgressIndicator()
                      else if (_error != null) ...[
                        Text(_error!, textAlign: TextAlign.center,
                            style: TextStyle(color: CompanyVisualTheme.danger)),
                      ] else if (_qr.isNotEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white,
                              borderRadius: BorderRadius.circular(14)),
                          child: QrImageView(
                            data: _qr,
                            version: QrVersions.auto,
                            size: 260,
                            backgroundColor: Colors.white,
                            errorCorrectionLevel: QrErrorCorrectLevel.M,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('Código manual: $_manual',
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold,
                                color: foreground)),
                        const SizedBox(height: 6),
                        Text('Actualización automática · válido durante ${remaining}s',
                            style: TextStyle(color: CompanyVisualTheme.muted)),
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _fetching ? null : _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Actualizar código'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text('Los códigos son temporales, vinculados a esta empresa y '
                  'validados en el servidor. No imprimas ni compartas un código fijo.',
                  style: TextStyle(color: CompanyVisualTheme.muted)),
            ],
          ),
        ),
      ),
    );
  }
}
