import 'dart:io';
import 'package:crypto/crypto.dart';
import '../data/database.dart';

class ReplacementRecoveryReport {
  final int finalized;
  final int rolledBack;
  final int preservedPartial;
  final int cleanedOrphans;
  const ReplacementRecoveryReport({this.finalized=0,this.rolledBack=0,this.preservedPartial=0,this.cleanedOrphans=0});
}

/// Recovers interrupted atomic media swaps conservatively.
/// The last known verified READY copy always wins unless the successor can be
/// re-verified from the persisted size/hash metadata.
class MediaReplacementRecovery {
  final LumeDb db;
  MediaReplacementRecovery(this.db);

  Future<bool> _matches(File file, Map<String,dynamic> row) async {
    if(!await file.exists()) return false;
    final expected=(row['expected_bytes'] as num?)?.toInt();
    if(expected!=null && await file.length()!=expected) return false;
    final expectedSha=(row['sha256'] as String?)?.trim().toLowerCase();
    if(expectedSha!=null && expectedSha.isNotEmpty){
      final digest=await sha256.bind(file.openRead()).first;
      if(digest.toString().toLowerCase()!=expectedSha) return false;
    }
    // If neither strong hash nor expected size exists, do not call an
    // interrupted successor verified merely because a file happens to exist.
    return expected!=null || (expectedSha!=null && expectedSha.isNotEmpty);
  }

  Future<ReplacementRecoveryReport> recoverAll(Directory mediaDirectory) async {
    var finalized=0, rolledBack=0, partial=0, cleaned=0;
    final rows=await db.listMediaReplacements();
    final referenced=<String>{};
    for(final row in rows){
      final editionId=row['edition_id'] as String;
      final asset=await db.getOfflineAsset(editionId);
      final targetPath=asset?['local_path'] as String?;
      if(targetPath==null || targetPath.isEmpty){
        // Without a canonical READY path we cannot perform a safe swap.
        final p=File(row['temp_path'] as String); if(await p.exists()){referenced.add(p.path);partial++;}
        continue;
      }
      final target=File(targetPath);
      final part=File((row['temp_path'] as String?)??'$targetPath.replacement.part');
      final staged=File((row['staged_path'] as String?)??'$targetPath.replacement.ready');
      final backup=File((row['backup_path'] as String?)??'$targetPath.previous');
      referenced.addAll([part.path,staged.path,backup.path]);

      final targetIsSuccessor=await _matches(target,row);
      final stagedIsSuccessor=await _matches(staged,row);

      if(targetIsSuccessor){
        if(await backup.exists()) await backup.delete();
        if(await staged.exists()) await staged.delete();
        if(await part.exists()) await part.delete();
        await db.upsertOfflineAsset({
          'editionId':editionId,'state':'ready','localPath':target.path,'tempPath':null,
          'expectedBytes':row['expected_bytes'],'receivedBytes':await target.length(),
          'etag':row['etag'],'sha256':row['sha256'],'sourceTag':row['source_tag'],
          'pinned':(asset?['pinned'] as num?)?.toInt()==1,
          'retryCount':0,'lastError':null,'lastAccessedAt':DateTime.now().millisecondsSinceEpoch,
        });
        await db.recordMediaRevalidation(editionId,remoteSourceTag:row['source_tag'] as String?,needsUpdate:false);
        await db.deleteMediaReplacement(editionId);
        finalized++;
        continue;
      }

      // A missing target with a previous verified copy means the process died
      // in the swap window. Roll back first; availability beats freshness.
      if(!await target.exists() && await backup.exists()){
        await backup.rename(target.path);
        if(await staged.exists()) await staged.delete();
        await db.upsertMediaReplacement({
          'editionId':editionId,'state':'failed','tempPath':part.path,
          'expectedBytes':row['expected_bytes'],'receivedBytes':await part.exists()?await part.length():0,
          'etag':row['etag'],'sha256':row['sha256'],'sourceTag':row['source_tag'],
          'stagedPath':staged.path,'backupPath':backup.path,'phase':'rolled_back',
          'lastError':'recovered process death during atomic swap; previous READY restored',
        });
        rolledBack++;
        if(await part.exists()) partial++;
        continue;
      }

      // If the old target still exists, never replace it during recovery. A
      // verified staged successor remains discardable and can be requested
      // again explicitly; this avoids guessing after a crash.
      if(await target.exists()){
        if(await backup.exists()) await backup.delete();
        if(await staged.exists()) await staged.delete();
        await db.upsertMediaReplacement({
          'editionId':editionId,'state':'failed','tempPath':part.path,
          'expectedBytes':row['expected_bytes'],'receivedBytes':await part.exists()?await part.length():0,
          'etag':row['etag'],'sha256':row['sha256'],'sourceTag':row['source_tag'],
          'stagedPath':staged.path,'backupPath':backup.path,'phase':stagedIsSuccessor?'staged_interrupted':'interrupted',
          'lastError':'replacement interrupted; previous READY retained',
        });
        if(await part.exists()) partial++;
      }
    }

    // Remove only unreferenced stale swap artifacts. Partial files are retained
    // for seven days to allow resume; older orphan partials are reclaimed.
    if(await mediaDirectory.exists()){
      final cutoff=DateTime.now().subtract(const Duration(days:7));
      await for(final entity in mediaDirectory.list(recursive:false,followLinks:false)){
        if(entity is! File || referenced.contains(entity.path)) continue;
        final name=entity.path;
        if(name.endsWith('.previous') || name.endsWith('.replacement.ready') || name.endsWith('.failed-successor') || name.endsWith('.previous-download')){
          await entity.delete(); cleaned++;
        }else if(name.endsWith('.replacement.part')){
          final stat=await entity.stat();
          if(stat.modified.isBefore(cutoff)){await entity.delete();cleaned++;}
        }
      }
    }
    return ReplacementRecoveryReport(finalized:finalized,rolledBack:rolledBack,preservedPartial:partial,cleanedOrphans:cleaned);
  }
}
