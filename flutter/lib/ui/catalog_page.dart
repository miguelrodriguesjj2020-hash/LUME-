import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../readers/reader_session_page.dart';
import '../services/app_services.dart';
import '../services/cover_cache.dart';
import '../services/library_repository.dart';
import 'admin_catalog_page.dart';
import 'admin_users_page.dart';
import 'catalog_diagnostics_page.dart';
import 'cover_image.dart';
import 'downloads_page.dart';
import 'lume_theme.dart';
import 'media_updates_page.dart';
import 'network_preferences_page.dart';
import 'work_detail_page.dart';

class CatalogPage extends StatefulWidget {
  final AppServices services;
  const CatalogPage({super.key,required this.services});
  @override State<CatalogPage> createState()=>_CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final LibraryRepository repo=LibraryRepository(widget.services.db);
  late Future<_LibrarySnapshot> initialRefresh;
  Set<String> favoriteIds=<String>{};
  int destination=0;

  @override void initState(){
    super.initState();
    initialRefresh=_bootstrap();
  }

  Future<_LibrarySnapshot> _bootstrap() async {
    try{await widget.services.sync.refreshCatalog();}catch(_){ }
    final works=await repo.all();
    final recent=await repo.recentReading(widget.services.profileId);
    final offline=await widget.services.db.readyOfflineWorkIds();
    favoriteIds=await repo.favorites(widget.services.profileId);
    return _LibrarySnapshot(works:works,recent:recent,offlineWorkIds:offline);
  }

  Future<void> reload() async {
    final refresh=_bootstrap();
    setState(()=>initialRefresh=refresh);
    await refresh;
  }

  Future<void> openEdition(Edition edition) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder:(_)=>ReaderSessionPage(edition:edition,services:widget.services),
    ));
    if(mounted)setState(()=>initialRefresh=_loadLocal());
  }

  Future<_LibrarySnapshot> _loadLocal() async {
    final works=await repo.all();
    final recent=await repo.recentReading(widget.services.profileId);
    final offline=await widget.services.db.readyOfflineWorkIds();
    favoriteIds=await repo.favorites(widget.services.profileId);
    return _LibrarySnapshot(works:works,recent:recent,offlineWorkIds:offline);
  }

  Future<void> download(Edition edition)=>widget.services.offlineDownloads.enqueueEdition(edition.id,pinned:true);

  Future<void> setFavorite(Work work,bool value) async {
    await repo.setFavorite(widget.services.profileId,work.id,value);
    if(!mounted)return;
    setState((){
      if(value){favoriteIds.add(work.id);}else{favoriteIds.remove(work.id);}
    });
  }

  Future<void> openWork(Work work,String scope) async {
    final heroTag='$scope:${work.id}';
    await Navigator.of(context).push(MaterialPageRoute(
      builder:(_)=>WorkDetailPage(
        work:work,
        coverCache:widget.services.coverCache,
        heroTag:heroTag,
        favorite:favoriteIds.contains(work.id),
        onFavoriteChanged:(value)=>setFavorite(work,value),
        onOpen:openEdition,
        onDownload:download,
      ),
    ));
    if(mounted)setState((){});
  }

  @override Widget build(BuildContext context)=>FutureBuilder<_LibrarySnapshot>(
    future:initialRefresh,
    builder:(context,snapshot){
      if(snapshot.connectionState!=ConnectionState.done){
        return const _CatalogLoading();
      }
      if(snapshot.hasError){
        return _CatalogFailure(onRetry:reload);
      }
      final data=snapshot.data!;
      return Scaffold(
        extendBody:true,
        body:IndexedStack(index:destination,children:[
          _HomeView(
            data:data,
            coverCache:widget.services.coverCache,
            onRefresh:reload,
            onOpen:openWork,
            onContinue:openEdition,
          ),
          _ExploreView(
            works:data.works,
            coverCache:widget.services.coverCache,
            onRefresh:reload,
            onOpen:openWork,
          ),
          _LibraryView(
            data:data,
            favoriteIds:favoriteIds,
            coverCache:widget.services.coverCache,
            onOpen:openWork,
            onDownloads:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>DownloadsPage(services:widget.services))),
          ),
          _ProfileView(
            data:data,
            services:widget.services,
          ),
        ]),
        bottomNavigationBar:NavigationBar(
          selectedIndex:destination,
          onDestinationSelected:(value)=>setState(()=>destination=value),
          destinations:const[
            NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Início'),
            NavigationDestination(icon:Icon(Icons.search_outlined),selectedIcon:Icon(Icons.manage_search),label:'Explorar'),
            NavigationDestination(icon:Icon(Icons.bookmarks_outlined),selectedIcon:Icon(Icons.bookmarks),label:'Biblioteca'),
            NavigationDestination(icon:Icon(Icons.person_outline),selectedIcon:Icon(Icons.person),label:'Perfil'),
          ],
        ),
      );
    },
  );
}

class _LibrarySnapshot {
  final List<Work> works;
  final List<ReadingEntry> recent;
  final Set<String> offlineWorkIds;
  const _LibrarySnapshot({required this.works,required this.recent,required this.offlineWorkIds});

  int count(String type)=>works.where((work)=>work.type==type).length;
}

class _CatalogLoading extends StatelessWidget {
  const _CatalogLoading();
  @override Widget build(BuildContext context)=>Scaffold(body:Center(child:Column(mainAxisSize:MainAxisSize.min,children:[
    const LumeMark(size:58),
    const SizedBox(height:22),
    Text('Preparando sua biblioteca',style:Theme.of(context).textTheme.titleLarge),
    const SizedBox(height:16),
    const SizedBox(width:150,child:LinearProgressIndicator()),
  ])));
}

class _CatalogFailure extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _CatalogFailure({required this.onRetry});
  @override Widget build(BuildContext context)=>Scaffold(body:SafeArea(child:Center(child:Padding(
    padding:const EdgeInsets.all(28),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      const LumeMark(size:54),
      const SizedBox(height:20),
      Text('A estante local não abriu',style:Theme.of(context).textTheme.headlineSmall,textAlign:TextAlign.center),
      const SizedBox(height:10),
      const Text('Seus downloads continuam preservados. Tente carregar o catálogo novamente.',textAlign:TextAlign.center),
      const SizedBox(height:22),
      FilledButton.icon(onPressed:onRetry,icon:const Icon(Icons.refresh),label:const Text('Tentar novamente')),
    ]),
  ))));
}

class _HomeView extends StatelessWidget {
  final _LibrarySnapshot data;
  final CoverCache coverCache;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Work,String) onOpen;
  final ValueChanged<Edition> onContinue;

  const _HomeView({required this.data,required this.coverCache,required this.onRefresh,required this.onOpen,required this.onContinue});

  @override Widget build(BuildContext context){
    final works=data.works;
    final feature=_featured(works);
    final classics=_section(works,LibrarySection.classics);
    final choices=_choices(works);
    final recent=_section(works,LibrarySection.recent).isNotEmpty
        ?_section(works,LibrarySection.recent)
        :works.reversed.take(12).toList(growable:false);
    final discover=_discover(works);
    return RefreshIndicator(
      onRefresh:onRefresh,
      child:CustomScrollView(
        physics:const AlwaysScrollableScrollPhysics(),
        slivers:[
          const SliverToBoxAdapter(child:_EditorialHeader()),
          if(feature!=null)SliverToBoxAdapter(child:_FeaturePanel(
            work:feature,coverCache:coverCache,onOpen:()=>onOpen(feature,'home-feature'),
          )),
          if(data.recent.isNotEmpty)SliverToBoxAdapter(child:_ContinueShelf(entries:data.recent,coverCache:coverCache,onContinue:onContinue,onOpen:onOpen)),
          if(discover.isNotEmpty)_ShelfSliver(title:'Descubra algo novo',eyebrow:'PARA SAIR DO ÓBVIO',works:discover,scope:'home-discover',coverCache:coverCache,onOpen:onOpen),
          if(classics.isNotEmpty)_ShelfSliver(title:'Grandes Clássicos',eyebrow:'LEITURAS QUE PERMANECEM',works:classics.take(14).toList(),scope:'home-classics',coverCache:coverCache,onOpen:onOpen),
          if(choices.isNotEmpty)_ShelfSliver(title:'Escolhas da LUME',eyebrow:'CURADORIA DO GRÊMIO',works:choices.take(14).toList(),scope:'home-choices',coverCache:coverCache,onOpen:onOpen),
          if(recent.isNotEmpty)_ShelfSliver(title:'Adicionados recentemente',eyebrow:'CHEGARAM ÀS ESTANTES',works:recent.take(14).toList(),scope:'home-recent',coverCache:coverCache,onOpen:onOpen),
          if(works.isEmpty)const SliverFillRemaining(hasScrollBody:false,child:_EmptyLibrary()),
          const SliverToBoxAdapter(child:SizedBox(height:112)),
        ],
      ),
    );
  }

  Work? _featured(List<Work> works){
    if(works.isEmpty)return null;
    for(final section in const[LibrarySection.recommendations,LibrarySection.essentials,LibrarySection.classics]){
      for(final work in works){if(work.sections.contains(section))return work;}
    }
    return works.first;
  }

  List<Work> _section(List<Work> works,String section)=>works.where((work)=>work.sections.contains(section)).toList(growable:false);

  List<Work> _choices(List<Work> works){
    final seen=<String>{};
    return works.where((work)=>work.sections.any(const[LibrarySection.recommendations,LibrarySection.bestWritten,LibrarySection.essentials].contains)&&seen.add(work.id)).toList(growable:false);
  }

  List<Work> _discover(List<Work> works){
    if(works.length<=12)return works;
    final result=<Work>[];
    final types=[ContentType.book,ContentType.comic,ContentType.manga,ContentType.graphicNovel,ContentType.magazine];
    for(var offset=0;result.length<12;offset++){
      var added=false;
      for(final type in types){
        final matches=works.where((work)=>work.type==type).toList(growable:false);
        if(offset<matches.length){result.add(matches[offset]);added=true;if(result.length==12)break;}
      }
      if(!added)break;
    }
    return result;
  }
}

class _EditorialHeader extends StatelessWidget {
  const _EditorialHeader();
  @override Widget build(BuildContext context)=>SafeArea(bottom:false,child:Padding(
    padding:const EdgeInsets.fromLTRB(20,18,20,18),
    child:Row(children:[
      const LumeMark(size:38),
      const SizedBox(width:12),
      Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('LUME',style:Theme.of(context).textTheme.titleLarge?.copyWith(letterSpacing:2.4)),
        Text('BIBLIOTECA ESTUDANTIL',style:Theme.of(context).textTheme.labelSmall?.copyWith(letterSpacing:1.3,color:LumePalette.inkSoft)),
      ]),
      const Spacer(),
      const _EditionBadge(),
    ]),
  ));
}

class _EditionBadge extends StatelessWidget {
  const _EditionBadge();
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:10,vertical:7),
    decoration:BoxDecoration(border:Border.all(color:const Color(0x381D211E)),borderRadius:BorderRadius.circular(999)),
    child:Text('NOVA EDIÇÃO',style:Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight:FontWeight.w900,letterSpacing:.8,color:LumePalette.emberDeep)),
  );
}

class _FeaturePanel extends StatelessWidget {
  final Work work;
  final CoverCache coverCache;
  final VoidCallback onOpen;
  const _FeaturePanel({required this.work,required this.coverCache,required this.onOpen});

  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.fromLTRB(16,4,16,30),
    child:InkWell(
      borderRadius:BorderRadius.circular(26),
      onTap:onOpen,
      child:Ink(
        height:286,
        decoration:BoxDecoration(
          borderRadius:BorderRadius.circular(26),
          gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF435E4C),LumePalette.night,Color(0xFF6E3425)]),
        ),
        child:Stack(children:[
          Positioned(right:-58,top:-70,child:Container(width:210,height:210,decoration:BoxDecoration(shape:BoxShape.circle,border:Border.all(color:Colors.white.withValues(alpha:.1),width:42)))),
          Padding(
            padding:const EdgeInsets.all(22),
            child:Row(children:[
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
                Text('LEITURA EM DESTAQUE',style:Theme.of(context).textTheme.labelSmall?.copyWith(color:const Color(0xFFF1C47F),fontWeight:FontWeight.w900,letterSpacing:1.4)),
                const SizedBox(height:12),
                Text(work.title,maxLines:4,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.headlineMedium?.copyWith(color:Colors.white)),
                if(work.author!=null)...[const SizedBox(height:8),Text(work.author!,maxLines:2,style:Theme.of(context).textTheme.bodyMedium?.copyWith(color:Colors.white.withValues(alpha:.72)))],
                const SizedBox(height:18),
                Row(children:[const Icon(Icons.arrow_forward,color:Colors.white,size:19),const SizedBox(width:8),Text('Conhecer a obra',style:Theme.of(context).textTheme.labelLarge?.copyWith(color:Colors.white))]),
              ])),
              const SizedBox(width:18),
              SizedBox(width:126,height:204,child:Material(
                elevation:16,shadowColor:Colors.black.withValues(alpha:.55),borderRadius:BorderRadius.circular(9),clipBehavior:Clip.antiAlias,
                child:WorkCoverImage(work:work,cache:coverCache,heroTag:'home-feature:${work.id}',borderRadius:BorderRadius.zero),
              )),
            ]),
          ),
        ]),
      ),
    ),
  );
}

class _ContinueShelf extends StatelessWidget {
  final List<ReadingEntry> entries;
  final CoverCache coverCache;
  final ValueChanged<Edition> onContinue;
  final Future<void> Function(Work,String) onOpen;
  const _ContinueShelf({required this.entries,required this.coverCache,required this.onContinue,required this.onOpen});

  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.only(bottom:30),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const _SectionTitle(eyebrow:'DE VOLTA À HISTÓRIA',title:'Continue lendo'),
      const SizedBox(height:14),
      SizedBox(height:166,child:ListView.separated(
        padding:const EdgeInsets.symmetric(horizontal:16),
        scrollDirection:Axis.horizontal,
        itemCount:entries.length,
        separatorBuilder:(_,__)=>const SizedBox(width:12),
        itemBuilder:(context,index){
          final entry=entries[index];
          return SizedBox(width:292,child:Card(child:InkWell(
            borderRadius:BorderRadius.circular(18),
            onTap:()=>onContinue(entry.edition),
            onLongPress:()=>onOpen(entry.work,'continue-$index'),
            child:Padding(padding:const EdgeInsets.all(12),child:Row(children:[
              SizedBox(width:86,height:132,child:WorkCoverImage(work:entry.work,cache:coverCache,heroTag:'continue-$index:${entry.work.id}')),
              const SizedBox(width:14),
              Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,mainAxisAlignment:MainAxisAlignment.center,children:[
                Text(entry.work.title,maxLines:3,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.titleMedium),
                const SizedBox(height:12),
                LinearProgressIndicator(value:entry.percent,minHeight:5,borderRadius:BorderRadius.circular(99)),
                const SizedBox(height:7),
                Text('${(entry.percent*100).round()}% lido',style:Theme.of(context).textTheme.labelMedium?.copyWith(color:LumePalette.emberDeep,fontWeight:FontWeight.w800)),
              ])),
            ])),
          )));
        },
      )),
    ]),
  );
}

class _ShelfSliver extends StatelessWidget {
  final String title,eyebrow,scope;
  final List<Work> works;
  final CoverCache coverCache;
  final Future<void> Function(Work,String) onOpen;
  const _ShelfSliver({required this.title,required this.eyebrow,required this.works,required this.scope,required this.coverCache,required this.onOpen});

  @override Widget build(BuildContext context)=>SliverToBoxAdapter(child:Padding(
    padding:const EdgeInsets.only(bottom:32),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      _SectionTitle(eyebrow:eyebrow,title:title),
      const SizedBox(height:14),
      SizedBox(height:258,child:ListView.separated(
        padding:const EdgeInsets.symmetric(horizontal:16),
        scrollDirection:Axis.horizontal,
        itemCount:works.length,
        separatorBuilder:(_,__)=>const SizedBox(width:13),
        itemBuilder:(context,index)=>_PosterCard(
          work:works[index],width:132,scope:'$scope-$index',coverCache:coverCache,onOpen:onOpen,
        ),
      )),
    ]),
  ));
}

class _SectionTitle extends StatelessWidget {
  final String eyebrow,title;
  const _SectionTitle({required this.eyebrow,required this.title});
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.symmetric(horizontal:20),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(eyebrow,style:Theme.of(context).textTheme.labelSmall?.copyWith(color:LumePalette.emberDeep,fontWeight:FontWeight.w900,letterSpacing:1.3)),
      const SizedBox(height:4),
      Text(title,style:Theme.of(context).textTheme.headlineSmall),
    ]),
  );
}

class _PosterCard extends StatelessWidget {
  final Work work;
  final double? width;
  final String scope;
  final CoverCache coverCache;
  final Future<void> Function(Work,String) onOpen;
  const _PosterCard({required this.work,this.width,required this.scope,required this.coverCache,required this.onOpen});

  @override Widget build(BuildContext context)=>SizedBox(
    width:width,
    child:InkWell(
      borderRadius:BorderRadius.circular(12),
      onTap:()=>onOpen(work,scope),
      child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Expanded(child:Container(
          decoration:BoxDecoration(borderRadius:BorderRadius.circular(10),boxShadow:[BoxShadow(color:Colors.black.withValues(alpha:.16),blurRadius:14,offset:const Offset(0,7))]),
          child:WorkCoverImage(work:work,cache:coverCache,heroTag:'$scope:${work.id}',borderRadius:BorderRadius.circular(10)),
        )),
        const SizedBox(height:10),
        Text(work.title,maxLines:2,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight:FontWeight.w800,height:1.16)),
        const SizedBox(height:3),
        Text(work.author??_typeLabel(work.type),maxLines:1,overflow:TextOverflow.ellipsis,style:Theme.of(context).textTheme.bodySmall),
      ]),
    ),
  );
}

class _ExploreView extends StatefulWidget {
  final List<Work> works;
  final CoverCache coverCache;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Work,String) onOpen;
  const _ExploreView({required this.works,required this.coverCache,required this.onRefresh,required this.onOpen});
  @override State<_ExploreView> createState()=>_ExploreViewState();
}

class _ExploreViewState extends State<_ExploreView> {
  final search=TextEditingController();
  String filter='all';
  String query='';
  @override void dispose(){search.dispose();super.dispose();}

  List<Work> get visible=>widget.works.where((work){
    final typeMatches=switch(filter){
      'book'=>work.type==ContentType.book,
      'hq'=>work.type==ContentType.comic||work.type==ContentType.graphicNovel,
      'manga'=>work.type==ContentType.manga,
      _=>true,
    };
    if(!typeMatches)return false;
    final needle=_fold(query);
    if(needle.isEmpty)return true;
    return _fold('${work.title} ${work.author??''} ${work.tags.join(' ')}').contains(needle);
  }).toList(growable:false);

  @override Widget build(BuildContext context){
    final result=visible;
    return RefreshIndicator(
      onRefresh:widget.onRefresh,
      child:CustomScrollView(physics:const AlwaysScrollableScrollPhysics(),slivers:[
        SliverToBoxAdapter(child:SafeArea(bottom:false,child:Padding(
          padding:const EdgeInsets.fromLTRB(20,22,20,10),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Explorar',style:Theme.of(context).textTheme.displayMedium),
            const SizedBox(height:8),
            Text('Encontre sua próxima leitura entre livros, HQs e mangás.',style:Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height:20),
            SearchBar(
              controller:search,
              hintText:'Título, autor ou tema',
              leading:const Icon(Icons.search),
              trailing:[if(query.isNotEmpty)IconButton(tooltip:'Limpar busca',onPressed:(){search.clear();setState(()=>query='');},icon:const Icon(Icons.close))],
              onChanged:(value)=>setState(()=>query=value),
            ),
            const SizedBox(height:16),
            SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
              _filterChip('all','Todos'),
              _filterChip('book','Livros'),
              _filterChip('hq','HQs'),
              _filterChip('manga','Mangás'),
            ])),
            const SizedBox(height:14),
            Text('${result.length} ${result.length==1?'obra encontrada':'obras encontradas'}',style:Theme.of(context).textTheme.labelLarge?.copyWith(color:LumePalette.inkSoft)),
          ]),
        ))),
        if(result.isEmpty)
          const SliverFillRemaining(hasScrollBody:false,child:Center(child:Padding(padding:EdgeInsets.all(30),child:Text('Nenhuma obra corresponde a esta busca.',textAlign:TextAlign.center))))
        else
          SliverPadding(
            padding:const EdgeInsets.fromLTRB(16,10,16,112),
            sliver:SliverLayoutBuilder(builder:(context,constraints){
              final width=constraints.crossAxisExtent;
              final columns=width>=1000?7:width>=720?5:width>=480?3:2;
              return SliverGrid(
                gridDelegate:SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:columns,childAspectRatio:.54,crossAxisSpacing:14,mainAxisSpacing:22),
                delegate:SliverChildBuilderDelegate(
                  (context,index)=>_PosterCard(work:result[index],scope:'explore-$index',coverCache:widget.coverCache,onOpen:widget.onOpen),
                  childCount:result.length,
                ),
              );
            }),
          ),
      ]),
    );
  }

  Widget _filterChip(String value,String label)=>Padding(
    padding:const EdgeInsets.only(right:8),
    child:FilterChip(label:Text(label),selected:filter==value,onSelected:(_)=>setState(()=>filter=value)),
  );

  String _fold(String value)=>value.toLowerCase()
    .replaceAll(RegExp('[áàãâä]'),'a').replaceAll(RegExp('[éèêë]'),'e')
    .replaceAll(RegExp('[íìîï]'),'i').replaceAll(RegExp('[óòõôö]'),'o')
    .replaceAll(RegExp('[úùûü]'),'u').replaceAll('ç','c');
}

class _LibraryView extends StatelessWidget {
  final _LibrarySnapshot data;
  final Set<String> favoriteIds;
  final CoverCache coverCache;
  final Future<void> Function(Work,String) onOpen;
  final VoidCallback onDownloads;
  const _LibraryView({required this.data,required this.favoriteIds,required this.coverCache,required this.onOpen,required this.onDownloads});

  @override Widget build(BuildContext context){
    final favorites=data.works.where((work)=>favoriteIds.contains(work.id)).toList(growable:false);
    final offline=data.works.where((work)=>data.offlineWorkIds.contains(work.id)).toList(growable:false);
    return CustomScrollView(slivers:[
      SliverToBoxAdapter(child:SafeArea(bottom:false,child:Padding(
        padding:const EdgeInsets.fromLTRB(20,22,20,24),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Sua biblioteca',style:Theme.of(context).textTheme.displayMedium),
          const SizedBox(height:8),
          Text('O que você guardou e o que pode ler sem internet.',style:Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height:22),
          Row(children:[
            Expanded(child:_LibraryMetric(value:'${favorites.length}',label:'favoritos',icon:Icons.bookmark_outline)),
            const SizedBox(width:12),
            Expanded(child:_LibraryMetric(value:'${offline.length}',label:'offline',icon:Icons.offline_pin_outlined)),
          ]),
          const SizedBox(height:12),
          SizedBox(width:double.infinity,child:OutlinedButton.icon(onPressed:onDownloads,icon:const Icon(Icons.download_for_offline_outlined),label:const Text('Gerenciar downloads'))),
        ]),
      ))),
      if(favorites.isNotEmpty)_ShelfSliver(title:'Favoritos',eyebrow:'GUARDADOS POR VOCÊ',works:favorites,scope:'library-favorites',coverCache:coverCache,onOpen:onOpen),
      if(offline.isNotEmpty)_ShelfSliver(title:'Disponíveis offline',eyebrow:'LEIA ONDE ESTIVER',works:offline,scope:'library-offline',coverCache:coverCache,onOpen:onOpen),
      if(favorites.isEmpty&&offline.isEmpty)const SliverFillRemaining(hasScrollBody:false,child:Center(child:Padding(
        padding:EdgeInsets.fromLTRB(28,0,28,100),
        child:Column(mainAxisSize:MainAxisSize.min,children:[
          Icon(Icons.collections_bookmark_outlined,size:54,color:LumePalette.inkSoft),
          SizedBox(height:16),
          Text('Sua estante começa aqui',style:TextStyle(fontFamily:'serif',fontSize:24,fontWeight:FontWeight.w700)),
          SizedBox(height:8),
          Text('Marque obras como favoritas ou baixe uma edição para vê-las reunidas nesta área.',textAlign:TextAlign.center),
        ]),
      ))),
      const SliverToBoxAdapter(child:SizedBox(height:112)),
    ]);
  }
}

class _LibraryMetric extends StatelessWidget {
  final String value,label;
  final IconData icon;
  const _LibraryMetric({required this.value,required this.label,required this.icon});
  @override Widget build(BuildContext context)=>Card(child:Padding(
    padding:const EdgeInsets.all(16),
    child:Row(children:[
      Icon(icon,color:LumePalette.ember),const SizedBox(width:12),
      Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(value,style:Theme.of(context).textTheme.titleLarge),Text(label,style:Theme.of(context).textTheme.bodySmall)]),
    ]),
  ));
}

class _ProfileView extends StatelessWidget {
  final _LibrarySnapshot data;
  final AppServices services;
  const _ProfileView({required this.data,required this.services});

  @override Widget build(BuildContext context){
    final admin=services.api.session.role=='admin';
    return CustomScrollView(slivers:[
      SliverToBoxAdapter(child:Container(
        color:LumePalette.night,
        child:SafeArea(bottom:false,child:Padding(
          padding:const EdgeInsets.fromLTRB(20,26,20,28),
          child:Row(children:[
            Container(width:58,height:58,decoration:const BoxDecoration(color:Color(0xFFF0D5C8),shape:BoxShape.circle),child:Icon(admin?Icons.admin_panel_settings_outlined:Icons.person_outline,color:LumePalette.emberDeep,size:30)),
            const SizedBox(width:16),
            Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(admin?'Administração LUME':'Leitor LUME',style:Theme.of(context).textTheme.headlineSmall?.copyWith(color:Colors.white)),
              const SizedBox(height:4),
              Text(admin?'Gerenciamento do acervo e dos estudantes':'Leituras sincronizadas neste perfil',style:Theme.of(context).textTheme.bodySmall?.copyWith(color:Colors.white.withValues(alpha:.7))),
            ])),
            const LumeMark(size:40,color:Color(0xFFE9BA73)),
          ]),
        )),
      )),
      SliverToBoxAdapter(child:Padding(
        padding:const EdgeInsets.all(20),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('O acervo agora',style:Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height:14),
          Wrap(spacing:10,runSpacing:10,children:[
            _CountChip(value:data.works.length,label:'obras'),
            _CountChip(value:data.count(ContentType.book),label:'livros'),
            _CountChip(value:data.count(ContentType.comic)+data.count(ContentType.graphicNovel),label:'HQs'),
            _CountChip(value:data.count(ContentType.manga),label:'mangás'),
          ]),
          const SizedBox(height:30),
          Text('Leitura e aparelho',style:Theme.of(context).textTheme.titleLarge),
          const SizedBox(height:8),
          _ProfileAction(icon:Icons.download_for_offline_outlined,title:'Downloads',subtitle:'Fila e obras salvas',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>DownloadsPage(services:services)))),
          _ProfileAction(icon:Icons.system_update_alt,title:'Atualizações',subtitle:'Novas versões dos arquivos offline',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>MediaUpdatesPage(services:services)))),
          _ProfileAction(icon:Icons.wifi_outlined,title:'Uso de dados',subtitle:'Preferências de Wi-Fi e rede móvel',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>NetworkPreferencesPage(services:services)))),
          if(admin)...[
            const SizedBox(height:24),
            Text('Administração',style:Theme.of(context).textTheme.titleLarge),
            const SizedBox(height:8),
            _ProfileAction(icon:Icons.groups_2_outlined,title:'Usuários e turmas',subtitle:'Até 91 perfis ativos, incluindo o Admin',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminUsersPage(services:services)))),
            _ProfileAction(icon:Icons.edit_note_outlined,title:'Gerenciar catálogo',subtitle:'Revisões e metadados do acervo',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminCatalogPage(services:services)))),
            _ProfileAction(icon:Icons.monitor_heart_outlined,title:'Diagnóstico do catálogo',subtitle:'Integridade da cópia local',onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>CatalogDiagnosticsPage(services:services)))),
          ],
          const SizedBox(height:24),
          SizedBox(width:double.infinity,child:OutlinedButton.icon(
            onPressed:()=>_logout(context),icon:const Icon(Icons.logout),label:const Text('Sair deste perfil'),
          )),
          const SizedBox(height:112),
        ]),
      )),
    ]);
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed=await showDialog<bool>(context:context,builder:(dialogContext)=>AlertDialog(
      title:const Text('Sair do LUME?'),
      content:const Text('Seu progresso e seus downloads locais serão preservados neste aparelho.'),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(dialogContext,false),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(dialogContext,true),child:const Text('Sair')),
      ],
    ));
    if(confirmed==true)await services.api.logout();
  }
}

class _CountChip extends StatelessWidget {
  final int value;
  final String label;
  const _CountChip({required this.value,required this.label});
  @override Widget build(BuildContext context)=>Container(
    padding:const EdgeInsets.symmetric(horizontal:14,vertical:10),
    decoration:BoxDecoration(color:const Color(0xFFFAF7F0),borderRadius:BorderRadius.circular(14),border:Border.all(color:const Color(0x261D211E))),
    child:Text('$value $label',style:Theme.of(context).textTheme.labelLarge),
  );
}

class _ProfileAction extends StatelessWidget {
  final IconData icon;
  final String title,subtitle;
  final VoidCallback onTap;
  const _ProfileAction({required this.icon,required this.title,required this.subtitle,required this.onTap});
  @override Widget build(BuildContext context)=>ListTile(
    contentPadding:const EdgeInsets.symmetric(vertical:3),
    leading:Container(width:44,height:44,decoration:BoxDecoration(color:Theme.of(context).colorScheme.secondaryContainer,borderRadius:BorderRadius.circular(13)),child:Icon(icon,color:LumePalette.forest)),
    title:Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),
    subtitle:Text(subtitle),
    trailing:const Icon(Icons.chevron_right),
    onTap:onTap,
  );
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();
  @override Widget build(BuildContext context)=>Center(child:Padding(
    padding:const EdgeInsets.all(32),
    child:Column(mainAxisSize:MainAxisSize.min,children:[
      const LumeMark(size:62),const SizedBox(height:18),
      Text('O acervo está a caminho',style:Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height:8),
      const Text('Conecte-se para receber a primeira revisão do catálogo.',textAlign:TextAlign.center),
    ]),
  ));
}

String _typeLabel(String type)=>switch(type){
  ContentType.manga=>'Mangá',
  ContentType.comic=>'HQ',
  ContentType.graphicNovel=>'Graphic novel',
  ContentType.magazine=>'Revista',
  _=>'Livro',
};
