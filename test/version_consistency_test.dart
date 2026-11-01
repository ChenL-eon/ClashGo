import 'dart:io';

import 'package:clash_go/core/app_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppInfo.version 与 pubspec.yaml 保持一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(r'^version:\s*([0-9]+(?:\.[0-9]+)*)', multiLine: true).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 缺少 version 行');
    expect(AppInfo.version, match!.group(1));
  });
}
