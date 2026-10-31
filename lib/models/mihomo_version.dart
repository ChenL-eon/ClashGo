class MihomoVersion {
  const MihomoVersion({required this.version, required this.meta});

  final String version;
  final bool meta;

  @override
  String toString() => version;
}
