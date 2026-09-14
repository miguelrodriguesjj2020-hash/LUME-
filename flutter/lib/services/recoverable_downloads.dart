import 'dart:async';
import 'dart:io';
import '../data/database.dart';
import 'api.dart';
import 'download.dart';
import 'download_queue.dart';
import 'media_descriptor.dart';

/// Durable intent + ephemeral authorization. Only edition identity is persisted;
/// signed/provider URLs are always resolved fresh at execution time.
class DownloadSnapshot {
  final String editionId; final String state; final int receivedBytes; final int? expectedBytes;
  const DownloadSnapshot(this.editionId,this.state,this.receivedBytes,this.expectedBytes);
  double? get fraction => expectedBytes == null || expectedBytes == 0 ? null : receivedBytes / expectedBytes!;
}

class RecoverableDownloadCoordinator {
  final LumeDb db; final LumeApi api; final DownloadManager manager; final Directory mediaDirectory;
  late final DownloadQueue queue;
  final _changes=StreamController<DownloadSnapshot>.broadcast();
  Stream<DownloadSnapshot> get changes=>_changes.stream;
  RecoverableDownloadCoordinator({required this.db,required this.api,required this.manager,required this.mediaDirectory,int concurrency=2}){
    queue=DownloadQueue(manager,concurrency:concurrency,onTerminal:_onTerminal,onProgress:_onProgress);
  }

  Future<void> initialize() async {
    await db.normalizeInterruptedDownloads();
    for(final row in await db.recoverableDownloadJobs()){
      if(row['state']=='failed')continue;
      _queue(row['edition_id'] as String);
    }
  }

  Future<void> enqueueEdition(String editionId,{bool pinned=false}) async {
    await db.upsertDownloadJob(editionId:editionId,state:'queued',request:{'editionId':editionId,'pinned':pinned});
    _queue(editionId);
  }

  Future<void> retry(String editionId) async {await db.setDownloadJobState(editionId,'queued');_queue(editionId);}
  void pause(String editionId){queue.pause(editionId);db.setDownloadJobState(editionId,'paused');}
  void cancel(String editionId){queue.cancel(editionId);db.deleteDownloadJob(editionId);}
  Future<void> resume(String editionId) async {await db.setDownloadJobState(editionId,'queued');_queue(editionId);}

  void _queue(String editionId){
    queue.enqueue(DownloadTask(
      editionId:editionId,
      directory:mediaDirectory,
      resolve:() async {
        final media=MediaDescriptor.fromJson(await api.media(editionId));
        return ResolvedDownload(uri:media.url,expectedBytes:media.byteSize,expectedSha256:media.sha256,sourceTag:media.fingerprint,headers:media.headers);
      },
    ));
  }

  void _onProgress(String editionId, OfflineState state, int receivedBytes, int? expectedBytes){
    if(!_changes.isClosed)_changes.add(DownloadSnapshot(editionId,state.name,receivedBytes,expectedBytes));
  }

  Future<void> reconcile() async {
    for(final row in await db.recoverableDownloadJobs()){
      if(row['state']=='queued')_queue(row['edition_id'] as String);
    }
  }

  Future<void> dispose() async { await _changes.close(); }

  Future<void> _onTerminal(String editionId,String state) async {
    if(state=='cancelled'){await db.deleteDownloadJob(editionId);return;}
    await db.setDownloadJobState(editionId,state);
    if(state=='ready'){
      final jobs=await db.listDownloadJobs();
      for(final row in jobs){
        if(row['edition_id']==editionId){final req=Map<String,dynamic>.from(row['request'] as Map);if(req['pinned']==true)await db.setOfflinePinned(editionId,true);break;}
      }
    }
  }
}
