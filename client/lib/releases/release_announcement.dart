class ReleaseAnnouncement {
  const ReleaseAnnouncement({
    required this.id,
    required this.title,
    required this.message,
    this.contactUrl,
  });

  final String id;
  final String title;
  final String message;
  final String? contactUrl;

  factory ReleaseAnnouncement.fromJson(Map<String, dynamic> json) {
    final id = _requiredString(json, 'id');
    final title = _requiredString(json, 'title');
    final message = _requiredString(json, 'message');

    final rawContactUrl = json['contactUrl'];
    String? contactUrl;

    if (rawContactUrl != null) {
      if (rawContactUrl is! String) {
        throw const FormatException(
          'Release announcement "contactUrl" must be a string.',
        );
      }

      final normalized = rawContactUrl.trim();

      if (normalized.isNotEmpty) {
        contactUrl = normalized;
      }
    }

    return ReleaseAnnouncement(
      id: id,
      title: title,
      message: message,
      contactUrl: contactUrl,
    );
  }

  static String _requiredString(Map<String, dynamic> json, String key) {
    final value = json[key];

    if (value is! String || value.trim().isEmpty) {
      throw FormatException('Release announcement is missing "$key".');
    }

    return value.trim();
  }
}
