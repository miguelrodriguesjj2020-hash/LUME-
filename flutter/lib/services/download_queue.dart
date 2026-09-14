import 'dart:async';
import 'dart:io';
import 'api.dart';
import 'download.dart';
import 'download_control.dart';

typedef DownloadTerminalCallback = Future<void> Function(String editionId,String state);
typedef DownloadProgressListener = void Function(String editionId, OfflineState state, int receivedBytes, int? expectedBytes);

class ResolvedDownload {
  final Uri uri;
  final int? expectedBytes;
  final String? expectedSha256;
  final String? sourceTag;
  final Map<String,String> headers;
  const ResolvedDownload({required this.uri,this.expectedBytes,this.expectedSha256,this.sourceTag,this.headers=const{}});
}

typedef DownloadResolver = Future<ResolvedDownload> Function();

class DownloadTask {
  final String editionId;
  final Directory directory;
  final DownloadResolver resolve;
  final DownloadControl control=DownloadControl();
  DownloadTask({required this.editionId,required this.directory,required this.resolve});
}

/// Bounded durable queue. Media URLs are resolved when a slot actually becomes
/// available, not when the user taps Download, so short-lived signed URLs do not
/// expire while waiting behind another large volume.
class DownloadQueue {
  final DownloadManager manager; final int concurrency; final DownloadTerminalCallback? onTerminal; final DownloadProgressListener? onProgress;
  final List<DownloadTask> _pending=[]; final Map<String,DownloadTask> _active={}; bool _pumping=false;
  DownloadQueue(this.manager,{this.concurrency=2,this.onTerminal,this.onProgress});
  void enqueue(DownloadTask task){if(_active.containsKey(task.editionId)||_pending.any((x)=>x.editionId==task.editionId))return;_pending.add(task);_pump();}
  void pause(String id){_active[id]?.control.pause();_pending.removeWhere((x)=>x.editionId==id);}
  void cancel(String id){_active[id]?.control.cancel();_pending.removeWhere((x)=>x.editionId==id);}
  Future<void> _pump() async{if(_pumping)return;_pumping=true;try{while(_pending.isNotEmpty&&_active.length<concurrency){final t=_pending.removeAt(0);_active[t.editionId]=t;unawaited(_run(t));}}finally{_pumping=false;}}
  Future<void> _run(DownloadTask t) async{
    var terminal='failed';
    try{
      var resolved=await t.resolve();
      try{
        await manager.download(editionId:t.editionId,uri:resolved.uri,directory:t.directory,expectedBytes:resolved.expectedBytes,expectedSha256:resolved.expectedSha256,headers:resolved.headers,sourceTag:resolved.sourceTag,control:t.control,onProgress:onProgress);
      } on ExpiredMediaAuthorization {
        // One fresh media resolution is safe: the persistent .part + ETag/Range
        // rules still protect integrity if the origin has changed.
        resolved=await t.resolve();
        await manager.download(editionId:t.editionId,uri:resolved.uri,directory:t.directory,expectedBytes:resolved.expectedBytes,expectedSha256:resolved.expectedSha256,headers:resolved.headers,sourceTag:resolved.sourceTag,control:t.control,onProgress:onProgress);
      }
      terminal='ready';
    } on DownloadPaused{terminal='paused';}
      on DownloadCancelled{terminal='cancelled';}
      on SessionExpiredException{terminal='queued';}
      catch(_){terminal='failed';}
    finally{_active.remove(t.editionId);if(onTerminal!=null)await onTerminal!(t.editionId,terminal);_pump();}
  }
}
