import 'dart:io';
import '../data/database.dart';

class StoragePolicyResult {
  final int freedBytes; final List<String> removedEditionIds;
  const StoragePolicyResult(this.freedBytes,this.removedEditionIds);
}

/// Persistent disk-cache LRU + reservation accounting. Pinned assets are never
/// auto-evicted. Queued/partial downloads reserve their remaining expected size
/// so two concurrent large volumes cannot both assume the same free budget.
class StoragePressurePolicy {
  final LumeDb db; final int maxDiskCacheBytes;
  const StoragePressurePolicy(this.db,{this.maxDiskCacheBytes=2*1024*1024*1024});

  Future<StoragePolicyResult> ensureBudget() async {
    final ready=await db.readyOfflineBytes();
    final reserved=await db.reservedOfflineBytes();
    final need=ready+reserved-maxDiskCacheBytes;
    if(need>0)return await freeAtLeast(need);
    return const StoragePolicyResult(0,[]);
  }

  Future<StoragePolicyResult> freeAtLeast(int bytesNeeded) async {
    if(bytesNeeded<=0)return const StoragePolicyResult(0,[]);
    var freed=0;final removed=<String>[];
    for(final asset in await db.evictionCandidates()){
      if(freed>=bytesNeeded)break;
      final id=asset['edition_id'] as String;final path=asset['local_path'] as String?;final file=path==null||path.isEmpty?null:File(path);
      final size=file!=null&&await file.exists()?await file.length():((asset['received_bytes'] as num?)?.toInt()??0);
      if(file!=null&&await file.exists())await file.delete();await db.deleteOfflineAsset(id);freed+=size;removed.add(id);
    }
    if(freed<bytesNeeded)throw FileSystemException('LUME disk-cache budget exhausted; pinned/active assets prevent eviction');
    return StoragePolicyResult(freed,removed);
  }
}
