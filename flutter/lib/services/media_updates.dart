import 'dart:io';
import '../data/database.dart';
import 'api.dart';
import 'media_descriptor.dart';
import 'media_replacement.dart';
import 'network_policy.dart';

class MediaUpdateService {
  final LumeDb db;
  final LumeApi api;
  final MediaReplacementCoordinator replacement;
  final Directory mediaDirectory;
  final NetworkPolicy? networkPolicy;
  final Future<NetworkClass> Function()? networkClass;
  MediaUpdateService({required this.db,required this.api,required this.replacement,required this.mediaDirectory,this.networkPolicy,this.networkClass});

  Future<List<Map<String,dynamic>>> pending() => db.listPendingMediaUpdates();

  /// Explicit opt-in update. Revalidation never consumes bandwidth by itself.
  Future<void> update(String editionId) async {
    if(networkPolicy!=null && networkClass!=null){
      final decision=await networkPolicy!.decide(await networkClass!(),TransferIntent.mediaUpdate);
      if(!decision.allowed) throw StateError(decision.reason ?? 'transfer blocked by network policy');
    }
    final descriptor=MediaDescriptor.fromJson(await api.media(editionId));
    await replacement.replace(editionId:editionId,descriptor:descriptor,directory:mediaDirectory,headers:descriptor.headers);
  }
}
