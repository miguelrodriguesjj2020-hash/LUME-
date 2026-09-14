import 'dart:async';
import 'package:flutter/material.dart';
import '../services/app_services.dart';
import '../services/recoverable_downloads.dart';

class DownloadsPage extends StatefulWidget {
  final AppServices services;
  const DownloadsPage({super.key,required this.services});
  @override State<DownloadsPage> createState()=>_DownloadsPageState();
}

class _DownloadsPageState extends State<DownloadsPage>{
  late Future<List<Map<String,dynamic>>> future;
  StreamSubscription<DownloadSnapshot>? sub;
  final Map<String,DownloadSnapshot> live={};
  @override void initState(){super.initState();_reload();sub=widget.services.offlineDownloads.changes.listen((e){if(!mounted)return;setState((){live[e.editionId]=e;_reload();});});}
  @override void dispose(){sub?.cancel();super.dispose();}
  void _reload(){future=widget.services.db.listDownloadJobs();}
  Future<void> _act(Future<void> Function() f) async{await f();if(mounted)setState(_reload);}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Downloads')),
    body:FutureBuilder<List<Map<String,dynamic>>>(future:future,builder:(context,s){
      if(s.hasError)return Center(child:Text('Erro ao abrir downloads: ${s.error}'));
      if(!s.hasData)return const Center(child:CircularProgressIndicator());
      final jobs=s.data!; if(jobs.isEmpty)return const Center(child:Text('Nenhum download.'));
      return RefreshIndicator(onRefresh:() async{setState(_reload);await future;},child:ListView.builder(itemCount:jobs.length,itemBuilder:(context,i){
        final j=jobs[i];final id=j['edition_id'] as String;final snap=live[id];final state=snap?.state??'${j['state']}';
        final req=Map<String,dynamic>.from(j['request'] as Map);final pinned=req['pinned']==true;
        final frac=snap?.fraction;
        final subtitle=<Widget>[Text('${_label(state)}${pinned?' · fixado':''}')];
        if(frac!=null && state=='downloading')subtitle.add(Padding(padding:const EdgeInsets.only(top:6),child:LinearProgressIndicator(value:frac.clamp(0,1))));
        return ListTile(
          leading:Icon(_icon(state)),title:Text(id),subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:subtitle),
          trailing:Wrap(spacing:4,children:[
            if(state=='downloading'||state=='queued')IconButton(tooltip:'Pausar',icon:const Icon(Icons.pause),onPressed:()=>_act(() async=>widget.services.offlineDownloads.pause(id))),
            if(state=='paused')IconButton(tooltip:'Retomar',icon:const Icon(Icons.play_arrow),onPressed:()=>_act(()=>widget.services.offlineDownloads.resume(id))),
            if(state=='failed')IconButton(tooltip:'Tentar novamente',icon:const Icon(Icons.refresh),onPressed:()=>_act(()=>widget.services.offlineDownloads.retry(id))),
            if(state!='ready')IconButton(tooltip:'Cancelar',icon:const Icon(Icons.close),onPressed:()=>_act(() async=>widget.services.offlineDownloads.cancel(id))),
          ]),
        );
      }));
    }),
  );
  String _label(String s)=>switch(s){'queued'=>'Na fila','downloading'=>'Baixando','verifying'=>'Verificando','ready'=>'Disponível offline','paused'=>'Pausado','failed'=>'Falhou',_=>s};
  IconData _icon(String s)=>switch(s){'ready'=>Icons.offline_pin,'failed'=>Icons.error_outline,'paused'=>Icons.pause_circle_outline,'downloading'=>Icons.downloading,_=>Icons.schedule};
}
