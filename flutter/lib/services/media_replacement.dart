import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../data/database.dart';
import 'download.dart';
import 'media_descriptor.dart';
import 'storage_policy.dart';

/// Downloads a successor into a shadow slot while the current READY asset
/// remains readable. The database is switched only after verification.
class MediaReplacementCoordinator {
  final LumeDb db;
  final http.Client client;
  final StoragePressurePolicy? storagePolicy;
  MediaReplacementCoordinator(this.db,{http.Client? client,this.storagePolicy}):client=client??http.Client();

  Future<File> replace({required String editionId,required MediaDescriptor descriptor,required Directory directory,Map<String,String> headers=const {}}) async {
    final current=await db.getOfflineAsset(editionId);
    if(current==null || current['state']!='ready') throw StateError('replacement requires current READY asset');
    final oldPath=current['local_path'] as String?;
    if(oldPath==null || oldPath.isEmpty || !await File(oldPath).exists()) throw StateError('current READY file missing');

    await directory.create(recursive:true);
    final target=File(oldPath);
    final part=File('${target.path}.replacement.part');
    final staged=File('${target.path}.replacement.ready');
    final backup=File('${target.path}.previous');
    var received=await part.exists()?await part.length():0;
    if(descriptor.byteSize==null && (descriptor.sha256==null || descriptor.sha256!.isEmpty)){
      throw StateError('replacement requires byteSize or sha256 integrity metadata');
    }
    final previousReplacement=await db.getMediaReplacement(editionId);
    final previousSourceTag=previousReplacement?['source_tag'] as String?;
    final previousEtag=previousReplacement?['etag'] as String?;
    if(received>0 && ((previousSourceTag!=null && previousSourceTag!=descriptor.sourceTag) ||
        (previousEtag!=null && descriptor.etag!=null && previousEtag!=descriptor.etag))){
      await part.delete();
      received=0;
    }

    try {
      await db.upsertMediaReplacement({
        'editionId':editionId,'state':'downloading','tempPath':part.path,
        'expectedBytes':descriptor.byteSize,'receivedBytes':received,
        'etag':descriptor.etag,'sha256':descriptor.sha256,'sourceTag':descriptor.sourceTag,
        'stagedPath':staged.path,'backupPath':backup.path,'phase':'downloading',
      });
      if(descriptor.byteSize!=null && storagePolicy!=null)await storagePolicy!.ensureBudget();
      final req=http.Request('GET',descriptor.url);
      req.headers.addAll(headers);
      if(received>0){
        req.headers['Range']='bytes=$received-';
        if(descriptor.etag!=null) req.headers['If-Range']=descriptor.etag!;
      }
      final response=await client.send(req);
      if(response.statusCode==401 || response.statusCode==403) throw ExpiredMediaAuthorization(response.statusCode);
      validateResponseContract(localBytes:received,response:response,expectedBytes:descriptor.byteSize,expectedEtag:descriptor.etag);
      final sink=part.openWrite(mode:received>0?FileMode.append:FileMode.write);
      try {
        await for(final chunk in response.stream){
          if(descriptor.byteSize!=null && received+chunk.length>descriptor.byteSize!){
            throw DownloadException('replacement exceeded expected size ${descriptor.byteSize}');
          }
          sink.add(chunk);received+=chunk.length;
        }
      } finally { await sink.close(); }
      await db.upsertMediaReplacement({
        'editionId':editionId,'state':'verifying','tempPath':part.path,
        'expectedBytes':descriptor.byteSize,'receivedBytes':received,
        'etag':descriptor.etag,'sha256':descriptor.sha256,'sourceTag':descriptor.sourceTag,
        'stagedPath':staged.path,'backupPath':backup.path,'phase':'verifying',
      });
      if(descriptor.byteSize!=null && await part.length()!=descriptor.byteSize) throw const DownloadException('replacement size mismatch');
      if(descriptor.sha256!=null && descriptor.sha256!.isNotEmpty){
        final digest=await sha256.bind(part.openRead()).first;
        if(digest.toString().toLowerCase()!=descriptor.sha256!.toLowerCase()) throw const DownloadException('replacement sha256 mismatch');
      }
      if(await staged.exists()) await staged.delete();
      await part.rename(staged.path);
      await db.upsertMediaReplacement({
        'editionId':editionId,'state':'verifying','tempPath':part.path,
        'expectedBytes':descriptor.byteSize,'receivedBytes':received,
        'etag':descriptor.etag,'sha256':descriptor.sha256,'sourceTag':descriptor.sourceTag,
        'stagedPath':staged.path,'backupPath':backup.path,'phase':'staged',
      });

      // Two-step swap with rollback. The old verified file remains available
      // until the successor itself has been fully verified.
      if(await backup.exists()) await backup.delete();
      await db.upsertMediaReplacement({
        'editionId':editionId,'state':'verifying','tempPath':part.path,
        'expectedBytes':descriptor.byteSize,'receivedBytes':received,
        'etag':descriptor.etag,'sha256':descriptor.sha256,'sourceTag':descriptor.sourceTag,
        'stagedPath':staged.path,'backupPath':backup.path,'phase':'swapping',
      });
      await target.rename(backup.path);
      try {
        await staged.rename(target.path);
      } catch(e) {
        if(await backup.exists() && !await target.exists()) await backup.rename(target.path);
        rethrow;
      }
      try{
        await db.upsertOfflineAsset({
          'editionId':editionId,'state':'ready','localPath':target.path,'tempPath':null,
          'expectedBytes':descriptor.byteSize,'receivedBytes':await target.length(),
          'etag':descriptor.etag,'sha256':descriptor.sha256,'sourceTag':descriptor.sourceTag,
          'pinned':(current['pinned'] as num?)?.toInt()==1,
          'retryCount':0,'lastError':null,'lastAccessedAt':DateTime.now().millisecondsSinceEpoch,
        });
        await db.recordMediaRevalidation(editionId,remoteSourceTag:descriptor.sourceTag,needsUpdate:false);
        await db.deleteMediaReplacement(editionId);
      }catch(e){
        // Database commit failed after filesystem swap. Restore both the
        // previous verified bytes and their metadata; never leave an old file
        // described by the successor's hash/ETag.
        if(await backup.exists()){
          final failedSuccessor=File('${target.path}.failed-successor');
          if(await failedSuccessor.exists())await failedSuccessor.delete();
          if(await target.exists())await target.rename(failedSuccessor.path);
          await backup.rename(target.path);
          try{
            await db.upsertOfflineAsset({
              'editionId':editionId,'state':'ready','localPath':target.path,'tempPath':null,
              'expectedBytes':current['expected_bytes'],'receivedBytes':await target.length(),
              'etag':current['etag'],'sha256':current['sha256'],'sourceTag':current['source_tag'],
              'pinned':(current['pinned'] as num?)?.toInt()==1,
              'retryCount':(current['retry_count'] as num?)?.toInt()??0,
              'lastError':current['last_error'],'lastAccessedAt':current['last_accessed_at'],
            });
            await db.recordMediaRevalidation(editionId,remoteSourceTag:descriptor.sourceTag,needsUpdate:true,lastError:'replacement commit rolled back: $e');
          }catch(_){/* recovery will prefer the restored READY bytes */}
        }
        rethrow;
      }
      if(await backup.exists()) await backup.delete();
      return target;
    } catch(e) {
      await db.upsertMediaReplacement({
        'editionId':editionId,'state':'failed','tempPath':part.path,
        'expectedBytes':descriptor.byteSize,'receivedBytes':await part.exists()?await part.length():received,
        'etag':descriptor.etag,'sha256':descriptor.sha256,'sourceTag':descriptor.sourceTag,'lastError':e.toString(),
        'stagedPath':staged.path,'backupPath':backup.path,'phase':'failed',
      });
      // Deliberately do not mutate offline_assets: old READY copy survives.
      rethrow;
    }
  }
}
