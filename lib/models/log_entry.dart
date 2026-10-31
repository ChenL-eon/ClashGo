class LogEntry {
  const LogEntry({
    required this.time,
    required this.level,
    required this.message,
    required this.sequence,
  });

  final DateTime time;
  final String level;
  final String message;
  final int sequence;

  String get levelKey {
    switch (level.toLowerCase()) {
      case 'warning':
      case 'warn':
        return 'warning';
      case 'error':
        return 'error';
      case 'debug':
        return 'debug';
      default:
        return 'info';
    }
  }

  bool matches(String normalizedLevel, String query) {
    if (normalizedLevel != 'all' && levelKey != normalizedLevel) return false;
    if (query.isEmpty) return true;
    return message.toLowerCase().contains(query);
  }
}
