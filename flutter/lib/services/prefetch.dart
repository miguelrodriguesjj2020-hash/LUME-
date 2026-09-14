import 'dart:async';
import 'dart:io';
import 'media_cache.dart';

class PrefetchWindow {
  final int behind;
  final int ahead;
  const PrefetchWindow({this.behind = 1, this.ahead = 3});

  List<int> around(int current, int length, {int direction = 1}) {
    if (length <= 0) return const [];
    final result = <int>[];
    final forward = direction >= 0;
    final firstCount = forward ? ahead : behind;
    final secondCount = forward ? behind : ahead;
    for (var d = 1; d <= firstCount; d++) {
      final i = current + (forward ? d : -d);
      if (i >= 0 && i < length) result.add(i);
    }
    for (var d = 1; d <= secondCount; d++) {
      final i = current + (forward ? -d : d);
      if (i >= 0 && i < length) result.add(i);
    }
    return result;
  }
}

/// Best-effort prefetch. Failures never fail the reader; disk remains authoritative.
class EpubPrefetcher {
  final MediaCache cache;
  final PrefetchWindow window;
  EpubPrefetcher(this.cache, {this.window = const PrefetchWindow()});

  Future<void> warm({
    required String editionId,
    required List<String> spine,
    required int currentIndex,
    int direction = 1,
  }) async {
    final indexes = window.around(currentIndex, spine.length, direction: direction);
    await Future.wait(indexes.map((i) async {
      try {
        await cache.readText(editionId: editionId, file: File(spine[i]));
      } catch (_) {
        // Prefetch is optional and must never block reading.
      }
    }));
  }
}
