import 'dart:convert';
import 'package:flutter/material.dart';
import '../services/app_services.dart';
import '../services/api.dart';

extension AdminCatalogApi on LumeApi {
  Future<int> publishCatalog(Map<String,dynamic> manifest) async {
    if(session.role!='admin')throw const ApiException('adminCatalog',403,'admin role required');
    final r=await client.post(base.resolve('/v1/admin/catalog'),headers:{'authorization':'Bearer ${session.token}','content-type':'application/json'},body:jsonEncode(manifest));
    if(r.statusCode==401)throw const SessionExpiredException('adminCatalog');
    if(r.statusCode!=200)throw ApiException('adminCatalog',r.statusCode,r.body);
    return (jsonDecode(r.body)['revision'] as num).toInt();
  }
}

class AdminCatalogPage extends StatefulWidget {
  final AppServices services;
  const AdminCatalogPage({super.key,required this.services});
  @override State<AdminCatalogPage> createState()=>_AdminCatalogPageState();
}
class _AdminCatalogPageState extends State<AdminCatalogPage>{
  bool loading=true,publishing=false; int revision=0; String? error;
  List<Map<String,dynamic>> works=[];
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    try{
      final j=await widget.services.api.bootstrap(-1);
      revision=(j?['revision'] as num?)?.toInt()??0;
      works=(j?['works'] as List? ?? const[]).map((x)=>Map<String,dynamic>.from(x as Map)).toList();
      error=null;
    }catch(e){error='$e';}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> _edit([int? index]) async {
    final seed=index==null?<String,dynamic>{'id':'work-${DateTime.now().microsecondsSinceEpoch}','type':'book','canonicalTitle':'','displayTitle':'','sourceFolderIds':<String>[],'sections':<String>[],'tags':<String>[],'editions':<dynamic>[]}:Map<String,dynamic>.from(works[index]);
    final value=await Navigator.of(context).push<Map<String,dynamic>>(MaterialPageRoute(builder:(_)=>_WorkEditor(seed:seed)));
    if(value==null||!mounted)return;
    setState(()=>index==null?works.add(value):works[index]=value);
  }
  Future<void> _publish() async {
    setState(()=>publishing=true);
    try{
      final next=revision+1;
      final got=await widget.services.api.publishCatalog({'revision':next,'generatedAt':DateTime.now().toUtc().toIso8601String(),'works':works,'tombstones':const[]});
      await widget.services.sync.refreshCatalog();
      if(mounted){setState(()=>revision=got);ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Catálogo publicado · revisão $got')));}
    }catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Falha ao publicar: $e')));}
    if(mounted)setState(()=>publishing=false);
  }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text('Gerenciar catálogo · r$revision'),actions:[IconButton(tooltip:'Recarregar',onPressed:loading?null:(){setState(()=>loading=true);_load();},icon:const Icon(Icons.refresh)),IconButton(tooltip:'Publicar revisão',onPressed:publishing||loading?null:_publish,icon:publishing?const SizedBox(width:20,height:20,child:CircularProgressIndicator(strokeWidth:2)):const Icon(Icons.cloud_upload_outlined))]),
    floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add),label:const Text('Nova obra')),
    body:loading?const Center(child:CircularProgressIndicator()):error!=null?Center(child:Padding(padding:const EdgeInsets.all(24),child:Text('Erro: $error'))):works.isEmpty?const Center(child:Text('Catálogo vazio. Adicione a primeira obra.')):ListView.separated(padding:const EdgeInsets.only(bottom:96),itemCount:works.length,separatorBuilder:(_,__)=>const Divider(height:1),itemBuilder:(context,i){final w=works[i];final ed=(w['editions'] as List? ?? const[]).length;return ListTile(title:Text('${w['displayTitle']??w['canonicalTitle']??'Sem título'}'),subtitle:Text('${w['type']} · $ed ${ed==1?'edição':'edições'}'),onTap:()=>_edit(i),trailing:IconButton(tooltip:'Remover obra',icon:const Icon(Icons.delete_outline),onPressed:()=>setState(()=>works.removeAt(i))));}),
  );
}

class _WorkEditor extends StatefulWidget{final Map<String,dynamic> seed;const _WorkEditor({required this.seed});@override State<_WorkEditor> createState()=>_WorkEditorState();}
class _WorkEditorState extends State<_WorkEditor>{
  late final TextEditingController title,sources,sections,tags; late String type; late List<Map<String,dynamic>> editions;
  @override void initState(){super.initState();final w=widget.seed;title=TextEditingController(text:'${w['displayTitle']??w['canonicalTitle']??''}');sources=TextEditingController(text:List<String>.from(w['sourceFolderIds']??const[]).join(', '));sections=TextEditingController(text:List<String>.from(w['sections']??const[]).join(', '));tags=TextEditingController(text:List<String>.from(w['tags']??const[]).join(', '));type='${w['type']??'book'}';editions=(w['editions'] as List? ?? const[]).map((e)=>Map<String,dynamic>.from(e as Map)).toList();}
  List<String> _csv(String x)=>x.split(',').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList();
  Future<void> _edition([int? i])async{final value=await showDialog<Map<String,dynamic>>(context:context,builder:(_)=>_EditionEditor(seed:i==null?null:editions[i]));if(value==null)return;setState(()=>i==null?editions.add(value):editions[i]=value);}
  void _save(){final t=title.text.trim();if(t.isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Informe o título.')));return;}final w=Map<String,dynamic>.from(widget.seed)..['canonicalTitle']=t..['displayTitle']=t..['type']=type..['sourceFolderIds']=_csv(sources.text)..['sections']=_csv(sections.text)..['tags']=_csv(tags.text)..['editions']=editions;Navigator.pop(context,w);}
  @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:const Text('Editar obra'),actions:[IconButton(onPressed:_save,tooltip:'Salvar',icon:const Icon(Icons.check))]),floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edition(),icon:const Icon(Icons.add),label:const Text('Edição')),body:ListView(padding:const EdgeInsets.all(16),children:[Text('ID: ${widget.seed['id']}',style:Theme.of(context).textTheme.bodySmall),TextField(controller:title,decoration:const InputDecoration(labelText:'Título')),const SizedBox(height:12),DropdownButtonFormField<String>(initialValue:type,decoration:const InputDecoration(labelText:'Tipo'),items:const['book','hq','manga','graphic_novel'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x)=>setState(()=>type=x!)),TextField(controller:sources,decoration:const InputDecoration(labelText:'Pastas de origem (IDs, separados por vírgula)')),TextField(controller:sections,decoration:const InputDecoration(labelText:'Seções editoriais, separadas por vírgula')),TextField(controller:tags,decoration:const InputDecoration(labelText:'Tags, separadas por vírgula')),const SizedBox(height:20),Text('Edições',style:Theme.of(context).textTheme.titleMedium),for(int i=0;i<editions.length;i++)ListTile(contentPadding:EdgeInsets.zero,title:Text('${editions[i]['fileName']??'Sem arquivo'}'),subtitle:Text('${editions[i]['format']??''} · ${editions[i]['language']??'unknown'}'),onTap:()=>_edition(i),trailing:IconButton(icon:const Icon(Icons.delete_outline),onPressed:()=>setState(()=>editions.removeAt(i))))]));
}

class _EditionEditor extends StatefulWidget{final Map<String,dynamic>? seed;const _EditionEditor({this.seed});@override State<_EditionEditor> createState()=>_EditionEditorState();}
class _EditionEditorState extends State<_EditionEditor>{
  late final TextEditingController file,source,language,bytes,volume,chapter;late String format;late String id;
  @override void initState(){super.initState();final e=widget.seed??{};id='${e['id']??'edition-${DateTime.now().microsecondsSinceEpoch}'}';file=TextEditingController(text:'${e['fileName']??''}');source=TextEditingController(text:'${e['sourceFileId']??''}');language=TextEditingController(text:'${e['language']??'pt-BR'}');bytes=TextEditingController(text:e['byteSize']?.toString()??'');volume=TextEditingController(text:e['volumeNumber']?.toString()??'');chapter=TextEditingController(text:e['chapterNumber']?.toString()??'');format='${e['format']??'pdf'}';}
  void _save(){if(file.text.trim().isEmpty||source.text.trim().isEmpty){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Arquivo e sourceFileId são obrigatórios.')));return;}final m=<String,dynamic>{'id':id,'format':format,'sourceFileId':source.text.trim(),'fileName':file.text.trim(),'language':language.text.trim().isEmpty?'unknown':language.text.trim()};final b=int.tryParse(bytes.text.trim());if(b!=null)m['byteSize']=b;final v=double.tryParse(volume.text.trim());if(v!=null)m['volumeNumber']=v;final c=double.tryParse(chapter.text.trim());if(c!=null)m['chapterNumber']=c;Navigator.pop(context,m);}
  @override Widget build(BuildContext context)=>AlertDialog(title:const Text('Edição'),content:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[Text('ID: $id'),TextField(controller:file,decoration:const InputDecoration(labelText:'Nome do arquivo')),TextField(controller:source,decoration:const InputDecoration(labelText:'Drive sourceFileId')),DropdownButtonFormField<String>(initialValue:format,decoration:const InputDecoration(labelText:'Formato'),items:const['pdf','epub','cbz','cbr'].map((x)=>DropdownMenuItem(value:x,child:Text(x))).toList(),onChanged:(x)=>setState(()=>format=x!)),TextField(controller:language,decoration:const InputDecoration(labelText:'Idioma')),TextField(controller:bytes,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Tamanho em bytes')),TextField(controller:volume,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Volume')),TextField(controller:chapter,keyboardType:TextInputType.number,decoration:const InputDecoration(labelText:'Capítulo'))])),actions:[TextButton(onPressed:()=>Navigator.pop(context),child:const Text('Cancelar')),FilledButton(onPressed:_save,child:const Text('Salvar'))]);
}
