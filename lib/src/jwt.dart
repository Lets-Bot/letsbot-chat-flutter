import 'dart:convert';

/// Returns the `sub` claim of a JWT without verifying it (verification
/// happens on the LetsBot server). `null` when [token] is not a readable JWT.
String? jwtSubject(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is Map && payload['sub'] is String) {
      return payload['sub'] as String;
    }
  } catch (_) {
    // Not a JWT.
  }
  return null;
}
