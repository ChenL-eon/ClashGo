class DnsAnswer {
  const DnsAnswer({required this.name, required this.ttl, required this.data, required this.type});

  factory DnsAnswer.fromJson(Map<String, dynamic> json) {
    return DnsAnswer(
      name: json['name'] as String? ?? '',
      ttl: (json['TTL'] as num?)?.toInt() ?? (json['ttl'] as num?)?.toInt() ?? 0,
      data: json['data'] as String? ?? '',
      type: (json['type'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final int ttl;
  final String data;
  final int type;

  String get typeName {
    switch (type) {
      case 1:
        return 'A';
      case 2:
        return 'NS';
      case 5:
        return 'CNAME';
      case 6:
        return 'SOA';
      case 15:
        return 'MX';
      case 16:
        return 'TXT';
      case 28:
        return 'AAAA';
      case 33:
        return 'SRV';
      default:
        return 'TYPE$type';
    }
  }
}

class DnsQueryResult {
  const DnsQueryResult({required this.status, required this.answers});

  factory DnsQueryResult.fromJson(Map<String, dynamic> json) {
    final raw = json['Answer'];
    final answers = <DnsAnswer>[];
    if (raw is List) {
      for (final item in raw) {
        if (item is Map) answers.add(DnsAnswer.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return DnsQueryResult(
      status: (json['Status'] as num?)?.toInt() ?? (json['status'] as num?)?.toInt() ?? 0,
      answers: answers,
    );
  }

  final int status;
  final List<DnsAnswer> answers;

  bool get success => status == 0;
}
