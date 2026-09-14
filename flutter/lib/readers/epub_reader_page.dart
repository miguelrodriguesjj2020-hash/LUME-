import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:webview_flutter/webview_flutter.dart';
import '../models/progress.dart';
import 'epub_bridge.dart';
import 'epub_cfi.dart';

class EpubReaderPage extends StatefulWidget {
  final Uri localEntry;
  final String rootPath;
  final List<String> spineEntries;
  final EpubLocator initial;
  final ValueChanged<EpubLocator>? onProgress;
  final bool fixedLayout;
  const EpubReaderPage({
    super.key,
    required this.localEntry,
    required this.rootPath,
    required this.spineEntries,
    required this.initial,
    this.onProgress,
    this.fixedLayout = false,
  });
  @override State<EpubReaderPage> createState() => _EpubReaderPageState();
}

class _EpubReaderPageState extends State<EpubReaderPage> {
  late final WebViewController controller;
  bool initialRestored = false;
  int currentSpineIndex = 0;

  bool _isAllowedLocal(Uri uri) {
    if (uri.scheme == 'about') return true;
    if (uri.scheme != 'file') return false;
    final root = p.normalize(p.absolute(widget.rootPath));
    final candidate = p.normalize(p.absolute(uri.toFilePath()));
    return candidate == root || p.isWithin(root, candidate);
  }

  String _hrefFor(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'file') return widget.initial.href;
    final rel = p.relative(uri.toFilePath(), from: widget.rootPath).replaceAll('\\', '/');
    return rel == '.' ? widget.initial.href : rel;
  }

  String _normalizeRel(String value) =>
      p.normalize(Uri.decodeComponent(value.split('#').first)).replaceAll('\\', '/');

  List<String> get _relativeSpine => widget.spineEntries
      .map((entry)=>p.relative(entry,from:widget.rootPath).replaceAll('\\','/'))
      .map(_normalizeRel)
      .toList(growable:false);

  int _spineIndexForHref(String href) {
    final rel=_normalizeRel(href);
    final spine=_relativeSpine;
    final i=spine.indexOf(rel);
    if(i>=0)return i;
    final fromInitial=widget.initial.spineIndex;
    if(fromInitial!=null && fromInitial>=0 && fromInitial<spine.length)return fromInitial;
    return 0;
  }

  Future<void> _installForPage(String url) async {
    final href=_hrefFor(url);
    final nextIndex=_spineIndexForHref(href);
    if(mounted && nextIndex!=currentSpineIndex)setState(()=>currentSpineIndex=nextIndex);
    await controller.runJavaScript(cfiBridgeInstallScript());
    if (widget.fixedLayout) {
      await controller.runJavaScript("""
        (() => {
          const meta = document.querySelector('meta[name=viewport]');
          if (!meta) { const m=document.createElement('meta'); m.name='viewport'; m.content='width=device-width,initial-scale=1,maximum-scale=1,user-scalable=yes'; document.head.appendChild(m); }
          document.documentElement.style.overflow='auto';
          document.body.style.margin='0';
        })();
      """);
    }
    if (!initialRestored) {
      initialRestored = true;
      await controller.runJavaScript(restoreScript(widget.initial));
    }
    await controller.runJavaScript(progressCaptureScript(href));
  }

  @override void initState() {
    super.initState();
    currentSpineIndex=_spineIndexForHref(
      widget.initial.href.isNotEmpty ? widget.initial.href : _hrefFor(widget.localEntry.toString()),
    );
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && _isAllowedLocal(uri) ? NavigationDecision.navigate : NavigationDecision.prevent;
        },
        onPageFinished: _installForPage,
      ))
      ..addJavaScriptChannel('LumeProgress', onMessageReceived: (message) {
        try {
          final j = Map<String, dynamic>.from(jsonDecode(message.message));
          final href='${j['href'] ?? widget.initial.href}';
          final chapterProgress=((j['progression'] as num?)?.toDouble() ?? 0).clamp(0,1).toDouble();
          final count=widget.spineEntries.isEmpty ? 1 : widget.spineEntries.length;
          final index=_spineIndexForHref(href).clamp(0,count-1).toInt();
          final whole=((index + chapterProgress)/count).clamp(0,1).toDouble();
          widget.onProgress?.call(EpubLocator(
            href,
            cfi: normalizeEpubCfi(j['cfi']),
            progression: chapterProgress,
            bookProgression: whole,
            spineIndex: index,
            spineCount: count,
          ));
        } catch (_) {}
      })
      ..loadFile(widget.localEntry.toFilePath());
  }

  Future<void> _goSpine(int delta) async {
    if(widget.spineEntries.isEmpty)return;
    final next=(currentSpineIndex+delta).clamp(0,widget.spineEntries.length-1).toInt();
    if(next==currentSpineIndex)return;
    currentSpineIndex=next;
    if(mounted)setState((){});
    await controller.loadFile(widget.spineEntries[next]);
  }

  @override Widget build(BuildContext context) {
    final total=widget.spineEntries.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(total>0 ? 'Leitor EPUB • ${currentSpineIndex+1}/$total' : 'Leitor EPUB'),
        actions:[
          IconButton(
            tooltip:'Capítulo anterior',
            onPressed:currentSpineIndex>0 ? ()=>_goSpine(-1) : null,
            icon:const Icon(Icons.chevron_left),
          ),
          IconButton(
            tooltip:'Próximo capítulo',
            onPressed:total>0 && currentSpineIndex<total-1 ? ()=>_goSpine(1) : null,
            icon:const Icon(Icons.chevron_right),
          ),
        ],
      ),
      body: WebViewWidget(controller: controller),
    );
  }
}
