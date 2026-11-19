import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/mycarwash_session.dart';

/// Avisos del plan y mensajes del administrador maestro.
/// Solo se muestra en el panel de la empresa (no en el panel maestro).
class CompanyBillingAlerts24N8 extends StatefulWidget {
  const CompanyBillingAlerts24N8({super.key});
  @override
  State<CompanyBillingAlerts24N8> createState() =>
      _CompanyBillingAlerts24N8State();
}

class _CompanyBillingAlerts24N8State extends State<CompanyBillingAlerts24N8> {
  Timer? _timer;
  List<Map<String, dynamic>> _notices = [];
  bool _blocked = false;
  final Set<String> _dismissed = {};

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
    _timer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_reload()),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (!MyCarWashSession.isAuthenticated) return;
    try {
      final url =
          '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/master-alerts-24n8';
      final response = await http
          .get(Uri.parse(url), headers: MyCarWashSession.headers)
          .timeout(const Duration(seconds: 12));
      if (response.statusCode == 403) {
        final data = jsonDecode(response.body);
        if (data is Map && data['code'] == 'COMPANY_SUSPENDED') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Cuenta de empresa suspendida; los datos se conservan. Contacta ADN Publicidad.',
                ),
                backgroundColor: Color(0xFF84242D),
              ),
            );
            MyCarWashSession.clear();
            Navigator.of(context).maybePop();
          }
        }
        return;
      }
      if (response.statusCode != 200) return;
      final raw = jsonDecode(response.body);
      if (raw is! Map || raw['notices'] is! List) return;
      if (mounted) {
        setState(() {
          _blocked = false;
          _notices = (raw['notices'] as List)
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
        });
      }
    } catch (_) {
      /* Mantener la interfaz operativa si la red falla. */
    }
  }

  Future<void> _dismiss(Map<String, dynamic> notice) async {
    final key = '${notice['id']}';
    setState(() => _dismissed.add(key));
    final id = notice['id'];
    if (id is! int) return; // Avisos automáticos siguen reapareciendo si el problema persiste.
    try {
      await http
          .post(
            Uri.parse(
              '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/master-alerts-24n8/$id/read',
            ),
            headers: MyCarWashSession.headers,
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final visible = _notices
        .where((n) => !_dismissed.contains('${n['id']}'))
        .toList();
    if (!_blocked && visible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          if (_blocked)
            _banner(
              'Servicio suspendido',
              'El acceso a MyCarWash está suspendido. Los datos se conservan. Contacta ADN Publicidad.',
              const Color(0xFFE84C57),
              null,
            ),
          for (final n in visible)
            _banner(
              '${n['title'] ?? 'Aviso'}',
              '${n['body'] ?? ''}',
              n['severity'] == 'critical'
                  ? const Color(0xFFE84C57)
                  : n['severity'] == 'warning'
                  ? const Color(0xFFFFB648)
                  : const Color(0xFF00DCE5),
              () => _dismiss(n),
            ),
        ],
      ),
    );
  }

  Widget _banner(
    String title,
    String body,
    Color color,
    VoidCallback? dismiss,
  ) => Container(
    margin: const EdgeInsets.only(bottom: 7),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      border: Border.all(color: color.withValues(alpha: 0.65)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Icon(Icons.notifications_active_outlined, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 3),
              Text(body, style: const TextStyle(color: Colors.white)),
            ],
          ),
        ),
        if (dismiss != null)
          IconButton(
            onPressed: dismiss,
            icon: const Icon(Icons.close, color: Colors.white70),
          ),
      ],
    ),
  );
}
