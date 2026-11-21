import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
        'from':day(month),'to':day(DateTime(month.year,month.month+1,0)),if(filter!=null)'employee_id':'$filter',
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
      const SizedBox(height:12),Text('Historial · ${month.year}-${month.month.toString().padLeft(2,'0')}',style:TextStyle(fontSize:18,color:CompanyVisualTheme.text,fontWeight:FontWeight.w700)),
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
  @override Widget build(BuildContext context){
    final total=rows.fold<int>(0,(sum,r)=>sum+minutes(r));
    final unique=rows.map((r)=>'${r['employee_id']}').toSet().length;
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(widget.monthlyReport?'Reporte mensual de asistencia':'Historial de asistencia',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold,color:CompanyVisualTheme.text)),
      const SizedBox(height:5),Text('Consulta las entradas y salidas del personal por mes.',style:TextStyle(color:CompanyVisualTheme.muted)),
      const SizedBox(height:14),Container(padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:CompanyVisualTheme.card,border:Border.all(color:CompanyVisualTheme.border),borderRadius:BorderRadius.circular(16)),child:Wrap(spacing:12,runSpacing:12,crossAxisAlignment:WrapCrossAlignment.center,children:[
        IconButton(onPressed:(){setState(()=>month=DateTime(month.year,month.month-1));load();},icon:const Icon(Icons.chevron_left)),
        Text('${month.year}-${month.month.toString().padLeft(2,'0')}',style:TextStyle(color:CompanyVisualTheme.text,fontWeight:FontWeight.bold)),
        IconButton(onPressed:(){setState(()=>month=DateTime(month.year,month.month+1));load();},icon:const Icon(Icons.chevron_right)),
        SizedBox(width:250,child:DropdownButtonFormField<int>(initialValue:filter,decoration:const InputDecoration(labelText:'Empleado'),items:[const DropdownMenuItem<int>(value:null,child:Text('Todos los empleados')),...employees.map((e)=>DropdownMenuItem<int>(value:id(e),child:Text('${e['full_name']}',overflow:TextOverflow.ellipsis)))],onChanged:(v){setState(()=>filter=v);load();})),
        OutlinedButton.icon(onPressed:busy?null:load,icon:const Icon(Icons.refresh),label:const Text('Actualizar')),
        OutlinedButton.icon(onPressed:rows.isEmpty?null:csv,icon:const Icon(Icons.copy_outlined),label:const Text('Copiar CSV')),
      ])),
      const SizedBox(height:12),Wrap(spacing:12,runSpacing:10,children:[
        _metric('Registros',rows.length.toString()),_metric('Empleados',unique.toString()),_metric('Horas registradas',(total/60).toStringAsFixed(2)),_metric('Sin salida',rows.where((r)=>r['check_out_at']==null).length.toString()),
      ]),
      if(busy)const LinearProgressIndicator(),if(error!=null)Text(error!,style:const TextStyle(color:Colors.redAccent)),
      const SizedBox(height:16),
      if(widget.monthlyReport) ...[
        Text('Detalle mensual',style:TextStyle(color:CompanyVisualTheme.text,fontSize:19,fontWeight:FontWeight.w700)),
        const SizedBox(height:9),
        ...rows.map((r)=>Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:CompanyVisualTheme.card,border:Border.all(color:CompanyVisualTheme.border),borderRadius:BorderRadius.circular(14)),child:Wrap(spacing:18,runSpacing:8,children:[Text('${r['full_name']}',style:TextStyle(fontWeight:FontWeight.bold,color:CompanyVisualTheme.text)),Text('${r['work_date']}'),Text('Entrada: ${clock(r['check_in_at'])}'),Text('Salida: ${clock(r['check_out_at'])}'),Text('${(minutes(r)/60).toStringAsFixed(2)} h')]))),
      ]else LayoutBuilder(builder:(ctx,c)=>GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:employees.where((e)=>filter==null||id(e)==filter).length,
        gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:c.maxWidth>=1100?3:c.maxWidth>=700?2:1,crossAxisSpacing:14,mainAxisSpacing:14,mainAxisExtent:395),
        itemBuilder:(ctx,i)=>employeeCard(employees.where((e)=>filter==null||id(e)==filter).elementAt(i)))),
      if(rows.isEmpty&&!busy&&widget.monthlyReport)const Text('No se registraron asistencias en el mes.'),
      const SizedBox(height:12),Text('Los tiempos se calculan con las marcas del servidor; una ausencia requiere contrastar el horario asignado.',style:TextStyle(color:CompanyVisualTheme.muted,fontSize:12)),
    ]);
  }
  Widget _metric(String title,String value)=>Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:CompanyVisualTheme.card,border:Border.all(color:CompanyVisualTheme.border),borderRadius:BorderRadius.circular(14)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:TextStyle(color:CompanyVisualTheme.muted)),const SizedBox(height:4),Text(value,style:TextStyle(fontSize:20,fontWeight:FontWeight.bold,color:CompanyVisualTheme.text))]));
}
