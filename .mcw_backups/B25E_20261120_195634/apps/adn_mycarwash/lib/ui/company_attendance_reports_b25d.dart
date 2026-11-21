import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';

/// B25D: historial y reporte mensual. Usa el endpoint B25A existente.
class CompanyAttendanceReportsB25D extends StatefulWidget {
  const CompanyAttendanceReportsB25D({super.key, required this.monthlyReport});
  final bool monthlyReport;
  @override
  State<CompanyAttendanceReportsB25D> createState() => _AttendanceState();
}

class _AttendanceState extends State<CompanyAttendanceReportsB25D> {
  final http.Client _client = http.Client();
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  static String _date(DateTime d) => '${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  int? _employee;
  List<Map<String,dynamic>> _employees = [];
  List<Map<String,dynamic>> _rows = [];
  bool _loading = false;
  String? _error;
  @override void initState() { super.initState(); _initialize(); }
  @override void dispose() { _client.close(); super.dispose(); }
  Future<void> _initialize() async {
    try {
      final response = await _api.request('GET','/schedule/options');
      final options = Map<String,dynamic>.from(response['data'] as Map);
      final raw = options['employees'];
      if (mounted) setState(() => _employees = raw is List ? raw.whereType<Map>().map((x) => Map<String,dynamic>.from(x)).toList() : []);
    } catch (e) { if (mounted) setState(() => _error = '$e'); }
    await _load();
  }
  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final from = _date(_month);
      final to = _date(DateTime(_month.year,_month.month+1,0));
      final result = await _api.request('GET','/attendance/report-b25',query: {
        'from':from,'to':to, if (_employee != null) 'employee_id':'$_employee',
      });
      final raw = result['data'];
      if (mounted) setState(() => _rows = raw is List ? raw.whereType<Map>().map((x)=>Map<String,dynamic>.from(x)).toList():[]);
    } catch(e) { if (mounted) setState(() => _error = '$e'); }
    finally { if (mounted) setState(() => _loading = false); }
  }
  int _minutes(Map<String,dynamic> row) {
    final a = DateTime.tryParse('${row['check_in_at']??''}');
    final b = DateTime.tryParse('${row['check_out_at']??''}');
    if (a == null || b == null) return 0;
    return b.difference(a).inMinutes.clamp(0,1440);
  }
  String _time(dynamic value) {
    if (value == null) return 'Sin salida';
    final text = '$value';
    // Las marcas provienen del servidor en UTC. Convertir a zona local del dispositivo.
    final utcText = text.endsWith('Z') || text.contains('+') ? text : '${text}Z';
    final parsed = DateTime.tryParse(utcText)?.toLocal();
    return parsed == null ? text : '${parsed.hour.toString().padLeft(2,'0')}:${parsed.minute.toString().padLeft(2,'0')}';
  }
  Future<void> _copyCsv() async {
    String safe(Object? input) => '"${(input??'').toString().replaceAll('"','""')}"';
    final lines = <String>['Empleado,Fecha,Entrada,Salida,Minutos'];
    for (final row in _rows) {
      lines.add([row['full_name'],row['work_date'],_time(row['check_in_at']),_time(row['check_out_at']),_minutes(row)].map(safe).join(','));
    }
    await Clipboard.setData(ClipboardData(text: '\uFEFF${lines.join('\r\n')}'));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('CSV copiado al portapapeles. Pégalo en Excel.')));
  }
  @override Widget build(BuildContext context) {
    final totalMinutes = _rows.fold<int>(0,(sum,r)=>sum+_minutes(r));
    final unique = _rows.map((r)=>'${r['employee_id']}').toSet().length;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(widget.monthlyReport?'Reporte mensual de asistencia':'Historial de asistencia',style:TextStyle(fontSize:25,fontWeight:FontWeight.w700,color:CompanyVisualTheme.text)),
      const SizedBox(height:8),
      Text('Entradas y salidas registradas por el servidor · Información mensual',style:TextStyle(color:CompanyVisualTheme.muted)),
      const SizedBox(height:18),
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:CompanyVisualTheme.card,border:Border.all(color:CompanyVisualTheme.border),borderRadius:BorderRadius.circular(18)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Wrap(spacing:12,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
          IconButton(tooltip:'Mes anterior',onPressed:()=>setState((){_month=DateTime(_month.year,_month.month-1);_load();}),icon:const Icon(Icons.chevron_left)),
          Text('${_month.year}-${_month.month.toString().padLeft(2,'0')}',style:TextStyle(color:CompanyVisualTheme.text,fontWeight:FontWeight.w700)),
          IconButton(tooltip:'Mes siguiente',onPressed:()=>setState((){_month=DateTime(_month.year,_month.month+1);_load();}),icon:const Icon(Icons.chevron_right)),
          SizedBox(width:260,child:DropdownButtonFormField<int>(initialValue:_employee,isExpanded:true,decoration:const InputDecoration(labelText:'Empleado'),items:[const DropdownMenuItem<int>(value:null,child:Text('Todos los empleados')), ..._employees.map((e)=>DropdownMenuItem<int>(value:(e['id'] as num).toInt(),child:Text('${e['full_name']}',overflow:TextOverflow.ellipsis)))],onChanged:(v){setState(()=>_employee=v);_load();})),
          OutlinedButton.icon(onPressed:_loading?null:_load,icon:const Icon(Icons.refresh),label:const Text('Actualizar')),
          OutlinedButton.icon(onPressed:_rows.isEmpty?null:_copyCsv,icon:const Icon(Icons.copy),label:const Text('Copiar CSV')),
        ]),
        const SizedBox(height:12),
        Wrap(spacing:18,runSpacing:8,children:[Text('Registros: ${_rows.length}'),Text('Empleados: $unique'),Text('Horas registradas: ${(totalMinutes/60).toStringAsFixed(2)}')]),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:const TextStyle(color:Colors.redAccent))),
      ])),
      const SizedBox(height:14),
      if (_rows.isEmpty && !_loading) const Padding(padding:EdgeInsets.all(18),child:Text('No hay asistencias registradas en el período seleccionado.')),
      ..._rows.map((row)=>Container(margin:const EdgeInsets.only(bottom:9),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:CompanyVisualTheme.card,border:Border.all(color:CompanyVisualTheme.border),borderRadius:BorderRadius.circular(15)),child:Wrap(spacing:20,runSpacing:8,alignment:WrapAlignment.spaceBetween,children:[
        SizedBox(width:190,child:Text('${row['full_name']??''}',style:TextStyle(fontWeight:FontWeight.w700,color:CompanyVisualTheme.text))),
        Text('${row['work_date']}'),Text('Entrada: ${_time(row['check_in_at'])}'),Text('Salida: ${_time(row['check_out_at'])}'),Text('${(_minutes(row)/60).toStringAsFixed(2)} h'),
      ]))),
      const SizedBox(height:8),
      Text('Las horas son orientativas y se basan en las marcas reales; no se interpretan automáticamente como nómina ni como ausencias.',style:TextStyle(color:CompanyVisualTheme.muted,fontSize:12)),
    ]);
  }
}
