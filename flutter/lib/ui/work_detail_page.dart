import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../services/cover_cache.dart';
import 'cover_image.dart';
import 'lume_theme.dart';

class WorkDetailPage extends StatefulWidget {
  final Work work;
  final CoverCache coverCache;
  final Object heroTag;
  final bool favorite;
  final Future<void> Function(bool favorite) onFavoriteChanged;
  final ValueChanged<Edition> onOpen;
  final Future<void> Function(Edition) onDownload;

  const WorkDetailPage({
    super.key,
    required this.work,
    required this.coverCache,
    required this.heroTag,
    required this.favorite,
    required this.onFavoriteChanged,
    required this.onOpen,
    required this.onDownload,
  });

  @override State<WorkDetailPage> createState()=>_WorkDetailPageState();
}

class _WorkDetailPageState extends State<WorkDetailPage> {
  late bool favorite=widget.favorite;
  bool changingFavorite=false;

  List<Edition> get editions=>[...widget.work.editions]..sort((a,b){
    final av=a.volume??a.chapter??double.infinity;
    final bv=b.volume??b.chapter??double.infinity;
    final sequence=av.compareTo(bv);
    return sequence!=0?sequence:a.fileName.compareTo(b.fileName);
  });

  Future<void> toggleFavorite() async {
    if(changingFavorite)return;
    final next=!favorite;
    setState((){favorite=next;changingFavorite=true;});
    try{
      await widget.onFavoriteChanged(next);
    }catch(_){
      if(mounted){
        setState(()=>favorite=!next);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Não foi possível atualizar sua biblioteca.')));
      }
    }finally{
      if(mounted)setState(()=>changingFavorite=false);
    }
  }

  Future<void> download(Edition edition) async {
    try{
      await widget.onDownload(edition);
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Edição adicionada à fila de downloads.')));
    }catch(_){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Não foi possível iniciar o download.')));
    }
  }

  @override Widget build(BuildContext context){
    final work=widget.work;
    final allEditions=editions;
    return Scaffold(
      body:CustomScrollView(slivers:[
        SliverAppBar.large(
          pinned:true,
          expandedHeight:390,
          backgroundColor:LumePalette.night,
          foregroundColor:Colors.white,
          surfaceTintColor:Colors.transparent,
          actions:[
            IconButton(
              tooltip:favorite?'Remover dos favoritos':'Adicionar aos favoritos',
              onPressed:changingFavorite?null:toggleFavorite,
              icon:Icon(favorite?Icons.bookmark:Icons.bookmark_border),
            ),
          ],
          flexibleSpace:FlexibleSpaceBar(
            background:_DetailHero(work:work,cache:widget.coverCache,heroTag:widget.heroTag),
          ),
        ),
        SliverToBoxAdapter(child:Padding(
          padding:const EdgeInsets.fromLTRB(20,28,20,18),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Row(children:[
              _MetadataPill(icon:Icons.auto_stories_outlined,label:_typeLabel(work.type)),
              const SizedBox(width:8),
              _MetadataPill(icon:Icons.library_books_outlined,label:'${allEditions.length} ${allEditions.length==1?'edição':'edições'}'),
            ]),
            if(work.description!=null)...[
              const SizedBox(height:22),
              Text(work.description!,style:Theme.of(context).textTheme.bodyLarge),
            ],
            if(work.sections.isNotEmpty)...[
              const SizedBox(height:22),
              Wrap(spacing:8,runSpacing:8,children:[for(final section in work.sections)Chip(label:Text(section))]),
            ],
            const SizedBox(height:24),
            Row(children:[
              Expanded(child:FilledButton.icon(
                onPressed:allEditions.isEmpty?null:()=>widget.onOpen(allEditions.first),
                icon:const Icon(Icons.chrome_reader_mode_outlined),
                label:Text(allEditions.length>1?'Começar pela primeira':'Começar leitura'),
              )),
              const SizedBox(width:10),
              IconButton.filledTonal(
                tooltip:favorite?'Remover dos favoritos':'Adicionar aos favoritos',
                onPressed:changingFavorite?null:toggleFavorite,
                icon:Icon(favorite?Icons.bookmark:Icons.bookmark_border),
              ),
            ]),
            const SizedBox(height:34),
            Text('Edições disponíveis',style:Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height:6),
            Text('Escolha por onde continuar ou guarde uma edição no aparelho.',style:Theme.of(context).textTheme.bodyMedium),
          ]),
        )),
        if(allEditions.isEmpty)
          const SliverToBoxAdapter(child:Padding(padding:EdgeInsets.all(32),child:Center(child:Text('Nenhuma edição disponível.'))))
        else
          SliverList.separated(
            itemCount:allEditions.length,
            separatorBuilder:(_,__)=>const Divider(height:1,indent:20,endIndent:20),
            itemBuilder:(context,index){
              final edition=allEditions[index];
              return ListTile(
                contentPadding:const EdgeInsets.symmetric(horizontal:20,vertical:6),
                leading:CircleAvatar(
                  backgroundColor:Theme.of(context).colorScheme.primaryContainer,
                  foregroundColor:Theme.of(context).colorScheme.onPrimaryContainer,
                  child:Text('${index+1}',style:const TextStyle(fontWeight:FontWeight.w800)),
                ),
                title:Text(_editionLabel(edition)),
                subtitle:Text('${edition.format.toUpperCase()} · ${edition.language}'),
                trailing:Wrap(spacing:2,children:[
                  IconButton(tooltip:'Baixar',onPressed:()=>download(edition),icon:const Icon(Icons.download_outlined)),
                  IconButton(tooltip:'Ler',onPressed:()=>widget.onOpen(edition),icon:const Icon(Icons.arrow_forward)),
                ]),
                onTap:()=>widget.onOpen(edition),
              );
            },
          ),
        const SliverToBoxAdapter(child:SizedBox(height:36)),
      ]),
    );
  }

  String _editionLabel(Edition edition){
    if(edition.volume!=null)return 'Volume ${_number(edition.volume!)}';
    if(edition.chapter!=null)return 'Capítulo ${_number(edition.chapter!)}';
    return edition.fileName;
  }

  String _number(double value)=>value==value.roundToDouble()?value.toInt().toString():value.toString();
  String _typeLabel(String type)=>switch(type){
    ContentType.manga=>'Mangá',
    ContentType.comic=>'HQ',
    ContentType.graphicNovel=>'Graphic novel',
    ContentType.magazine=>'Revista',
    _=>'Livro',
  };
}

class _DetailHero extends StatelessWidget {
  final Work work;
  final CoverCache cache;
  final Object heroTag;
  const _DetailHero({required this.work,required this.cache,required this.heroTag});

  @override Widget build(BuildContext context)=>DecoratedBox(
    decoration:const BoxDecoration(
      gradient:LinearGradient(
        begin:Alignment.topLeft,end:Alignment.bottomRight,
        colors:[Color(0xFF293B32),LumePalette.night,Color(0xFF4E281F)],
      ),
    ),
    child:SafeArea(child:Padding(
      padding:const EdgeInsets.fromLTRB(22,70,22,24),
      child:Row(crossAxisAlignment:CrossAxisAlignment.end,children:[
        SizedBox(
          width:142,height:216,
          child:Material(
            elevation:18,
            shadowColor:Colors.black.withValues(alpha:.5),
            borderRadius:BorderRadius.circular(10),
            clipBehavior:Clip.antiAlias,
            child:WorkCoverImage(work:work,cache:cache,heroTag:heroTag,borderRadius:BorderRadius.zero),
          ),
        ),
        const SizedBox(width:20),
        Expanded(child:Padding(
          padding:const EdgeInsets.only(bottom:4),
          child:Column(mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('ACERVO LUME',style:Theme.of(context).textTheme.labelMedium?.copyWith(color:const Color(0xFFE9BA73),fontWeight:FontWeight.w900,letterSpacing:1.6)),
            const SizedBox(height:10),
            Text(work.title,maxLines:5,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.headlineMedium?.copyWith(color:Colors.white)),
            if(work.author!=null)...[
              const SizedBox(height:8),
              Text(work.author!,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.bodyMedium?.copyWith(color:Colors.white.withValues(alpha:.78))),
            ],
          ]),
        )),
      ]),
    )),
  );
}

class _MetadataPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MetadataPill({required this.icon,required this.label});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:12,vertical:8),
    decoration:BoxDecoration(color:Theme.of(context).colorScheme.secondaryContainer,borderRadius:BorderRadius.circular(999)),
    child:Row(mainAxisSize:MainAxisSize.min,children:[Icon(icon,size:17),const SizedBox(width:6),Text(label,style:Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight:FontWeight.w800))]),
  );
}
