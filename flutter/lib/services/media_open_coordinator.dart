import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import '../data/database.dart';
import '../models/catalog.dart';
import '../models/progress.dart';
import 'api.dart';
import 'download.dart';
import 'epub_preparer.dart';
import 'cbz_preparer.dart';
import 'media_cache.dart';
import 'media_descriptor.dart';
import 'prefetch.dart';

class OpenedMedia {
  final String localPath;
  final PreparedEpub? epub;
  final String? epubEntryPath;
  final PreparedCbz? cbz;
  final ReadingLocator? locator;
  const OpenedMedia({required this.localPath, this.epub, this.epubEntryPath, this.cbz, this.locator});
}

class MediaOpenCoordinator {
  final LumeDb db;
  final LumeApi api;
  final DownloadManager downloads;
  final EpubPreparer epubPreparer;
  final CbzPreparer cbzPreparer;
  final MediaCache cache;
  final Directory mediaDirectory;
  final Directory preparedDirectory;

  MediaOpenCoordinator({
    required this.db,
    required this.api,
    required this.downloads,
    required this.epubPreparer,
    required this.cbzPreparer,
    required this.cache,
    required this.mediaDirectory,
    required this.preparedDirectory,
  });

  Future<OpenedMedia> open({required Edition edition, String? profileId}) async {
    final asset = await db.getOfflineAsset(edition.id);
    final readyFile = await _readyFile(asset);
    // Strong offline-first invariant: a verified READY asset is sufficient to
    // read. Opening local media must never require a live session/network.
    // Remote freshness is handled by catalog/sync and explicit revalidation,
    // not on the critical first-paint path.
    late final File local;
    late final String sourceTag;
    if (readyFile != null) {
      local = readyFile;
      sourceTag = (asset?['source_tag'] as String?) ?? 'offline:${edition.id}';
    } else {
      final descriptor = MediaDescriptor.fromJson(await api.media(edition.id));
      local = await _ensureLocal(edition, descriptor, asset: asset, readyFile: null);
      sourceTag = descriptor.sourceTag;
    }

    final progress = profileId == null ? null : await db.getProgress(profileId, edition.id);
    final locator = _locatorFromProgress(progress);

    final format=edition.format.toLowerCase();
    if(format=='cbz'){
      final preparedCbz=await _ensurePreparedCbz(edition,local,sourceTag);
      await db.touchOfflineAsset(edition.id);
      return OpenedMedia(localPath:local.path,cbz:preparedCbz,locator:locator);
    }
    if (format != 'epub') {
      await db.touchOfflineAsset(edition.id);
      return OpenedMedia(localPath: local.path, locator: locator);
    }

    final prepared = await _ensurePreparedEpub(edition, local, sourceTag);
    final initialIndex = _spineIndex(prepared, locator);
    // Warm adjacent chapters without blocking first paint.
    EpubPrefetcher(cache).warm(
      editionId: edition.id,
      spine: prepared.spine,
      currentIndex: initialIndex,
    );
    await db.touchOfflineAsset(edition.id);
    return OpenedMedia(
      localPath: local.path,
      epub: prepared,
      epubEntryPath: prepared.spine[initialIndex],
      locator: locator,
    );
  }

  Future<File?> _readyFile(Map<String, dynamic>? asset) async {
    if (asset == null || asset['state'] != OfflineState.ready.name) return null;
    final path = asset['local_path'] as String?;
    if (path == null) return null;
    final f = File(path);
    return await f.exists() ? f : null;
  }

  Future<File> _ensureLocal(Edition edition, MediaDescriptor descriptor, {Map<String, dynamic>? asset, File? readyFile}) async {
    if (asset != null && asset['state'] == OfflineState.ready.name) {
      final tag = asset['source_tag'] as String?;
      if (readyFile != null && tag == descriptor.sourceTag) return readyFile;
      await db.setOfflineAssetState(edition.id, OfflineState.stale.name);
      cache.hot.clearEdition(edition.id);
    }
    try {
      return await downloads.download(
        editionId: edition.id,
        uri: descriptor.url,
        directory: mediaDirectory,
        expectedBytes: descriptor.byteSize ?? edition.byteSize,
        expectedSha256: descriptor.sha256,
        headers: descriptor.headers,
        sourceTag: descriptor.sourceTag,
      );
    } on ExpiredMediaAuthorization {
      // Reader-open path gets the same signed-URL recovery guarantee as the
      // background queue. Resolve once more; DownloadManager will resume the
      // verified .part only when Range/ETag still agree.
      final fresh = MediaDescriptor.fromJson(await api.media(edition.id));
      return downloads.download(
        editionId: edition.id,
        uri: fresh.url,
        directory: mediaDirectory,
        expectedBytes: fresh.byteSize ?? edition.byteSize,
        expectedSha256: fresh.sha256,
        headers: fresh.headers,
        sourceTag: fresh.sourceTag,
      );
    }
  }

  Future<PreparedEpub> _ensurePreparedEpub(Edition edition, File epub, String sourceTag) async {
    final root = Directory(p.join(preparedDirectory.path, edition.id));
    final marker = File(p.join(root.path, '.lume-prepared.json'));
    if (await marker.exists()) {
      try {
        final j = Map<String, dynamic>.from(jsonDecode(await marker.readAsString()));
        if (j['sourceTag'] == sourceTag) {
          final spine = List<String>.from(j['spine'] ?? const []);
          final rootCanonical=p.normalize(p.absolute(root.path));
          var valid=spine.isNotEmpty;
          for(final entry in spine){
            final candidate=p.normalize(p.absolute(entry));
            if(!(candidate==rootCanonical || p.isWithin(rootCanonical,candidate)) || !await File(candidate).exists()){
              valid=false; break;
            }
          }
          final packagePath='${j['packagePath']}';
          final packageCandidate=p.normalize(p.absolute(p.join(root.path,packagePath)));
          if(!(packageCandidate==rootCanonical || p.isWithin(rootCanonical,packageCandidate)) || !await File(packageCandidate).exists()){
            valid=false;
          }
          if (valid) {
            return PreparedEpub(root, packagePath, spine, j['fixedLayout'] == true);
          }
        }
      } catch (_) {}
    }

    if (await root.exists()) await root.delete(recursive: true);
    cache.hot.clearEdition(edition.id);
    final prepared = await epubPreparer.prepare(epub: epub, destination: root);
    await marker.writeAsString(jsonEncode({
      'sourceTag': sourceTag,
      'packagePath': prepared.packagePath,
      'spine': prepared.spine,
      'fixedLayout': prepared.fixedLayout,
    }), flush: true);
    return prepared;
  }

  Future<PreparedCbz> _ensurePreparedCbz(Edition edition,File cbz,String sourceTag) async {
    final root=Directory(p.join(preparedDirectory.path,'cbz-${edition.id}'));
    final marker=File(p.join(root.path,'.lume-cbz.json'));
    if(await marker.exists()){
      try{
        final j=Map<String,dynamic>.from(jsonDecode(await marker.readAsString()));
        if(j['sourceTag']==sourceTag){
          final pages=List<String>.from(j['pages']??const[]);
          final rootCanonical=p.normalize(p.absolute(root.path));
          var valid=pages.isNotEmpty;
          for(final page in pages){
            final candidate=p.normalize(p.absolute(page));
            if(!(candidate==rootCanonical || p.isWithin(rootCanonical,candidate)) || !await File(candidate).exists()){
              valid=false;break;
            }
          }
          if(valid)return PreparedCbz(root,List.unmodifiable(pages));
        }
      }catch(_){}
    }
    if(await root.exists())await root.delete(recursive:true);
    final prepared=await cbzPreparer.prepare(cbz:cbz,destination:root);
    await cbzPreparer.writeMarker(prepared,marker,sourceTag);
    return prepared;
  }

  ReadingLocator? _locatorFromProgress(Map<String, dynamic>? p) {
    final raw = p?['locator'];
    if (raw is! Map) return null;
    final j = Map<String, dynamic>.from(raw);
    if (j['kind'] == 'page') {
      return PageLocator((j['page'] as num?)?.toInt() ?? 1, pageCount: (j['pageCount'] as num?)?.toInt());
    }
    if (j['kind'] == 'epub') {
      return EpubLocator(
        '${j['href'] ?? ''}',
        cfi: j['cfi'] as String?,
        progression: (j['progression'] as num?)?.toDouble(),
        bookProgression: (j['bookProgression'] as num?)?.toDouble(),
        spineIndex: (j['spineIndex'] as num?)?.toInt(),
        spineCount: (j['spineCount'] as num?)?.toInt(),
      );
    }
    return null;
  }

  int _spineIndex(PreparedEpub p, ReadingLocator? locator) {
    if (locator is! EpubLocator) return 0;
    final stored=locator.spineIndex;
    if(stored!=null && stored>=0 && stored<p.spine.length)return stored;
    if(locator.href.isEmpty)return 0;
    final needle = Uri.decodeComponent(locator.href.split('#').first);
    final i = p.spine.indexWhere((x) => x.endsWith(needle));
    return i < 0 ? 0 : i;
  }
}
