import 'dart:math';
import '../data/database.dart';

class PersistentSyncBackoff {
  final LumeDb db;
  final Duration baseDelay;
  final Duration maxDelay;
  final Random _random;
  PersistentSyncBackoff(this.db,{this.baseDelay=const Duration(seconds:1),this.maxDelay=const Duration(minutes:2),Random? random}):_random=random??Random();

  Future<Duration?> remaining(String profileId,{DateTime? now}) async {
    final row=await db.getSyncRetry(profileId);
    final at=(row?['next_retry_at'] as num?)?.toInt();
    if(at==null)return null;
    final current=(now??DateTime.now()).millisecondsSinceEpoch;
    if(at<=current)return Duration.zero;
    return Duration(milliseconds:at-current);
  }

  Future<Duration> recordFailure(String profileId,Object error,{Duration? retryAfter,DateTime? now}) async {
    final row=await db.getSyncRetry(profileId);
    final attempt=((row?['attempt'] as num?)?.toInt()??0)+1;
    final raw=min(maxDelay.inMilliseconds,baseDelay.inMilliseconds*(1 << min(attempt-1,20))).toInt();
    final jitter=(raw*0.20*_random.nextDouble()).round();
    final delay=retryAfter!=null && retryAfter<=maxDelay?retryAfter:Duration(milliseconds:raw+jitter);
    final next=(now??DateTime.now()).add(delay).millisecondsSinceEpoch;
    await db.saveSyncRetry(profileId,attempt:attempt,nextRetryAt:next,lastError:error.toString());
    return delay;
  }

  Future<void> recordSuccess(String profileId)=>db.clearSyncRetry(profileId);
}
