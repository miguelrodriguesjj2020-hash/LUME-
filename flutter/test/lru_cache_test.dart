import 'package:flutter_test/flutter_test.dart';
import 'package:lume/cache/lru_cache.dart';

void main() {
  test('LRU evicts least recently used item by bytes', () {
    final cache=LruCache<String,List<int>>(maxBytes:6,sizeOf:(v)=>v.length);
    cache.put('a',[1,2]);
    cache.put('b',[1,2]);
    expect(cache.get('a'),isNotNull); // a becomes most recent
    cache.put('c',[1,2,3]);
    expect(cache.get('b'),isNull);
    expect(cache.get('a'),isNotNull);
    expect(cache.get('c'),isNotNull);
  });

  test('oversized item never flushes hot cache', () {
    final cache=LruCache<String,List<int>>(maxBytes:4,sizeOf:(v)=>v.length);
    cache.put('a',[1,2]);
    cache.put('huge',[1,2,3,4,5]);
    expect(cache.get('a'),isNotNull);
    expect(cache.get('huge'),isNull);
  });
}
