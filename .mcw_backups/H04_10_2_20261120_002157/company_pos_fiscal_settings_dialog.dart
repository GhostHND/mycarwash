import 'package:flutter/material.dart';

import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';

/// Misma autorización fiscal para Mi empresa y Smart POS.
/// Los permisos, la secuencia y la vigencia deben validarse en Laravel.
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
  static Color get _accent =>
      CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get _surface =>
      CompanyVisualTheme.legacy(const Color(0xFF101F25));
  static Color get _border =>
      CompanyVisualTheme.legacy(const Color(0xFF2A414A));
  static Color get _muted =>
      CompanyVisualTheme.legacy(const Color(0xFF9BAEB6));

  final _name = TextEditingController();
  final _rtn = TextEditingController();
  final _cai = TextEditingController();
  final _est = TextEditingController(text: '000');
  final _point = TextEditingController(text: '001');
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _next = TextEditingController();
  final _expiry = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _confirmed = false;
  bool _hasExisting = false;
  int? _originalNext;
  String _originalCai = '';
  String? _error;
  String? _loadError;

  bool get _sameAuthorization =>
      _hasExisting && _cai.text.trim() == _originalCai;

  @override
  void initState() {
    super.initState();
    _cai.addListener(_refreshAuthorizationState);
    _loadCurrent();
  }

  void _refreshAuthorizationState() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _cai.removeListener(_refreshAuthorizationState);
    for (final controller in [
      _name, _rtn, _cai, _est, _point, _start, _end, _next, _expiry,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String _value(Map<dynamic, dynamic> data, String primary, [String? fallback]) {
    final raw = data[primary] ?? (fallback == null ? null : data[fallback]);
    return raw == null ? '' : raw.toString();
  }

  Future<void> _loadCurrent() async {
    setState(() {
      _loading = true;
      _loadError = null;
      _error = null;
    });
    try {
      final response = await widget.api.request(
        'GET', '/pos/fiscal-settings',
        query: {'branch_id': '${widget.branchId}'},
      );
      final data = response['data'];
      if (data is! Map) {
        throw const FormatException(
          'La API fiscal no devolvió la información de la sucursal.',
        );
      }
      if (!mounted) return;
      final cai = _value(data, 'cai');
      final exists = cai.trim().isNotEmpty;
      final nextText = _value(data, 'next_sequence');
      final startText = _value(data, 'start_sequence', 'range_start');
      final endText = _value(data, 'end_sequence', 'range_end');
      // Nunca permitir que una consulta parcial resetee un CAI existente.
      if (exists && (nextText.isEmpty || startText.isEmpty || endText.isEmpty)) {
        throw const FormatException(
          'La API devolvió un CAI existente sin rango o correlativo completo. '
          'No se permite editar hasta verificar el backend.',
        );
      }
      _name.text = _value(data, 'legal_name');
      _rtn.text = _value(data, 'rtn');
      _cai.text = cai;
      _est.text = _value(data, 'establishment_code').isEmpty
          ? '000' : _value(data, 'establishment_code');
      _point.text = _value(data, 'point_code').isEmpty
          ? '001' : _value(data, 'point_code');
      _start.text = startText;
      _end.text = endText;
      _next.text = nextText;
      _expiry.text = _value(data, 'expires_on');
      setState(() {
        _hasExisting = exists;
        _originalCai = cai;
        _originalNext = int.tryParse(nextText);
        _confirmed = false;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = '$e';
        _loading = false;
      });
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    String? hint,
    bool readOnly = false,
    TextInputType keyboardType = TextInputType.text,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      readOnly: readOnly,
      keyboardType: keyboardType,
      style: TextStyle(color: CompanyVisualTheme.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: _muted),
        hintText: hint,
        filled: true,
        fillColor: CompanyVisualTheme.legacy(const Color(0xFF13262C)),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _border),
          borderRadius: BorderRadius.circular(11),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _accent),
          borderRadius: BorderRadius.circular(11),
        ),
      ),
    ),
  );

  String? _validate() {
    if (!_confirmed) {
      return 'Confirma que los datos coinciden con la autorización oficial del SAR.';
    }
    if ([_name, _rtn, _cai, _est, _point, _start, _end, _next, _expiry]
        .any((x) => x.text.trim().isEmpty)) {
      return 'Completa todos los datos obligatorios de la autorización.';
    }
    if (!RegExp(r'^\d{14}$').hasMatch(_rtn.text.trim())) {
      return 'El RTN debe tener 14 dígitos.';
    }
    if (!RegExp(r'^\d{3}$').hasMatch(_est.text.trim()) ||
        !RegExp(r'^\d{3}$').hasMatch(_point.text.trim())) {
      return 'Establecimiento y punto de emisión deben tener 3 dígitos.';
    }
    final start = int.tryParse(_start.text.trim());
    final end = int.tryParse(_end.text.trim());
    final next = int.tryParse(_next.text.trim());
    if (start == null || end == null || next == null ||
        start < 0 || end < start || next < start || next > end) {
      return 'Verifica el rango inicial, rango final y siguiente correlativo.';
    }
    if (_sameAuthorization &&
        _originalNext != null && next != _originalNext) {
      return 'El siguiente correlativo de una autorización vigente no puede editarse manualmente.';
    }
    if (_sameAuthorization &&
        _originalNext != null && end < _originalNext! - 1) {
      return 'El rango final no puede excluir el correlativo ya alcanzado.';
    }
    final date = _expiry.text.trim();
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date) == null) {
      return 'La fecha límite debe tener formato AAAA-MM-DD.';
    }
    return null;
  }

  Future<void> _save() async {
    if (_loading || _saving || _loadError != null) return;
    final message = _validate();
    if (message != null) {
      setState(() => _error = message);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.request(
        'POST', '/pos/fiscal-settings',
        body: {
          'branch_id': widget.branchId,
          'legal_name': _name.text.trim(),
          'rtn': _rtn.text.trim(),
          'cai': _cai.text.trim(),
          'establishment_code': _est.text.trim(),
          'point_code': _point.text.trim(),
          'start_sequence': int.parse(_start.text.trim()),
          'end_sequence': int.parse(_end.text.trim()),
          'next_sequence': int.parse(_next.text.trim()),
          'expires_on': _expiry.text.trim(),
          'authorization_confirmed': true,
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se guardó el CAI: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: _border),
      borderRadius: BorderRadius.circular(20),
    ),
    title: Row(
      children: [
        Icon(Icons.receipt_long_outlined, color: _accent),
        const SizedBox(width: 11),
        Expanded(child: Text(
          _hasExisting ? 'Editar autorización fiscal CAI' : 'Configurar autorización fiscal CAI',
          style: TextStyle(color: CompanyVisualTheme.text, fontWeight: FontWeight.w800),
        )),
      ],
    ),
    content: SizedBox(
      width: 560,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(35),
              child: Center(child: CircularProgressIndicator()),
            )
          : _loadError != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText('No se puede abrir el formulario: $_loadError',
                      style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995)))),
                    TextButton(onPressed: _loadCurrent, child: const Text('Reintentar')),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sucursal #${widget.branchId}. Solo utilice datos autorizados por el SAR. '
                        'La aplicación no verifica el CAI en línea.',
                        style: TextStyle(color: _muted),
                      ),
                      const SizedBox(height: 16),
                      _field('Razón social autorizada', _name),
                      _field('RTN de la empresa (14 dígitos)', _rtn,
                        keyboardType: TextInputType.number),
                      _field('CAI autorizado', _cai),
                      Row(children: [
                        Expanded(child: _field('Establecimiento (3)', _est,
                          keyboardType: TextInputType.number)),
                        const SizedBox(width: 9),
                        Expanded(child: _field('Punto de emisión (3)', _point,
                          keyboardType: TextInputType.number)),
                      ]),
                      Row(children: [
                        Expanded(child: _field('Rango inicial', _start,
                          keyboardType: TextInputType.number)),
                        const SizedBox(width: 9),
                        Expanded(child: _field('Rango final', _end,
                          keyboardType: TextInputType.number)),
                      ]),
                      _field(
                        _sameAuthorization
                            ? 'Siguiente correlativo (protegido)'
                            : 'Siguiente correlativo autorizado',
                        _next,
                        readOnly: _sameAuthorization,
                        keyboardType: TextInputType.number,
                      ),
                      if (_sameAuthorization)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'El siguiente folio se controla desde la emisión de facturas; '
                            'no se puede retroceder desde este formulario.',
                            style: TextStyle(color: _muted, fontSize: 12),
                          ),
                        ),
                      _field('Fecha límite (AAAA-MM-DD)', _expiry,
                        hint: '2027-12-31'),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        activeColor: _accent,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _confirmed,
                        onChanged: _saving
                            ? null
                            : (value) => setState(() => _confirmed = value ?? false),
                        title: Text(
                          'He verificado esta autorización y su rango con los datos del SAR.',
                          style: TextStyle(color: CompanyVisualTheme.text, fontSize: 13),
                        ),
                      ),
                      if (_error != null)
                        SelectableText(_error!,
                          style: TextStyle(color: CompanyVisualTheme.legacy(const Color(0xFFFF8995)))),
                    ],
                  ),
                ),
    ),
    actions: [
      TextButton(
        onPressed: _saving ? null : () => Navigator.of(context).pop(false),
        child: const Text('Cancelar'),
      ),
      if (!_loading && _loadError == null)
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Guardando...' : 'Guardar autorización CAI'),
          style: FilledButton.styleFrom(backgroundColor: _accent),
        ),
    ],
  );
}
