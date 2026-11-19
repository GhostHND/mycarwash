import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/mycarwash_session.dart';

/// Fotografías privadas para vehículo o empleado; disponibles para la
/// futura pantalla Raspberry solo si el negocio habilita su visualización.
class CompanyMediaPhotoDialog extends StatefulWidget {
  const CompanyMediaPhotoDialog({
    super.key,
    required this.client,
    required this.kind,
    required this.recordId,
    required this.title,
  });

  final http.Client client;
  final String kind;
  final int recordId;
  final String title;

  @override
  State<CompanyMediaPhotoDialog> createState() =>
      _CompanyMediaPhotoDialogState();
}

class _CompanyMediaPhotoDialogState extends State<CompanyMediaPhotoDialog> {
  static Color get _turquoise => CompanyVisualTheme.legacy(const Color(0xFF0FA7B4));
  static Color get _surface => CompanyVisualTheme.legacy(const Color(0xFF0A1519));
  bool _loading = true;
  bool _busy = false;
  bool _exists = false;
  bool _showOnKiosk = false;
  String? _error;
  List<int>? _imageBytes;

  Uri get _endpoint => Uri.parse(
    '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}'
    '/media/${widget.kind}/${widget.recordId}',
  );

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _toast(String message, {bool error = false}) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? CompanyVisualTheme.legacy(const Color(0xFF9C3541))
            : CompanyVisualTheme.legacy(const Color(0xFF126F75)),
      ),
    );
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await widget.client.get(
        _endpoint,
        headers: MyCarWashSession.headers,
      );
      if (res.statusCode != 200) {
        throw Exception(
          'No se pudo consultar la fotografía (${res.statusCode}).',
        );
      }
      final raw = jsonDecode(res.body) as Map<String, dynamic>;
      final data = Map<String, dynamic>.from(raw['data'] as Map);
      final exists = data['exists'] == true;
      List<int>? image;
      if (exists) {
        final file = await widget.client.get(
          Uri.parse('$_endpoint/file'),
          headers: MyCarWashSession.headers,
        );
        if (file.statusCode == 200) {
          image = file.bodyBytes;
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _exists = exists;
        _showOnKiosk = data['show_on_kiosk'] == true;
        _imageBytes = image;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _upload() async {
    if (_busy) {
      return;
    }
    PlatformFile? selected;
    try {
      selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
    } catch (_) {
      _toast('No se pudo seleccionar el archivo.', error: true);
      return;
    }
    if (selected == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty || bytes.lengthInBytes > 2 * 1024 * 1024) {
        throw Exception('La imagen debe pesar como máximo 2 MB.');
      }
      final ext = selected.name.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'png'
          : ext == 'webp'
          ? 'webp'
          : 'jpeg';
      final request = http.MultipartRequest('POST', _endpoint);
      request.headers.addAll(MyCarWashSession.headers);
      request.headers.remove('Content-Type');
      request.fields['show_on_kiosk'] = _showOnKiosk ? '1' : '0';
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes,
          filename: 'foto.$ext',
          contentType: MediaType('image', mime),
        ),
      );
      final streamed = await widget.client
          .send(request)
          .timeout(const Duration(seconds: 30));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 201) {
        throw Exception(
          'Laravel rechazó la fotografía (${response.statusCode}).',
        );
      }
      if (!mounted) {
        return;
      }
      _toast('Fotografía guardada.');
      await _reload();
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _visibility(bool visible) async {
    if (_busy || !_exists) {
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.client.patch(
        _endpoint,
        headers: MyCarWashSession.headers,
        body: jsonEncode({'show_on_kiosk': visible}),
      );
      if (res.statusCode != 200) {
        throw Exception('No se pudo actualizar la visibilidad.');
      }
      if (mounted) {
        setState(() => _showOnKiosk = visible);
      }
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _remove() async {
    if (_busy || !_exists) {
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar fotografía'),
        content: const Text(
          'Esta acción elimina la fotografía asociada al registro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await widget.client.delete(
        _endpoint,
        headers: MyCarWashSession.headers,
      );
      if (res.statusCode != 200) {
        throw Exception('No se pudo eliminar la fotografía.');
      }
      if (mounted) {
        _toast('Fotografía eliminada.');
        await _reload();
      }
    } catch (e) {
      _toast('$e', error: true);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    backgroundColor: _surface,
    title: Text('Fotografía · ${widget.title}'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_loading)
            Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: _turquoise),
            )
          else if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.redAccent))
          else ...[
            Container(
              height: 220,
              width: double.infinity,
              alignment: Alignment.center,
              color: CompanyVisualTheme.legacy(const Color(0xFF17282D)),
              child: _imageBytes != null
                  ? Image.memory(
                      Uint8List.fromList(_imageBytes!),
                      fit: BoxFit.contain,
                    )
                  : const Icon(
                      Icons.add_a_photo_outlined,
                      size: 64,
                      color: Colors.white54,
                    ),
            ),
            const SizedBox(height: 14),
            const Text(
              'JPG, PNG o WebP · máximo 2 MB.',
              style: TextStyle(color: Colors.white70),
            ),
            SwitchListTile(
              title: const Text('Permitir foto en pantalla Raspberry'),
              subtitle: const Text(
                'Se mostrará solo en dispositivos autorizados de este negocio.',
              ),
              value: _showOnKiosk,
              onChanged: _busy
                  ? null
                  : (v) {
                      if (_exists) {
                        _visibility(v);
                      } else {
                        setState(() => _showOnKiosk = v);
                      }
                    },
              activeThumbColor: _turquoise,
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cerrar'),
      ),
      if (_exists)
        TextButton(
          onPressed: _busy ? null : _remove,
          child: const Text('Eliminar'),
        ),
      FilledButton.icon(
        onPressed: _busy || _loading ? null : _upload,
        icon: const Icon(Icons.upload_file_outlined),
        label: Text(
          _busy
              ? 'Guardando...'
              : _exists
              ? 'Cambiar fotografía'
              : 'Subir fotografía',
        ),
      ),
    ],
  );
}
