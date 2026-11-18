import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/company_business_api.dart';

/// Bloque 22B: pantalla de reportes unificados, exportable por rango y sucursal.
/// No consulta datos ajenos al tenant ni modifica registros operativos.
class CompanyUnifiedReportsPage extends StatefulWidget {
  const CompanyUnifiedReportsPage({super.key, required this.kind, this.client});
  final String kind;
  final http.Client? client;

  @override
  State<CompanyUnifiedReportsPage> createState() =>
      _CompanyUnifiedReportsPageState();
}

class _CompanyUnifiedReportsPageState extends State<CompanyUnifiedReportsPage> {
  static const accent = Color(0xFF0FA7B4);
  static const panel = Color(0xFF102229);
  static const muted = Color(0xFFA7B8BF);
  late final http.Client client;
  late final bool ownsClient;
  CompanyBusinessApi get api => CompanyBusinessApi(client);
  DateTime from = DateTime.now().subtract(const Duration(days: 29));
  DateTime to = DateTime.now();
  int branch = 0;
  bool loading = true;
  bool exporting = false;
  int loadSerial = 0;
  String pageFormat = 'Carta';
  String? error;
  List<Map<String, dynamic>> branches = [];
  Map<String, dynamic>? report;

  static const titles = <String, String>{
    'overview': 'Resumen general',
    'pos': 'Ventas Smart POS',
    'washes': 'Lavados y servicios',
    'bookings': 'Agenda y reservas',
    'cash': 'Caja y cobros',
    'inventory': 'Inventario y productos',
    'customers': 'Clientes y vehículos',
    'staff': 'Personal y asignaciones',
    'fiscal': 'Comprobantes e ISV',
    'purchases': 'Proveedores y entradas',
  };

  @override
  void initState() {
    super.initState();
    ownsClient = widget.client == null;
    client = widget.client ?? http.Client();
    initialize();
  }

  @override
  void didUpdateWidget(covariant CompanyUnifiedReportsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kind != widget.kind) {
      report = null;
      loadReport();
    }
  }

  @override
  void dispose() {
    if (ownsClient) {
      client.close();
    }
    super.dispose();
  }

  static String date(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static List<Map<String, dynamic>> list(dynamic x) => x is List
      ? x.whereType<Map>().map((v) => Map<String, dynamic>.from(v)).toList()
      : [];

  Future<void> initialize() async {
    try {
      final res = await api.request('GET', '/pos/options');
      if (!mounted) {
        return;
      }
      setState(() {
        branches = list((res['data'] as Map)['branches']);
      });
      await loadReport();
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        loading = false;
        error = 'No se pudieron cargar las sucursales: $e';
      });
    }
  }

  Future<void> loadReport() async {
    if (!mounted) {
      return;
    }
    final serial = ++loadSerial;
    setState(() {
      loading = true;
      error = null;
      report = null; // Evita exportar datos anteriores al cambiar filtros.
    });
    try {
      final params = <String, String>{
        'kind': widget.kind,
        'from': date(from),
        'to': date(to),
        if (branch != 0) 'branch_id': '$branch',
      };
      final result = await api.request(
        'GET',
        '/reports/unified',
        query: params,
      );
      if (!mounted || serial != loadSerial) {
        return;
      }
      setState(() {
        report = Map<String, dynamic>.from(result['data'] as Map);
        loading = false;
      });
    } catch (e) {
      if (!mounted || serial != loadSerial) {
        return;
      }
      setState(() {
        loading = false;
        error = 'No se pudo consultar el reporte: $e';
      });
    }
  }

  Future<void> selectDates() async {
    final chosen = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(start: from, end: to),
      helpText: 'Período del reporte',
    );
    if (!mounted || chosen == null) {
      return;
    }
    if (chosen.duration.inDays > 365) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecciona como máximo 366 días por reporte.'),
        ),
      );
      return;
    }
    setState(() {
      from = chosen.start;
      to = chosen.end;
    });
    await loadReport();
  }

  /// La identidad se obtiene del backend autenticado, jamás de valores de ejemplo.
  static Uint8List? logoBytes(Map<String, dynamic> company) {
    final encoded = '${company['logo_base64'] ?? ''}';
    if (encoded.isEmpty || encoded.length > 1398108) {
      return null;
    }
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length > 1048576) {
        return null;
      }
      return bytes;
    } on FormatException {
      return null;
    }
  }

  // El mismo snapshot se usa para pantalla y PDF, con el rango seleccionado.
  Future<void> exportPdf() async {
    final snapshot = report;
    if (snapshot == null || exporting || loading) {
      return;
    }
    setState(() => exporting = true);
    try {
      final doc = pw.Document();
      final scope = Map<String, dynamic>.from(snapshot['scope'] as Map);
      final company = Map<String, dynamic>.from(snapshot['company'] as Map);
      final metrics = list(snapshot['metrics']);
      final sections = list(snapshot['sections']);
      final warnings = (snapshot['warnings'] as List? ?? [])
          .map((e) => '$e')
          .toList();
      final logo = logoBytes(company);
      final logoImg = logo == null ? null : pw.MemoryImage(logo);
      final businessName = '${company['name'] ?? 'Empresa'}';
      final brand = PdfColor.fromHex('#0FA7B4');
      final dataLines = <String>[
        if ('${company['legal_name'] ?? ''}'.trim().isNotEmpty)
          'Razón social: ${company['legal_name']}',
        if ('${company['rtn'] ?? ''}'.trim().isNotEmpty)
          'RTN: ${company['rtn']}',
        if ('${company['address'] ?? ''}'.trim().isNotEmpty)
          'Dirección: ${company['address']}',
        if ('${company['phone'] ?? ''}'.trim().isNotEmpty)
          'Teléfono: ${company['phone']}',
        if ('${company['email'] ?? ''}'.trim().isNotEmpty)
          'Correo: ${company['email']}',
        if ('${company['website'] ?? ''}'.trim().isNotEmpty)
          'Web: ${company['website']}',
      ];
      final elements = <pw.Widget>[
        pw.Text(
          '${snapshot['title']}',
          style: pw.TextStyle(
            fontSize: 17,
            fontWeight: pw.FontWeight.bold,
            color: brand,
          ),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          'Sucursal: ${company['branch_name'] ?? 'Todas las sucursales'}',
        ),
        pw.Text(
          'Período: ${scope['from']} al ${scope['to']} (incluye ambos días)',
        ),
        pw.Text(
          'Generado: ${snapshot['generated_at'] ?? ''}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
        pw.SizedBox(height: 12),
        if (metrics.isNotEmpty) ...[
          pw.Text(
            'Indicadores',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          for (final m in metrics)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(child: pw.Text('${m['label']}')),
                  pw.Text(
                    '${m['value']}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
            ),
          pw.SizedBox(height: 10),
        ],
        for (final section in sections) ...[
          pw.Text(
            '${section['title']}',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          if (list(section['rows']).isEmpty)
            pw.Text('Sin registros en el período seleccionado.')
          else
            pw.TableHelper.fromTextArray(
              headers: Map<String, dynamic>.from(section['columns'] as Map)
                  .values
                  .map((v) => '$v')
                  .toList(),
              data: [
                for (final row in list(section['rows']))
                  Map<String, dynamic>.from(section['columns'] as Map).keys
                      .map((k) => '${row[k] ?? ''}')
                      .toList(),
              ],
              headerDecoration: pw.BoxDecoration(color: brand),
              headerStyle: pw.TextStyle(
                color: PdfColors.white,
                fontWeight: pw.FontWeight.bold,
                fontSize: 8,
              ),
              cellStyle: const pw.TextStyle(fontSize: 8),
              cellPadding: const pw.EdgeInsets.all(5),
            ),
          if ('${section['note'] ?? ''}'.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text(
                '${section['note']}',
                style: const pw.TextStyle(
                  fontSize: 8,
                  color: PdfColors.grey700,
                ),
              ),
            ),
          pw.SizedBox(height: 13),
        ],
        if (warnings.isNotEmpty) ...[
          pw.Divider(),
          pw.Text(
            'Notas de interpretación',
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
          ),
          for (final w in warnings)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 4),
              child: pw.Text('• $w', style: const pw.TextStyle(fontSize: 8)),
            ),
        ],
        pw.SizedBox(height: 8),
        pw.Text(
          'Reporte operativo interno: no sustituye contabilidad ni documento fiscal.',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
        ),
      ];
      doc.addPage(
        pw.MultiPage(
          maxPages: 200,
          pageFormat: pageFormat == 'A4'
              ? PdfPageFormat.a4
              : PdfPageFormat.letter,
          margin: const pw.EdgeInsets.fromLTRB(31, 27, 31, 34),
          header: (_) => pw.Container(
            padding: const pw.EdgeInsets.only(bottom: 8),
            margin: const pw.EdgeInsets.only(bottom: 10),
            decoration: pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(color: brand, width: 1.6),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                if (logoImg != null) ...[
                  pw.Image(
                    logoImg,
                    width: 69,
                    height: 55,
                    fit: pw.BoxFit.contain,
                  ),
                  pw.SizedBox(width: 12),
                ],
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        businessName,
                        style: pw.TextStyle(
                          fontSize: 16,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      for (final line in dataLines)
                        pw.Text(line, style: const pw.TextStyle(fontSize: 8)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          footer: (ctx) => pw.Container(
            decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey500)),
            ),
            padding: const pw.EdgeInsets.only(top: 7),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  'Sistema MyCarWash · ADN Publicidad · adnpublicidad.site',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
                pw.Text(
                  'Página ${ctx.pageNumber} de ${ctx.pagesCount}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          build: (_) => elements,
        ),
      );
      final bytes = await doc.save();
      try {
        await Printing.sharePdf(
          bytes: bytes,
          filename: 'Reporte_${widget.kind}_${date(from)}_${date(to)}.pdf',
        );
      } on MissingPluginException {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      }
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo exportar el documento: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => exporting = false);
      }
    }
  }

  // Misma grilla en todas las categorias. Los tamaños dependen del espacio
  // real del panel (no del ancho completo del navegador).
  static int metricColumns(double width) {
    if (width >= 1050) return 3;
    if (width >= 620) return 2;
    return 1;
  }

  static int detailColumns(double width) => width >= 1000 ? 2 : 1;

  static IconData metricIcon(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('descuento')) return Icons.local_offer_outlined;
    if (lower.contains('isv') || lower.contains('impuesto')) {
      return Icons.percent_outlined;
    }
    if (lower.contains('venta')) return Icons.shopping_cart_outlined;
    if (lower.contains('ingreso') || lower.contains('cobro')) {
      return Icons.payments_outlined;
    }
    if (lower.contains('lavado') || lower.contains('orden')) {
      return Icons.local_car_wash_outlined;
    }
    if (lower.contains('caja')) return Icons.account_balance_wallet_outlined;
    if (lower.contains('inventario') || lower.contains('producto')) {
      return Icons.inventory_2_outlined;
    }
    if (lower.contains('cliente') || lower.contains('vehiculo')) {
      return Icons.people_outline;
    }
    if (lower.contains('cita') || lower.contains('reserva')) {
      return Icons.event_available_outlined;
    }
    if (lower.contains('personal') || lower.contains('empleado')) {
      return Icons.badge_outlined;
    }
    if (lower.contains('comprobante') || lower.contains('factura')) {
      return Icons.receipt_long_outlined;
    }
    return Icons.analytics_outlined;
  }

  Widget metricCard(Map<String, dynamic> metric) {
    return Container(
      key: ValueKey('report-metric-${metric['label']}'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF173D45), Color(0xFF0C2229)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF28626D)),
        boxShadow: [
          BoxShadow(color: accent.withValues(alpha: .045), blurRadius: 16),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF0B3942),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF23717B)),
            ),
            child: Icon(
              metricIcon('${metric['label']}'),
              color: accent,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // El titulo cede altura al importe cuando el usuario tiene
                // pantalla pequena o escala de texto ampliada. Nunca fuerces
                // la altura natural de dos lineas en una tarjeta fija.
                Flexible(
                  fit: FlexFit.loose,
                  child: Text(
                    '${metric['label']}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${metric['value']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget sectionTable(Map<String, dynamic> section) {
    final cols = Map<String, dynamic>.from(section['columns'] as Map);
    final rows = list(section['rows']);
    final note = '${section['note'] ?? ''}';
    return Container(
      key: ValueKey('report-section-${section['title']}'),
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: panel,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF28515A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 3,
                height: 21,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 9),
              const Icon(Icons.insert_chart_outlined, color: accent, size: 20),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  '${section['title']}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFF163942),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  rows.length == 1 ? '1 registro' : '${rows.length} registros',
                  style: const TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFF315059)),
          const SizedBox(height: 5),
          Expanded(
            child: rows.isEmpty
                ? const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.only(top: 13),
                      child: Text(
                        'Sin registros en el período seleccionado.',
                        style: TextStyle(color: muted, fontSize: 15),
                      ),
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, bounds) {
                      // El ancho real del panel manda. Con muchas columnas, el
                      // desbordamiento permanece dentro del scroll de la tabla.
                      final widthPerColumn = bounds.maxWidth < 500
                          ? 138.0
                          : 155.0;
                      final requiredWidth = cols.length * widthPerColumn;
                      final tableWidth = bounds.maxWidth >= requiredWidth
                          ? bounds.maxWidth
                          : requiredWidth;
                      return ClipRect(
                        child: SingleChildScrollView(
                          scrollDirection: Axis.vertical,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minWidth: tableWidth),
                              child: DataTable(
                                key: ValueKey(
                                  'report-data-${section['title']}',
                                ),
                                headingRowHeight: 56,
                                dataRowMinHeight: 52,
                                dataRowMaxHeight: 66,
                                horizontalMargin: 15,
                                columnSpacing: 24,
                                dividerThickness: .7,
                                headingTextStyle: const TextStyle(
                                  color: accent,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                                dataTextStyle: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                                columns: [
                                  for (final c in cols.values)
                                    DataColumn(
                                      label: Text('$c', softWrap: false),
                                    ),
                                ],
                                rows: [
                                  for (final r in rows)
                                    DataRow(
                                      cells: [
                                        for (final c in cols.keys)
                                          DataCell(
                                            Text(
                                              '${r[c] ?? ''}',
                                              softWrap: false,
                                            ),
                                          ),
                                      ],
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (note.isNotEmpty) ...[
            const Divider(height: 8, color: Color(0xFF315059)),
            Tooltip(
              message: note,
              child: Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget reportGrid({
    required String keyName,
    required int columns,
    required double rowHeight,
    required List<Widget> cards,
  }) {
    return GridView.builder(
      key: ValueKey(keyName),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: rowHeight,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) => cards[index],
    );
  }

  Widget sectionHeading(String title, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Icon(icon, color: accent, size: 21),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            softWrap: true,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  static const Map<String, String> _reportDescriptions24M = {
    'overview':
        'Una lectura clara de la operación y los resultados del negocio.',
    'pos': 'Ventas, formas de cobro y comportamiento comercial.',
    'washes': 'Servicios, órdenes y actividad de lavado.',
    'bookings': 'Reservas, agenda y cumplimiento de citas.',
    'cash': 'Movimientos y resultados registrados en caja.',
    'inventory': 'Existencias y movimientos registrados del inventario.',
    'customers': 'Actividad de clientes y vehículos.',
    'staff': 'Personal, asignaciones y desempeño operativo.',
    'fiscal': 'Comprobantes fiscales e impuestos registrados.',
    'purchases': 'Compras, proveedores y entradas de productos.',
  };

  static IconData _reportIcon24M(String kind) {
    switch (kind) {
      case 'overview':
        return Icons.space_dashboard_outlined;
      case 'pos':
        return Icons.point_of_sale_outlined;
      case 'washes':
        return Icons.local_car_wash_outlined;
      case 'bookings':
        return Icons.event_available_outlined;
      case 'cash':
        return Icons.account_balance_wallet_outlined;
      case 'inventory':
        return Icons.inventory_2_outlined;
      case 'customers':
        return Icons.people_outline;
      case 'staff':
        return Icons.badge_outlined;
      case 'fiscal':
        return Icons.receipt_long_outlined;
      case 'purchases':
        return Icons.local_shipping_outlined;
      default:
        return Icons.insights_outlined;
    }
  }

  Widget _reportHero24M() => Container(
    key: const ValueKey('reports-hero-24m'),
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 21),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF123D46), Color(0xFF0B2027), Color(0xFF102229)],
      ),
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: const Color(0xFF23717B)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF0B3038),
            border: Border.all(color: const Color(0xFF278792)),
          ),
          child: Icon(_reportIcon24M(widget.kind), color: accent, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                titles[widget.kind] ?? 'Reportes',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                _reportDescriptions24M[widget.kind] ??
                    'Información operativa de la empresa.',
                style: const TextStyle(color: Color(0xFFD4E5E8), fontSize: 12),
              ),
              const SizedBox(height: 9),
              const Text(
                'Reportes por sucursal, período y fuente verificable',
                style: TextStyle(color: muted, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _quickRange24M(DateTime start, DateTime end) async {
    if (loading || exporting) {
      return;
    }
    setState(() {
      from = start;
      to = end;
    });
    await loadReport();
  }

  Widget _periodButton24M(String label, DateTime start, DateTime end) {
    final selected = date(from) == date(start) && date(to) == date(end);
    return OutlinedButton(
      key: ValueKey<String>('reports-quick-$label'),
      onPressed: loading ? null : () => _quickRange24M(start, end),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        visualDensity: VisualDensity.compact,
        backgroundColor: selected ? const Color(0xFF16434B) : panel,
        foregroundColor: selected ? Colors.white : muted,
        side: BorderSide(color: selected ? accent : const Color(0xFF35535C)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
    );
  }

  Widget _quickPeriods24M() {
    final today = DateUtils.dateOnly(DateTime.now());
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 5),
          child: Text(
            'PERÍODO RÁPIDO',
            style: TextStyle(
              color: muted,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        _periodButton24M('Hoy', today, today),
        _periodButton24M(
          '7 días',
          today.subtract(const Duration(days: 6)),
          today,
        ),
        _periodButton24M(
          '30 días',
          today.subtract(const Duration(days: 29)),
          today,
        ),
        _periodButton24M('Este mes', DateTime(today.year, today.month), today),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = report;
    final metrics = list(snapshot?['metrics']);
    final sections = list(snapshot?['sections']);
    final warnings = (snapshot?['warnings'] as List? ?? [])
        .map((x) => '$x')
        .toList();
    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reportHero24M(),
              const SizedBox(height: 14),
              Container(
                key: const ValueKey('reports-filters-24m'),
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D252C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF28515A)),
                ),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 245,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(branch),
                        initialValue: branch,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Sucursal',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 0,
                            child: Text('Todas las sucursales'),
                          ),
                          for (final row in branches)
                            DropdownMenuItem(
                              value: int.tryParse('${row['id']}') ?? -1,
                              child: Text(
                                '${row['name']}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) {
                          if (v == null) {
                            return;
                          }
                          setState(() => branch = v);
                          loadReport();
                        },
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: selectDates,
                      icon: const Icon(Icons.date_range),
                      label: Text('${date(from)} — ${date(to)}'),
                    ),
                    OutlinedButton.icon(
                      onPressed: loading ? null : loadReport,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Actualizar'),
                    ),
                    SizedBox(
                      width: 155,
                      child: DropdownButtonFormField<String>(
                        initialValue: pageFormat,
                        decoration: const InputDecoration(
                          labelText: 'Papel PDF',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'Carta',
                            child: Text('Carta'),
                          ),
                          DropdownMenuItem(value: 'A4', child: Text('A4')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() => pageFormat = v);
                          }
                        },
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: snapshot == null || loading || exporting
                          ? null
                          : exportPdf,
                      icon: const Icon(Icons.picture_as_pdf_outlined),
                      label: Text(
                        exporting
                            ? 'Generando documento...'
                            : 'Exportar PDF del período',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _quickPeriods24M(),
              const SizedBox(height: 18),
              if (loading) const LinearProgressIndicator(color: accent),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Text(
                    '$error',
                    style: const TextStyle(color: Color(0xFFFF8D94)),
                  ),
                ),
              if (snapshot != null) ...[
                LayoutBuilder(
                  builder: (context, constraints) {
                    final available = constraints.maxWidth;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (metrics.isNotEmpty) ...[
                          sectionHeading(
                            'Indicadores del período',
                            Icons.dashboard_outlined,
                          ),
                          reportGrid(
                            keyName: 'reports-kpi-grid',
                            columns: metricColumns(available),
                            rowHeight: 112,
                            cards: [for (final m in metrics) metricCard(m)],
                          ),
                        ],
                        if (sections.isNotEmpty) ...[
                          const SizedBox(height: 24),
                          sectionHeading(
                            'Detalle de operaciones',
                            Icons.table_chart_outlined,
                          ),
                          reportGrid(
                            keyName: 'reports-detail-grid',
                            columns: detailColumns(available),
                            rowHeight: 305,
                            cards: [
                              for (final section in sections)
                                sectionTable(section),
                            ],
                          ),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 17),
                for (final w in warnings)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF30271E),
                      border: Border.all(color: const Color(0xFF665037)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: Color(0xFFEAB77A),
                          size: 18,
                        ),
                        const SizedBox(width: 9),
                        Expanded(
                          child: Text(
                            w,
                            style: const TextStyle(
                              color: Color(0xFFE7D8C2),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 13),
                const Text(
                  'Los reportes operativos no sustituyen contabilidad ni documentos fiscales autorizados.',
                  style: TextStyle(color: muted, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
