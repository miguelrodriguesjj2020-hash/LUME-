import 'dart:collection';

/// Byte-budgeted LRU for small hot objects. Large media files stay on disk.
class LruCache<K, V> {
  final int maxBytes;
  final int Function(V value) sizeOf;
  final LinkedHashMap<K, V> _items = LinkedHashMap<K, V>();
  int _bytes = 0;

  LruCache({required this.maxBytes, required this.sizeOf}) {
    if (maxBytes <= 0) throw ArgumentError.value(maxBytes, 'maxBytes');
  }

  int get length => _items.length;
  int get bytes => _bytes;

  V? get(K key) {
    final value = _items.remove(key);
    if (value == null) return null;
    _items[key] = value; // most recently used
    return value;
  }

  void put(K key, V value) {
    final cost = sizeOf(value);
    if (cost < 0) throw StateError('negative cache cost');
    final old = _items.remove(key);
    if (old != null) _bytes -= sizeOf(old);
    if (cost > maxBytes) return; // never let one huge object evict everything
    _items[key] = value;
    _bytes += cost;
    _evict();
  }

  V? remove(K key) {
    final value = _items.remove(key);
    if (value != null) _bytes -= sizeOf(value);
    return value;
  }

  void clear() {
    _items.clear();
    _bytes = 0;
  }

  void _evict() {
    while (_bytes > maxBytes && _items.isNotEmpty) {
      final key = _items.keys.first;
      final value = _items.remove(key)!;
      _bytes -= sizeOf(value);
    }
  }
}

/// Two-tier cache coordinator. Disk is authoritative; RAM is only an accelerator.
class HybridReadCache {
  final LruCache<String, String> xhtml;
  final LruCache<String, List<int>> pageBytes;

  HybridReadCache({int xhtmlBytes = 8 * 1024 * 1024, int pageBytesBudget = 24 * 1024 * 1024})
      : xhtml = LruCache(maxBytes: xhtmlBytes, sizeOf: (s) => s.length * 2),
        pageBytes = LruCache(maxBytes: pageBytesBudget, sizeOf: (b) => b.length);

  void clearEdition(String editionId) {
    // Keys are namespaced as editionId:path. Iterate on snapshots to avoid mutation issues.
    for (final key in List<String>.from(xhtml._items.keys)) {
      if (key.startsWith('$editionId:')) xhtml.remove(key);
    }
    for (final key in List<String>.from(pageBytes._items.keys)) {
      if (key.startsWith('$editionId:')) pageBytes.remove(key);
    }
  }
}
