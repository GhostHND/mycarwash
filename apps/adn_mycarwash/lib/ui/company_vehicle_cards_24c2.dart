import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../core/mycarwash_session.dart';

String vehicleValue(Object? value, [String fallback = 'No registrado']) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? fallback : text;
}

/// Fotografía privada del vehículo; no utiliza URL pública ni comparte empresas.
class CompanyVehiclePhoto24C2 extends StatefulWidget {
  const CompanyVehiclePhoto24C2({
    super.key,
    required this.client,
    required this.vehicleId,
  });
  final http.Client client;
  final int vehicleId;

  @override
  State<CompanyVehiclePhoto24C2> createState() =>
      _CompanyVehiclePhoto24C2State();
}

class _CompanyVehiclePhoto24C2State extends State<CompanyVehiclePhoto24C2> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CompanyVehiclePhoto24C2 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.vehicleId != widget.vehicleId) {
      _load();
    }
  }

  Future<void> _load() async {
    final id = widget.vehicleId;
    if (mounted) {
      setState(() {
        _loading = true;
        _bytes = null;
      });
    }
    try {
      final uri = Uri.parse(
        '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/media/vehicles/$id/file',
      );
      final response = await widget.client
          .get(uri, headers: MyCarWashSession.headers)
          .timeout(const Duration(seconds: 12));
      if (mounted && id == widget.vehicleId) {
        setState(() {
          _bytes = response.statusCode == 200 && response.bodyBytes.isNotEmpty
              ? response.bodyBytes
              : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted && id == widget.vehicleId) {
        setState(() {
          _bytes = null;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 23,
          height: 23,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_bytes == null) {
      return Center(
        child: Icon(
          Icons.directions_car_filled_outlined,
          color: Theme.of(context).colorScheme.primary,
          size: 70,
        ),
      );
    }
    return Image.memory(
      _bytes!,
      fit: BoxFit.contain,
      gaplessPlayback: true,
      errorBuilder: (context, error, stack) =>
          const Center(child: Icon(Icons.directions_car_outlined, size: 58)),
    );
  }
}

class CompanyVehiclesGrid24C2 extends StatelessWidget {
  const CompanyVehiclesGrid24C2({
    super.key,
    required this.rows,
    required this.client,
    required this.onEdit,
    required this.onArchive,
  });
  final List<Map<String, dynamic>> rows;
  final http.Client client;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onArchive;

  Widget _line(IconData icon, String title, String value, Color muted) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon, color: muted, size: 15),
            const SizedBox(width: 7),
            Text('$title: ', style: TextStyle(color: muted, fontSize: 12)),
            Expanded(
              child: Tooltip(
                message: value,
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _card(BuildContext context, Map<String, dynamic> vehicle) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final inactive = vehicle['is_active'] == false || vehicle['is_active'] == 0;
    final id = int.tryParse('${vehicle['id']}') ?? 0;
    final brand = vehicleValue(vehicle['brand'], 'Sin marca');
    final model = vehicleValue(vehicle['model'], 'Sin modelo');
    final notes = vehicleValue(vehicle['notes'], 'Sin observaciones');
    return Container(
      key: ValueKey('vehicle_card_$id'),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(color: accent.withValues(alpha: 0.65)),
        borderRadius: BorderRadius.circular(17),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Tooltip(
                  message: '$brand $model',
                  child: Text(
                    '$brand $model',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: inactive ? scheme.error : const Color(0xFF23C8A0),
                  ),
                ),
                child: Text(
                  inactive ? 'Inactivo' : 'Activo',
                  style: TextStyle(
                    color: inactive ? scheme.error : const Color(0xFF23C8A0),
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Container(
            height: 155,
            width: double.infinity,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: id > 0
                ? CompanyVehiclePhoto24C2(
                    key: ValueKey('vehicle_image_$id'),
                    client: client,
                    vehicleId: id,
                  )
                : const Icon(Icons.directions_car_outlined, size: 68),
          ),
          const SizedBox(height: 12),
          _line(
            Icons.pin_outlined,
            'Placa',
            vehicleValue(vehicle['plate'], 'Sin placa'),
            scheme.onSurfaceVariant,
          ),
          _line(
            Icons.person_outline,
            'Propietario',
            vehicleValue(vehicle['client_name'], 'Sin propietario'),
            scheme.onSurfaceVariant,
          ),
          _line(
            Icons.category_outlined,
            'Tipo',
            vehicleValue(vehicle['vehicle_type']),
            scheme.onSurfaceVariant,
          ),
          _line(
            Icons.palette_outlined,
            'Color',
            vehicleValue(vehicle['color']),
            scheme.onSurfaceVariant,
          ),
          _line(
            Icons.event_outlined,
            'Año',
            vehicleValue(vehicle['year']),
            scheme.onSurfaceVariant,
          ),
          _line(Icons.numbers_outlined, 'ID', '$id', scheme.onSurfaceVariant),
          Tooltip(
            message: notes,
            child: Text(
              'Observaciones: $notes',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
            ),
          ),
          const Spacer(),
          Divider(color: accent.withValues(alpha: 0.35)),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                key: ValueKey('vehicle_edit_$id'),
                onPressed: () => onEdit(vehicle),
                icon: Icon(Icons.edit_outlined, color: accent, size: 18),
                label: const Text('Editar'),
              ),
              IconButton(
                key: ValueKey('vehicle_archive_$id'),
                tooltip: 'Archivar vehículo',
                onPressed: () => onArchive(vehicle),
                icon: Icon(Icons.archive_outlined, color: scheme.error),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth;
      final columns = width >= 1040
          ? 3
          : width >= 700
          ? 2
          : 1;
      const gap = 14.0;
      final cardWidth = (width - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: gap,
        children: [
          for (final row in rows)
            SizedBox(width: cardWidth, height: 490, child: _card(context, row)),
        ],
      );
    },
  );
}
