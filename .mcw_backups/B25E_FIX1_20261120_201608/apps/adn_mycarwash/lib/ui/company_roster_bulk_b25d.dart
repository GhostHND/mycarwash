import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';
import 'company_employee_cards_24c3.dart';
import 'company_booking_page.dart';

/// B25E: tarjetas por empleado. El alta masiva reutiliza la API transaccional B25D.
class CompanyRosterBulkB25D extends StatefulWidget {
  const CompanyRosterBulkB25D({super.key});
  @override
  State<CompanyRosterBulkB25D> createState() => _RosterCardsState();
}
class _RosterCardsState extends State<CompanyRosterBulkB25D> {
  final http.Client _client = http.Client();
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  List<Map<String,dynamic>> _employees=[];
  List<Map<String,dynamic>> _shifts=[];
  List<Map<String,dynamic>> _rows=[];
  bool _loading=true;
  bool _legacy=false;
  String? _error;
  @override void initState(){super.initState();_load();}
  @override void dispose(){_client.close();super.dispose();}
  Future<void> _load() async {
    setState((){_loading=true;_error=null;});
    try {
      final results=await Future.wait([
        _api.request('GET','/schedule/options'),
        _api.request('GET','/schedule/roster',query:{'per_page':'200'}),
      ]);
      final options=Map<String,dynamic>.from(results[0]['data'] as Map);
      List<Map<String,dynamic>> rows(dynamic x)=>x is List?x.whereType<Map>().map((e)=>Map<String,dynamic>.from(e)).toList():[];
      if(mounted) {
        setState((){
          _employees=rows(options['employees']);_shifts=rows(options['shifts']);_rows=rows(results[1]['data']);
        });
      }
    }catch(e){if(mounted)setState(()=>_error='$e');}
    finally{if(mounted)setState(()=>_loading=false);}
  }
  int _id(Map<String,dynamic> m)=>int.tryParse('${m['id']}')??0;
  String _name(Map<String,dynamic> m)=>'${m['full_name']??'Empleado'}';
  List<Map<String,dynamic>> _for(int employeeId)=>_rows.where((r)=>int.tryParse('${r['employee_id']}')==employeeId).toList();
  Future<void> _assign(Map<String,dynamic> employee) async {
    final saved=await showDialog<bool>(context:context,barrierDismissible:false,builder:(ctx)=>_AssignmentDialog(
      employee:employee,shifts:_shifts,api:_api,
    ));
    if(saved==true) await _load();
  }
  Widget _tile(Map<String,dynamic> employee){
    final id=_id(employee);
    final existing=_for(id);
    final names=existing.map((r)=>'${r['shift_name']??r['shift_id']}').toSet().join(' · ');
    return Container(
      padding:const EdgeInsets.all(17),
      decoration:BoxDecoration(color:CompanyVisualTheme.card,border:Border.all(color:CompanyVisualTheme.primary.withValues(alpha:.65)),borderRadius:BorderRadius.circular(18)),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Expanded(child:Text(_name(employee),maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:CompanyVisualTheme.text,fontSize:20,fontWeight:FontWeight.bold))),Text(employee['is_active']==false?'Inactivo':'Activo',style:TextStyle(color:CompanyVisualTheme.primary,fontSize:12))]),
        const SizedBox(height:12),
        SizedBox(height:128,width:double.infinity,child:ClipRRect(borderRadius:BorderRadius.circular(13),child:CompanyEmployeePhoto24C3(client:_client,employeeId:id))),
        const SizedBox(height:12),
        Text('Cargo: ${employee['position']??'Lavador'}',style:TextStyle(color:CompanyVisualTheme.muted)),
        const SizedBox(height:5),
        Text('Turnos asignados: ${existing.length}',style:TextStyle(color:CompanyVisualTheme.text,fontWeight:FontWeight.w600)),
        const SizedBox(height:5),
        Text(names.isEmpty?'Sin turnos asignados':names,maxLines:3,overflow:TextOverflow.ellipsis,style:TextStyle(color:CompanyVisualTheme.muted)),
        const Spacer(),
        Divider(color:CompanyVisualTheme.border),
        Row(children:[Expanded(child:FilledButton.icon(onPressed:()=>_assign(employee),icon:const Icon(Icons.add_circle_outline),label:const Text('Asignar turnos'))),const SizedBox(width:7),IconButton(tooltip:'Administrar asignaciones',onPressed:()=>setState(()=>_legacy=true),icon:const Icon(Icons.edit_outlined))]),
      ]),
    );
  }
  @override Widget build(BuildContext context){
    if(_legacy) {
      return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        OutlinedButton.icon(onPressed:(){setState(()=>_legacy=false);_load();},icon:const Icon(Icons.arrow_back),label:const Text('Volver a tarjetas')),
        const SizedBox(height:12),const CompanyBookingPage(module:BookingModule.roster),
      ]);
    }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Wrap(crossAxisAlignment:WrapCrossAlignment.center,spacing:14,runSpacing:10,children:[
        Text('Asignaciones de turnos',style:TextStyle(color:CompanyVisualTheme.text,fontSize:26,fontWeight:FontWeight.bold)),
        IconButton(onPressed:_loading?null:_load,tooltip:'Actualizar',icon:const Icon(Icons.refresh)),
      ]),
      Text('Selecciona al lavador desde su tarjeta y marca todos los días que trabajará.',style:TextStyle(color:CompanyVisualTheme.muted)),
      if(_loading)const LinearProgressIndicator(),
      if(_error!=null)Text(_error!,style:const TextStyle(color:Colors.redAccent)),
      const SizedBox(height:18),
      LayoutBuilder(builder:(ctx,c){
        final cols=c.maxWidth>=1100?3:c.maxWidth>=700?2:1;
        return GridView.builder(shrinkWrap:true,physics:const NeverScrollableScrollPhysics(),itemCount:_employees.length,
          gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:cols,mainAxisSpacing:14,crossAxisSpacing:14,mainAxisExtent:355),
          itemBuilder:(ctx,i)=>_tile(_employees[i]));
      }),
      if(_employees.isEmpty&&!_loading)const Text('No se encontraron empleados.'),
    ]);
  }
}

class _AssignmentDialog extends StatefulWidget {
  const _AssignmentDialog({required this.employee,required this.shifts,required this.api});
  final Map<String,dynamic> employee;
  final List<Map<String,dynamic>> shifts;
  final CompanyBusinessApi api;
  @override State<_AssignmentDialog> createState()=>_AssignmentDialogState();
}
class _AssignmentDialogState extends State<_AssignmentDialog>{
  final Set<int> selected={};
  DateTime from=DateTime.now();
  DateTime? to;
  bool loading=false;
  String? error;
  static const days=['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];
  String date(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  Future<void> pick(bool end) async {
    final value=await showDatePicker(context:context,initialDate:end?(to??from):from,firstDate:DateTime(2020),lastDate:DateTime(2100));
    if(value!=null&&mounted)setState((){if(end){to=value;}else{from=value;if(to!=null&&to!.isBefore(from))to=null;}});
  }
  Future<void> save() async{
    if(selected.isEmpty||loading)return;
    setState((){loading=true;error=null;});
    try{
      final result=await widget.api.request('POST','/schedule/roster-bulk-b25d',body:{
        'employee_id':widget.employee['id'], 'shift_ids':selected.toList()..sort(),
        'effective_from':date(from),if(to!=null)'effective_to':date(to!),
      });
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Turnos guardados: ${result['created']}')));
      Navigator.pop(context,true);
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context){
    final groups=<int,List<Map<String,dynamic>>>{};
    for(final s in widget.shifts){final d=(s['day_of_week'] as num?)?.toInt()??0;groups.putIfAbsent(d,()=>[]).add(s);}
    return Dialog(backgroundColor:CompanyVisualTheme.card,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(20)),child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:670,maxHeight:740),child:Padding(padding:const EdgeInsets.all(22),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Asignar turnos · ${widget.employee['full_name']}',style:TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:CompanyVisualTheme.text)),
      const SizedBox(height:9),Text('Selecciona los turnos de los días que trabajará.',style:TextStyle(color:CompanyVisualTheme.muted)),
      const SizedBox(height:16),Expanded(child:ListView(children:[
        for(var i=1;i<=7;i++) if(groups.containsKey(i%7)) Padding(padding:const EdgeInsets.only(bottom:13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(days[i%7],style:TextStyle(fontWeight:FontWeight.w600,color:CompanyVisualTheme.text)),
          const SizedBox(height:6),Wrap(spacing:8,runSpacing:8,children:[for(final shift in groups[i%7]!) FilterChip(
            selected:selected.contains((shift['id'] as num).toInt()),label:Text('${shift['name']}'),onSelected:loading?null:(on)=>setState((){final id=(shift['id'] as num).toInt();if(on){selected.add(id);}else{selected.remove(id);}}),
          )]),
        ])),
        if(widget.shifts.isEmpty)const Text('Define los turnos en Turnos de trabajo antes de asignarlos.'),
        const SizedBox(height:12),Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton.icon(onPressed:loading?null:()=>pick(false),icon:const Icon(Icons.event),label:Text('Desde: ${date(from)}')),
          OutlinedButton.icon(onPressed:loading?null:()=>pick(true),icon:const Icon(Icons.event_available),label:Text(to==null?'Hasta: indefinido':'Hasta: ${date(to!)}')),
          if(to!=null)TextButton(onPressed:()=>setState(()=>to=null),child:const Text('Indefinido')),
        ]),
      ])),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.redAccent)),
      if(loading)const LinearProgressIndicator(),
      Row(mainAxisAlignment:MainAxisAlignment.end,children:[TextButton(onPressed:loading?null:()=>Navigator.pop(context,false),child:const Text('Cancelar')),const SizedBox(width:12),FilledButton(onPressed:loading||selected.isEmpty?null:save,child:Text('Guardar ${selected.length} turnos'))]),
    ]))));
  }
}
