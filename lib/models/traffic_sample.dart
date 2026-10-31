class TrafficSample {
  const TrafficSample({
    required this.upload,
    required this.download,
    required this.uploadTotal,
    required this.downloadTotal,
  });

  final int upload;
  final int download;
  final int uploadTotal;
  final int downloadTotal;
}

/// 固定容量的环形缓冲。
///
/// 流量每秒推一条，用 `List` 追加再 sublist 等于每秒复制整张表，
/// 亮屏一小时就是一万次 90 元素的分配。这里只覆盖一个槽位，零分配。
class TrafficRing {
  TrafficRing(this.capacity) : _items = List<TrafficSample?>.filled(capacity, null);

  final int capacity;
  final List<TrafficSample?> _items;
  int _start = 0;
  int _length = 0;
  int _revision = 0;

  /// 每次写入/清空自增，供 CustomPainter 的 shouldRepaint 判断——
  /// 缓冲实例本身不再换引用，靠不了 identity。
  int get revision => _revision;

  int get length => _length;

  bool get isEmpty => _length == 0;

  /// 按时间正序取第 index 条（0 是最旧）。
  TrafficSample operator [](int index) => _items[(_start + index) % capacity]!;

  void add(TrafficSample sample) {
    _items[(_start + _length) % capacity] = sample;
    if (_length < capacity) {
      _length++;
    } else {
      _start = (_start + 1) % capacity;
    }
    _revision++;
  }

  void clear() {
    _start = 0;
    _length = 0;
    _revision++;
  }
}
