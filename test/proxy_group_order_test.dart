import 'package:clash_go/models/proxy_info.dart';
import 'package:clash_go/services/config_generator.dart';
import 'package:flutter_test/flutter_test.dart';

/// 内核 /proxies 的键序是 Go map 的字典序，订阅里的分组顺序要从 profile 恢复。
void main() {
  const profile = '''
proxies:
  - {name: "节点1", type: socks, server: 127.0.0.1, port: 7891}
proxy-groups:
  - name: Zulu组
    type: select
    proxies: [节点1]
  - name: Alpha组
    type: url-test
    proxies: [节点1]
  - name: Mike组
    type: fallback
    proxies: [节点1]
rules:
  - MATCH,Zulu组
''';

  Map<String, dynamic> groupJson(String name, String type) => {
        'name': name,
        'type': type,
        'all': ['节点1'],
        'now': '',
      };

  group('ConfigGenerator.groupOrder', () {
    const generator = ConfigGenerator();

    test('按 proxy-groups 书写顺序返回，重复名只保留一次', () {
      expect(generator.groupOrder(profile: profile), ['Zulu组', 'Alpha组', 'Mike组']);
      final duplicated = profile.replaceFirst(
        '  - name: Mike组\n    type: fallback\n    proxies: [节点1]',
        '  - name: Zulu组\n    type: fallback\n    proxies: [节点1]',
      );
      expect(generator.groupOrder(profile: duplicated), ['Zulu组', 'Alpha组']);
    });

    test('YAML 覆写替换 proxy-groups 时以覆写后的顺序为准', () {
      final order = generator.groupOrder(
        profile: profile,
        overrideYaml: '''
proxy-groups:
  - name: Mike组
    type: select
    proxies: [节点1]
  - name: Zulu组
    type: select
    proxies: [节点1]
''',
      );
      expect(order, ['Mike组', 'Zulu组']);
    });

    test('非法输入返回空列表，调用方退回原顺序', () {
      expect(generator.groupOrder(profile: 'not: [a'), isEmpty);
      expect(generator.groupOrder(profile: 'proxies: []'), isEmpty);
      // 覆写本身非法（受保护键）时 generate 会报错，这里同样不再给出顺序。
      expect(
        generator.groupOrder(profile: profile, overrideYaml: 'mixed-port: 7890'),
        isEmpty,
      );
    });
  });

  group('ProxiesSnapshot.orderedBy', () {
    ProxiesSnapshot snapshot() => ProxiesSnapshot.fromJson({
          'proxies': {
            'Alpha组': groupJson('Alpha组', 'Selector'),
            'Mike组': groupJson('Mike组', 'Fallback'),
            'Zulu组': groupJson('Zulu组', 'Selector'),
            '节点1': {'name': '节点1', 'type': 'Socks', 'history': []},
          },
        });

    test('按 profile 顺序重排，未知分组稳定排在末尾', () {
      final source = snapshot();
      expect(source.groups.map((g) => g.name), ['Alpha组', 'Mike组', 'Zulu组']);

      final ordered = source.orderedBy(['Zulu组', 'Alpha组']);
      expect(ordered.groups.map((g) => g.name), ['Zulu组', 'Alpha组', 'Mike组']);
      expect(identical(ordered.proxies, source.proxies), isTrue);
    });

    test('空顺序或未命中时保持原样', () {
      final source = snapshot();
      expect(source.orderedBy(const []).groups.map((g) => g.name), ['Alpha组', 'Mike组', 'Zulu组']);
      expect(source.orderedBy(const ['不存在']).groups.map((g) => g.name), ['Alpha组', 'Mike组', 'Zulu组']);
    });
  });
}
