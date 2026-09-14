import 'dart:io';
import '../cache/lru_cache.dart';

class MediaCache {
  final HybridReadCache hot;
  MediaCache({HybridReadCache? hot}) : hot = hot ?? HybridReadCache();

  Future<String> readText({required String editionId, required File file}) async {
    final key = '$editionId:${file.path}';
    final cached = hot.xhtml.get(key);
    if (cached != null) return cached;
    final text = await file.readAsString();
    hot.xhtml.put(key, text);
    return text;
  }

  Future<List<int>> readSmallBinary({required String editionId, required File file, int maxCacheBytes = 2 * 1024 * 1024}) async {
    final key = '$editionId:${file.path}';
    final cached = hot.pageBytes.get(key);
    if (cached != null) return cached;
    final bytes = await file.readAsBytes();
    if (bytes.length <= maxCacheBytes) hot.pageBytes.put(key, bytes);
    return bytes;
  }
}
