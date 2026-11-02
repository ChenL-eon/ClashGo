/// 订阅链接解析：二维码、剪贴板、clash:// 深链共用同一套规则。
/// 支持直接 http(s) 链接，也支持 `clash://install-config?url=…` 这类包装。
String? subscriptionUrlFromLink(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme == 'http' || uri.scheme == 'https') return text;
  final embedded = _queryParameter(uri, 'url') ?? _queryParameter(uri, 'config');
  if (embedded == null) return null;
  final decoded = embedded.trim();
  return decoded.startsWith('http') ? decoded : null;
}

/// queryParameters 已经解码过一次；它遇到残缺的百分号转义还会抛异常，
/// 这里统一吞掉，让解析函数对任何输入都只返回 null 而不中断调用方。
String? _queryParameter(Uri uri, String name) {
  try {
    return uri.queryParameters[name];
  } catch (_) {
    return null;
  }
}
