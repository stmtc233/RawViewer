import 'dart:collection';

/// A size-bounded LRU cache.
///
/// [onEvict] is called for every value that leaves the cache — evicted, replaced
/// by a newer value for the same key, rejected as oversized, or dropped by
/// [clear]. Callers holding native resources (such as `ui.Image` handles) must
/// release them there, otherwise eviction leaks the underlying texture.
class LruCache<K, V> {
  final int maximumSize;
  final int Function(V value)? sizeOf;
  final void Function(K key, V value)? onEvict;
  final LinkedHashMap<K, V> _cache;
  int _currentSize = 0;

  /// [maximumSize] is the max size of the cache.
  /// If [sizeOf] is provided, size is calculated by sum of sizeOf(value).
  /// If [sizeOf] is null, size is the number of entries.
  LruCache(this.maximumSize, {this.sizeOf, this.onEvict})
      : _cache = LinkedHashMap<K, V>();

  int _measure(V value) => sizeOf != null ? sizeOf!(value) : 1;

  V? get(K key) {
    final value = _cache.remove(key);
    if (value == null) return null;

    // Reinserting moves the entry to the most-recently-used end.
    _cache[key] = value;
    return value;
  }

  void put(K key, V value) {
    final itemSize = _measure(value);

    final oldValue = _cache.remove(key);
    if (oldValue != null) {
      _currentSize -= _measure(oldValue);
      onEvict?.call(key, oldValue);
    }

    // An item larger than the whole budget can never be held without emptying
    // the cache and still overflowing, so reject it outright rather than
    // evicting everything else for something that does not fit.
    if (itemSize > maximumSize) {
      onEvict?.call(key, value);
      return;
    }

    _cache[key] = value;
    _currentSize += itemSize;

    while (_currentSize > maximumSize && _cache.isNotEmpty) {
      final keyToRemove = _cache.keys.first;
      if (keyToRemove == key) break; // Never evict the value just inserted.

      final valueToRemove = _cache.remove(keyToRemove) as V;
      _currentSize -= _measure(valueToRemove);
      onEvict?.call(keyToRemove, valueToRemove);
    }
  }

  /// Removes [key] and reports it to [onEvict].
  void remove(K key) {
    final value = _cache.remove(key);
    if (value == null) return;
    _currentSize -= _measure(value);
    onEvict?.call(key, value);
  }

  void clear() {
    if (onEvict != null) {
      // Snapshot first: onEvict may touch the cache.
      final entries = List<(K, V)>.from(
        _cache.entries.map((entry) => (entry.key, entry.value)),
      );
      _cache.clear();
      _currentSize = 0;
      for (final (key, value) in entries) {
        onEvict!.call(key, value);
      }
      return;
    }

    _cache.clear();
    _currentSize = 0;
  }

  bool containsKey(K key) => _cache.containsKey(key);

  int get size => _currentSize;
  int get length => _cache.length;
}
