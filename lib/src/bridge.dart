import 'dart:convert';

/// Event posted by the hosted chat page through the `LetsBotFlutter`
/// JavaScript channel: a JSON string `{"lb": "<event>", ...}`.
sealed class LetsBotBridgeEvent {
  const LetsBotBridgeEvent();
}

/// The page loaded and waits for `LetsBotHost.boot(...)`.
final class BridgeReady extends LetsBotBridgeEvent {
  /// Creates the event.
  const BridgeReady();
}

/// The page's visitor token was rejected; native must create a new session.
final class BridgeTokenInvalid extends LetsBotBridgeEvent {
  /// Creates the event.
  const BridgeTokenInvalid();
}

/// The user tapped close in the page.
final class BridgeClose extends LetsBotBridgeEvent {
  /// Creates the event.
  const BridgeClose();
}

/// The page asks native to open an http(s) link in the system browser.
final class BridgeOpenUrl extends LetsBotBridgeEvent {
  /// Creates the event.
  const BridgeOpenUrl(this.url);

  /// Validated http/https URL.
  final Uri url;
}

/// New unread count (0 while the chat is visible).
final class BridgeUnread extends LetsBotBridgeEvent {
  /// Creates the event.
  const BridgeUnread(this.count);

  /// Unread messages.
  final int count;
}

/// A team/AI message arrived while the chat is open.
final class BridgeMessage extends LetsBotBridgeEvent {
  /// Creates the event.
  const BridgeMessage(this.text);

  /// Message text. Never log it.
  final String text;
}

/// The page hit an error with an API error code.
final class BridgeError extends LetsBotBridgeEvent {
  /// Creates the event.
  const BridgeError(this.code);

  /// Error code (see `LetsBotErrorCode`).
  final String code;
}

/// Parses a bridge message. Returns `null` for anything malformed or unknown,
/// so a hostile or buggy page cannot crash the host.
LetsBotBridgeEvent? parseBridgeEvent(String raw) {
  if (raw.length > 64 * 1024) return null;
  final Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return null;
  }
  if (decoded is! Map) return null;
  final event = decoded['lb'];
  if (event is! String) return null;
  switch (event) {
    case 'ready':
      return const BridgeReady();
    case 'token_invalid':
      return const BridgeTokenInvalid();
    case 'close':
      return const BridgeClose();
    case 'open_url':
      final url = decoded['url'];
      if (url is! String) return null;
      final uri = Uri.tryParse(url);
      if (uri == null || !isWebUrl(uri)) return null;
      return BridgeOpenUrl(uri);
    case 'unread':
      final count = decoded['count'];
      if (count is! num || count < 0) return null;
      return BridgeUnread(count.toInt());
    case 'message':
      final text = decoded['t'];
      return BridgeMessage(text is String ? text : '');
    case 'error':
      final code = decoded['code'];
      return BridgeError(code is String && code.isNotEmpty ? code : 'unknown');
    default:
      return null;
  }
}

/// Whether [uri] is an absolute http(s) URL with a host.
bool isWebUrl(Uri uri) =>
    (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;

/// JavaScript that calls `window.LetsBotHost.<method>(<arg>)` when present.
///
/// [arg] is JSON-encoded, with U+2028/U+2029 escaped so the literal is valid
/// JavaScript in every engine.
String hostCallScript(String method, Object? arg) {
  final literal = jsonEncode(arg)
      .replaceAll('\u2028', r'\u2028')
      .replaceAll('\u2029', r'\u2029');
  return '(function(){var h=window.LetsBotHost;'
      'if(h&&typeof h.$method==="function"){h.$method($literal);}})();';
}
