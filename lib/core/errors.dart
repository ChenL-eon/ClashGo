import 'l10n.dart';

class AppError implements Exception {
  const AppError(this.code, {this.detail, this.statusCode});

  final String code;
  final String? detail;
  final int? statusCode;

  String localized(L10n l10n) {
    final key = 'err.$code';
    final text = l10n.contains(key) ? l10n.get(key, [statusCode ?? '']) : l10n.get('err.generic');
    if (detail == null || detail!.isEmpty) return text;
    return '$text\n$detail';
  }

  @override
  String toString() => detail == null ? code : '$code: $detail';
}

AppError errorFrom(Object error) {
  if (error is AppError) return error;
  return AppError('generic', detail: error.toString());
}
