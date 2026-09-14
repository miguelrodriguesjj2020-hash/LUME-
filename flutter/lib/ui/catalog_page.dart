import 'package:flutter/material.dart';
import '../models/catalog.dart';
import '../readers/reader_session_page.dart';
import '../services/app_services.dart';
import '../services/library_repository.dart';
import '../services/cover_cache.dart';
import 'downloads_page.dart';
import 'media_updates_page.dart';
import 'network_preferences_page.dart';
import 'catalog_diagnostics_page.dart';
import 'admin_catalog_page.dart';
import 'admin_users_page.dart';
import 'cover_image.dart';

class CatalogPage extends StatefulWidget {
  final AppServices services;
  const CatalogPage({super.key, required this.services});
  @override State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final LibraryRepository repo = LibraryRepository(widget.services.db);
  late Future<void> initialRefresh;

  @override
  void initState() {
    super.initState();
    initialRefresh = widget.services.sync.refreshCatalog().then((_) {}).catchError((_) {});
  }

  Future<void> _openEdition(BuildContext context, Edition edition) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ReaderSessionPage(edition: edition, services: widget.services),
    ));
  }

  @override Widget build(BuildContext context) => FutureBuilder<void>(
        future: initialRefresh,
        builder: (context, _) => DefaultTabController(
          length: 3,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('LUME'),
              actions:[
                IconButton(tooltip:'Atualizações',icon:const Icon(Icons.system_update_alt),onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>MediaUpdatesPage(services:widget.services)))),
                IconButton(tooltip:'Downloads',icon:const Icon(Icons.download_for_offline_outlined),onPressed:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>DownloadsPage(services:widget.services)))),
                PopupMenuButton<String>(onSelected:(value){
                  if(value=='network')Navigator.of(context).push(MaterialPageRoute(builder:(_)=>NetworkPreferencesPage(services:widget.services)));
                  if(value=='diagnostics')Navigator.of(context).push(MaterialPageRoute(builder:(_)=>CatalogDiagnosticsPage(services:widget.services)));
                  if(value=='admin')Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminCatalogPage(services:widget.services)));
                  if(value=='users')Navigator.of(context).push(MaterialPageRoute(builder:(_)=>AdminUsersPage(services:widget.services)));
                },itemBuilder:(_)=>[
                  const PopupMenuItem(value:'network',child:Text('Uso de dados')),
                  if(widget.services.api.session.role=='admin')const PopupMenuItem(value:'users',child:Text('Usuários e turmas')),
                  if(widget.services.api.session.role=='admin')const PopupMenuItem(value:'admin',child:Text('Gerenciar catálogo')),
                  if(widget.services.api.session.role=='admin')const PopupMenuItem(value:'diagnostics',child:Text('Diagnóstico do catálogo')),
                ])
              ],
              bottom: const TabBar(tabs: [Tab(text: 'Livros'), Tab(text: 'HQs'), Tab(text: 'Mangás')]),
            ),
            body: TabBarView(children: [
              _Shelf(loader: repo.books, coverCache:widget.services.coverCache, onOpen: (e) => _openEdition(context, e), onDownload:(e)=>widget.services.offlineDownloads.enqueueEdition(e.id,pinned:true)),
              _Shelf(loader: repo.comics, coverCache:widget.services.coverCache, onOpen: (e) => _openEdition(context, e), onDownload:(e)=>widget.services.offlineDownloads.enqueueEdition(e.id,pinned:true)),
              _Shelf(loader: repo.manga, coverCache:widget.services.coverCache, onOpen: (e) => _openEdition(context, e), onDownload:(e)=>widget.services.offlineDownloads.enqueueEdition(e.id,pinned:true)),
            ]),
          ),
        ),
      );
}

class _Shelf extends StatefulWidget {
  final Future<List<Work>> Function() loader;
  final CoverCache coverCache;
  final ValueChanged<Edition> onOpen;
  final Future<void> Function(Edition) onDownload;
  const _Shelf({required this.loader,required this.coverCache,required this.onOpen,required this.onDownload});
  @override State<_Shelf> createState() => _ShelfState();
}

class _ShelfState extends State<_Shelf> {
  late Future<List<Work>> future = widget.loader();
  String? selectedSection;
  Future<void> refresh() async { setState(() => future = widget.loader()); await future; }

  List<String> _sections(List<Work> works){
    final found=<String>{};
    for(final w in works){found.addAll(w.sections);}
    const priority=[
      LibrarySection.classics,
      LibrarySection.recommendations,
      LibrarySection.bestWritten,
      LibrarySection.essentials,
      LibrarySection.recent,
    ];
    final result=<String>[];
    for(final x in priority){if(found.remove(x))result.add(x);}
    result.addAll(found.toList()..sort());
    return result;
  }

  @override Widget build(BuildContext context) => RefreshIndicator(
        onRefresh: refresh,
        child: FutureBuilder<List<Work>>(
          future: future,
          builder: (context, snapshot) {
            if (snapshot.hasError) return ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Erro ao abrir catálogo: ${snapshot.error}'))]);
            if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
            final works = snapshot.data!;
            if (works.isEmpty) return ListView(children: const [Padding(padding: EdgeInsets.all(24), child: Text('Nenhuma obra sincronizada ainda.'))]);
            final sections=_sections(works);
            if(selectedSection!=null && !sections.contains(selectedSection)){
              selectedSection=null;
            }
            final visible=selectedSection==null
                ? works
                : works.where((w)=>w.sections.contains(selectedSection)).toList(growable:false);
            return CustomScrollView(
              slivers:[
                if(sections.isNotEmpty) SliverToBoxAdapter(
                  child:SingleChildScrollView(
                    scrollDirection:Axis.horizontal,
                    padding:const EdgeInsets.fromLTRB(16,12,16,0),
                    child:Row(children:[
                      ChoiceChip(
                        label:const Text('Todos'),
                        selected:selectedSection==null,
                        onSelected:(_)=>setState(()=>selectedSection=null),
                      ),
                      const SizedBox(width:8),
                      for(final section in sections)...[
                        ChoiceChip(
                          label:Text(section),
                          selected:selectedSection==section,
                          onSelected:(selected)=>setState(()=>selectedSection=selected ? section : null),
                        ),
                        const SizedBox(width:8),
                      ],
                    ]),
                  ),
                ),
                if(visible.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody:false,
                    child:Center(child:Padding(
                      padding:EdgeInsets.all(24),
                      child:Text('Nenhuma obra nesta seção editorial.'),
                    )),
                  )
                else
                  SliverPadding(
                    padding:const EdgeInsets.all(16),
                    sliver:SliverGrid(
                      gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount:2,
                        childAspectRatio:.62,
                        crossAxisSpacing:14,
                        mainAxisSpacing:18,
                      ),
                      delegate:SliverChildBuilderDelegate(
                        (_,index)=>_WorkCard(work:visible[index],coverCache:widget.coverCache,onOpen:widget.onOpen,onDownload:widget.onDownload),
                        childCount:visible.length,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      );
}

class _WorkCard extends StatelessWidget {
  final Work work;
  final CoverCache coverCache;
  final ValueChanged<Edition> onOpen;
  final Future<void> Function(Edition) onDownload;
  const _WorkCard({required this.work,required this.coverCache,required this.onOpen,required this.onDownload});
  @override Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () async {
            final edition = await showModalBottomSheet<Edition>(context: context, showDragHandle: true, builder: (_) => _EditionSheet(work: work,onDownload:onDownload));
            if (edition != null && context.mounted) onOpen(edition);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child:SizedBox(width:double.infinity,child:WorkCoverImage(work:work,cache:coverCache))),
              Text(work.title, maxLines: 3, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                work.sections.isEmpty
                  ? '${work.editions.length} ${work.editions.length == 1 ? 'edição' : 'edições'}'
                  : '${work.editions.length} ${work.editions.length == 1 ? 'edição' : 'edições'} · ${work.sections.first}',
                maxLines:2,
                overflow:TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ]),
          ),
        ),
      );
}

class _EditionSheet extends StatelessWidget {
  final Work work;
  final Future<void> Function(Edition) onDownload;
  const _EditionSheet({required this.work,required this.onDownload});
  @override Widget build(BuildContext context) {
    final editions = [...work.editions]..sort((a,b) => (a.volume ?? a.chapter ?? 0).compareTo(b.volume ?? b.chapter ?? 0));
    return SafeArea(child: ListView(shrinkWrap: true, children: [
      ListTile(title: Text(work.title), subtitle: Text('${editions.length} edições disponíveis')),
      for (final e in editions) Builder(builder:(context){
        final unsupportedCbr=e.format.toLowerCase()=='cbr';
        return ListTile(
          leading: Icon(unsupportedCbr ? Icons.lock_outline : Icons.description_outlined),
          title: Text(e.volume != null ? 'Volume ${_n(e.volume!)}' : e.chapter != null ? 'Capítulo ${_n(e.chapter!)}' : e.fileName),
          subtitle: Text(unsupportedCbr
              ? 'CBR · indisponível até validação RAR segura'
              : '${e.format.toUpperCase()} · ${e.language}'),
          trailing: Row(mainAxisSize:MainAxisSize.min,children:[
            IconButton(
              tooltip:unsupportedCbr ? 'CBR ainda não suportado' : 'Baixar para leitura offline',
              icon:Icon(unsupportedCbr ? Icons.block : Icons.download_outlined),
              onPressed:unsupportedCbr ? null : () async {
                await onDownload(e);
                if(context.mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Adicionado à fila de downloads')));
              },
            ),
            Icon(unsupportedCbr ? Icons.lock_outline : Icons.chevron_right),
          ]),
          onTap: unsupportedCbr
              ? ()=>ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('CBR/RAR ainda não possui leitor validado na LUME.')))
              : ()=>Navigator.pop(context,e),
        );
      }),
    ]));
  }
  String _n(double n) => n == n.roundToDouble() ? n.toInt().toString() : n.toString();
}
