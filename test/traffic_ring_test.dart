import 'package:clash_go/models/traffic_sample.dart';
import 'package:flutter_test/flutter_test.dart';

TrafficSample sample(int up) => TrafficSample(
      upload: up,
      download: up * 2,
      uploadTotal: up,
      downloadTotal: up * 2,
    );

void main() {
  group('TrafficRing', () {
    test('未满时按写入顺序读取', () {
      final ring = TrafficRing(5);
      for (var i = 1; i <= 3; i++) {
        ring.add(sample(i));
      }
      expect(ring.length, 3);
      expect(ring[0].upload, 1);
      expect(ring[2].upload, 3);
    });

    test('写满后继续写入会覆盖最旧，顺序仍然是时间正序', () {
      final ring = TrafficRing(3);
      for (var i = 1; i <= 7; i++) {
        ring.add(sample(i));
      }
      expect(ring.length, 3);
      expect([for (var i = 0; i < ring.length; i++) ring[i].upload], [5, 6, 7]);
    });

    test('正好写满 capacity 时不越界', () {
      final ring = TrafficRing(4);
      for (var i = 1; i <= 4; i++) {
        ring.add(sample(i));
      }
      expect([for (var i = 0; i < ring.length; i++) ring[i].upload], [1, 2, 3, 4]);
    });

    test('revision 每次写入和清空都自增，供 shouldRepaint 判断', () {
      final ring = TrafficRing(2);
      expect(ring.revision, 0);
      ring.add(sample(1));
      expect(ring.revision, 1);
      ring.add(sample(2));
      ring.add(sample(3));
      expect(ring.revision, 3);
      ring.clear();
      expect(ring.revision, 4);
      expect(ring.isEmpty, isTrue);
      expect(ring.length, 0);
    });

    test('clear 之后重新从下标 0 开始写', () {
      final ring = TrafficRing(3);
      ring.add(sample(9));
      ring.add(sample(9));
      ring.clear();
      ring.add(sample(1));
      ring.add(sample(2));
      expect(ring[0].upload, 1);
      expect(ring[1].upload, 2);
    });
  });
}
