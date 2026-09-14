import '../data/database.dart';
import 'api.dart';
import 'media_descriptor.dart';

class MediaRevalidationResult {
  final bool checked;
  final bool needsUpdate;
  final String? remoteSourceTag;
  const MediaRevalidationResult({required this.checked,required this.needsUpdate,this.remoteSourceTag});
}

class MediaRevalidator {
  final LumeDb db;
  final LumeApi api;
  MediaRevalidator(this.db,this.api);

  Future<MediaRevalidationResult> check(String editionId) async {
    final asset=await db.getOfflineAsset(editionId);
    if(asset==null || asset['state']!='ready')return const MediaRevalidationResult(checked:false,needsUpdate:false);
    try{
      final descriptor=MediaDescriptor.fromJson(await api.media(editionId));
      final localTag=(asset['source_tag'] as String?)??'';
      final remoteTag=descriptor.sourceTag;
      // Empty/weak remote fingerprint is never enough to invalidate a verified local asset.
      final changed=remoteTag.isNotEmpty && localTag.isNotEmpty && remoteTag!=localTag;
      await db.recordMediaRevalidation(editionId,remoteSourceTag:remoteTag,needsUpdate:changed);
      return MediaRevalidationResult(checked:true,needsUpdate:changed,remoteSourceTag:remoteTag);
    }catch(e){
      // Revalidation is advisory. Never demote READY media because the network failed.
      await db.recordMediaRevalidation(editionId,needsUpdate:false,lastError:e.toString());
      return const MediaRevalidationResult(checked:false,needsUpdate:false);
    }
  }
}
