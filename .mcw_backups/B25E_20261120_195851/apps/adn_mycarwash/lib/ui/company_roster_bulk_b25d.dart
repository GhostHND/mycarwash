import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';
import 'company_booking_page.dart';

/// Un empleado + varios turnos seleccionados en una sola operación atómica.
class CompanyRosterBulkB25D extends StatefulWidget {
  const CompanyRosterBulkB25D({super.key});
  @override State<CompanyRosterBulkB25D> createState()=>_RosterState();
}
class _RosterState extends State<CompanyRosterBulkB25D> {
  final http.Client _client = http.Client();
  CompanyBusinessApi get _api => CompanyBusinessApi(_client);
  List<Map<String,dynamic>> _employees=[];
  List<Map<String,dynamic>> _shifts=[];
  List<Map<String,dynamic>> _rows=[];
  final Set<int> _selected={};
  int? _employee;
  bool _busy=false;
  bool _legacy=false;
  String? _error;
  DateTime _from=DateTime.now();
  DateTime? _to;
  @override void initState(){super.initState();_load();}
  @override void dispose(){_client.close();super.dispose();}
  static String _date(DateTime d)=>'${d.year.toString().padLeft(4,'0')}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
  static const _days=['Domingo','Lunes','Martes','Miércoles','Jueves','Viernes','Sábado'];
  Future<void> _load() async {
    setState((){_busy=true;_error=null;});
    try {
      final results=await Future.wait([
        _api.request('GET','/schedule/options'),
        _api.request('GET','/schedule/roster',query:{'per_page':'50'}),
      ]);
      final opt=Map<String,dynamic>.from(results[0]['data'] as Map);
      List<Map<String,dynamic>> maps(dynamic v)=>v is List?v.whereType<Map>().map((r)=>Map<String,dynamic>.from(r)).toList():[];
      if (mounted) {
        setState(() {
          _employees=maps(opt['employees']);_shifts=maps(opt['shifts']);_rows=maps(results[1]['data']);
        });
      }
    }catch(e){if(mounted)setState(()=>_error='$e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  Future<void> _chooseDate(bool isEnd) async {
    final picked=await showDatePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime(2100),initialDate:isEnd?(_to??_from):_from);
    if(picked!=null&&mounted)setState((){if(isEnd){_to=picked;}else{_from=picked;if(_to!=null&&_to!.isBefore(picked))_to=null;}});
  }
  Future<void> _save() async {
    if(_employee==null||_selected.isEmpty)return;
    setState((){_busy=true;_error=null;});
    try{
      final result=await _api.request('POST','/schedule/roster-bulk-b25d',body:{
        'employee_id':_employee,'shift_ids':_selected.toList()..sort(),
        'effective_from':_date(_from),if(_to!=null)'effective_to':_date(_to!),
      });
      if(!mounted)return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Asignaciones guardadas: ${result['created']}')));
      setState(()=>_selected.clear());
      await _load();
    }catch(e){if(mounted)setState(()=>_error='$e');}
    finally{if(mounted)setState(()=>_busy=false);}
  }
  @override Widget build(BuildContext context){
    final groups=<int,List<Map<String,dynamic>>>{};
    for(final s in _shifts){final d=(s['day_of_week'] as num?)?.toInt()??0;groups.putIfAbsent(d,()=>[]).add(s);}
    if (_legacy) { return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      OutlinedButton.icon(onPressed:()=>setState(()=>_legacy=false),icon:const Icon(Icons.arrow_back),label:const Text('Volver a asignación semanal')),
      const SizedBox(height:12),
      const CompanyBookingPage(module:BookingModule.roster),
    ]); }
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Asignación semanal de lavadores',style:TextStyle(fontSize:25,fontWeight:FontWeight.w700,color:CompanyVisualTheme.text)),
      const SizedBox(height:8),Text('Selecciona un lavador y todos los turnos que cubrirá. Se guardarán juntos, sin duplicar operaciones manuales.',style:TextStyle(color:CompanyVisualTheme.muted)),
      const SizedBox(height:18),
      Container(padding:const EdgeInsets.all(18),decoration:BoxDecoration(color:CompanyVisualTheme.card,borderRadius:BorderRadius.circular(18),border:Border.all(color:CompanyVisualTheme.border)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        SizedBox(width:420,child:DropdownButtonFormField<int>(initialValue:_employee,decoration:const InputDecoration(labelText:'Lavador'),isExpanded:true,items:_employees.map((e)=>DropdownMenuItem(value:(e['id'] as num).toInt(),child:Text('${e['full_name']}',overflow:TextOverflow.ellipsis))).toList(),onChanged:_busy?null:(v)=>setState(()=>_employee=v))),
        const SizedBox(height:18),Text('Marca los días y turnos',style:TextStyle(color:CompanyVisualTheme.text,fontWeight:FontWeight.w700)),
        const SizedBox(height:10),
        for(var d=1;d<=7;d++) if(groups.containsKey(d%7)) Padding(padding:const EdgeInsets.only(bottom:13),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(_days[d%7],style:TextStyle(color:CompanyVisualTheme.muted,fontWeight:FontWeight.w600)),
          const SizedBox(height:6),Wrap(spacing:8,runSpacing:8,children:[for(final shift in groups[d%7]!) FilterChip(
            label:Text('${shift['name']}'),selected:_selected.contains((shift['id'] as num).toInt()),
            onSelected:_busy?null:(on)=>setState((){final id=(shift['id'] as num).toInt();if(on){_selected.add(id);}else{_selected.remove(id);}}),
          )]),
        ])),
        if(_shifts.isEmpty)const Text('No hay turnos activos. Primero define los horarios en «Turnos de trabajo». '),
        const SizedBox(height:12),Wrap(spacing:12,runSpacing:10,crossAxisAlignment:WrapCrossAlignment.center,children:[
          OutlinedButton.icon(onPressed:_busy?null:()=>_chooseDate(false),icon:const Icon(Icons.calendar_today_outlined),label:Text('Desde: ${_date(_from)}')),
          OutlinedButton.icon(onPressed:_busy?null:()=>_chooseDate(true),icon:const Icon(Icons.event_outlined),label:Text(_to==null?'Hasta: indefinido':'Hasta: ${_date(_to!)}')),
          if(_to!=null)TextButton(onPressed:()=>setState(()=>_to=null),child:const Text('Sin fecha final')),
        ]),
        const SizedBox(height:12),FilledButton.icon(onPressed:_busy||_employee==null||_selected.isEmpty?null:_save,icon:const Icon(Icons.save_outlined),label:Text('Guardar ${_selected.length} turnos seleccionados')),
        if(_busy)const Padding(padding:EdgeInsets.only(top:10),child:LinearProgressIndicator()),
        if(_error!=null)Padding(padding:const EdgeInsets.only(top:12),child:Text(_error!,style:const TextStyle(color:Colors.redAccent))),
      ])),
      const SizedBox(height:20),Row(children:[OutlinedButton.icon(onPressed:()=>setState(()=>_legacy=true),icon:const Icon(Icons.edit_outlined),label:const Text('Administrar asignaciones existentes')),const SizedBox(width:14),Expanded(child:Text('Asignaciones existentes',style:TextStyle(fontSize:19,fontWeight:FontWeight.w700,color:CompanyVisualTheme.text))),IconButton(onPressed:_busy?null:_load,icon:const Icon(Icons.refresh))]),
      const SizedBox(height:8),
      ..._rows.map((r)=>Container(margin:const EdgeInsets.only(bottom:8),padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:CompanyVisualTheme.card,border:Border.all(color:CompanyVisualTheme.border),borderRadius:BorderRadius.circular(14)),child:Wrap(spacing:16,runSpacing:8,children:[
        Text('${r['employee_name']??r['employee_id']}',style:TextStyle(fontWeight:FontWeight.w700,color:CompanyVisualTheme.text)),
        Text('${r['shift_name']??r['shift_id']}'),Text('Desde: ${r['effective_from']}'),Text('Hasta: ${r['effective_to']??'Indefinido'}'),
      ]))),
      if(_rows.isEmpty&&!_busy)const Text('Sin asignaciones registradas.'),
      Text('Se muestran hasta 50 registros recientes. Las asignaciones existentes se conservan.',style:TextStyle(color:CompanyVisualTheme.muted,fontSize:12)),
    ]);
  }
}
