import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../data/database.dart';
import 'download_control.dart';
import 'storage_policy.dart';

class DownloadException implements Exception {
  final String message;
  const DownloadException(this.message);
  @override String toString() => 'DownloadException: $message';
}

class ExpiredMediaAuthorization extends DownloadException {
  final int statusCode;
  const ExpiredMediaAuthorization(this.statusCode):super('media authorization expired ($statusCode)');
}

enum OfflineState { notDownloaded, queued, downloading, verifying, ready, paused, failed, stale, removing }

class DownloadPlan {
  final bool append;
  final Map<String, String> headers;
  const DownloadPlan(this.append, this.headers);
}

DownloadPlan planResume(int bytes, String? etag) {
  if (bytes <= 0) return const DownloadPlan(false, {});
  return DownloadPlan(true, {'Range': 'bytes=$bytes-', if (etag != null && etag.isNotEmpty) 'If-Range': etag});
}

bool validResume(int local, http.StreamedResponse r) {
  if (local == 0) return r.statusCode == 200 || r.statusCode == 206;
  if (r.statusCode != 206) return false;
  final cr = r.headers['content-range'];
  if (cr == null) return false;
  final m = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(cr);
  return m != null && int.parse(m.group(1)!) == local;
}

class ResumeResponseContract {
  final int start;
  final int end;
  final int? total;
  const ResumeResponseContract(this.start,this.end,this.total);
}

ResumeResponseContract? parseContentRange(String? value){
  if(value==null)return null;
  final m=RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(value.trim());
  if(m==null)return null;
  final start=int.parse(m.group(1)!); final end=int.parse(m.group(2)!);
  if(end<start)return null;
  final total=m.group(3)=='*'?null:int.parse(m.group(3)!);
  if(total!=null && (total<=end || total<=0))return null;
  return ResumeResponseContract(start,end,total);
}

void validateResponseContract({required int localBytes,required http.StreamedResponse response,int? expectedBytes,String? expectedEtag}){
  if(localBytes==0){
    if(response.statusCode!=200 && response.statusCode!=206)throw DownloadException('unexpected HTTP status ${response.statusCode}');
    if(response.statusCode==206){
      final cr=parseContentRange(response.headers['content-range']);
      if(cr==null || cr.start!=0)throw const DownloadException('invalid initial Content-Range');
      if(expectedBytes!=null && cr.total!=expectedBytes)throw DownloadException('Content-Range total mismatch ${cr.total} != $expectedBytes');
    }
  }else{
    if(response.statusCode!=206)throw DownloadException('resume expected 206, got ${response.statusCode}');
    final cr=parseContentRange(response.headers['content-range']);
    if(cr==null || cr.start!=localBytes)throw const DownloadException('resume Content-Range mismatch');
    if(expectedBytes!=null && cr.total!=expectedBytes)throw DownloadException('Content-Range total mismatch ${cr.total} != $expectedBytes');
  }
  final responseEtag=response.headers['etag'];
  if(expectedEtag!=null && expectedEtag.isNotEmpty && responseEtag!=null && responseEtag!=expectedEtag){
    throw DownloadException('etag mismatch $responseEtag != $expectedEtag');
  }
  final contentLength=int.tryParse(response.headers['content-length']??'');
  if(contentLength!=null && expectedBytes!=null){
    final wanted=expectedBytes-localBytes;
    if(contentLength!=wanted)throw DownloadException('content-length mismatch $contentLength != $wanted');
  }
}

typedef DownloadProgressCallback = void Function(String editionId, OfflineState state, int receivedBytes, int? expectedBytes);

class DownloadManager {
  final LumeDb db;
  final http.Client client;
  final StoragePressurePolicy? storagePolicy;
  DownloadManager(this.db, {http.Client? client, this.storagePolicy}) : client = client ?? http.Client();

  Future<File> download({
    required String editionId,
    required Uri uri,
    required Directory directory,
    int? expectedBytes,
    String? expectedSha256,
    Map<String, String> headers = const {},
    String? sourceTag,
    DownloadControl? control,
    DownloadProgressCallback? onProgress,
  }) async {
    await directory.create(recursive: true);
    final target = File('${directory.path}/$editionId.bin');
    final part = File('${target.path}.part');
    var localBytes = await part.exists() ? await part.length() : 0;
    final previous = await db.getOfflineAsset(editionId);
    final previousEtag = previous?['etag'] as String?;
    final previousSourceTag=previous?['source_tag'] as String?;
    final pinned = (previous?['pinned'] as num?)?.toInt() == 1;
    var retryCount = (previous?['retry_count'] as num?)?.toInt() ?? 0;
    String? effectiveEtag = previousEtag;

    // A partial belongs to one exact media revision. Never append bytes from a
    // newly resolved source to a stale partial merely because the filename is identical.
    if(localBytes>0 && (sourceTag==null || sourceTag.isEmpty || previousSourceTag==null || previousSourceTag!=sourceTag ||
        (expectedBytes!=null && localBytes>expectedBytes))){
      await part.delete();
      localBytes=0;
      effectiveEtag=null;
      retryCount++;
    }
    // A normal download must never overwrite an already verified READY copy.
    // Media refreshes use MediaReplacementCoordinator's shadow-slot protocol.
    if(previous?['state']=='ready' && await target.exists()){
      if(sourceTag==null || previousSourceTag==sourceTag)return target;
      throw StateError('READY asset update requires MediaReplacementCoordinator');
    }

    // Persist the reservation before evaluating the shared disk budget. This
    // lets concurrent tasks see each other's remaining expected bytes.
    await _persist(editionId, OfflineState.queued, target, part, expectedBytes, localBytes, effectiveEtag, expectedSha256, sourceTag, pinned: pinned, retryCount: retryCount);
    onProgress?.call(editionId, OfflineState.queued, localBytes, expectedBytes);
    try {
      if (expectedBytes != null && storagePolicy != null) {
        await storagePolicy!.ensureBudget();
      }
      for (var attempt = 0; attempt < 2; attempt++) {
        control?.checkpoint();
        final plan = planResume(localBytes, effectiveEtag);
        final req = http.Request('GET', uri)..headers.addAll(headers)..headers.addAll(plan.headers);
        final response = await client.send(req);
        if (response.statusCode == 401 || response.statusCode == 403) {
          throw ExpiredMediaAuthorization(response.statusCode);
        }
        try{
          validateResponseContract(localBytes:localBytes,response:response,expectedBytes:expectedBytes,expectedEtag:effectiveEtag);
        }on DownloadException{
          if(localBytes>0 && attempt==0){
            if(await part.exists())await part.delete();
            localBytes=0; effectiveEtag=null; retryCount++;
            continue;
          }
          rethrow;
        }
        final responseEtag = response.headers['etag'];
        effectiveEtag = responseEtag ?? effectiveEtag;
        await _persist(editionId, OfflineState.downloading, target, part, expectedBytes, localBytes, effectiveEtag, expectedSha256, sourceTag, pinned: pinned, retryCount: retryCount);
        onProgress?.call(editionId, OfflineState.downloading, localBytes, expectedBytes);
        final sink = part.openWrite(mode: localBytes > 0 ? FileMode.append : FileMode.write);
        try {
          await for (final chunk in response.stream) {
            control?.checkpoint();
            if(expectedBytes!=null && localBytes+chunk.length>expectedBytes){
              throw DownloadException('response exceeded expected size $expectedBytes');
            }
            sink.add(chunk);
            localBytes += chunk.length;
            onProgress?.call(editionId, OfflineState.downloading, localBytes, expectedBytes);
          }
        } finally {
          await sink.close();
        }
        control?.checkpoint();
        await _persist(editionId, OfflineState.verifying, target, part, expectedBytes, localBytes, effectiveEtag, expectedSha256, sourceTag, pinned: pinned, retryCount: retryCount);
        onProgress?.call(editionId, OfflineState.verifying, localBytes, expectedBytes);
        await _verify(part, expectedBytes: expectedBytes, expectedSha256: expectedSha256);
        final promotionBackup=File('${target.path}.previous-download');
        if(await promotionBackup.exists())await promotionBackup.delete();
        final hadTarget=await target.exists();
        if(hadTarget)await target.rename(promotionBackup.path);
        try{
          await part.rename(target.path);
        }catch(e){
          if(hadTarget && await promotionBackup.exists() && !await target.exists())await promotionBackup.rename(target.path);
          rethrow;
        }
        final finalBytes = await target.length();
        try{
          await _persist(editionId, OfflineState.ready, target, part, expectedBytes, finalBytes, effectiveEtag, expectedSha256, sourceTag, pinned: pinned, retryCount: retryCount, lastAccessedAt: DateTime.now().millisecondsSinceEpoch);
        }catch(e){
          if(hadTarget && await promotionBackup.exists()){
            if(await target.exists())await target.delete();
            await promotionBackup.rename(target.path);
          }else if(await target.exists()){
            // Preserve the verified bytes as resumable state when READY metadata
            // could not be committed for a first-time download.
            await target.rename(part.path);
            localBytes=await part.length();
          }
          rethrow;
        }
        if(await promotionBackup.exists())await promotionBackup.delete();
        onProgress?.call(editionId, OfflineState.ready, finalBytes, expectedBytes);
        return target;
      }
      throw const DownloadException('resume retry exhausted');
    } on DownloadPaused {
      final bytes = await part.exists() ? await part.length() : 0;
      await _persist(editionId, OfflineState.paused, target, part, expectedBytes, bytes, effectiveEtag, expectedSha256, sourceTag, pinned: pinned, retryCount: retryCount);
      onProgress?.call(editionId, OfflineState.paused, bytes, expectedBytes);
      rethrow;
    } on DownloadCancelled {
      if (await part.exists()) await part.delete();
      await db.deleteOfflineAsset(editionId);
      rethrow;
    } catch (e) {
      final bytes = await part.exists() ? await part.length() : 0;
      retryCount++;
      await _persist(editionId, OfflineState.failed, target, part, expectedBytes, bytes, effectiveEtag, expectedSha256, sourceTag, pinned: pinned, retryCount: retryCount, lastError: e.toString());
      onProgress?.call(editionId, OfflineState.failed, bytes, expectedBytes);
      rethrow;
    }
  }

  Future<void> remove(String editionId) async {
    final asset = await db.getOfflineAsset(editionId);
    if (asset == null) return;
    await db.setOfflineAssetState(editionId, OfflineState.removing.name);
    for (final key in ['local_path', 'temp_path']) {
      final path = asset[key] as String?;
      if (path != null && path.isNotEmpty) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    }
    await db.deleteOfflineAsset(editionId);
  }

  Future<void> _verify(File file, {int? expectedBytes, String? expectedSha256}) async {
    if (!await file.exists()) throw const DownloadException('partial file missing');
    final length = await file.length();
    if (expectedBytes != null && length != expectedBytes) throw DownloadException('size mismatch $length != $expectedBytes');
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() != expectedSha256.toLowerCase()) throw const DownloadException('sha256 mismatch');
    }
  }

  Future<void> _persist(String editionId, OfflineState state, File target, File part, int? expectedBytes, int receivedBytes, String? etag, String? sha256Value, String? sourceTag, {required bool pinned, required int retryCount, String? lastError, int? lastAccessedAt}) {
    return db.upsertOfflineAsset({
      'editionId': editionId,
      'state': state.name,
      'localPath': state == OfflineState.ready ? target.path : null,
      'tempPath': state == OfflineState.ready ? null : part.path,
      'expectedBytes': expectedBytes,
      'receivedBytes': receivedBytes,
      'etag': etag,
      'sha256': sha256Value,
      'sourceTag': sourceTag,
      'pinned': pinned,
      'retryCount': retryCount,
      'lastError': lastError,
      'lastAccessedAt': lastAccessedAt,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }
}
