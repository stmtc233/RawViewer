import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rawviewer/native_lib.dart';
import 'package:rawviewer/worker_service.dart';

List<String> _drain(WorkerRequestQueue<String> queue) {
  final order = <String>[];
  while (queue.isNotEmpty) {
    order.add(queue.removeNext());
  }
  return order;
}

void _sendDecodedImage(SendPort reply) {
  final pixels = Uint8List.fromList(List.generate(16, (i) => i * 7));
  reply.send(TransferableLibRawImage(TransferableTypedData.fromList([pixels]),
      2, 2, RawPixelFormat.rgba8888, 8));
}

void main() {
  test('runs every high-priority request before low, FIFO within each', () {
    final queue = WorkerRequestQueue<String>()
      ..add(1, 'low-1', TaskPriority.low)
      ..add(2, 'high-2', TaskPriority.high)
      ..add(3, 'low-3', TaskPriority.low)
      ..add(4, 'high-4', TaskPriority.high);

    expect(_drain(queue), ['high-2', 'high-4', 'low-1', 'low-3']);
  });

  test('demoted requests stay queued and yield to wanted work', () {
    final queue = WorkerRequestQueue<String>()
      ..add(1, 'scrolled-past', TaskPriority.high)
      ..add(2, 'visible', TaskPriority.high)
      ..add(3, 'prefetch', TaskPriority.low);

    expect(queue.demote(1), isTrue);
    // Demoting is not cancelling: the request still runs, after the others.
    expect(_drain(queue), ['visible', 'prefetch', 'scrolled-past']);
  });

  test('promotion and demotion only move requests of the other level', () {
    final queue = WorkerRequestQueue<String>()
      ..add(1, 'high', TaskPriority.high)
      ..add(2, 'low', TaskPriority.low);

    expect(queue.promote(1), isFalse);
    expect(queue.demote(2), isFalse);
    expect(queue.demote(99), isFalse);
    expect(queue.promote(2), isTrue);
    expect(_drain(queue), ['high', 'low']);
  });

  test('removing drops a queued request from either level', () {
    final queue = WorkerRequestQueue<String>()
      ..add(1, 'high', TaskPriority.high)
      ..add(2, 'low', TaskPriority.low);

    expect(queue.remove(2), isTrue);
    expect(queue.remove(2), isFalse);
    expect(_drain(queue), ['high']);
  });

  test('decoded images reach the main isolate intact without a second copy',
      () async {
    // Built on a spawned isolate and sent back through a SendPort, the way a
    // decode worker replies.
    final port = ReceivePort();
    await Isolate.spawn(_sendDecodedImage, port.sendPort);
    final received = await port.first as TransferableLibRawImage;

    final image = received.materialize();
    expect(image.data, List.generate(16, (i) => i * 7));
    expect([image.width, image.height, image.stride, image.isRgba],
        [2, 2, 8, true]);
    // Materializing hands the buffer over; there is no copy left to take.
    expect(received.materialize, throwsA(anything));
  });
}
