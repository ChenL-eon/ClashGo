class ConnectionInfo {
  const ConnectionInfo({
    required this.id,
    required this.upload,
    required this.download,
    required this.start,
    required this.chains,
    required this.rule,
    required this.rulePayload,
    required this.network,
    required this.type,
    required this.source,
    required this.destination,
    required this.host,
    required this.processPath,
    required this.process,
    required this.destinationPort,
  });

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
    final metadata = json['metadata'] is Map ? Map<String, dynamic>.from(json['metadata'] as Map) : const <String, dynamic>{};
    final host = (metadata['host'] as String?)?.trim() ?? '';
    final destinationIp = (metadata['destinationIP'] as String?)?.trim() ?? '';
    final sourceIp = (metadata['sourceIP'] as String?)?.trim() ?? '';
    final sourcePort = (metadata['sourcePort'] as String?)?.trim() ?? '';
    final destinationPort = (metadata['destinationPort'] as String?)?.trim() ?? '';
    final processPath = (metadata['processPath'] as String?)?.trim() ?? '';
    return ConnectionInfo(
      id: json['id'] as String? ?? '',
      upload: (json['upload'] as num?)?.toInt() ?? 0,
      download: (json['download'] as num?)?.toInt() ?? 0,
      start: DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime.now(),
      chains: (json['chains'] as List?)?.whereType<String>().toList(growable: false) ?? const [],
      rule: json['rule'] as String? ?? '',
      rulePayload: json['rulePayload'] as String? ?? '',
      network: metadata['network'] as String? ?? '',
      type: metadata['type'] as String? ?? '',
      source: sourceIp.isEmpty ? '—' : (sourcePort.isEmpty ? sourceIp : '$sourceIp:$sourcePort'),
      destination: destinationIp.isEmpty ? '—' : (destinationPort.isEmpty ? destinationIp : '$destinationIp:$destinationPort'),
      host: host.isNotEmpty ? host : destinationIp,
      processPath: processPath,
      process: metadata['process'] as String? ?? _fileName(processPath),
      destinationPort: destinationPort,
    );
  }

  final String id;
  final int upload;
  final int download;
  final DateTime start;
  final List<String> chains;
  final String rule;
  final String rulePayload;
  final String network;
  final String type;
  final String source;
  final String destination;
  final String host;
  final String processPath;
  final String process;
  final String destinationPort;

  int get total => upload + download;

  String? get node => chains.isNotEmpty ? chains.first : null;

  String get ruleLabel => rule.isEmpty ? '—' : (rulePayload.isEmpty ? rule : '$rule($rulePayload)');

  Duration get age => DateTime.now().difference(start);

  static String _fileName(String path) {
    if (path.isEmpty) return '';
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index >= 0 ? normalized.substring(index + 1) : normalized;
  }
}

class ConnectionsSnapshot {
  const ConnectionsSnapshot({
    required this.connections,
    required this.uploadTotal,
    required this.downloadTotal,
  });

  factory ConnectionsSnapshot.fromJson(Map<String, dynamic> json) {
    final raw = json['connections'];
    final list = <ConnectionInfo>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) list.add(ConnectionInfo.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return ConnectionsSnapshot(
      connections: list,
      uploadTotal: (json['uploadTotal'] as num?)?.toInt() ?? 0,
      downloadTotal: (json['downloadTotal'] as num?)?.toInt() ?? 0,
    );
  }

  final List<ConnectionInfo> connections;
  final int uploadTotal;
  final int downloadTotal;

  int get count => connections.length;
}
