import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../core/company_business_api.dart';
import '../core/company_visual_theme.dart';
import '../core/business_identity.dart';

/// B25E: QR y código manual estables. PDF carta corporativo imprimible.
class CompanyAttendanceStation24N4 extends StatefulWidget {
  const CompanyAttendanceStation24N4({super.key,this.client});
  final http.Client? client;
  @override State<CompanyAttendanceStation24N4> createState()=>_StationState();
}
class _StationState extends State<CompanyAttendanceStation24N4>{
  late final http.Client client;
  late final bool ownsClient;
  late final CompanyBusinessApi api;
  bool loading=true;
  bool printing=false;
  String? error;
  String qr='';
  String manual='';
  String point='';
  @override void initState(){super.initState();ownsClient=widget.client==null;client=widget.client??http.Client();api=CompanyBusinessApi(client);refresh();}
  @override void dispose(){if(ownsClient)client.close();super.dispose();}
  Future<void> refresh() async{
    if(!mounted)return;
    setState((){loading=true;error=null;});
    try{
      final result=await api.request('GET','/attendance-points/station');
      if(mounted)setState((){qr='${result['qr_payload']??''}';manual='${result['manual_code']??''}';point='${result['name']??'Punto principal'}';});
    }catch(e){if(mounted)setState(()=>error='$e');}
    finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> downloadPdf() async{
    if(qr.isEmpty||printing)return;
    setState(()=>printing=true);
    try{
      // Se toma la identidad activa, no un logotipo de ADN fijo.
      await BusinessIdentity.refresh(client:client);
      final identity=BusinessIdentity.current.value;
      final palette=CompanyVisualTheme.current.value;
      final primary=PdfColor.fromInt(palette.primary.toARGB32());
      final secondary=PdfColor.fromInt(palette.secondary.toARGB32());
      final accent=PdfColor.fromInt(palette.accent.toARGB32());
      final document=pw.Document();
      final bytes=identity.logoBytes;
      final logo=bytes==null?null:pw.MemoryImage(bytes);
      final business=identity.companyName.trim().isEmpty?'Mi empresa':identity.companyName;
      document.addPage(pw.Page(pageFormat:PdfPageFormat.letter,margin:pw.EdgeInsets.zero,build:(ctx)=>pw.Stack(children:[
        pw.Container(width:PdfPageFormat.letter.width,height:PdfPageFormat.letter.height,color:PdfColors.white),
        pw.Positioned(top:0,left:0,right:0,child:pw.Container(height:20,color:primary)),
        pw.Positioned(bottom:0,left:0,right:0,child:pw.Container(height:24,color:secondary)),
        pw.Padding(padding:const pw.EdgeInsets.fromLTRB(46,43,46,43),child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.center,children:[
          pw.Row(mainAxisAlignment:pw.MainAxisAlignment.center,children:[
            if(logo!=null)pw.Container(width:82,height:82,child:pw.Image(logo,fit:pw.BoxFit.contain)),
            if(logo!=null)pw.SizedBox(width:16),
            pw.Expanded(child:pw.Column(crossAxisAlignment:pw.CrossAxisAlignment.start,children:[
              pw.Text(business,maxLines:2,style:pw.TextStyle(fontSize:23,color:secondary,fontWeight:pw.FontWeight.bold)),
              pw.Text('CONTROL DE ASISTENCIA DEL PERSONAL',style:pw.TextStyle(fontSize:10,color:primary,fontWeight:pw.FontWeight.bold)),
            ])),
          ]),
          pw.SizedBox(height:28),
          pw.Container(width:450,padding:const pw.EdgeInsets.all(20),decoration:pw.BoxDecoration(border:pw.Border.all(color:primary,width:2),borderRadius:pw.BorderRadius.circular(14)),child:pw.Column(children:[
            pw.Text('REGISTRA TU ASISTENCIA',style:pw.TextStyle(fontWeight:pw.FontWeight.bold,fontSize:23,color:secondary)),
            pw.SizedBox(height:8),
            pw.Text(point,style:pw.TextStyle(fontSize:14,color:primary,fontWeight:pw.FontWeight.bold)),
            pw.SizedBox(height:18),
            pw.Container(color:PdfColors.white,padding:const pw.EdgeInsets.all(10),child:pw.BarcodeWidget(barcode:pw.Barcode.qrCode(),data:qr,width:260,height:260)),
            pw.SizedBox(height:15),
            pw.Text('CODIGO MANUAL',style:pw.TextStyle(fontSize:11,color:secondary)),
            pw.Text(manual,style:pw.TextStyle(fontSize:25,color:primary,fontWeight:pw.FontWeight.bold,letterSpacing:2)),
            pw.SizedBox(height:8),
            pw.Text('QR y codigo manual permanentes',style:pw.TextStyle(color:secondary,fontSize:10)),
          ])),
          pw.SizedBox(height:27),
          pw.Container(padding:const pw.EdgeInsets.all(16),decoration:pw.BoxDecoration(color:PdfColors.grey100,borderRadius:pw.BorderRadius.circular(12)),child:pw.Column(children:[
            pw.Text('Tu asistencia cuenta',style:pw.TextStyle(color:secondary,fontWeight:pw.FontWeight.bold,fontSize:19)),
            pw.SizedBox(height:8),
            pw.Text('1. Abre tu aplicacion de ADN MyCarWash.',textAlign:pw.TextAlign.center,style:pw.TextStyle(color:secondary,fontSize:12)),
            pw.Text('2. Escanea el QR con tu sesion autorizada.',textAlign:pw.TextAlign.center,style:pw.TextStyle(color:secondary,fontSize:12)),
            pw.Text('3. Registra tu entrada y salida cada jornada.',textAlign:pw.TextAlign.center,style:pw.TextStyle(color:secondary,fontSize:12)),
            pw.SizedBox(height:9),
            pw.Text('Marca tu asistencia para mantener al dia el registro de tu jornada y la produccion reconocida.',textAlign:pw.TextAlign.center,style:pw.TextStyle(color:accent,fontWeight:pw.FontWeight.bold,fontSize:11)),
          ])),
          pw.Spacer(),
          pw.Divider(color:primary),
          pw.Text('Uso interno del personal autorizado  |  Generado con ADN MyCarWash',style:pw.TextStyle(color:secondary,fontSize:10)),
        ])),
      ])));
      await Printing.layoutPdf(name:'Punto_Asistencia_${business.replaceAll(RegExp(r'[^a-zA-Z0-9]'),'_')}',onLayout:(_)=>document.save());
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('No se pudo generar el PDF: $e')));}
    finally{if(mounted)setState(()=>printing=false);}
  }
  @override Widget build(BuildContext context){
    final accent=CompanyVisualTheme.primary;
    return SingleChildScrollView(padding:const EdgeInsets.all(18),child:Center(child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:620),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      Text('Punto de asistencia QR',style:TextStyle(color:CompanyVisualTheme.text,fontSize:27,fontWeight:FontWeight.bold)),
      const SizedBox(height:7),Text('Imprime este punto fijo para que los empleados registren su entrada y salida desde su aplicación.',style:TextStyle(color:CompanyVisualTheme.muted)),
      const SizedBox(height:18),Container(padding:const EdgeInsets.all(22),decoration:BoxDecoration(color:CompanyVisualTheme.card,borderRadius:BorderRadius.circular(19),border:Border.all(color:CompanyVisualTheme.border)),child:Column(children:[
        Icon(Icons.qr_code_2,color:accent,size:35),const SizedBox(height:10),Text(point.isEmpty?'Punto principal':point,style:TextStyle(color:CompanyVisualTheme.text,fontSize:20,fontWeight:FontWeight.bold)),
        const SizedBox(height:16),
        if(loading)const CircularProgressIndicator()else if(error!=null)Text(error!,style:const TextStyle(color:Colors.redAccent))else if(qr.isNotEmpty)...[
          Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:Colors.white,borderRadius:BorderRadius.circular(14)),child:QrImageView(data:qr,version:QrVersions.auto,size:260,backgroundColor:Colors.white)),
          const SizedBox(height:14),Text('Código manual: $manual',style:TextStyle(color:CompanyVisualTheme.text,fontSize:23,fontWeight:FontWeight.bold)),
          const SizedBox(height:6),Text('QR permanente · código manual permanente',style:TextStyle(color:CompanyVisualTheme.muted)),
        ],
        const SizedBox(height:18),Wrap(alignment:WrapAlignment.center,spacing:11,runSpacing:9,children:[
          FilledButton.icon(onPressed:loading||printing||qr.isEmpty?null:downloadPdf,icon:const Icon(Icons.picture_as_pdf_outlined),label:Text(printing?'Generando PDF...':'Descargar QR · Carta')),
          OutlinedButton.icon(onPressed:loading?null:refresh,icon:const Icon(Icons.refresh),label:const Text('Actualizar vista')),
        ]),
      ])),
      const SizedBox(height:13),Text('La marca de asistencia exige una sesión autenticada. No compartas el código fuera de las instalaciones. Si el cartel se extravía, desactiva el punto desde administración.',style:TextStyle(color:CompanyVisualTheme.muted)),
    ]))));
  }
}
