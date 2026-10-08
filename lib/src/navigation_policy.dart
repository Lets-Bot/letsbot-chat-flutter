import 'bridge.dart' show isWebUrl;

/// What the chat WebView does with a navigation request.
enum LetsBotNavigationAction {
  /// Load it inside the WebView (only the hosted chat screen).
  allow,

  /// Cancel it and open the URL in the system browser.
  openExternally,

  /// Cancel it silently.
  block,
}

/// Decides a navigation from the hosted chat page at [ui] to [url].
///
/// Only the chat screen itself (same origin and path as [ui]) may load in the
/// WebView. Other http(s) main-frame links open in the system browser; any
/// other scheme is blocked.
LetsBotNavigationAction decideNavigation(
  Uri ui,
  String url, {
  bool isMainFrame = true,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return LetsBotNavigationAction.block;
  if (uri.scheme == 'about' && (uri.path == 'blank' || uri.path == 'srcdoc')) {
    return LetsBotNavigationAction.allow;
  }
  if (isSameOrigin(uri, ui)) {
    if (_samePath(uri, ui)) return LetsBotNavigationAction.allow;
    if (!isMainFrame) return LetsBotNavigationAction.allow;
  }
  if (!isMainFrame) return LetsBotNavigationAction.block;
  return isWebUrl(uri)
      ? LetsBotNavigationAction.openExternally
      : LetsBotNavigationAction.block;
}

/// Whether [current] (the WebView's current URL) is the hosted chat page at
/// [ui]. Bridge messages are accepted only then.
bool isTrustedPage(Uri ui, String? current) {
  if (current == null) return false;
  final uri = Uri.tryParse(current);
  return uri != null && isSameOrigin(uri, ui) && _samePath(uri, ui);
}

/// Same scheme, host and effective port.
bool isSameOrigin(Uri a, Uri b) =>
    a.scheme.toLowerCase() == b.scheme.toLowerCase() &&
    a.host.toLowerCase() == b.host.toLowerCase() &&
    _port(a) == _port(b);

int _port(Uri uri) {
  if (uri.hasPort) return uri.port;
  return switch (uri.scheme.toLowerCase()) {
    'http' => 80,
    'https' => 443,
    _ => 0,
  };
}

bool _samePath(Uri a, Uri b) => _trim(a.path) == _trim(b.path);

String _trim(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;
