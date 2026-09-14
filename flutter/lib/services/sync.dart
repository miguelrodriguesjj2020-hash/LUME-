import '../data/database.dart';
import 'api.dart';
import 'retry_policy.dart';
import 'persistent_sync_backoff.dart';

class SyncResult {
  final bool catalogChanged;
  final int sentOps;
  final int receivedEvents;
  final String cursor;
  const SyncResult({required this.catalogChanged, required this.sentOps, required this.receivedEvents, required this.cursor});
}

class SyncBackoffActive implements Exception {
  final Duration remaining;
  const SyncBackoffActive(this.remaining);
  @override String toString()=>'SyncBackoffActive(${remaining.inMilliseconds}ms)';
}

enum SyncRunMode { manual, foreground, background }

class SyncDeferred implements Exception {
  final Duration remaining; final String reason;
  const SyncDeferred(this.remaining,this.reason);
  @override String toString()=>'SyncDeferred(${remaining.inMilliseconds}ms,$reason)';
}

class SyncCoordinator {
  final LumeDb db;
  final LumeApi api;
  final RetryPolicy retryPolicy;
  final PersistentSyncBackoff persistentBackoff;
  SyncCoordinator(this.db, this.api,{RetryPolicy? retryPolicy,PersistentSyncBackoff? persistentBackoff})
    :retryPolicy=retryPolicy??RetryPolicy(),persistentBackoff=persistentBackoff??PersistentSyncBackoff(db);

  Future<bool> refreshCatalog() async {
    final revision = await db.getRevision();
    final manifest = await retryPolicy.run(()=>api.bootstrap(revision));
    if (manifest == null) return false;
    await db.applyCatalog(manifest);
    return true;
  }

  Future<SyncResult> run(String profileId, {int maxRounds = 8, int batchSize = 50, SyncRunMode mode=SyncRunMode.manual}) async {
    final now=DateTime.now().millisecondsSinceEpoch;
    final schedule=await db.getSyncSchedule(profileId);
    final deferred=(schedule?['deferred_until'] as num?)?.toInt();
    if(mode!=SyncRunMode.manual && deferred!=null && deferred>now)throw SyncDeferred(Duration(milliseconds:deferred-now),'scheduled');
    final remaining=await persistentBackoff.remaining(profileId);
    if(remaining!=null && remaining>Duration.zero)throw SyncBackoffActive(remaining);
    await db.saveSyncSchedule(profileId,mode:mode.name,lastAttemptAt:now,deferredUntil:null,lastError:null);
    try {
      final catalogChanged = await refreshCatalog();
      var cursor = await db.getSyncCursor(profileId);
      var sent = 0;
      var received = 0;
      for (var round = 0; round < maxRounds; round++) {
        final ops = await db.loadOutbox(profileId,limit: batchSize);
        final response = await retryPolicy.run(()=>api.sync(profileId, cursor, ops));
        final ack = List<String>.from(response['ack'] ?? const []);
        final events = List<dynamic>.from(response['events'] ?? const []);
        final rejected = List<dynamic>.from(response['rejected'] ?? const []);
        final previousCursor = cursor;
        final next = '${response['cursor'] ?? cursor}';
        await db.applySyncBatch(
          profileId,
          ackOpIds:ack,
          events:events,
          rejected:rejected,
          previousCursor:previousCursor,
          nextCursor:next,
        );
        if (next != previousCursor) cursor = next;
        sent += ack.length;
        received += events.length;
        final noPending = (await db.loadOutbox(profileId,limit: 1)).isEmpty;
        if (noPending && events.isEmpty) break;
        if (next == previousCursor && events.isEmpty && ack.isEmpty) break;
      }
      await persistentBackoff.recordSuccess(profileId);
      await db.clearSyncScheduleDeferral(profileId,mode:mode.name);
      return SyncResult(catalogChanged: catalogChanged, sentOps: sent, receivedEvents: received, cursor: cursor);
    } catch(e) {
      if(e is SessionExpiredException || e is SyncBackoffActive || e is SyncDeferred)rethrow;
      if(retryPolicy.isTransient(e)){
        await persistentBackoff.recordFailure(profileId,e,retryAfter:e is ApiException?e.retryAfter:null);
        final barrier=await persistentBackoff.remaining(profileId);
        final until=DateTime.now().add(barrier??const Duration(seconds:30)).millisecondsSinceEpoch;
        await db.saveSyncSchedule(profileId,mode:mode.name,deferredUntil:until,lastError:e.toString());
      }else{
        await db.saveSyncSchedule(profileId,mode:mode.name,deferredUntil:null,lastError:e.toString());
      }
      rethrow;
    }
  }
}
