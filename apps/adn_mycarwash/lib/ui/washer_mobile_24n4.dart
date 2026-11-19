import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';
import '../core/business_identity.dart';
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';
import '../core/mycarwash_session.dart';

// ADN MyCarWash: cinco destinos exclusivos de la aplicación nativa del lavador.
// Los colores se derivan de la identidad de la empresa; el tema base es claro.
class WasherMobileColors {
  static const base = Color(0xFF0FA7B4);
  static const ink = Color(0xFF111827);
  static const grey = Color(0xFF64748B);
  static const line = Color(0xFFE5E7EB);
  static const pale = Color(0xFFE8F8F9);
  static const paper = Color(0xFFFFFFFF);

  static Color get primary {
    final c = CompanyVisualTheme.primary;
    // El sistema administrativo predeterminado usa otro matiz de turquesa;
    // la variante móvil clara conserva el matiz de la referencia original.
    return c == const Color(0xFF00DCE5) ? base : c;
  }
  static Color get success => CompanyVisualTheme.success;
  static Color get warning => CompanyVisualTheme.warning;
  static Color get danger => CompanyVisualTheme.danger;
  static Color get outline => CompanyVisualTheme.border == const Color(0xFF17434B)
      ? line : CompanyVisualTheme.border;
  static Color get background => CompanyVisualTheme.background == const Color(0xFF050C0F)
      ? paper : CompanyVisualTheme.background;
  static Color get card => CompanyVisualTheme.card == const Color(0xFF071F23)
      ? paper : CompanyVisualTheme.card;
  static Color get text => CompanyVisualTheme.text == const Color(0xFFF4F7F8)
      ? ink : CompanyVisualTheme.text;
  static Color get muted => CompanyVisualTheme.muted == const Color(0xFFA5B6BB)
      ? grey : CompanyVisualTheme.muted;
}

class WasherMobile24N4 extends StatefulWidget {
  const WasherMobile24N4({super.key, this.client});
  final http.Client? client;
  static const destinations = ['Inicio', 'Órdenes de lavado', 'Escanear QR', 'Calendario', 'Perfil'];
  @override
  State<WasherMobile24N4> createState() => _WasherMobile24N4State();
}

class _WasherMobile24N4State extends State<WasherMobile24N4> {
  late final http.Client _client;
  late final bool _ownsClient;
  late final CompanyBusinessApi _api;
  int _tab = 0;
  int _page = 1;
  int _lastPage = 1;
  String _status = 'TODAS';
  final _search = TextEditingController();
  Timer? _clock;
  DateTime _now = DateTime.now();
  DateTime _selected = DateTime.now();
  List<Map<String, dynamic>> _orders = [];
  List<Map<String, dynamic>> _agenda = [];
  Map<String, dynamic> _counts = {};
  Map<String, dynamic> _profile = {};
  Map<String, dynamic> _summary = {};
  bool _onDuty = false;
  bool _busy = false;
  bool _loading = true;
  String? _error;
  bool _scannerBusy = false;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _client = widget.client ?? http.Client();
    _api = CompanyBusinessApi(_client);
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _tab == 0) setState(() => _now = DateTime.now());
    });
    BusinessIdentity.refresh(client: _client).then((_) {
      if (mounted) setState(() {});
    });
    _refresh();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _search.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  static List<Map<String, dynamic>> _toRows(dynamic v) => v is List
      ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
      : <Map<String, dynamic>>[];
  static String _date(DateTime v) => '${v.year.toString().padLeft(4,'0')}-${v.month.toString().padLeft(2,'0')}-${v.day.toString().padLeft(2,'0')}';
  static String _read(Map<String, dynamic> r, String key, [String blank = '']) {
    final v = (r[key] ?? '').toString().trim();
    return v.isEmpty ? blank : v;
  }
  static int _int(dynamic v) => int.tryParse('$v') ?? 0;
  Color get turquoise => WasherMobileColors.primary;
  Color get ink => WasherMobileColors.text;
  Color get muted => WasherMobileColors.muted;
  Color get outline => WasherMobileColors.outline;

  Future<void> _refresh() async {
    if (!MyCarWashSession.isWasher || !MyCarWashSession.isAuthenticated) return;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _api.request('GET','/washer/orders',query: {'page':'$_page','status':_status,'q':_search.text.trim()}),
        _api.request('GET','/washer/me'),
        _api.request('GET','/washer/agenda',query: {'view':'month','date':_date(_selected)}),
        _api.request('GET','/washer/attendance',query: {'month':_date(_selected).substring(0,7)}),
        _api.request('GET','/washer/summary'),
      ]);
      if (!mounted) return;
      setState(() {
        _orders = _toRows(results[0]['data']);
        _lastPage = _int(results[0]['last_page']);
        _counts = results[0]['status_counts'] is Map ? Map<String,dynamic>.from(results[0]['status_counts']) : {};
        _profile = results[1]['user'] is Map ? Map<String,dynamic>.from(results[1]['user']) : {};
        _agenda = _toRows(results[2]['data']);
        _onDuty = results[3]['on_duty'] == true;
        _summary = Map<String,dynamic>.from(results[4]);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _switch(int target) {
    if (_busy) return;
    if(target == 0) {_page = 1;_status = 'TODAS';_search.clear();}
    setState(() { _tab = target; _error = null; });
    _refresh();
  }

  void _message(String msg) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool> _action(String path, Map<String,dynamic> body, {String method = 'POST'}) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      final response = await _api.request(method,path,body:body);
      if (!mounted) return false;
      _message(_read(response,'message','Operación completada.'));
      // Cambiar contraseña revoca la sesión actual desde Laravel.
      // No consultar de nuevo con un token que ya no es válido.
      if (path != '/washer/password') await _refresh();
      return true;
    } catch(e) {
      if (mounted) _message('$e');
      return false;
    } finally { if (mounted) setState(() => _busy = false); }
  }

  Future<void> _logout() async {
    try {
      await _client.post(Uri.parse('${MyCarWashSession.apiBaseUrl}/auth/logout'),
        headers: MyCarWashSession.headers).timeout(const Duration(seconds: 5));
    } catch (_) { /* La sesión local se elimina igualmente. */ }
    MyCarWashSession.clear();
    BusinessIdentity.reset();
    if (mounted) Navigator.of(context).pop();
  }

  Widget _surface(Widget child, {EdgeInsets padding = const EdgeInsets.all(15)}) =>
    Container(padding:padding,decoration:BoxDecoration(
      color:WasherMobileColors.card, borderRadius:BorderRadius.circular(15),
      border:Border.all(color:outline)),child:child);

  Widget _heading(String text, {String? subtitle}) => Padding(
    padding: const EdgeInsets.only(bottom:12,top:4), child:Column(crossAxisAlignment:CrossAxisAlignment.start, children:[
      Text(text,style:TextStyle(fontSize:20,fontWeight:FontWeight.w800,color:ink)),
      if (subtitle != null) Text(subtitle, style:TextStyle(fontSize:11,color:muted)),
    ]));

  Widget _chip(String value, Color bg, Color fg) => Container(
    padding: const EdgeInsets.symmetric(horizontal:10,vertical:5),
    decoration:BoxDecoration(color:bg,borderRadius:BorderRadius.circular(18)),
    child:Text(value,style:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:fg)));

  String _statusText(String state) => switch(state) {
    'ASIGNADO' => 'En espera', 'EN_ESPERA' => 'Nueva', 'EN_PROCESO' => 'En proceso',
    'TERMINADO' => 'Terminada', 'ENTREGADO' => 'Entregada',
    'CANCELADO' => 'Cancelada', _ => state,
  };
  Color _statusBg(String state) => switch(state) {
    'ASIGNADO' => const Color(0xFFFFF4CC), 'EN_ESPERA' => const Color(0xFFE5F3FF),
    'EN_PROCESO' => const Color(0xFFDDF8FA), 'TERMINADO' || 'ENTREGADO' => const Color(0xFFDAF8E7),
    _ => const Color(0xFFF3F4F6),
  };
  Color _statusFg(String state) => switch(state) {
    'ASIGNADO' => const Color(0xFFAB6600), 'EN_PROCESO' => const Color(0xFF008D98),
    'TERMINADO' || 'ENTREGADO' => const Color(0xFF11803B),
    _ => const Color(0xFF2864A1),
  };

  Widget _statusBadge(String state) => _chip(_statusText(state),_statusBg(state),_statusFg(state));
  // La placa no debe truncarse en teléfonos estrechos.
  Widget _plate(String plate) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      border: Border.all(color: turquoise),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.badge_outlined, color: turquoise, size: 14),
      const SizedBox(width: 4),
      Flexible(child: Text(
        plate,
        softWrap: true,
        style: TextStyle(color: ink, fontWeight: FontWeight.bold, fontSize: 11),
      )),
    ]),
  );

  // BoxFit.contain preserva todo el vehículo sin recortar la fotografía.
  Widget _vehiclePhoto(dynamic id, {double width = 82, double height = 60}) {
    final vehicleId = _int(id);
    final placeholder = Center(child: Icon(
      Icons.directions_car_filled_outlined, color: muted, size: 34));
    return Container(
      width: width,
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFB),
        borderRadius: BorderRadius.circular(10),
      ),
      child: vehicleId <= 0
        ? placeholder
        : Image.network(
            '${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/washer/photo/vehicles/$vehicleId',
            headers: MyCarWashSession.headers,
            fit: BoxFit.contain,
            alignment: Alignment.center,
            errorBuilder: (context, error, stackTrace) => placeholder,
          ),
    );
  }

  Widget _header() => ValueListenableBuilder<BusinessIdentityData>(
    valueListenable: BusinessIdentity.current,
    builder:(context, identity, _) => Container(
      color:WasherMobileColors.background, padding:const EdgeInsets.fromLTRB(16,8,16,10),
      child:Row(children:[
        Image.asset('assets/branding/logo_adn.png',width:130,height:61,fit:BoxFit.contain),
        const Spacer(),
        Container(width:65,height:62,padding:const EdgeInsets.all(4),decoration:BoxDecoration(
          borderRadius:BorderRadius.circular(13),color:WasherMobileColors.pale,
          border:Border.all(color:turquoise.withValues(alpha:.25))),
          child:identity.logoBytes == null
          ? Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.local_car_wash,color:turquoise),
            Text('Mi empresa',textAlign:TextAlign.center,style:TextStyle(color:ink,fontSize:9))])
          : Image.memory(identity.logoBytes!,fit:BoxFit.contain,semanticLabel:identity.companyName)),
      ])));

  Widget _navigation() => Container(
    decoration:BoxDecoration(color:WasherMobileColors.background,border:Border(top:BorderSide(color:outline))),
    child:SafeArea(top:false,child:Padding(padding:const EdgeInsets.only(top:7,bottom:3),
      child:Row(children:List.generate(5,(index){
        final icons = [Icons.home_outlined,Icons.directions_car_outlined,Icons.qr_code_scanner,
          Icons.calendar_month_outlined,Icons.person_outline];
        final short = ['Inicio','Órdenes\nde lavado','Escanear QR\n(Asistencia)','Calendario\nde reservas','Perfil'];
        final active = index == _tab;
        return Expanded(child:InkWell(onTap:()=>_switch(index),child:Column(
          mainAxisSize:MainAxisSize.min,children:[
            Icon(icons[index],size:24,color:active?turquoise:muted),
            const SizedBox(height:2),
            Text(short[index],textAlign:TextAlign.center,maxLines:2,
              style:TextStyle(fontSize:10,height:1.1,fontWeight:active?FontWeight.bold:FontWeight.normal,
                color:active?turquoise:ink)),
          ])));
      })))));

  String _elapsed(Map<String,dynamic> order) {
    final raw = _read(order,'started_at');
    if(raw.isEmpty) return '--:--:--';
    final parsed = DateTime.tryParse(raw.endsWith('Z') ? raw : '${raw.replaceFirst(' ','T')}Z');
    if(parsed == null) return '--:--:--';
    final total = _now.difference(parsed.toLocal()).inSeconds;
    if(total < 0) return '00:00:00';
    final h = (total ~/ 3600).toString().padLeft(2,'0');
    final m = ((total % 3600) ~/ 60).toString().padLeft(2,'0');
    final s = (total % 60).toString().padLeft(2,'0');
    return '$h:$m:$s';
  }

  double _progress(Map<String,dynamic> order) {
    final elapsed = _elapsed(order).split(':');
    if(elapsed.length != 3 || elapsed.any((part) => int.tryParse(part) == null)) return 0;
    final elapsedSeconds = _int(elapsed[0])*3600 + _int(elapsed[1])*60 + _int(elapsed[2]);
    final expected = _int(order['estimated_minutes']);
    return expected < 1 ? 0 : (elapsedSeconds / (expected*60)).clamp(0.0,1.0);
  }

  // Los detalles deben desplazarse y respetar los controles del sistema Android.
  void _detail(Map<String, dynamic> order) {
    final state = _read(order, 'status');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: WasherMobileColors.background,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SafeArea(
          top: false,
          maintainBottomViewPadding: true,
          minimum: const EdgeInsets.only(bottom: 20),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.83,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                _heading(
                  '${_read(order,'brand')} ${_read(order,'model')}'.trim(),
                  subtitle: 'Orden ${_read(order,'tracking_code')}',
                ),
                _vehiclePhoto(order['vehicle_id'], width: double.infinity, height: 204),
                const SizedBox(height: 15),
                Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  _plate(_read(order, 'plate', 'Sin placa')),
                  _statusBadge(state),
                ]),
                const SizedBox(height: 13),
                Text('Servicio: ${_read(order,'service_name','Sin registrar')}', style: TextStyle(color: ink)),
                const SizedBox(height: 5),
                Text('Cliente: ${_read(order,'client_name','No registrado')}', style: TextStyle(color: muted)),
                const SizedBox(height: 5),
                Text('Bahía: ${_read(order,'bay_name','Sin asignar')}', style: TextStyle(color: muted)),
                const SizedBox(height: 18),
                if ((state == 'ASIGNADO' || state == 'EN_PROCESO')
                    && order['worker_finished'] != true)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: turquoise,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(52),
                      ),
                      onPressed: _busy ? null : () {
                        Navigator.pop(ctx);
                        _action(
                          '/washer/orders/${order['id']}/${state == 'EN_PROCESO' ? 'finish' : 'start'}',
                          {'expected_version': _int(order['version'])},
                        );
                      },
                      icon: Icon(state == 'EN_PROCESO' ? Icons.check_circle_outline : Icons.play_arrow),
                      label: Text(state == 'EN_PROCESO' ? 'Finalizar mi lavado' : 'Iniciar lavado'),
                    ),
                  ),
                if (!['ASIGNADO', 'EN_PROCESO'].contains(state) || order['worker_finished'] == true)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      order['worker_finished'] == true
                        ? 'Tu participación ya finalizó; el equipo puede seguir trabajando.'
                        : 'Trabajo de solo lectura.',
                      softWrap: true,
                      style: TextStyle(color: muted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _home() {
    final current = _summary['active'] is Map ? Map<String,dynamic>.from(_summary['active'] as Map) : null;
    final upcoming = _summary['next'] is Map ? Map<String,dynamic>.from(_summary['next'] as Map) : null;
    final done = _int(_summary['completed_today']);
    final pending = _int(_summary['pending']);
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _surface(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Row(children:[Expanded(child:Text('Lavado activo',style:TextStyle(color:ink,fontSize:18,fontWeight:FontWeight.w800))),
          if(current!=null)_statusBadge(_read(current,'status'))]),
        const SizedBox(height:13),
        if(current==null) Padding(padding:const EdgeInsets.symmetric(vertical:18),
          child:Text('No tienes lavados activos.',style:TextStyle(color:muted)))
        else ...[
          Row(children:[_vehiclePhoto(current['vehicle_id'],width:114,height:94),const SizedBox(width:10),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text('${_read(current,'brand')} ${_read(current,'model')}',maxLines:2,
                style:TextStyle(color:ink,fontSize:17,fontWeight:FontWeight.w800)),
              const SizedBox(height:5),_plate(_read(current,'plate','Sin placa')),
              const SizedBox(height:4),Text('Orden ${_read(current,'tracking_code')}',
                softWrap:true,style:TextStyle(color:muted,fontSize:11)),
              Text(_read(current,'service_name'),softWrap:true,style:TextStyle(color:muted,fontSize:11)),
            ]))]),const SizedBox(height:12),
          Row(children:[Text('Tiempo transcurrido',style:TextStyle(color:muted)),const Spacer(),
            Text(_elapsed(current),style:TextStyle(color:ink,fontWeight:FontWeight.w800,fontSize:16))]),
          const SizedBox(height:7),ClipRRect(borderRadius:BorderRadius.circular(6),
            child:LinearProgressIndicator(value:_progress(current),minHeight:7,
              color:turquoise,backgroundColor:const Color(0xFFE8EAED))),
          const SizedBox(height:12),SizedBox(width:double.infinity,
            child:FilledButton.icon(onPressed:()=>_detail(current),
              style:FilledButton.styleFrom(backgroundColor:turquoise,foregroundColor:Colors.white),
              icon:const Icon(Icons.check_circle_outline),label:const Text('Continuar lavado'))),
        ],
      ])),const SizedBox(height:18),
      _heading('Resumen de hoy'),
      _surface(Row(children:[_summaryItem('Completados','$done',Icons.check_circle_outline),
        _verticalLine(),_summaryItem('Pendientes','$pending',Icons.schedule),
        _verticalLine(),_summaryItem('En cola',upcoming == null?'0':'1',Icons.layers_outlined)]),
        padding:const EdgeInsets.symmetric(vertical:14,horizontal:4)),
      const SizedBox(height:19),_heading('Siguiente trabajo'),
      if(upcoming==null) _surface(Text('No tienes trabajos pendientes.',style:TextStyle(color:muted)))
      else InkWell(onTap:()=>_detail(upcoming),child:_surface(Row(children:[
        _vehiclePhoto(upcoming['vehicle_id'],width:70,height:48),const SizedBox(width:11),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('${_read(upcoming,'brand')} ${_read(upcoming,'model')}',style:TextStyle(color:ink,fontWeight:FontWeight.bold)),
          _plate(_read(upcoming,'plate','Sin placa')),
          Text('Orden ${_read(upcoming,'tracking_code')} · ${_read(upcoming,'service_name')}',
            maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(color:muted,fontSize:10)),
        ])),Icon(Icons.chevron_right,color:ink)]))),
      const SizedBox(height:18),_heading('Accesos rápidos'),
      Row(children:[Expanded(child:_quick('Ver trabajos',Icons.checklist_outlined,()=>_switch(1))),
        const SizedBox(width:9),Expanded(child:_quick('Mi perfil',Icons.person_outline,()=>_switch(4)))]),
    ]);
  }
  Widget _verticalLine() => Container(width:1,height:35,color:outline);
  Widget _summaryItem(String title,String num,IconData icon) => Expanded(child:Column(children:[
    Row(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(icon,color:muted,size:16),const SizedBox(width:3),
      Flexible(child:Text(title,maxLines:1,style:TextStyle(color:ink,fontSize:10)))]),
    Text(num,style:TextStyle(color:ink,fontSize:20,fontWeight:FontWeight.w800)),
  ]));
  Widget _quick(String label,IconData icon,VoidCallback callback) => InkWell(onTap:callback,
    child:_surface(Row(children:[Icon(icon,color:muted),const SizedBox(width:8),
      Expanded(child:Text(label,style:TextStyle(color:ink,fontWeight:FontWeight.w700,fontSize:12))),
      Icon(Icons.chevron_right,color:ink,size:18)]),padding:const EdgeInsets.all(10)));

  Widget _ordersView() {
    const options = ['TODAS','EN_ESPERA','ASIGNADO','EN_PROCESO','TERMINADO','ENTREGADO'];
    const labels = ['Todas','Nuevas','En espera','En proceso','Terminadas','Entregadas'];
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[Expanded(child:_heading('Órdenes de lavado',subtitle:'Control y seguimiento de tus vehículos.')),
        IconButton(tooltip:'Actualizar',onPressed:_refresh,icon:Icon(Icons.refresh,color:turquoise))]),
      Row(children:[
        _smallStat('Nuevas',_counts['EN_ESPERA'],const Color(0xFFE5F3FF)),
        _smallStat('En espera',_counts['ASIGNADO'],const Color(0xFFFFF4CC)),
        _smallStat('En proceso',_counts['EN_PROCESO'],const Color(0xFFE0F7F8)),
        _smallStat('Terminadas',_counts['TERMINADO'],const Color(0xFFDAF8E7)),
      ]),const SizedBox(height:13),
      TextField(controller:_search,style:TextStyle(color:ink),
        decoration:InputDecoration(prefixIcon:Icon(Icons.search,color:muted),
        hintText:'Buscar por placa, vehículo u orden...',hintStyle:TextStyle(color:muted,fontSize:12),
        fillColor:WasherMobileColors.paper,filled:true,border:OutlineInputBorder(
          borderSide:BorderSide(color:outline),borderRadius:BorderRadius.circular(27))),
        onSubmitted:(_) { _page=1;_refresh(); },
        textInputAction:TextInputAction.search),
      const SizedBox(height:9),SingleChildScrollView(scrollDirection:Axis.horizontal,
        child:Row(children:List.generate(options.length,(i){final active=_status==options[i];
          return Padding(padding:const EdgeInsets.only(right:5),child:TextButton(
            onPressed:(){_status=options[i];_page=1;_refresh();},
            style:TextButton.styleFrom(foregroundColor:active?Colors.white:ink,
              backgroundColor:active?turquoise:Colors.transparent),child:Text(labels[i],style:const TextStyle(fontSize:11))));
        }))),const SizedBox(height:10),
      if (_orders.isEmpty)
        _surface(Text('No tienes órdenes para estos filtros.', style: TextStyle(color: muted)))
      else
        ..._orders.map((order) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _orderCard(order),
        )),

      const SizedBox(height:9),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[
        TextButton(onPressed:_page<=1?null:(){_page--;_refresh();},child:const Text('Anterior')),
        Text('Página $_page de $_lastPage',style:TextStyle(fontSize:11,color:ink)),
        TextButton(onPressed:_page>=_lastPage?null:(){_page++;_refresh();},child:const Text('Siguiente')),
      ])
    ]);
  }
  // Diseño adaptativo: código y estado arriba, foto y datos al centro,
  // bahía e importe abajo. Ninguna columna estrecha debe recortar placas o servicios.
  Widget _orderCard(Map<String, dynamic> order) => InkWell(
    onTap: () => _detail(order),
    borderRadius: BorderRadius.circular(15),
    child: _surface(Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(
            _read(order, 'tracking_code'),
            softWrap: true,
            style: TextStyle(color: ink, fontSize: 11, fontWeight: FontWeight.w800),
          )),
          const SizedBox(width: 8),
          _statusBadge(_read(order, 'status')),
        ]),
        const SizedBox(height: 10),
        LayoutBuilder(builder: (context, constraints) {
          final photoWidth = (constraints.maxWidth * 0.34).clamp(88.0, 130.0).toDouble();
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _vehiclePhoto(order['vehicle_id'], width: photoWidth, height: 102),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_read(order,'brand')} ${_read(order,'model')}'.trim(),
                  softWrap: true,
                  style: TextStyle(color: ink, fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                _plate(_read(order, 'plate', 'Sin placa')),
                const SizedBox(height: 7),
                Text('Cliente: ${_read(order,'client_name','No registrado')}',
                  softWrap: true, style: TextStyle(color: muted, fontSize: 11)),
                Text('Servicio: ${_read(order,'service_name','Lavado')}',
                  softWrap: true, style: TextStyle(color: muted, fontSize: 11)),
              ],
            )),
          ]);
        }),
        const SizedBox(height: 10),
        Divider(height: 1, color: outline),
        const SizedBox(height: 9),
        Row(children: [
          Expanded(child: Text('Bahía: ${_read(order,'bay_name','Sin asignar')}',
            softWrap: true, style: TextStyle(color: muted, fontSize: 11))),
          if (_read(order, 'quoted_price').isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('L ${_read(order,'quoted_price')}',
              style: TextStyle(color: ink, fontSize: 12, fontWeight: FontWeight.w800)),
          ],
          const SizedBox(width: 6),
          Icon(Icons.chevron_right, color: ink, size: 20),
        ]),
      ],
    ), padding: const EdgeInsets.all(12)),
  );

  Widget _smallStat(String label,dynamic count,Color color) => Expanded(child:Container(
    margin:const EdgeInsets.only(right:4),padding:const EdgeInsets.symmetric(vertical:9,horizontal:2),
    decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(10)),
    child:Column(children:[Text(label,style:const TextStyle(fontSize:9,color:WasherMobileColors.ink)),
      Text('${_int(count)}',style:const TextStyle(color:WasherMobileColors.ink,fontSize:18,fontWeight:FontWeight.bold))])));

  Widget _attendanceView() => Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    _heading('Escanear QR (Asistencia)',subtitle:'Escanea el QR autorizado del punto de asistencia.'),
    _surface(ClipRRect(borderRadius:BorderRadius.circular(13),child:SizedBox(height:330,
      child:Stack(fit:StackFit.expand,children:[
        MobileScanner(onDetect:(capture){
          if(_scannerBusy || _busy || capture.barcodes.isEmpty) return;
          final value=capture.barcodes.first.rawValue;
          if(value==null || value.isEmpty) return;
          _confirmScan(value);
        },errorBuilder:(context,error)=>Center(child:Padding(padding:const EdgeInsets.all(15),
          child:Text('No se pudo abrir la cámara. Autoriza el permiso o usa el código manual.',
            textAlign:TextAlign.center,style:TextStyle(color:ink))))),
        IgnorePointer(child:Center(child:Container(width:225,height:225,
          decoration:BoxDecoration(border:Border.all(color:turquoise,width:3),
          borderRadius:BorderRadius.circular(19)),child:Center(child:Container(height:2,color:turquoise))))),
      ]))),padding:const EdgeInsets.all(7)),const SizedBox(height:13),
    Container(padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:WasherMobileColors.pale,
      borderRadius:BorderRadius.circular(13)),child:Row(children:[Icon(Icons.qr_code_scanner,color:turquoise),
      const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('Enfoca el código QR',style:TextStyle(fontWeight:FontWeight.w700,color:ink)),
        Text('Asegúrate de que está dentro del recuadro.',style:TextStyle(color:muted,fontSize:11)),
      ]))])),const SizedBox(height:15),
    Row(children:[Expanded(child:Divider(color:outline)),const Padding(padding:EdgeInsets.symmetric(horizontal:12),
      child:Text('O',style:TextStyle(color:WasherMobileColors.grey))),Expanded(child:Divider(color:outline))]),
    const SizedBox(height:9),SizedBox(width:double.infinity,child:OutlinedButton.icon(
      style:OutlinedButton.styleFrom(foregroundColor:ink,side:BorderSide(color:turquoise)),
      icon:const Icon(Icons.keyboard_outlined),label:const Text('Ingresar código manualmente'),
      onPressed:_manualCode)),const SizedBox(height:12),
    Text('Estado de jornada: ${_onDuty?'Entrada registrada':'Sin entrada activa'}',
      style:TextStyle(color:muted,fontSize:12)),
  ]);

  Future<void> _manualCode() async {
    final controller = TextEditingController();
    final result=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Código de asistencia'),
      content:TextField(controller:controller,maxLength:8,keyboardType:TextInputType.number,
        decoration:const InputDecoration(labelText:'Código autorizado de 8 dígitos')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,controller.text.trim()),child:const Text('Validar'))]));
    controller.dispose();
    if(result!=null && result.isNotEmpty) _confirmScan(result);
  }

  Future<void> _confirmScan(String code) async {
    if(_scannerBusy || _busy) return;
    _scannerBusy = true;
    final event = _onDuty?'check_out':'check_in';
    final confirmed = await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(event=='check_in'?'Registrar entrada':'Registrar salida'),
      content:Text('El servidor validará el punto de asistencia y registrará tu ${event=='check_in'?'entrada':'salida'} real. ¿Continuar?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmar'))]));
    if(confirmed==true) await _action('/washer/attendance/scan',{'code':code,'event':event});
    _scannerBusy = false;
  }

  static const _months=['','enero','febrero','marzo','abril','mayo','junio','julio','agosto','septiembre','octubre','noviembre','diciembre'];
  DateTime _monthShift(int delta) => DateTime(_selected.year,_selected.month+delta,1);
  void _moveMonth(int delta) {setState(()=>_selected=_monthShift(delta));_refresh();}
  void _chooseDay(DateTime d) {setState(()=>_selected=d);_refresh();}

  Widget _calendar() {
    final first=DateTime(_selected.year,_selected.month,1);
    final start=first.subtract(Duration(days:first.weekday-1));
    final agendaForDay=_agenda.where((item)=>_read(item,'date')==_date(_selected)).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _heading('Calendario de reservas',subtitle:'Visualiza únicamente tus reservas programadas.'),
      Row(children:[IconButton(onPressed:()=>_moveMonth(-1),icon:Icon(Icons.chevron_left,color:turquoise)),
        Expanded(child:Center(child:Text('${_months[_selected.month]} ${_selected.year}',
          style:TextStyle(color:ink,fontWeight:FontWeight.bold)))),
        IconButton(onPressed:()=>_moveMonth(1),icon:Icon(Icons.chevron_right,color:turquoise)),
        OutlinedButton(onPressed:(){setState(()=>_selected=DateTime.now());_refresh();},child:const Text('Hoy'))]),
      const SizedBox(height:10),_surface(Column(children:[
        Row(children:['Lun','Mar','Mié','Jue','Vie','Sáb','Dom'].map((label)=>Expanded(child:Center(child:Text(label,
          style:TextStyle(color:ink,fontWeight:FontWeight.bold,fontSize:11))))).toList()),
        const SizedBox(height:5),...List.generate(6,(week)=>Row(children:List.generate(7,(column){
          final d=start.add(Duration(days:week*7+column));
          final selected=_date(d)==_date(_selected);
          final hasReservations=_agenda.any((item)=>_read(item,'date')==_date(d));
          return Expanded(child:InkWell(onTap:()=>_chooseDay(d),child:Container(height:49,
            margin:const EdgeInsets.all(1),decoration:BoxDecoration(
              color:selected?turquoise:WasherMobileColors.card,
              border:Border.all(color:outline),borderRadius:BorderRadius.circular(10)),
            child:Column(mainAxisAlignment:MainAxisAlignment.center,children:[
              Text('${d.day}',style:TextStyle(color:selected?Colors.white:
                d.month!=_selected.month?muted:ink,fontWeight:selected?FontWeight.w800:FontWeight.normal)),
              const SizedBox(height:3),if(hasReservations)CircleAvatar(radius:3,backgroundColor:selected?Colors.white:turquoise),
            ]))));
        })))
      ]),padding:const EdgeInsets.all(8)),const SizedBox(height:18),
      Row(children:[Expanded(child:_heading('Reservas del ${_selected.day} de ${_months[_selected.month]}')),
        _chip('${agendaForDay.length} reservas',const Color(0xFFDAF8E7),const Color(0xFF167A34))]),
      if(agendaForDay.isEmpty)_surface(Text('No tienes reservas asignadas para esta fecha.',style:TextStyle(color:muted)))
      else ...agendaForDay.map((booking)=>Padding(padding:const EdgeInsets.only(bottom:8),child:
        InkWell(onTap:()=>_bookingDetail(booking),child:_surface(Row(children:[
          _vehiclePhoto(booking['vehicle_id'],width:73,height:48),const SizedBox(width:9),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(_read(booking,'vehicle','Vehículo'),maxLines:1,overflow:TextOverflow.ellipsis,
              style:TextStyle(color:ink,fontWeight:FontWeight.w700,fontSize:12)),
            _plate(_read(booking,'plate','Sin placa')),
          ])),Column(crossAxisAlignment:CrossAxisAlignment.end,children:[
            Text(_read(booking,'time'),style:TextStyle(color:ink,fontSize:11,fontWeight:FontWeight.w700)),
            Text(_read(booking,'service','Lavado'),style:TextStyle(color:muted,fontSize:10)),
            _chip('Confirmada',const Color(0xFFDAF8E7),const Color(0xFF16833B)),
          ]),Icon(Icons.chevron_right,color:ink,size:17),
        ]),padding:const EdgeInsets.all(9)))))
    ]);
  }
  // El detalle de la reserva también respeta el área segura y el desplazamiento.
  void _bookingDetail(Map<String, dynamic> booking) => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: WasherMobileColors.background,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(
        top: false,
        maintainBottomViewPadding: true,
        minimum: const EdgeInsets.only(bottom: 20),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.80),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            children: [
              _heading('Reserva ${_read(booking,'booking_code')}', subtitle: 'Información de solo lectura'),
              _vehiclePhoto(booking['vehicle_id'], width: double.infinity, height: 180),
              const SizedBox(height: 12),
              Text('${_read(booking,'vehicle')} · ${_read(booking,'plate')}',
                softWrap: true, style: TextStyle(color: ink, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Fecha: ${_read(booking,'date')}  Hora: ${_read(booking,'time')}', style: TextStyle(color: muted)),
              Text('Servicio: ${_read(booking,'service')}', style: TextStyle(color: muted)),
              Text('Sucursal: ${_read(booking,'branch')}', style: TextStyle(color: muted)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _profileView() => Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
    _heading('Mi perfil',subtitle:'Consulta y gestiona tu información personal.'),
    _surface(Row(children:[
      ClipOval(child:Image.network('${MyCarWashSession.apiBaseUrl}/companies/${MyCarWashSession.companyId}/washer/photo/employees/${_profile['employee_id']}',
        headers:MyCarWashSession.headers,width:70,height:70,fit:BoxFit.cover,
        errorBuilder:(context,error,stackTrace)=>Container(width:70,height:70,color:WasherMobileColors.pale,
          child:Icon(Icons.person,color:turquoise,size:35)))),const SizedBox(width:13),
      Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(_read(_profile,'name','Mi cuenta'),maxLines:2,style:TextStyle(color:ink,fontWeight:FontWeight.w800,fontSize:17)),
        _chip('Lavador',WasherMobileColors.pale,ink),
        Text('ID: LAV-${_profile['employee_id'] ?? ''}',style:TextStyle(color:muted,fontSize:11)),
      ])),OutlinedButton.icon(onPressed:_editProfile,icon:const Icon(Icons.edit_outlined,size:15),
        label:const Text('Editar'))])),const SizedBox(height:11),
    _surface(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _sectionHead('Información personal',Icons.badge_outlined),
      _line('Nombre completo',_read(_profile,'full_name',_read(_profile,'name','No registrado'))),
      _line('Correo electrónico',_read(_profile,'email','No registrado')),
      _line('Teléfono',_read(_profile,'phone','No registrado')),
      _line('Cédula',_read(_profile,'identity_document','No registrado')),
    ])),const SizedBox(height:11),_surface(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _sectionHead('Información laboral',Icons.work_outline),
      _line('Rol','Lavador'),
      _line('Fecha de ingreso',_read(_profile,'hire_date','No registrada')),
      _line('Estado',_profile['is_active']==true?'Activo':'Inactivo'),
    ])),const SizedBox(height:11),
    _surface(Column(children:[
      _option('Cambiar contraseña',Icons.lock_outline,_changePassword),
      _option('Notificaciones',Icons.notifications_none,()=>_message('Las notificaciones aún no están disponibles.')),
      _option('Ayuda y soporte',Icons.help_outline,()=>_message('Contacta al administrador de tu empresa.')),
      _option('Acerca de la app',Icons.info_outline,()=>showAboutDialog(context:context,
        applicationName:'ADN MyCarWash',applicationVersion:'1.0.0',
        children:[const Text('Desarrollado por ADN Publicidad.')]))
    ])),const SizedBox(height:15),
    SizedBox(width:double.infinity,child:OutlinedButton.icon(
      style:OutlinedButton.styleFrom(foregroundColor:Colors.red,side:const BorderSide(color:Colors.red)),
      onPressed:_logout,icon:const Icon(Icons.logout),label:const Text('Cerrar sesión'))),
  ]);
  Widget _sectionHead(String text,IconData icon)=>Padding(padding:const EdgeInsets.only(bottom:8),child:Row(children:[
    Icon(icon,color:turquoise,size:19),const SizedBox(width:9),Text(text,
      style:TextStyle(color:ink,fontWeight:FontWeight.w800))]));
  Widget _line(String name,String value)=>Padding(padding:const EdgeInsets.symmetric(vertical:9),
    child:Row(children:[Expanded(flex:4,child:Text(name,style:TextStyle(color:ink,fontSize:11))),
      Expanded(flex:6,child:Text(value,textAlign:TextAlign.right,maxLines:2,overflow:TextOverflow.ellipsis,
        style:TextStyle(color:ink,fontSize:11,fontWeight:FontWeight.w600)))]));
  Widget _option(String text,IconData icon,VoidCallback action)=>ListTile(contentPadding:EdgeInsets.zero,
    dense:true,leading:Icon(icon,color:ink),title:Text(text,style:TextStyle(color:ink)),
    trailing:Icon(Icons.chevron_right,color:ink),onTap:action);

  Future<void> _editProfile() async {
    final name=TextEditingController(text:_read(_profile,'name'));
    final email=TextEditingController(text:_read(_profile,'email'));
    final phone=TextEditingController(text:_read(_profile,'phone'));
    final submit=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Editar información personal'),
      content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:name,decoration:const InputDecoration(labelText:'Nombre')),
        TextField(controller:email,decoration:const InputDecoration(labelText:'Correo')),
        TextField(controller:phone,decoration:const InputDecoration(labelText:'Teléfono')),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Guardar'))]));
    if(submit==true) {
      await _action('/washer/me',{'name':name.text.trim(),
        'email':email.text.trim(),'phone':phone.text.trim()},method:'PATCH');
    }
    name.dispose(); email.dispose(); phone.dispose();
  }

  Future<void> _changePassword() async {
    final old=TextEditingController(), newest=TextEditingController(), confirm=TextEditingController();
    final submit=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Cambiar contraseña'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        TextField(controller:old,obscureText:true,decoration:const InputDecoration(labelText:'Contraseña actual')),
        TextField(controller:newest,obscureText:true,decoration:const InputDecoration(labelText:'Nueva contraseña (mín. 10)')),
        TextField(controller:confirm,obscureText:true,decoration:const InputDecoration(labelText:'Confirmar contraseña')),
      ])),actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Actualizar'))]));
    if(submit==true) {
      if(newest.text.length<10 || newest.text!=confirm.text) {
        _message('Revisa la contraseña y su confirmación.');
      } else {
        final changed = await _action('/washer/password',{'current_password':old.text,
          'password':newest.text,'password_confirmation':confirm.text},method:'PATCH');
        // El servidor invalida todos los tokens después de cambiar la clave.
        if(changed) await _logout();
      }
    }
    old.dispose();newest.dispose();confirm.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
    data:ThemeData(useMaterial3:true,brightness:Brightness.light,
      colorScheme:ColorScheme.fromSeed(seedColor:turquoise,brightness:Brightness.light),
      scaffoldBackgroundColor:WasherMobileColors.background),
    child:Scaffold(backgroundColor:WasherMobileColors.background,
      body:SafeArea(bottom:false,child:Column(children:[
        _header(),Expanded(child:RefreshIndicator(onRefresh:_refresh,child:ListView(
          padding:const EdgeInsets.fromLTRB(13,2,13,24),children:[
          if(_loading)Padding(padding:const EdgeInsets.all(32),child:Center(child:CircularProgressIndicator(color:turquoise)))
          else if(_error!=null)_surface(Column(children:[Text('Error al cargar: $_error',style:TextStyle(color:ink)),
            TextButton(onPressed:_refresh,child:const Text('Reintentar'))]))
          else switch(_tab){0=>_home(),1=>_ordersView(),2=>_attendanceView(),3=>_calendar(),_=>_profileView()},
        ]))),_navigation(),
      ]))),
  );
}
