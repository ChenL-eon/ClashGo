import 'package:yaml/yaml.dart';

import '../models/proxy_info.dart';

class OfflineEndpoint {
  const OfflineEndpoint({required this.host, required this.port});

  final String host;
  final int port;
}

class OfflineProxiesResult {
  const OfflineProxiesResult({required this.snapshot, required this.endpoints});

  final ProxiesSnapshot snapshot;
  final Map<String, OfflineEndpoint> endpoints;
}

class OfflineProxies {
  const OfflineProxies._();

  static OfflineProxiesResult? parse(
    String content, {
    String fallbackGroupName = '',
    Map<String, String> selections = const {},
  }) {
    dynamic doc;
    try {
      doc = loadYaml(content);
    } catch (_) {
      return null;
    }
    if (doc is! Map) return null;
    final map = Map<String, dynamic>.from(doc);

    final proxies = <String, ProxyInfo>{};
    final endpoints = <String, OfflineEndpoint>{};
    final rawProxies = map['proxies'];
    if (rawProxies is List) {
      for (final item in rawProxies) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        proxies[name] = ProxyInfo(
          name: name,
          type: item['type']?.toString() ?? '',
          alive: true,
          now: '',
          all: const [],
          delay: null,
          udp: item['udp'] == true,
          xudp: item['xudp'] == true,
          tfo: item['tfo'] == true,
        );
        final host = item['server']?.toString().trim() ?? '';
        final rawPort = item['port'];
        final port = rawPort is num ? rawPort.toInt() : int.tryParse(rawPort?.toString() ?? '');
        if (host.isNotEmpty && port != null && port > 0 && port <= 65535) {
          endpoints[name] = OfflineEndpoint(host: host, port: port);
        }
      }
    }

    final groups = <ProxyInfo>[];
    final rawGroups = map['proxy-groups'];
    if (rawGroups is List) {
      for (final item in rawGroups) {
        if (item is! Map) continue;
        final name = item['name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        final members = <String>[];
        final rawMembers = item['proxies'];
        if (rawMembers is List) {
          for (final member in rawMembers) {
            final value = member?.toString().trim() ?? '';
            if (value.isNotEmpty && proxies.containsKey(value)) members.add(value);
          }
        }
        // Provider-backed groups have no static members in the profile.
        if (members.isEmpty) continue;
        groups.add(
          ProxyInfo(
            name: name,
            type: item['type']?.toString() ?? 'select',
            alive: true,
            now: selections[name] ?? '',
            all: List.unmodifiable(members),
            delay: null,
            udp: false,
            xudp: false,
            tfo: false,
          ),
        );
      }
    }

    if (groups.isEmpty && proxies.isNotEmpty) {
      final name = fallbackGroupName.trim().isEmpty ? 'PROXY' : fallbackGroupName.trim();
      groups.add(
        ProxyInfo(
          name: name,
          type: 'select',
          alive: true,
          now: selections[name] ?? '',
          all: List.unmodifiable(proxies.keys),
          delay: null,
          udp: false,
          xudp: false,
          tfo: false,
        ),
      );
    }

    if (groups.isEmpty) return null;
    return OfflineProxiesResult(
      snapshot: ProxiesSnapshot(proxies: proxies, groups: groups),
      endpoints: endpoints,
    );
  }
}
