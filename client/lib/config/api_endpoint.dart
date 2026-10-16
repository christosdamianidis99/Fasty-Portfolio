import 'package:flutter/foundation.dart';

const _configuredApiBaseUrl = String.fromEnvironment('FASTY_API_BASE_URL');

String resolveApiBaseUrl() {
  final configured = _configuredApiBaseUrl.trim();
  if (configured.isNotEmpty) {
    return _withoutTrailingSlash(configured);
  }

  if (kIsWeb) {
    return 'http://localhost:8080';
  }

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => 'http://10.0.2.2:8080',
    _ => 'http://localhost:8080',
  };
}

String _withoutTrailingSlash(String value) {
  var normalized = value;
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
