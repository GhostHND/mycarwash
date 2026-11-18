import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../core/mycarwash_session.dart';

/// Estado de imagen compartido con el formulario de alta/edición.
class CompanyVehiclePhotoDraft24C2 {
  Uint8List? bytes;
  String? fileName;
  bool showOnKiosk = false;
  bool removeExisting = false;

  bool get hasChanges => bytes != null || removeExisting;

  Future<void> save(http.Client client, int vehicleId) async {
    if (!hasChanges) {
      return;
    }
    final endpoint = Uri.parse(
      '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/vehicles/$vehicleId',
    );
    if (bytes != null) {
      final name = fileName ?? 'vehiculo.jpg';
      final ext = name.split('.').last.toLowerCase();
      final mime = ext == 'png'
          ? 'png'
          : ext == 'webp'
          ? 'webp'
          : 'jpeg';
      final request = http.MultipartRequest('POST', endpoint);
      request.headers.addAll(MyCarWashSession.headers);
      request.headers.remove('Content-Type');
      request.fields['show_on_kiosk'] = showOnKiosk ? '1' : '0';
      request.files.add(
        http.MultipartFile.fromBytes(
          'photo',
          bytes!,
          filename: name,
          contentType: MediaType('image', mime),
        ),
      );
      final response = await http.Response.fromStream(
        await client.send(request).timeout(const Duration(seconds: 30)),
      );
      if (response.statusCode != 201) {
        throw Exception(
          'No se pudo guardar la fotografía (${response.statusCode}).',
        );
      }
      bytes = null;
      removeExisting = false;
      return;
    }
    if (removeExisting) {
      final response = await client.delete(
        endpoint,
        headers: MyCarWashSession.headers,
      );
      if (response.statusCode != 200) {
        throw Exception(
          'No se pudo quitar la fotografía (${response.statusCode}).',
        );
      }
      removeExisting = false;
    }
  }
}

class CompanyVehiclePhotoField24C2 extends StatefulWidget {
  const CompanyVehiclePhotoField24C2({
    super.key,
    required this.client,
    required this.draft,
    this.vehicleId,
  });
  final http.Client client;
  final CompanyVehiclePhotoDraft24C2 draft;
  final int? vehicleId;

  @override
  State<CompanyVehiclePhotoField24C2> createState() =>
      _CompanyVehiclePhotoField24C2State();
}

class _CompanyVehiclePhotoField24C2State
    extends State<CompanyVehiclePhotoField24C2> {
  Uint8List? _existing;
  bool _loading = false;
  String? _warning;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.vehicleId;
    if (id == null) {
      return;
    }
    setState(() => _loading = true);
    try {
      final endpoint = Uri.parse(
        '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/vehicles/$id',
      );
      final metadata = await widget.client.get(
        endpoint,
        headers: MyCarWashSession.headers,
      );
      if (metadata.statusCode == 200) {
        final payload = jsonDecode(metadata.body);
        final data = payload is Map ? payload['data'] : null;
        if (data is Map && mounted) {
          setState(
            () => widget.draft.showOnKiosk = data['show_on_kiosk'] == true,
          );
        }
        if (data is Map && data['exists'] == true) {
          final response = await widget.client.get(
            Uri.parse('$endpoint/file'),
            headers: MyCarWashSession.headers,
          );
          if (mounted && response.statusCode == 200) {
            setState(() => _existing = response.bodyBytes);
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _warning = 'No fue posible cargar la fotografía anterior.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pick() async {
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp'],
      );
      if (selected == null) {
        return;
      }
      final bytes = await selected.readAsBytes();
      if (bytes.isEmpty || bytes.length > 2 * 1024 * 1024) {
        if (mounted) {
          setState(() => _warning = 'Imagen no válida. Máximo 2 MB.');
        }
        return;
      }
      if (mounted) {
        setState(() {
          widget.draft.bytes = bytes;
          widget.draft.fileName = selected.name;
          widget.draft.removeExisting = false;
          _warning = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _warning = 'No se pudo seleccionar la imagen: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final image =
        widget.draft.bytes ?? (widget.draft.removeExisting ? null : _existing);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Fotografía del vehículo',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 140,
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFF15262C),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : image == null
              ? const Center(
                  child: Icon(
                    Icons.directions_car_outlined,
                    size: 58,
                    color: Colors.white54,
                  ),
                )
              : Image.memory(image, fit: BoxFit.contain, gaplessPlayback: true),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 5,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('vehicle_pick_photo'),
              onPressed: _pick,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(
                image == null ? 'Seleccionar fotografía' : 'Cambiar fotografía',
              ),
            ),
            if (image != null)
              TextButton.icon(
                onPressed: () => setState(() {
                  widget.draft.bytes = null;
                  widget.draft.fileName = null;
                  widget.draft.removeExisting = widget.vehicleId != null;
                }),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Quitar foto'),
              ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text(
            'Mostrar en monitor autorizado',
            style: TextStyle(color: Colors.white70),
          ),
          value: widget.draft.showOnKiosk,
          onChanged: (v) => setState(() => widget.draft.showOnKiosk = v),
        ),
        const Text(
          'JPG, PNG, WebP · hasta 2 MB. La foto se guarda al confirmar el formulario.',
          style: TextStyle(color: Colors.white54, fontSize: 11),
        ),
        if (_warning != null)
          Text(_warning!, style: const TextStyle(color: Colors.orangeAccent)),
      ],
    );
  }
}
