import 'dart:math';
import '../data/database.dart';
import '../models/progress.dart';

class ReadingProgressService {
  final LumeDb db;
  final String profileId;
  final String deviceId;
  ReadingProgressService(this.db, {required this.profileId, required this.deviceId});

  Future<void> save(String editionId, ReadingLocator locator, {double? percent, bool completed = false}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = _derivePercent(locator, explicit: percent, completed: completed);
    final opId = '$deviceId:$editionId:$now:${Random().nextInt(1 << 31)}';
    await db.upsertProgress({
      'profileId': profileId,
      'editionId': editionId,
      'locator': locator.toJson(),
      'percent': p,
      'completed': completed || p >= 0.999,
      'clientUpdatedAt': now,
      'deviceId': deviceId,
      'opId': opId,
    }, enqueue: true);
  }

  Future<Map<String, dynamic>?> load(String editionId) => db.getProgress(profileId, editionId);

  double _derivePercent(ReadingLocator locator, {double? explicit, required bool completed}) {
    if (completed) return 1;
    if (explicit != null) return explicit.clamp(0, 1);
    if (locator is PageLocator && locator.pageCount != null && locator.pageCount! > 0) {
      return (locator.page / locator.pageCount!).clamp(0, 1);
    }
    if (locator is EpubLocator && locator.bookProgression != null) return locator.bookProgression!.clamp(0, 1);
    return 0;
  }
}
