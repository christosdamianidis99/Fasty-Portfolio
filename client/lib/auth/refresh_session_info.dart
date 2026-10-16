class RefreshSessionInfo {
  const RefreshSessionInfo({
    required this.id,
    required this.deviceName,
    required this.createdAt,
    required this.lastUsedAt,
    required this.expiresAt,
  });

  final String id;
  final String deviceName;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final DateTime expiresAt;

  factory RefreshSessionInfo.fromJson(Map<String, dynamic> json) {
    return RefreshSessionInfo(
      id: _requiredString(json, 'id'),
      deviceName: _requiredString(json, 'deviceName'),
      createdAt: _requiredDateTime(json, 'createdAt'),
      lastUsedAt: _optionalDateTime(json, 'lastUsedAt'),
      expiresAt: _requiredDateTime(json, 'expiresAt'),
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Refresh session response is missing "$key".');
    }

    return value.trim();
  }

  static DateTime _requiredDateTime(Map<String, dynamic> json, String key) {
    final value = _requiredString(json, key);

    return DateTime.parse(value).toUtc();
  }

  static DateTime? _optionalDateTime(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value == null) {
      return null;
    }

    if (value is! String || value.trim().isEmpty) {
      throw FormatException(
        'Refresh session response contains invalid "$key".',
      );
    }

    return DateTime.parse(value).toUtc();
  }
}
