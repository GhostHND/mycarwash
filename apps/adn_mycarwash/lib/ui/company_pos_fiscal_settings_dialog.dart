import 'package:flutter/material.dart';

import '../core/company_business_api.dart';

/// Registro de autorizacion CAI proporcionada por la empresa. El sistema no
/// verifica CAI en linea: debe contrastarse con la autorizacion SAR real.
class CompanyPosFiscalSettingsDialog extends StatefulWidget {
  const CompanyPosFiscalSettingsDialog({
    super.key,
    required this.api,
    required this.branchId,
  });
  final CompanyBusinessApi api;
  final int branchId;

  @override
  State<CompanyPosFiscalSettingsDialog> createState() =>
      _CompanyPosFiscalSettingsDialogState();
}

class _CompanyPosFiscalSettingsDialogState
    extends State<CompanyPosFiscalSettingsDialog> {
  final _name = TextEditingController();
  final _rtn = TextEditingController();
  final _cai = TextEditingController();
  final _est = TextEditingController(text: '000');
  final _point = TextEditingController(text: '001');
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _next = TextEditingController();
  final _expiry = TextEditingController();
  bool _confirmed = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [
      _name,
      _rtn,
      _cai,
      _est,
      _point,
      _start,
      _end,
      _next,
      _expiry,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Widget _field(String label, TextEditingController c, {String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 11),
        child: TextField(
          controller: c,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    if (!_confirmed) {
      setState(
        () => _error =
            'Confirma que los datos coinciden con la autorizacion del SAR.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.request(
        'POST',
        '/pos/fiscal-settings',
        body: {
          'branch_id': widget.branchId,
          'legal_name': _name.text.trim(),
          'rtn': _rtn.text.trim(),
          'cai': _cai.text.trim(),
          'establishment_code': _est.text.trim(),
          'point_code': _point.text.trim(),
          'start_sequence': int.tryParse(_start.text.trim()),
          'end_sequence': int.tryParse(_end.text.trim()),
          'next_sequence': int.tryParse(_next.text.trim()),
          'expires_on': _expiry.text.trim(),
          'authorization_confirmed': true,
        },
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se guardo el CAI: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Configurar autorizacion fiscal CAI'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Solo datos autorizados por el SAR. El sistema no verifica el CAI en linea.',
            ),
            const SizedBox(height: 14),
            _field('Razon social autorizada', _name),
            _field('RTN de la empresa (14 digitos)', _rtn),
            _field('CAI autorizado', _cai),
            Row(
              children: [
                Expanded(child: _field('Establecimiento (3)', _est)),
                const SizedBox(width: 8),
                Expanded(child: _field('Punto de emision (3)', _point)),
              ],
            ),
            Row(
              children: [
                Expanded(child: _field('Correlativo inicial', _start)),
                const SizedBox(width: 8),
                Expanded(child: _field('Correlativo final', _end)),
              ],
            ),
            _field('Siguiente correlativo por emitir', _next),
            _field('Fecha limite (AAAA-MM-DD)', _expiry),
            CheckboxListTile(
              value: _confirmed,
              onChanged: (v) => setState(() => _confirmed = v ?? false),
              title: const Text(
                'He verificado la autorizacion real del SAR y su rango.',
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_error != null)
              SelectableText(
                _error!,
                style: const TextStyle(color: Colors.redAccent),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Guardando...' : 'Guardar CAI'),
      ),
    ],
  );
}
