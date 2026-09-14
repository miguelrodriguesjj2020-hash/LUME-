import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../data/database.dart';
import 'api.dart';
import 'download.dart';
import 'epub_preparer.dart';
import 'cbz_preparer.dart';
import 'media_cache.dart';
import 'media_open_coordinator.dart';
import 'media_revalidator.dart';
import 'media_replacement.dart';
import 'media_replacement_recovery.dart';
import 'media_updates.dart';
import 'reading_progress.dart';
import 'recoverable_downloads.dart';
import 'network_policy.dart';
import 'connectivity_adapter.dart';
import 'cover_cache.dart';
import 'catalog_diagnostics.dart';
import 'reconnect_coordinator.dart';
import 'storage_policy.dart';
import 'sync.dart';

class AppServices {
  final LumeDb db;
  final LumeApi api;
  final MediaCache mediaCache;
  final CoverCache coverCache;
  final MediaOpenCoordinator mediaOpen;
  final MediaRevalidator mediaRevalidator;
  final MediaReplacementCoordinator mediaReplacement;
  final MediaUpdateService mediaUpdates;
  final SyncCoordinator sync;
  final RecoverableDownloadCoordinator offlineDownloads;
  final NetworkPolicy networkPolicy;
  final ConnectivityAdapter connectivity;
  final CatalogDiagnostics catalogDiagnostics;
  final ReconnectCoordinator reconnect;
  final String profileId;
  final String deviceId;

  AppServices._({
    required this.db,
    required this.api,
    required this.mediaCache,
    required this.coverCache,
    required this.mediaOpen,
    required this.mediaRevalidator,
    required this.mediaReplacement,
    required this.mediaUpdates,
    required this.sync,
    required this.offlineDownloads,
    required this.networkPolicy,
    required this.connectivity,
    required this.catalogDiagnostics,
    required this.reconnect,
    required this.profileId,
    required this.deviceId,
  });


  Future<void> revalidateRecentMedia({int limit=5}) async {
    final assets=await db.recentlyAccessedReadyAssets(limit:limit);
    for(final asset in assets){
      final id=asset['edition_id'] as String?;
      if(id==null || id.isEmpty)continue;
      await mediaRevalidator.check(id);
    }
  }

  ReadingProgressService progress() => ReadingProgressService(
        db,
        profileId: profileId,
        deviceId: deviceId,
      );

  static Future<AppServices> create({
    required Uri apiBase,
    String? profileId,
    LumeApi? existingApi,
    LumeSession? session,
  }) async {
    final db = LumeDb();
    final deviceId = await db.getOrCreateDeviceId();
    await db.repairLegacyOutboxProfiles();
    final app = await getApplicationSupportDirectory();
    final media = Directory('${app.path}/media');
    final prepared = Directory('${app.path}/prepared');
    final covers = Directory('${app.path}/covers');
    await media.create(recursive: true);
    await prepared.create(recursive: true);
    await covers.create(recursive: true);
    final api = existingApi ?? LumeApi(apiBase, session: session);
    final resolvedProfileId = profileId ?? api.session.profileId ?? 'local-profile';
    final cache = MediaCache();
    final storagePolicy = StoragePressurePolicy(db);
    final downloader = DownloadManager(db, storagePolicy: storagePolicy);
    final opener = MediaOpenCoordinator(
      db: db,
      api: api,
      downloads: downloader,
      epubPreparer: EpubPreparer(),
      cbzPreparer: CbzPreparer(),
      cache: cache,
      mediaDirectory: media,
      preparedDirectory: prepared,
    );
    final sync = SyncCoordinator(db, api);
    final replacement=MediaReplacementCoordinator(db,storagePolicy:storagePolicy);
    final recovery=MediaReplacementRecovery(db);
    await recovery.recoverAll(media);
    final networkPolicy=NetworkPolicy(db);
    final connectivity=ConnectivityAdapter();
    final reconnect=ReconnectCoordinator(api:api,sync:sync,profileId:resolvedProfileId);
    final mediaUpdates=MediaUpdateService(db:db,api:api,replacement:replacement,mediaDirectory:media,networkPolicy:networkPolicy,networkClass:connectivity.current);
    final offlineDownloads=RecoverableDownloadCoordinator(db:db,api:api,manager:downloader,mediaDirectory:media);
    await offlineDownloads.initialize();
    return AppServices._(
      db: db,
      api: api,
      mediaCache: cache,
      coverCache: CoverCache(api:api,directory:covers),
      mediaOpen: opener,
      mediaRevalidator: MediaRevalidator(db,api),
      mediaReplacement: replacement,
      mediaUpdates: mediaUpdates,
      sync: sync,
      offlineDownloads: offlineDownloads,
      networkPolicy: networkPolicy,
      connectivity: connectivity,
      catalogDiagnostics: CatalogDiagnostics(db),
      reconnect: reconnect,
      profileId: resolvedProfileId,
      deviceId: deviceId,
    );
  }
}
