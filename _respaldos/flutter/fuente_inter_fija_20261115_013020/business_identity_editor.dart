import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/business_identity.dart';
import '../core/mycarwash_session.dart';

class BusinessIdentityEditor extends StatefulWidget {
  const BusinessIdentityEditor({
    super.key,
    required this.fontFamily,
    required this.onFontChanged,
    required this.client,
  });

  final String fontFamily;
  final ValueChanged<String> onFontChanged;
  final http.Client client;

  @override
  State<BusinessIdentityEditor> createState() => _BusinessIdentityEditorState();
}

class _BusinessIdentityEditorState extends State<BusinessIdentityEditor> {
  static const turquoise = Color(0xFF0FA7B4);
  static const muted = Color(0xFF9BAEB6);
  static const border = Color(0xFF20343C);
  static const surface = Color(0xFF111F25);

  bool _busy = false;

  Uri get _logoUrl => Uri.parse(
    '${MyCarWashSession.apiBaseUrl}'
    '/companies/${MyCarWashSession.companyId}'
    '/settings/logo',
  );

  void _message(String message, {bool error = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFF9C3541)
            : const Color(0xFF126F75),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _upload() async {
    if (_busy) return;

    PlatformFile? picked;

    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp'],
      );
    } catch (_) {
      _message('No se pudo abrir el selector de archivos.', error: true);
      return;
    }

    if (picked == null || !mounted) return;

    setState(() => _busy = true);

    try {
      final length = picked.lengthSync() ?? await picked.length();

      if (length != null && length > 2 * 1024 * 1024) {
        throw const _EditorError('El logotipo supera los 2 MB.');
      }

      final bytes = await picked.readAsBytes();

      if (bytes.isEmpty || bytes.lengthInBytes > 2 * 1024 * 1024) {
        throw const _EditorError('El archivo está vacío o supera los 2 MB.');
      }

      final filename = picked.name;
      final extension = filename.split('.').last.toLowerCase();

      if (!['png', 'jpg', 'jpeg', 'webp'].contains(extension)) {
        throw const _EditorError('Formato de imagen no admitido.');
      }

      final subtype = extension == 'jpg' ? 'jpeg' : extension;

      final request = http.MultipartRequest('POST', _logoUrl);

      final headers = Map<String, String>.from(MyCarWashSession.headers);

      // El boundary del formulario multipart se calcula
      // automaticamente por http.MultipartRequest.
      headers.remove('Content-Type');

      request.headers.addAll(headers);

      request.files.add(
        http.MultipartFile.fromBytes(
          'logo',
          bytes,
          filename: filename,
          contentType: MediaType('image', subtype),
        ),
      );

      final streamed = await widget.client
          .send(request)
          .timeout(const Duration(seconds: 30));

      final response = await http.Response.fromStream(streamed);

      if (response.statusCode != 201) {
        var message = 'Laravel rechazó el logotipo.';

        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map) {
            final errors = decoded['errors'];

            if (errors is Map && errors.isNotEmpty) {
              final first = errors.values.first;

              if (first is List && first.isNotEmpty) {
                message = first.first.toString();
              }
            } else if (decoded['message'] != null) {
              message = decoded['message'].toString();
            }
          }
        } catch (_) {
          // Conservar mensaje general.
        }

        throw _EditorError(message);
      }

      // Confirmar la identidad leyendo nuevamente Laravel.
      final refreshed = await BusinessIdentity.refresh(client: widget.client);

      if (refreshed) {
        _message('Logotipo guardado y recuperado desde Laravel.');
      } else {
        BusinessIdentity.setLogoBytes(bytes);

        _message(
          'El servidor aceptó el logotipo, pero no se pudo '
          'verificar su lectura. Comprueba la conexión.',
          error: true,
        );
      }
    } on _EditorError catch (error) {
      _message(error.message, error: true);
    } catch (_) {
      _message('No se pudo completar la carga.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF0A1519),
        title: const Text(
          'Eliminar logotipo del negocio',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Se eliminará el logo de esta empresa. '
          'El logotipo oficial de ADN Publicidad no cambiará.',
          style: TextStyle(color: muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);

    try {
      final response = await widget.client
          .delete(_logoUrl, headers: MyCarWashSession.headers)
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        throw const _EditorError('No fue posible eliminar el logotipo.');
      }

      BusinessIdentity.setLogoBytes(null);

      _message('Logotipo empresarial eliminado.');
    } on _EditorError catch (error) {
      _message(error.message, error: true);
    } catch (_) {
      _message('Error de conexión con Laravel.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<BusinessIdentityData>(
      valueListenable: BusinessIdentity.current,
      builder: (context, identity, _) {
        final logo = identity.logoBytes;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: border),
            const SizedBox(height: 17),
            const Text(
              'Logotipo del negocio',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Este logotipo pertenece al autolavado y se mostrará '
              'junto a la identidad oficial de ADN MyCarWash.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
              ),
              child: Wrap(
                spacing: 20,
                runSpacing: 16,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    width: 125,
                    height: 105,
                    padding: const EdgeInsets.all(10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: logo != null
                        ? Image.memory(
                            logo,
                            fit: BoxFit.contain,
                            width: 110,
                            height: 85,
                            gaplessPlayback: true,
                          )
                        : const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.business_outlined,
                                size: 30,
                                color: Color(0xFF64748B),
                              ),
                              SizedBox(height: 7),
                              Text(
                                'Sin logotipo',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PNG, JPG o WebP · Máximo 2 MB',
                        style: TextStyle(color: muted, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          FilledButton.icon(
                            onPressed: _busy ? null : _upload,
                            icon: const Icon(Icons.upload_file_outlined),
                            label: Text(
                              _busy
                                  ? 'Procesando...'
                                  : logo == null
                                  ? 'Subir logotipo'
                                  : 'Cambiar logotipo',
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: turquoise,
                            ),
                          ),
                          if (logo != null)
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _remove,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Eliminar'),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 27),
            const Text(
              'Tipografía del negocio',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Selecciona una fuente. Podrás ver el resultado '
              'antes de guardar los cambios.',
              style: TextStyle(color: muted),
            ),
            const SizedBox(height: 17),
            DropdownButtonFormField<String>(
              key: ValueKey(widget.fontFamily),
              initialValue: widget.fontFamily,
              dropdownColor: surface,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Fuente empresarial',
                labelStyle: const TextStyle(color: muted),
                filled: true,
                fillColor: surface,
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: border),
                  borderRadius: BorderRadius.circular(10),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: turquoise),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              items: [
                for (final font in BusinessIdentity.supportedFonts)
                  DropdownMenuItem(value: font, child: Text(font)),
              ],
              onChanged: (font) {
                if (font != null) widget.onFontChanged(font);
              },
            ),
            const SizedBox(height: 17),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    identity.companyName.isEmpty
                        ? 'Tu autolavado'
                        : identity.companyName,
                    style: GoogleFonts.getFont(
                      widget.fontFamily,
                      fontSize: 25,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Gestiona cada lavado con una experiencia profesional.',
                    style: GoogleFonts.getFont(
                      widget.fontFamily,
                      fontSize: 14,
                      color: muted,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'ABCDEFG abcdefg 0123456789',
                    style: GoogleFonts.getFont(
                      widget.fontFamily,
                      fontSize: 14,
                      color: turquoise,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 13),
            const Text(
              'El logotipo oficial de ADN Publicidad permanece '
              'independiente y no puede ser reemplazado.',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

class _EditorError implements Exception {
  const _EditorError(this.message);

  final String message;
}
