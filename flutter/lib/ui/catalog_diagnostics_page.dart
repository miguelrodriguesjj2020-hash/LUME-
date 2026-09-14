import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/app_services.dart';
import '../services/catalog_diagnostics.dart';

class CatalogDiagnosticsPage extends StatefulWidget{
  final AppServices services;
  const CatalogDiagnosticsPage({super.key,required this.services});
  @override State<CatalogDiagnosticsPage> createState()=>_CatalogDiagnosticsPageState();
}
class _CatalogDiagnosticsPageState extends State<CatalogDiagnosticsPage>{
  late Future<List<CatalogDiagnosticIssue>> future;
  @override void initState(){super.initState();future=widget.services.catalogDiagnostics.run();}
  void reload()=>setState(()=>future=widget.services.catalogDiagnostics.run());
  Future<void> copyReport(bool csv) async {
    final issues=await future;
    final text=csv?widget.services.catalogDiagnostics.toCsvReport(issues):widget.services.catalogDiagnostics.toJsonReport(issues);
    await Clipboard.setData(ClipboardData(text:text));
    if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(csv?'Relatório CSV copiado.':'Relatório JSON copiado.')));
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Diagnóstico do catálogo'),actions:[
      PopupMenuButton<String>(onSelected:(v)=>copyReport(v=='csv'),itemBuilder:(_)=>const [
        PopupMenuItem(value:'json',child:Text('Copiar relatório JSON')),
        PopupMenuItem(value:'csv',child:Text('Copiar relatório CSV')),
      ]),
      IconButton(onPressed:reload,icon:const Icon(Icons.refresh),tooltip:'Reexecutar')]),
    body:FutureBuilder<List<CatalogDiagnosticIssue>>(future:future,builder:(context,s){
      if(s.hasError)return Center(child:Text('Falha no diagnóstico: ${s.error}'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final issues=s.data!;
      if(issues.isEmpty)return const Center(child:Padding(padding:EdgeInsets.all(24),child:Text('Nenhuma inconsistência editorial detectada no catálogo local.')));
      return ListView.separated(
        padding:const EdgeInsets.all(12),itemCount:issues.length,separatorBuilder:(_,__)=>const Divider(height:1),
        itemBuilder:(context,i){final x=issues[i];final severe=x.severity=='error';return ListTile(
          leading:Icon(severe?Icons.error_outline:Icons.warning_amber_outlined),
          title:Text(x.message),
          subtitle:Text('${x.code}\n${const JsonEncoder.withIndent('  ').convert(x.context)}'),
          isThreeLine:true,
        );},
      );
    }),
  );
}
