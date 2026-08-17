import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/image_store.dart';
import 'package:rawviewer/lru_cache.dart';
import 'package:rawviewer/main.dart';
import 'package:rawviewer/native_lib.dart';
import 'package:rawviewer/viewer_image.dart';

void main() {
  group('bucketDecodeWidth', () {
    test('snaps up to the next bucket', () {
      expect(bucketDecodeWidth(1), kDecodeWidthBucket);
      expect(bucketDecodeWidth(kDecodeWidthBucket.toDouble()),
          kDecodeWidthBucket);
      expect(bucketDecodeWidth(kDecodeWidthBucket + 1), kDecodeWidthBucket * 2);
      expect(bucketDecodeWidth(300), 384);
    });

    test('is stable across small width changes', () {
      // The point of bucketing: resizing the window by a pixel must not change
      // the decode target, otherwise every cached image is invalidated.
      final widths = [400.0, 401.0, 447.0, 512.0];
      final buckets = widths.map(bucketDecodeWidth).toSet();
      expect(buckets, hasLength(1));
      expect(buckets.single, 512);
    });
  });

  group('LruCache', () {
    test('evicts least-recently-used entries and reports them', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        3,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('a', 1);
      cache.put('b', 1);
      cache.put('c', 1);
      cache.get('a'); // 'a' becomes most recently used, so 'b' is next out.
      cache.put('d', 1);

      expect(evicted, ['b']);
      expect(cache.containsKey('a'), isTrue);
      expect(cache.containsKey('b'), isFalse);
      expect(cache.length, 3);
    });

    test('reports replaced values so their handles can be released', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(
        10,
        onEvict: (_, value) => evicted.add(value),
      );

      cache.put('a', 1);
      cache.put('a', 2);

      expect(evicted, [1]);
      expect(cache.get('a'), 2);
      expect(cache.length, 1);
    });

    test('rejects an oversized value instead of emptying the cache', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        100,
        sizeOf: (value) => value,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('small', 40);
      cache.put('huge', 500);

      // The oversized entry is handed straight back for disposal, and the
      // entries that do fit survive.
      expect(evicted, ['huge']);
      expect(cache.containsKey('small'), isTrue);
      expect(cache.containsKey('huge'), isFalse);
      expect(cache.size, 40);
    });

    test('accounts for size and evicts until within budget', () {
      final cache = LruCache<String, int>(100, sizeOf: (value) => value);

      cache.put('a', 60);
      cache.put('b', 60);

      expect(cache.containsKey('a'), isFalse);
      expect(cache.containsKey('b'), isTrue);
      expect(cache.size, 60);
    });

    test('clear reports every entry', () {
      final evicted = <String>[];
      final cache = LruCache<String, int>(
        10,
        onEvict: (key, _) => evicted.add(key),
      );

      cache.put('a', 1);
      cache.put('b', 1);
      cache.clear();

      expect(evicted, unorderedEquals(['a', 'b']));
      expect(cache.length, 0);
      expect(cache.size, 0);
    });
  });

  group('ImageStore.cacheKey', () {
    const path = '/photos/a.arw';

    test('separates layers and half-size variants', () {
      final fast = ImageStore.cacheKey(path, RawLayer.fastPreview);
      final half = ImageStore.cacheKey(path, RawLayer.decoded, halfSize: 1);
      final full = ImageStore.cacheKey(path, RawLayer.decoded, halfSize: 0);

      expect({fast, half, full}, hasLength(3));
    });

    test('separates resolutions of the same layer', () {
      // The grid and the full-screen preview want the same source at different
      // sizes; sharing one entry would show a blurry preview.
      final thumb =
          ImageStore.cacheKey(path, RawLayer.fastPreview, targetWidth: 512);
      final fullRes = ImageStore.cacheKey(path, RawLayer.fastPreview);

      expect(thumb, isNot(fullRes));
    });

    test('is stable for identical requests', () {
      expect(
        ImageStore.cacheKey(path, RawLayer.fastPreview, targetWidth: 512),
        ImageStore.cacheKey(path, RawLayer.fastPreview, targetWidth: 512),
      );
    });
  });

  group('decodeToUiImage', () {
    // A 2x2 RGBA block: red, green, blue, white.
    LibRawImage rgbaFixture() {
      final pixels = Uint8List.fromList(<int>[
        255, 0, 0, 255, /**/ 0, 255, 0, 255, //
        0, 0, 255, 255, /**/ 255, 255, 255, 255, //
      ]);
      return LibRawImage(pixels, 2, 2, RawPixelFormat.rgba8888, 2 * 4);
    }

    test('wraps raw RGBA pixels without re-encoding', () async {
      final image = await decodeToUiImage(rgbaFixture());
      addTearDown(image.dispose);

      expect(image.width, 2);
      expect(image.height, 2);
    });

    test('preserves pixel values', () async {
      final image = await decodeToUiImage(rgbaFixture());
      addTearDown(image.dispose);

      final data = await image.toByteData();
      expect(data, isNotNull);
      // First pixel stays opaque red, confirming channel order survives.
      expect(data!.buffer.asUint8List().sublist(0, 4), [255, 0, 0, 255]);
    });

    test('downscales to targetWidth', () async {
      final pixels = Uint8List(8 * 8 * 4)..fillRange(0, 8 * 8 * 4, 255);
      final source = LibRawImage(pixels, 8, 8, RawPixelFormat.rgba8888, 8 * 4);

      final image = await decodeToUiImage(source, targetWidth: 4);
      addTearDown(image.dispose);

      expect(image.width, 4);
      expect(image.height, 4);
    });

    test('never upscales past the source resolution', () async {
      final image = await decodeToUiImage(rgbaFixture(), targetWidth: 64);
      addTearDown(image.dispose);

      // Upscaling a preview costs memory and adds no detail.
      expect(image.width, 2);
      expect(image.height, 2);
    });
  });

  group('ViewerImage', () {
    test('clone shares pixels and survives the original being disposed',
        () async {
      final pixels = Uint8List.fromList(<int>[1, 2, 3, 255]);
      final uiImage = await decodeToUiImage(
        LibRawImage(pixels, 1, 1, RawPixelFormat.rgba8888, 4),
      );

      final master = ViewerImage(image: uiImage);
      final handle = master.clone();

      master.dispose();

      // The clone is an independent handle onto the same underlying image, so
      // a widget disposing its copy must not invalidate the cached master.
      expect(handle.width, 1);
      expect(handle.image.debugDisposed, isFalse);

      handle.dispose();
    });

    test('reports its texture footprint for cache accounting', () async {
      final pixels = Uint8List(4 * 4 * 4);
      final uiImage = await decodeToUiImage(
        LibRawImage(pixels, 4, 4, RawPixelFormat.rgba8888, 4 * 4),
      );
      final image = ViewerImage(image: uiImage);
      addTearDown(image.dispose);

      expect(image.sizeInBytes, 4 * 4 * 4);
    });
  });
}
