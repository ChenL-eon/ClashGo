import 'dart:io';

class CoreLog {
  CoreLog(this.file);

  final File file;
  final List<String> _recent = [];
  Future<void> _queue = Future.value();

  List<String> get recent => List.unmodifiable(_recent);

  void reset() {
    _recent.clear();
    _queue = _queue.then((_) async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString('', flush: true);
      } catch (_) {}
    });
  }

  void append(String line) {
    final trimmed = line.trimRight();
    if (trimmed.isEmpty) return;
    final entry = '[${DateTime.now().toIso8601String()}] $trimmed';
    _recent.add(entry);
    if (_recent.length > 500) _recent.removeRange(0, _recent.length - 500);
    _queue = _queue.then((_) async {
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString('$entry\n', mode: FileMode.append, flush: false);
      } catch (_) {}
    });
  }

  String tail([int lines = 30]) {
    if (_recent.isEmpty) return '—';
    return _recent.skip(_recent.length > lines ? _recent.length - lines : 0).join('\n');
  }

  Future<void> flush() => _queue;
}
