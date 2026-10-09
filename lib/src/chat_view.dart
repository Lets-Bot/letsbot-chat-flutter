import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import 'bridge.dart';
import 'chrome.dart';
import 'client.dart';
import 'errors.dart';
import 'native.dart';
import 'navigation_policy.dart';
import 'options.dart';
import 'runtime.dart';
import 'strings.dart';

/// Name of the JavaScript channel the hosted page posts bridge events to.
const String letsBotJavaScriptChannel = 'LetsBotFlutter';

/// The LetsBot chat screen as an embeddable widget.
///
/// Shows the hosted conversation UI (with the mandatory «Powered by LetsBot»
/// credit) for the configured app. Give it the space it should fill, e.g. a
/// tab or a bottom sheet. For a full-screen chat use `LetsBot.show(context)`.
///
/// The view is edge-to-edge: it passes the safe-area padding it receives
/// from [MediaQuery] to the page, which pads its header and composer itself
/// and paints the status-bar area with the header colour. Don't wrap it in a
/// `SafeArea` when it covers the whole screen; the status-bar icon style
/// follows the chat header while the view is under the status bar.
///
/// ```dart
/// Scaffold(body: LetsBotChatView())
/// ```
class LetsBotChatView extends StatefulWidget {
  /// Creates the chat view.
  const LetsBotChatView({super.key, this.onClose});

  /// Called when the user taps close inside the chat. Defaults to
  /// `Navigator.maybePop(context)`.
  final VoidCallback? onClose;

  @override
  State<LetsBotChatView> createState() => _LetsBotChatViewState();
}

class _LetsBotChatViewState extends State<LetsBotChatView> {
  LetsBotClient? _client;
  WebViewController? _controller;
  Uri? _ui;
  String? _token;
  String? _themeSent;
  LetsBotException? _error;
  bool _loading = true;
  bool _started = false;
  bool _booted = false;
  int _generation = 0;
  LetsBotChrome? _chrome;
  bool _chromeFromPage = false;
  Map<String, double>? _insetsSent;
  final StatusBarStyleKeeper _statusBar = StatusBarStyleKeeper();

  @override
  void initState() {
    super.initState();
    _statusBar.capture();
    LetsBotRuntime.viewOpened();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _chrome = _initialChrome(LetsBotRuntime.client);
      _publishChrome(_chrome);
      unawaited(_start());
    } else {
      unawaited(_syncTheme());
      unawaited(_syncInsets());
    }
  }

  @override
  void dispose() {
    _detach();
    final chrome = _chrome;
    _chrome = null;
    scheduleMicrotask(() {
      if (identical(LetsBotRuntime.chrome.value, chrome)) {
        LetsBotRuntime.chrome.value = null;
      }
    });
    _statusBar.restore();
    LetsBotRuntime.viewClosed();
    super.dispose();
  }

  // ---- lifecycle ---------------------------------------------------------

  Future<void> _start() async {
    final generation = ++_generation;
    if (_error != null || !_loading) {
      setState(() {
        _error = null;
        _loading = true;
      });
    }
    try {
      final client = await LetsBotRuntime.requireClient();
      if (!mounted || generation != _generation) return;
      _attach(client);
      unawaited(_loadCachedChrome(client));
      final token = await client.ensureSession();
      if (!mounted || generation != _generation) return;
      _token = token;
      final theme = _resolvedTheme(client);
      final ui = client.api.uiUri(locale: _locale(client), theme: theme);
      _ui = ui;
      _themeSent = theme;
      _booted = false;
      final controller = _controller ?? await _createController();
      if (!mounted || generation != _generation) return;
      if (_controller == null) setState(() => _controller = controller);
      await controller.loadRequest(ui);
    } on LetsBotException catch (e) {
      _fail(e, generation);
    } catch (e) {
      _fail(
        LetsBotException(
          LetsBotErrorCode.unknown,
          message: 'chat failed to start: ${e.runtimeType}',
        ),
        generation,
      );
    }
  }

  void _fail(LetsBotException error, [int? generation]) {
    if (!mounted || (generation != null && generation != _generation)) return;
    LetsBotRuntime.reportError(error);
    setState(() {
      _error = error;
      _loading = false;
    });
  }

  void _attach(LetsBotClient client) {
    if (identical(_client, client)) return;
    _detach();
    _client = client;
    client.context.addListener(_onContextChanged);
    client.theme.addListener(_onThemeChanged);
    client.locale.addListener(_onLocaleChanged);
  }

  void _detach() {
    final client = _client;
    if (client == null) return;
    try {
      client.context.removeListener(_onContextChanged);
      client.theme.removeListener(_onThemeChanged);
      client.locale.removeListener(_onLocaleChanged);
    } catch (_) {
      // The client was disposed by a re-configure.
    }
    _client = null;
  }

  void _onContextChanged() {
    final client = _client;
    if (client == null || !_booted) return;
    unawaited(_run(hostCallScript('setContext', client.context.value)));
  }

  void _onThemeChanged() => unawaited(_syncTheme());

  void _onLocaleChanged() {
    if (_ui != null) unawaited(_start());
  }

  // ---- WebView -----------------------------------------------------------

  Future<WebViewController> _createController() async {
    final controller = WebViewController(
      onPermissionRequest: _onPermissionRequest,
    );
    await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
    await controller.setBackgroundColor(_backgroundColor);
    await controller.addJavaScriptChannel(
      letsBotJavaScriptChannel,
      onMessageReceived: _onBridgeMessage,
    );
    await controller.setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: _onNavigationRequest,
      onPageFinished: (_) {
        if (mounted && _error == null) setState(() => _loading = false);
      },
      onWebResourceError: _onWebResourceError,
      onHttpError: _onHttpError,
    ));
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      await platform.setMediaPlaybackRequiresUserGesture(false);
      await platform.setOnShowFileSelector(_onShowFileSelector);
    }
    return controller;
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final ui = _ui;
    if (ui == null) return NavigationDecision.prevent;
    switch (
        decideNavigation(ui, request.url, isMainFrame: request.isMainFrame)) {
      case LetsBotNavigationAction.allow:
        return NavigationDecision.navigate;
      case LetsBotNavigationAction.openExternally:
        unawaited(_openExternally(Uri.parse(request.url)));
        return NavigationDecision.prevent;
      case LetsBotNavigationAction.block:
        return NavigationDecision.prevent;
    }
  }

  void _onWebResourceError(WebResourceError error) {
    if (error.isForMainFrame == false) return;
    if (error.errorType == WebResourceErrorType.webContentProcessTerminated) {
      unawaited(_start());
      return;
    }
    // -999 / 102: navigation cancelled by our own policy (iOS).
    if (_booted || error.errorCode == -999 || error.errorCode == 102) return;
    _fail(LetsBotException(
      LetsBotErrorCode.network,
      message: 'chat screen failed to load (${error.errorCode})',
    ));
  }

  void _onHttpError(HttpResponseError error) {
    final ui = _ui;
    final status = error.response?.statusCode;
    final url = error.request?.uri.toString();
    if (ui == null || status == null || _booted) return;
    if (!isTrustedPage(ui, url)) return;
    final code = switch (status) {
      404 => LetsBotErrorCode.notFound,
      403 => LetsBotErrorCode.appNotRegistered,
      429 => LetsBotErrorCode.slowDown,
      >= 500 => LetsBotErrorCode.server,
      _ => LetsBotErrorCode.unknown,
    };
    _fail(LetsBotException(code, statusCode: status));
  }

  Future<void> _onPermissionRequest(WebViewPermissionRequest request) async {
    final types = request.types;
    final microphoneOnly = types.isNotEmpty &&
        types.every((t) => t == WebViewPermissionResourceType.microphone);
    if (microphoneOnly && await LetsBotNative.requestMicrophone()) {
      await request.grant();
    } else {
      await request.deny();
    }
  }

  Future<List<String>> _onShowFileSelector(FileSelectorParams params) {
    return LetsBotNative.pickFiles(
      accept: params.acceptTypes,
      multiple: params.mode == FileSelectorMode.openMultiple,
    );
  }

  // ---- bridge ------------------------------------------------------------

  Future<void> _onBridgeMessage(JavaScriptMessage message) async {
    final controller = _controller;
    final ui = _ui;
    final client = _client;
    if (controller == null || ui == null || client == null) return;
    // Accept bridge calls only while the LetsBot chat page is loaded.
    if (!isTrustedPage(ui, await controller.currentUrl())) return;
    final event = parseBridgeEvent(message.message);
    if (event == null || !mounted) return;
    switch (event) {
      case BridgeReady():
        await _boot();
      case BridgeTokenInvalid():
        try {
          _token = await client.renewSession();
          await _boot();
        } on LetsBotException catch (e) {
          _fail(e);
        }
      case BridgeClose():
        _close();
      case BridgeOpenUrl(:final url):
        await _openExternally(url);
      case BridgeUnread(:final count):
        client.setUnreadFromPage(count);
      case BridgeMessage(:final text):
        LetsBotRuntime.reportMessage(text);
      case BridgeError(:final code):
        LetsBotRuntime.reportError(LetsBotException.fromWire(code));
      case BridgeChrome(
          :final lightStatusBar,
          :final header,
          :final background
        ):
        final theme = _themeSent ?? _resolvedTheme(client);
        final chrome = (_chrome ?? _initialChrome(client)).merge(
          lightStatusBar: lightStatusBar,
          header: header,
          background: background,
        );
        _chromeFromPage = true;
        _applyChrome(chrome);
        unawaited(client.saveChrome(theme, chrome));
    }
  }

  // ---- chrome & insets ---------------------------------------------------

  LetsBotChrome _initialChrome(LetsBotClient? client) {
    final dark = client == null
        ? Theme.of(context).brightness == Brightness.dark
        : _resolvedTheme(client) == 'dark';
    return client?.cachedChrome(dark ? 'dark' : 'light') ??
        LetsBotChrome.neutral(dark: dark, brandColor: client?.color);
  }

  Future<void> _loadCachedChrome(LetsBotClient client) async {
    final theme = _resolvedTheme(client);
    final cached = await client.loadChrome(theme);
    if (!mounted || _chromeFromPage) return;
    _applyChrome(cached ?? _initialChrome(client));
  }

  void _applyChrome(LetsBotChrome chrome) {
    if (!mounted || chrome == _chrome) return;
    final backgroundChanged = chrome.background != _chrome?.background;
    setState(() => _chrome = chrome);
    _publishChrome(chrome);
    if (backgroundChanged) {
      unawaited(_controller?.setBackgroundColor(chrome.backgroundColor));
    }
  }

  /// Shares the chrome with [LetsBotChatScreen] outside the build phase.
  void _publishChrome(LetsBotChrome? chrome) {
    scheduleMicrotask(() {
      if (mounted && identical(_chrome, chrome)) {
        LetsBotRuntime.chrome.value = chrome;
      }
    });
  }

  Color get _backgroundColor =>
      (_chrome ?? _initialChrome(_client)).backgroundColor;

  Map<String, double> _currentInsets() =>
      insetsPayload(MediaQuery.paddingOf(context));

  Future<void> _syncInsets() async {
    if (!_booted || !mounted) return;
    final insets = _currentInsets();
    if (mapEquals(insets, _insetsSent)) return;
    _insetsSent = insets;
    await _run(hostCallScript('setInsets', insets));
  }

  Future<void> _boot() async {
    final client = _client;
    final token = _token;
    if (client == null || token == null) return;
    if (!mounted) return;
    final insets = _currentInsets();
    _insetsSent = insets;
    await _run(
        hostCallScript('boot', client.bootPayload(token, insets: insets)));
    _booted = true;
    if (mounted) setState(() => _loading = false);
    await _syncTheme();
    await _syncInsets();
  }

  Future<void> _syncTheme() async {
    final client = _client;
    if (client == null || !_booted || !mounted) return;
    final theme = _resolvedTheme(client);
    if (theme == _themeSent) return;
    _themeSent = theme;
    // Until the page reports its chrome for the new theme, use the cached
    // (or neutral) colours of that theme.
    _chromeFromPage = false;
    _applyChrome(_initialChrome(client));
    unawaited(_loadCachedChrome(client));
    await _run(hostCallScript('setTheme', theme));
  }

  Future<void> _run(String script) async {
    try {
      await _controller?.runJavaScript(script);
    } catch (_) {
      // Page not ready or navigated away; the next boot resends state.
    }
  }

  Future<void> _openExternally(Uri url) async {
    if (!isWebUrl(url)) return;
    try {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      // No browser available; nothing else to do.
    }
  }

  void _close() {
    final onClose = widget.onClose;
    if (onClose != null) {
      onClose();
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  // ---- helpers -----------------------------------------------------------

  String _locale(LetsBotClient client) {
    final appLocale = Localizations.maybeLocaleOf(context) ??
        WidgetsBinding.instance.platformDispatcher.locale;
    return client.effectiveLocale(appLocale.languageCode);
  }

  String _resolvedTheme(LetsBotClient client) {
    switch (client.theme.value) {
      case LetsBotTheme.light:
        return 'light';
      case LetsBotTheme.dark:
        return 'dark';
      case LetsBotTheme.auto:
        return Theme.of(context).brightness == Brightness.dark
            ? 'dark'
            : 'light';
    }
  }

  Color? _brandColor() {
    final hex = _client?.color;
    if (hex == null) return null;
    final value = int.tryParse(hex.substring(1), radix: 16);
    return value == null ? null : Color(0xFF000000 | value);
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final error = _error;
    final client = _client;
    final strings = LetsBotStrings.of(client == null ? null : _locale(client));
    final chrome = _chrome ?? _initialChrome(client);
    final background = chrome.backgroundColor;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: chrome.overlayStyle,
      child: ColoredBox(
        color: background,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null) WebViewWidget(controller: controller),
            if (_loading && error == null)
              Material(
                color: background,
                child: SafeArea(
                  child: Stack(
                    children: [
                      Center(
                        child: CircularProgressIndicator(color: _brandColor()),
                      ),
                      // Always offer a way out while the screen loads.
                      Align(
                        alignment: AlignmentDirectional.topEnd,
                        child: IconButton(
                          tooltip: strings.close,
                          icon: Icon(
                            Icons.close,
                            color: background.computeLuminance() < 0.5
                                ? Colors.white
                                : const Color(0xFF1F2328),
                          ),
                          onPressed: _close,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            if (error != null)
              _ErrorPane(
                background: background,
                dark: background.computeLuminance() < 0.5,
                strings: strings,
                message: strings.messageFor(error),
                onRetry: () => unawaited(_start()),
                onClose: _close,
              ),
          ],
        ),
      ),
    );
  }
}

class _ErrorPane extends StatelessWidget {
  const _ErrorPane({
    required this.background,
    required this.dark,
    required this.strings,
    required this.message,
    required this.onRetry,
    required this.onClose,
  });

  final Color background;
  final bool dark;
  final LetsBotStrings strings;
  final String message;
  final VoidCallback onRetry;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final foreground = dark ? Colors.white : const Color(0xFF1F2328);
    return Directionality(
      textDirection: strings.rtl ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: background,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline, size: 48, color: foreground),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: foreground, fontSize: 16),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onRetry, child: Text(strings.retry)),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: onClose,
                    child: Text(strings.close,
                        style: TextStyle(color: foreground)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen chat page used by `LetsBot.show`. You can also push it
/// yourself, e.g. with your own route or navigation package.
///
/// Edge-to-edge: the chat page paints under the status bar and the home
/// indicator, the status-bar icons follow the chat header, and the app's
/// previous status-bar style comes back when the screen closes. The body
/// resizes above the keyboard.
class LetsBotChatScreen extends StatelessWidget {
  /// Creates the screen.
  const LetsBotChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<LetsBotChrome?>(
      valueListenable: LetsBotRuntime.chrome,
      builder: (context, chrome, child) {
        final client = LetsBotRuntime.client;
        final dark = switch (client?.theme.value) {
          LetsBotTheme.dark => true,
          LetsBotTheme.light => false,
          _ => Theme.of(context).brightness == Brightness.dark,
        };
        final background = chrome?.backgroundColor ??
            (dark ? const Color(0xFF111418) : Colors.white);
        return Scaffold(
          backgroundColor: background,
          resizeToAvoidBottomInset: true,
          body: child,
        );
      },
      child: LetsBotChatView(
        onClose: () => unawaited(Navigator.of(context).maybePop()),
      ),
    );
  }
}
