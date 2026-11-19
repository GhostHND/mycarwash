import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../core/company_visual_theme.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/mycarwash_session.dart';

Uri _productMediaUrl24J(int id) => Uri.parse(
  '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/items/$id',
);

class CompanyProductPhotoDraft24J {
  Uint8List? bytes;
  String? name;
  bool removeExisting = false;
  bool get hasChanges => bytes != null || removeExisting;

  Future<void> save(http.Client client, int id) async {
    if (!hasChanges) {
      return;
    }
    final endpoint = _productMediaUrl24J(id);
    if (bytes != null) {
      final filename = name ?? 'producto.jpg';
      final ext = filename.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'png'
          : ext == 'webp'
          ? 'webp'
          : 'jpeg';
      final request = http.MultipartRequest('POST', endpoint);
      request.headers.addAll(MyCarWashSession.headers);
      request.headers.remove('Content-Type');
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes!,
          filename: filename,
          contentType: MediaType('image', mime),
        ),
      );
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 30)),
      );
      if (response.statusCode != 201) {
        throw Exception(
          'No se pudo guardar la foto del producto (HTTP ${response.statusCode}).',
        );
      }
    } else if (removeExisting) {
      final response = await client.delete(
        endpoint,
        headers: MyCarWashSession.headers,
      );
      if (response.statusCode != 200 && response.statusCode != 404) {
        throw Exception(
          'No se pudo eliminar la foto (HTTP ${response.statusCode}).',
        );
      }
    }
    bytes = null;
    name = null;
    removeExisting = false;
  }
}

class CompanyProductPhotoField24J extends StatefulWidget {
  const CompanyProductPhotoField24J({
    super.key,
    required this.client,
    required this.draft,
    this.productId,
  });
  final http.Client client;
  final CompanyProductPhotoDraft24J draft;
  final int? productId;
  @override
  State<CompanyProductPhotoField24J> createState() =>
      _CompanyProductPhotoField24JState();
}

class _CompanyProductPhotoField24JState
    extends State<CompanyProductPhotoField24J> {
  Uint8List? existing;
  bool loading = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.productId;
    if (id == null) {
      return;
    }
    setState(() => loading = true);
    try {
      final response = await widget.client.get(
        Uri.parse('${_productMediaUrl24J(id)}/file'),
        headers: MyCarWashSession.headers,
      );
      if (mounted && response.statusCode == 200) {
        setState(() => existing = response.bodyBytes);
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'No se pudo consultar la fotografía anterior.');
      }
    } finally {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> _pick() async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (file == null) {
        return;
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        if (mounted) {
          setState(() => error = 'Imagen inválida: máximo 2 MB.');
        }
        return;
      }
      if (!mounted) {
        return;
      }
      setState(() {
        widget.draft.bytes = bytes;
        widget.draft.name = file.name;
        widget.draft.removeExisting = false;
        error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = 'No se pudo seleccionar la fotografía: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image =
        widget.draft.bytes ?? (widget.draft.removeExisting ? null : existing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Fotografía del producto',
            style: TextStyle(color: CompanyVisualTheme.text, fontWeight: FontWeight.bold),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 132,
          width: double.infinity,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CompanyVisualTheme.legacy(const Color(0xFF182A30)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : image == null
              ? const Icon(
                  Icons.inventory_2_outlined,
                  size: 54,
                  color: Colors.white54,
                )
              : Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('inventory_product_photo_pick_24j'),
              onPressed: _pick,
              icon: const Icon(Icons.upload_file),
              label: Text(image == null ? 'Cargar imagen' : 'Cambiar imagen'),
            ),
            if (image != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  widget.draft.bytes = null;
                  widget.draft.name = null;
                  widget.draft.removeExisting = widget.productId != null;
                }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar imagen'),
              ),
          ],
        ),
        const Text(
          'JPG, PNG o WebP · máximo 2 MB. Se guarda al confirmar el producto.',
          style: TextStyle(color: Colors.white60, fontSize: 11),
        ),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
        const SizedBox(height: 12),
      ],
    );
  }
}

/// Foto privada, con autorización y caché por instancia; nunca se publica una URL sin token.
class CompanyProductPhotoView24J extends StatefulWidget {
  const CompanyProductPhotoView24J({
    super.key,
    required this.client,
    required this.itemId,
    this.size = 56,
    this.icon = Icons.inventory_2_outlined,
  });
  final http.Client client;
  final int? itemId;
  final double size;
  final IconData icon;
  @override
  State<CompanyProductPhotoView24J> createState() =>
      _CompanyProductPhotoView24JState();
}

class _CompanyProductPhotoView24JState
    extends State<CompanyProductPhotoView24J> {
  Future<Uint8List?>? photo;
  @override
  void initState() {
    super.initState();
    photo = _fetch();
  }

  @override
  void didUpdateWidget(covariant CompanyProductPhotoView24J old) {
    super.didUpdateWidget(old);
    if (old.itemId != widget.itemId || old.client != widget.client) {
      photo = _fetch();
    }
  }

  Future<Uint8List?> _fetch() async {
    if (widget.itemId == null || !MyCarWashSession.isAuthenticated) {
      return null;
    }
    try {
      final res = await widget.client
          .get(
            Uri.parse('${_productMediaUrl24J(widget.itemId!)}/file'),
            headers: MyCarWashSession.headers,
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200 &&
          res.headers['content-type']?.startsWith('image/') == true) {
        return res.bodyBytes;
      }
    } catch (_) {
      /* ícono de respaldo */
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: widget.size,
    height: widget.size,
    child: FutureBuilder<Uint8List?>(
      future: photo,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return Icon(
            widget.icon,
            size: widget.size * .57,
            color: CompanyVisualTheme.legacy(const Color(0xFF0FA7B4)),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Image.memory(
            bytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
            errorBuilder: (context, error, stack) => Icon(widget.icon),
          ),
        );
      },
    ),
  );
}
