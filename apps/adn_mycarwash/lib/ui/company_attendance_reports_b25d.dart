import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/business_identity.dart';
import 'package:http/http.dart' as http;
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';
import 'company_employee_cards_24c3.dart';

/// B25E: historial visual por empleado y reporte mensual independiente.
class CompanyAttendanceReportsB25D extends StatefulWidget {
  const CompanyAttendanceReportsB25D({super.key,required this.monthlyReport});
  final bool monthlyReport;
  @override State<CompanyAttendanceReportsB25D> createState()=>_AttendanceCardsState();
}
class _AttendanceCardsState extends State<CompanyAttendanceReportsB25D>{
  final http.Client client=http.Client();
  CompanyBusinessApi get api=>CompanyBusinessApi(client);
  DateTime month=DateTime(DateTime.now().year,DateTime.now().month);
  int? filter;
  DateTime from=DateTime(DateTime.now().year,DateTime.now().month);
  DateTime to=DateTime(DateTime.now().year,DateTime.now().month+1,0);
  String paper='Carta';
  bool exporting=false;
  List<Map<String,dynamic>> employees=[];
  List<Map<String,dynamic>> rows=[];
  bool busy=false;
  String? error;
  @override void initState(){super.initState();initialize();}
  @override void dispose(){client.close();super.dispose();}
  static String day(DateTime date)=>'${date.year.toString().padLeft(4,'0')}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
  int id(Map<String,dynamic> row)=>int.tryParse('${row['id']??row['employee_id']}')??0;
  Future<void> initialize() async {
    try{
      // El catalogo de empleados incluye cargo, documento y telefono.
      // schedule/options solo devuelve id y nombre.
      final response=await api.request('GET','/employees',query:{'per_page':'50'});
      final data=response['data'];
      if(mounted)setState(()=>employees=data is List?data.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList():[]);
    }catch(e){if(mounted)setState(()=>error='$e');}
    await load();
  }
  Future<void> load() async{
    setState((){busy=true;error=null;});
    try{
      final response=await api.request('GET','/attendance/report-b25',query:{
        'from':day(from),'to':day(to),if(filter!=null)'employee_id':'$filter',
      });
      final data=response['data'];
      if(mounted)setState(()=>rows=data is List?data.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList():[]);
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>busy=false);}
  }
  String clock(dynamic input){
    if(input==null)return 'Sin salida';
    final text='$input';
    final value=DateTime.tryParse(text.endsWith('Z')||text.contains('+')?text:'${text}Z')?.toLocal();
    return value==null?text:'${value.hour.toString().padLeft(2,'0')}:${value.minute.toString().padLeft(2,'0')}';
  }
  int minutes(Map<String,dynamic> row){
    final a=DateTime.tryParse('${row['check_in_at']??''}');
    final b=DateTime.tryParse('${row['check_out_at']??''}');
    if(a==null||b==null||b.isBefore(a))return 0;
    return b.difference(a).inMinutes.clamp(0,1440);
  }
  List<Map<String,dynamic>> forEmployee(int employeeId)=>rows.where((r)=>int.tryParse('${r['employee_id']}')==employeeId).toList();
  Future<void> csv() async{
    String safe(Object? v)=>'"${(v??'').toString().replaceAll('"','""')}"';
    final text=<String>['Empleado,Fecha,Entrada,Salida,Horas'];
    for(final r in rows){text.add([r['full_name'],r['work_date'],clock(r['check_in_at']),clock(r['check_out_at']),(minutes(r)/60).toStringAsFixed(2)].map(safe).join(','));}
    await Clipboard.setData(ClipboardData(text:'\uFEFF${text.join('\r\n')}'));
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('CSV copiado para pegar en Excel.')));
  }
  Future<void> detail(Map<String,dynamic> employee)async{
    final r=forEmployee(id(employee));
    final hours=r.fold<int>(0,(sum,row)=>sum+minutes(row))/60;
    await showDialog<void>(context:context,builder:(ctx)=>Dialog(backgroundColor:CompanyVisualTheme.card,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:760,maxHeight:760),child:Padding(padding:const EdgeInsets.all(23),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[ClipRRect(borderRadius:BorderRadius.circular(12),child:SizedBox(width:85,height:85,child:CompanyEmployeePhoto24C3(client:client,employeeId:id(employee)))),const SizedBox(width:14),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('${employee['full_name']??''}',style:TextStyle(fontSize:23,color:CompanyVisualTheme.text,fontWeight:FontWeight.bold)),
        Text('Cargo: ${employee['position']??'No registrado'}',style:TextStyle(color:CompanyVisualTheme.muted)),
        Text('Documento: ${employee['identity_document']??'No registrado'}',style:TextStyle(color:CompanyVisualTheme.muted)),
        Text('Teléfono: ${employee['phone']??'No registrado'}',style:TextStyle(color:CompanyVisualTheme.muted)),
      ])),IconButton(onPressed:()=>Navigator.pop(ctx),icon:const Icon(Icons.close))]),
      const SizedBox(height:12),Text('Historial · ${day(from)} al ${day(to)}',style:TextStyle(fontSize:18,color:CompanyVisualTheme.text,fontWeight:FontWeight.w700)),
      const SizedBox(height:6),Text('${r.length} registros · ${hours.toStringAsFixed(2)} horas · ${r.where((x)=>x['check_out_at']==null).length} sin salida',style:TextStyle(color:CompanyVisualTheme.muted)),
      const SizedBox(height:14),Expanded(child:ListView.builder(itemCount:r.length,itemBuilder:(ctx,i){final a=r[i];return Container(margin:const EdgeInsets.only(bottom:9),padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:CompanyVisualTheme.surface,border:Border.all(color:CompanyVisualTheme.border),borderRadius:BorderRadius.circular(13)),child:Wrap(spacing:15,runSpacing:7,children:[
        Text('${a['work_date']}',style:TextStyle(color:CompanyVisualTheme.text,fontWeight:FontWeight.bold)),
        Text('Entrada: ${clock(a['check_in_at'])}'),Text('Salida: ${clock(a['check_out_at'])}'),Text('${(minutes(a)/60).toStringAsFixed(2)} h'),
        Text(a['check_out_at']==null?'Sin salida':'Jornada registrada',style:TextStyle(color:CompanyVisualTheme.primary)),
      ]));})),
      if(r.isEmpty)const Text('Sin asistencias para el mes seleccionado.'),
    ])))));
  }
  Widget employeeCard(Map<String,dynamic> e){
    final idValue=id(e);final r=forEmployee(idValue);
    final count=r.length;final hours=r.fold<int>(0,(sum,v)=>sum+minutes(v))/60;
    final last=r.isEmpty?null:r.last;
    return Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:CompanyVisualTheme.card,borderRadius:BorderRadius.circular(18),border:Border.all(color:CompanyVisualTheme.primary.withValues(alpha:.65))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:Text('${e['full_name']}',maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:19,fontWeight:FontWeight.bold,color:CompanyVisualTheme.text))),Text(e['is_active']==false?'Inactivo':'Activo',style:TextStyle(color:CompanyVisualTheme.primary,fontSize:12))]),
      const SizedBox(height:9),SizedBox(height:118,width:double.infinity,child:ClipRRect(borderRadius:BorderRadius.circular(12),child:CompanyEmployeePhoto24C3(client:client,employeeId:idValue))),
      const SizedBox(height:9),Text('Cargo: ${e['position']??'No registrado'}',style:TextStyle(color:CompanyVisualTheme.muted)),
      Text('Identidad: ${e['identity_document']??'No registrada'}',style:TextStyle(color:CompanyVisualTheme.muted)),
      const SizedBox(height:6),Text('Marcas: $count  ·  Horas: ${hours.toStringAsFixed(2)}',style:TextStyle(color:CompanyVisualTheme.text,fontWeight:FontWeight.w600)),
      Text('Última entrada: ${last==null?'—':clock(last['check_in_at'])}',style:TextStyle(color:CompanyVisualTheme.muted)),
      Text('Última salida: ${last==null?'—':clock(last['check_out_at'])}',style:TextStyle(color:CompanyVisualTheme.muted)),
      const Spacer(),Divider(color:CompanyVisualTheme.border),SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:()=>detail(e),icon:const Icon(Icons.visibility_outlined),label:const Text('Ver historial'))),
    ]));
  }
  void _setPeriod(DateTime a, DateTime b) {
    setState(() { from=a; to=b; month=DateTime(a.year,a.month); });
    load();
  }

  Future<void> _selectPeriod() async {
    final selection=await showDateRangePicker(
      context:context,firstDate:DateTime(2020),
      lastDate:DateTime.now().add(const Duration(days:365)),
      initialDateRange:DateTimeRange(start:from,end:to),
      helpText:'Período del reporte de asistencia',
    );
    if(!mounted || selection==null) return;
    if(selection.duration.inDays>365){
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Selecciona un período máximo de 366 días.')),
      );
      return;
    }
    _setPeriod(selection.start,selection.end);
  }

  static PdfColor _pdfColor(Color color) => PdfColor(
    color.r,color.g,color.b,
  );

  Future<void> _exportPdf() async {
    if(busy || exporting || error!=null) return;
    final data=rows.map((e)=>Map<String,dynamic>.from(e)).toList();
    final periodFrom=day(from);
    final periodTo=day(to);
    final employeeLabel=filter==null ? 'Todos los empleados' : employees
      .where((e)=>id(e)==filter).map((e)=>'${e['full_name']}')
      .firstOrNull ?? 'Empleado seleccionado';
    final currentPalette=CompanyVisualTheme.current.value;
    final currentIdentity=BusinessIdentity.current.value;
    final businessName=currentIdentity.companyName.trim().isEmpty
      ? 'Mi Empresa' : currentIdentity.companyName.trim();
    final imageBytes=currentIdentity.logoBytes;
    final logo=imageBytes==null || imageBytes.isEmpty ? null : pw.MemoryImage(imageBytes);
    final accent=_pdfColor(currentPalette.primary);
    final secondary=_pdfColor(currentPalette.secondary);
    final totalMinutes=data.fold<int>(0,(sum,row)=>sum+minutes(row));
    final unique=data.map((e)=>'${e['employee_id']}').toSet().length;
    final open=data.where((r)=>r['check_out_at']==null).length;
    setState(()=>exporting=true);
    try {
      final pdf=pw.Document();
      final tableRows=data.map((r)=><String>[
        '${r['full_name']??''}', '${r['work_date']??''}',
        clock(r['check_in_at']),clock(r['check_out_at']),
        (minutes(r)/60).toStringAsFixed(2),
        r['check_out_at']==null?'Sin salida':'Registrada',
      ]).toList();
      pdf.addPage(pw.MultiPage(
        maxPages:200,
        pageFormat:paper=='A4'?PdfPageFormat.a4:PdfPageFormat.letter,
        margin:const pw.EdgeInsets.fromLTRB(32,28,32,35),
        header:(ctx)=>pw.Container(
          margin:const pw.EdgeInsets.only(bottom:14),
          padding:const pw.EdgeInsets.only(bottom:12),
          decoration:pw.BoxDecoration(border:pw.Border(bottom:pw.BorderSide(color:accent,width:2))),
          child:pw.Row(children:[
            if(logo!=null)...[
              pw.Image(logo,width:62,height:54,fit:pw.BoxFit.contain),
              pw.SizedBox(width:12),
            ],
            pw.Expanded(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
              pw.Text(businessName,style:pw.TextStyle(fontSize:16,fontWeight:pw.FontWeight.bold,color:secondary)),
              pw.Text('CONTROL DE ASISTENCIA DEL PERSONAL',style:pw.TextStyle(fontSize:9,color:accent,fontWeight:pw.FontWeight.bold)),
              pw.Text('Período: $periodFrom al $periodTo',style:const pw.TextStyle(fontSize:8)),
            ])),
          ]),
        ),
        footer:(ctx)=>pw.Container(
          padding:const pw.EdgeInsets.only(top:7),
          decoration:pw.BoxDecoration(border:pw.Border(top:pw.BorderSide(color:accent,width:.7))),
          child:pw.Row(mainAxisAlignment:pw.MainAxisAlignment.spaceBetween,children:[
            pw.Text('ADN MyCarWash · Reporte administrativo de asistencia',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey700)),
            pw.Text('Página ${ctx.pageNumber} de ${ctx.pagesCount}',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey700)),
          ]),
        ),
        build:(ctx)=>[
          pw.Text('Reporte de asistencia',style:pw.TextStyle(fontSize:20,fontWeight:pw.FontWeight.bold,color:secondary)),
          pw.SizedBox(height:5),
          pw.Text('Empleado: $employeeLabel',style:const pw.TextStyle(fontSize:10)),
          pw.Text('Generado: ${DateTime.now().toLocal().toString().substring(0,16)}',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey700)),
          pw.SizedBox(height:15),
          pw.Row(children:[
            _pdfMetric('Registros','${data.length}',accent),
            pw.SizedBox(width:8),
            _pdfMetric('Empleados','$unique',accent),
            pw.SizedBox(width:8),
            _pdfMetric('Horas',(totalMinutes/60).toStringAsFixed(2),accent),
            pw.SizedBox(width:8),
            _pdfMetric('Sin salida','$open',accent),
          ]),
          pw.SizedBox(height:17),
          pw.Text('Detalle de entradas y salidas',style:pw.TextStyle(fontSize:12,fontWeight:pw.FontWeight.bold,color:secondary)),
          pw.SizedBox(height:8),
          if(tableRows.isEmpty) pw.Text('No se registraron asistencias durante el período seleccionado.')
          else pw.TableHelper.fromTextArray(
            headers:const ['Empleado','Fecha','Entrada','Salida','Horas','Estado'],
            data:tableRows,
            border:pw.TableBorder.all(color:PdfColors.grey300,width:.4),
            headerDecoration:pw.BoxDecoration(color:accent),
            headerStyle:pw.TextStyle(color:PdfColors.white,fontSize:8,fontWeight:pw.FontWeight.bold),
            cellStyle:const pw.TextStyle(fontSize:8),
            cellPadding:const pw.EdgeInsets.symmetric(horizontal:5,vertical:7),
            oddRowDecoration:const pw.BoxDecoration(color:PdfColors.grey100),
            columnWidths:{0:const pw.FlexColumnWidth(1.6),1:const pw.FlexColumnWidth(1.1),2:const pw.FlexColumnWidth(.9),3:const pw.FlexColumnWidth(.9),4:const pw.FlexColumnWidth(.65),5:const pw.FlexColumnWidth(1)},
          ),
          pw.SizedBox(height:13),
          pw.Text('Notas: Las horas se calculan a partir de las marcas registradas por el servidor. Las jornadas sin salida no se consideran completas. La ausencia requiere comparar las marcas con los turnos programados.',style:const pw.TextStyle(fontSize:8,color:PdfColors.grey700)),
        ],
      ));
      final bytes=await pdf.save();
      try {
        await Printing.sharePdf(bytes:bytes,filename:'Asistencia_${periodFrom}_$periodTo.pdf');
      } on MissingPluginException {
        await Printing.layoutPdf(onLayout:(_)=>bytes);
      }
    } catch(e){
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content:Text('No se pudo exportar el PDF: $e')),
        );
      }
    } finally {
      if(mounted) setState(()=>exporting=false);
    }
  }

  pw.Widget _pdfMetric(String label,String value,PdfColor accent) =>
    pw.Expanded(child:pw.Container(
      padding:const pw.EdgeInsets.all(9),
      decoration:pw.BoxDecoration(
        color:PdfColors.grey100,
        border:pw.Border(left:pw.BorderSide(color:accent,width:2)),
      ),
      child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
        pw.Text(label,style:const pw.TextStyle(fontSize:8,color:PdfColors.grey700)),
        pw.SizedBox(height:4),
        pw.Text(value,style:pw.TextStyle(fontSize:15,fontWeight:pw.FontWeight.bold)),
      ]),
    ));

  Widget _panel({required Widget child,EdgeInsets padding=const EdgeInsets.all(17)}) =>
    Container(padding:padding,decoration:BoxDecoration(
      color:CompanyVisualTheme.card,
      borderRadius:BorderRadius.circular(16),
      border:Border.all(color:CompanyVisualTheme.border),
    ),child:child);

  Widget _kpi(String caption,String value,IconData icon){
    final colors=CompanyVisualTheme.current.value;
    return Container(
      padding:const EdgeInsets.all(18),
      decoration:BoxDecoration(
        color:colors.card,borderRadius:BorderRadius.circular(13),
        border:Border.all(color:colors.primary.withValues(alpha:.75)),
      ),child:Row(children:[
        Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(
          color:colors.primary.withValues(alpha:.09),
          border:Border.all(color:colors.primary),borderRadius:BorderRadius.circular(11),
        ),child:Icon(icon,color:colors.primary,size:23)),
        const SizedBox(width:14),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisSize:MainAxisSize.min,children:[
          Text(caption,style:TextStyle(color:colors.muted,fontSize:13)),
          const SizedBox(height:7),
          Text(value,style:TextStyle(color:colors.text,fontSize:24,fontWeight:FontWeight.w800)),
        ])),
      ]),
    );
  }

  Widget _reportTable(){
    final c=CompanyVisualTheme.current.value;
    if(rows.isEmpty) return _panel(child:Text('Sin marcas de asistencia durante el período seleccionado.',style:TextStyle(color:c.muted)));
    final grouped=<String,List<Map<String,dynamic>>>{};
    for(final r in rows){
      grouped.putIfAbsent('${r['employee_id']} - ${r['full_name']}',()=>[]).add(r);
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      for(final entry in grouped.entries)...[
        const SizedBox(height:12),
        _panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Row(children:[Icon(Icons.badge_outlined,color:c.primary,size:21),const SizedBox(width:9),
            Expanded(child:Text(entry.key.split(' - ').skip(1).join(' - '),style:TextStyle(fontSize:17,fontWeight:FontWeight.w700,color:c.text))),
            Text('${entry.value.length} registro(s)',style:TextStyle(color:c.muted,fontSize:12)),
          ]),
          const SizedBox(height:12),
          LayoutBuilder(builder:(context,limits)=>SingleChildScrollView(
            scrollDirection:Axis.horizontal,
            child:ConstrainedBox(constraints:BoxConstraints(minWidth:limits.maxWidth),child:DataTable(
              headingRowHeight:43,dataRowMinHeight:45,dataRowMaxHeight:50,
              headingTextStyle:TextStyle(color:c.primary,fontWeight:FontWeight.bold),
              dataTextStyle:TextStyle(color:c.text,fontSize:13),
              dividerThickness:.5,
              columns:const [DataColumn(label:Text('Fecha')),DataColumn(label:Text('Entrada')),DataColumn(label:Text('Salida')),DataColumn(label:Text('Horas')),DataColumn(label:Text('Estado'))],
              rows:entry.value.map((r)=>DataRow(cells:[
                DataCell(Text('${r['work_date']}')),
                DataCell(Text(clock(r['check_in_at']))),
                DataCell(Text(clock(r['check_out_at']))),
                DataCell(Text((minutes(r)/60).toStringAsFixed(2))),
                DataCell(Text(r['check_out_at']==null?'Sin salida':'Registrada',style:TextStyle(color:r['check_out_at']==null?c.warning:c.success))),
              ])).toList(),
            )),
          )),
        ])),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c=CompanyVisualTheme.current.value;
    final total=rows.fold<int>(0,(sum,r)=>sum+minutes(r));
    final unique=rows.map((r)=>'${r['employee_id']}').toSet().length;
    final open=rows.where((r)=>r['check_out_at']==null).length;
    final monthly=widget.monthlyReport;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      if(monthly)...[
        Container(width:double.infinity,padding:const EdgeInsets.all(22),
          decoration:BoxDecoration(
            border:Border.all(color:c.primary),borderRadius:BorderRadius.circular(16),
            gradient:LinearGradient(colors:[c.card,c.surface],begin:Alignment.centerLeft,end:Alignment.centerRight),
          ),child:Row(children:[
            Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:c.background,borderRadius:BorderRadius.circular(13),border:Border.all(color:c.primary)),child:Icon(Icons.event_available_outlined,color:c.primary,size:28)),
            const SizedBox(width:14),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('Reporte de asistencia',style:TextStyle(color:c.text,fontSize:26,fontWeight:FontWeight.w800)),
              const SizedBox(height:5),Text('Entradas, salidas, horas registradas y cumplimiento documental del personal.',style:TextStyle(color:c.muted)),
              const SizedBox(height:5),Text('Reporte administrativo por período y empleado.',style:TextStyle(color:c.muted,fontSize:12)),
            ])),
          ])),
        const SizedBox(height:15),
      ]else ...[
        Text('Historial de asistencia',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold,color:c.text)),
        const SizedBox(height:6),Text('Consulta el historial individual de entradas y salidas.',style:TextStyle(color:c.muted)),
        const SizedBox(height:15),
      ],
      _panel(child:Wrap(spacing:10,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
        OutlinedButton.icon(onPressed:_selectPeriod,icon:const Icon(Icons.date_range_outlined),label:Text('${day(from)} — ${day(to)}')),
        SizedBox(width:250,child:DropdownButtonFormField<int>(initialValue:filter,
          decoration:const InputDecoration(labelText:'Empleado'),
          items:[const DropdownMenuItem<int>(value:null,child:Text('Todos los empleados')),
            ...employees.map((e)=>DropdownMenuItem<int>(value:id(e),child:Text('${e['full_name']}',overflow:TextOverflow.ellipsis)))],
          onChanged:(v){setState(()=>filter=v);load();},
        )),
        OutlinedButton.icon(onPressed:busy?null:load,icon:const Icon(Icons.refresh),label:const Text('Actualizar')),
        if(monthly)...[
          SizedBox(width:120,child:DropdownButtonFormField<String>(initialValue:paper,
            decoration:const InputDecoration(labelText:'Papel PDF'),
            items:const [DropdownMenuItem(value:'Carta',child:Text('Carta')),DropdownMenuItem(value:'A4',child:Text('A4'))],
            onChanged:(v){if(v!=null)setState(()=>paper=v);},
          )),
          FilledButton.icon(onPressed:busy||exporting||error!=null?null:_exportPdf,
            icon:exporting?const SizedBox(width:17,height:17,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.picture_as_pdf_outlined),
            label:Text(exporting?'Generando PDF...':'Exportar PDF del período'),
          ),
          OutlinedButton.icon(onPressed:rows.isEmpty?null:csv,icon:const Icon(Icons.copy_outlined),label:const Text('Copiar CSV')),
        ]else OutlinedButton.icon(onPressed:rows.isEmpty?null:csv,icon:const Icon(Icons.copy_outlined),label:const Text('Copiar CSV')),
      ])),
      const SizedBox(height:11),
      if(monthly)Wrap(spacing:8,runSpacing:8,crossAxisAlignment:WrapCrossAlignment.center,children:[
        Text('PERÍODO RÁPIDO',style:TextStyle(color:c.muted,fontSize:11,fontWeight:FontWeight.bold)),
        OutlinedButton(onPressed:()=>_setPeriod(DateTime.now(),DateTime.now()),child:const Text('Hoy')),
        OutlinedButton(onPressed:()=>_setPeriod(DateTime.now().subtract(const Duration(days:6)),DateTime.now()),child:const Text('7 días')),
        OutlinedButton(onPressed:()=>_setPeriod(DateTime.now().subtract(const Duration(days:29)),DateTime.now()),child:const Text('30 días')),
        OutlinedButton(onPressed:()=>_setPeriod(DateTime(DateTime.now().year,DateTime.now().month),DateTime(DateTime.now().year,DateTime.now().month+1,0)),child:const Text('Este mes')),
      ]),
      const SizedBox(height:18),
      if(monthly)Text('Indicadores del período',style:TextStyle(color:c.text,fontSize:19,fontWeight:FontWeight.bold)),
      if(monthly)const SizedBox(height:10),
      LayoutBuilder(builder:(context,limits){
        final width=(limits.maxWidth>=1050?(limits.maxWidth-30)/3:limits.maxWidth>=700?(limits.maxWidth-15)/2:limits.maxWidth);
        return Wrap(spacing:15,runSpacing:12,children:[
          SizedBox(width:width,child:_kpi('Registros de asistencia','${rows.length}',Icons.how_to_reg_outlined)),
          SizedBox(width:width,child:_kpi('Empleados con marcas','$unique',Icons.people_outline)),
          SizedBox(width:width,child:_kpi('Horas registradas',(total/60).toStringAsFixed(2),Icons.schedule_outlined)),
          SizedBox(width:width,child:_kpi('Jornadas sin salida','$open',Icons.warning_amber_rounded)),
        ]);
      }),
      if(busy)...[const SizedBox(height:10),const LinearProgressIndicator()],
      if(error!=null)...[const SizedBox(height:10),Text(error!,style:TextStyle(color:c.danger))],
      const SizedBox(height:22),
      if(monthly)...[
        Text('Detalle por empleado',style:TextStyle(color:c.text,fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:6),Text('Las marcas se muestran en tarjetas con tablas que se adaptan al ancho de pantalla.',style:TextStyle(color:c.muted,fontSize:12)),
        _reportTable(),
      ]else LayoutBuilder(builder:(ctx,limits){
        final visible=employees.where((e)=>filter==null||id(e)==filter).toList();
        return GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:visible.length,
          gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:limits.maxWidth>=1100?3:limits.maxWidth>=700?2:1,
            crossAxisSpacing:14,mainAxisSpacing:14,mainAxisExtent:395,
          ),itemBuilder:(ctx,i)=>employeeCard(visible[i]),
        );
      }),
      const SizedBox(height:16),
      Text('Nota: los registros provienen de las marcas del servidor. Este reporte no determina ausencias ni remuneraciones sin contrastar turnos y reglas laborales.',style:TextStyle(color:c.muted,fontSize:12)),
    ]);
  }
}
