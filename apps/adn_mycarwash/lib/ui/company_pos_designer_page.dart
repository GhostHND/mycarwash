import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/company_business_api.dart';
import 'company_pos_template_designer.dart';

/// Dedicated Mi empresa page; selecting another branch reloads its templates.
class CompanyPosDesignerPage extends StatefulWidget {
  const CompanyPosDesignerPage({super.key, this.client});
  final http.Client? client;

  @override
  State<CompanyPosDesignerPage> createState() => _CompanyPosDesignerPageState();
}

class _CompanyPosDesignerPageState extends State<CompanyPosDesignerPage> {
  late final http.Client _client;
  late final bool _ownsClient;
  late final CompanyBusinessApi _api;
  bool _loading = true;
  String? _error;
  int? _branchId;
  List<Map<String, dynamic>> _branches = [];

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _api = CompanyBusinessApi(_client);
    _load();
  }

  @override
  void dispose() {
    if (_ownsClient) {
      _client.close();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final response = await _api.request('GET', '/pos/options');
      if (!mounted) {
        return;
      }
      final data = Map<String, dynamic>.from(response['data'] as Map);
      final raw = data['branches'];
      final branches = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      setState(() {
        _branches = branches;
        _branchId = branches.isEmpty
            ? null
            : (branches.first['id'] as num).toInt();
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Diseñar comprobantes',
            style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Mi empresa / Diseñar comprobantes · Plantillas por sucursal',
            style: TextStyle(color: Color(0xFF9CB1BB)),
          ),
          const SizedBox(height: 12),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null)
            SelectableText('No se cargaron las sucursales: $_error'),
          if (_branches.isNotEmpty)
            DropdownButtonFormField<int>(
              key: const ValueKey('designer_branch_selector'),
              initialValue: _branchId,
              decoration: const InputDecoration(
                labelText: 'Sucursal',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: _branches
                  .map(
                    (branch) => DropdownMenuItem<int>(
                      value: (branch['id'] as num).toInt(),
                      child: Text('${branch['name']}'),
                    ),
                  )
                  .toList(),
              onChanged: (id) => setState(() => _branchId = id),
            ),
          const SizedBox(height: 12),
          Expanded(
            child: _branchId == null
                ? const Center(child: Text('Selecciona una sucursal activa.'))
                : CompanyPosTemplateDesigner(
                    key: ValueKey('designer_for_$_branchId'),
                    api: _api,
                    branchId: _branchId!,
                    embedded: true,
                  ),
          ),
        ],
      ),
    );
  }
}
