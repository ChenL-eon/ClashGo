import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../services/mihomo_api.dart';

class JsonSocket {
  JsonSocket({
    required this.api,
    required this.path,
    required this.onData,
    this.query,
    this.onState,
  });

  final MihomoApi api;
  final String path;
  final Map<String, String> Function()? query;
  final void Function(Map<String, dynamic> data) onData;
  final void Function(bool connected)? onState;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  bool _closed = false;
  bool _reconnecting = false;
  int _attempt = 0;

  void start() {
    _closed = false;
    _connect();
  }

  Future<void> _connect() async {
    if (_closed) return;
    try {
      final uri = api.websocketUri(path, query: query?.call());
      final channel = WebSocketChannel.connect(uri);
      _channel = channel;
      await channel.ready.timeout(const Duration(seconds: 5));
      if (_closed) {
        await channel.sink.close();
        return;
      }
      _attempt = 0;
      onState?.call(true);
      _subscription = channel.stream.listen(
        (event) {
          if (event is! String) return;
          try {
            final decoded = jsonDecode(event);
            if (decoded is Map) onData(Map<String, dynamic>.from(decoded));
          } catch (_) {}
        },
        onError: (_) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    if (_closed || _reconnecting) return;
    _reconnecting = true;
    onState?.call(false);
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    final delay = Duration(milliseconds: (1000 * (1 << _attempt.clamp(0, 5))).clamp(1000, 30000));
    _attempt = (_attempt + 1).clamp(0, 5);
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _reconnecting = false;
      _connect();
    });
  }

  void dispose() {
    _closed = true;
    _retryTimer?.cancel();
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
    onState?.call(false);
  }
}
