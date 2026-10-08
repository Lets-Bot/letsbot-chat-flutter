import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'chat_view.dart';
import 'client.dart';
import 'device_info.dart';
import 'errors.dart';
import 'notifications.dart';
import 'options.dart';
import 'runtime.dart';
import 'token_store.dart';

/// Entry point of the LetsBot In-App Chat SDK.
///
/// ```dart
/// Future<void> main() async {
///   WidgetsFlutterBinding.ensureInitialized();
///   await LetsBot.configure(appKey: 'YOUR_APP_KEY', locale: 'en');
///   runApp(const MyApp());
/// }
///
/// // Anywhere with a BuildContext:
/// LetsBot.show(context);
/// ```
abstract final class LetsBot {
  static const String _defaultBaseUrl = 'https://letsbot.net';
  static final RegExp _hexColor = RegExp(r'^#[0-9a-fA-F]{6}$');

  static _LifecycleObserver? _observer;
  static Route<void>? _route;
  static VoidCallback? _unreadListener;

  static Map<String, Object?>? _pendingContext;
  static String? _pendingLocale;
  static bool _hasPendingLocale = false;
  static LetsBotTheme? _pendingTheme;

  // ---- setup -------------------------------------------------------------

  /// Configures the SDK. Call once, as early as possible (in `main()` before
  /// `runApp`). Calling it again replaces the previous configuration.
  ///
  /// - [appKey]: the public App Key from LetsBot panel → Channels → In-App
  ///   Chat (safe to ship in the app).
  /// - [baseUrl]: LetsBot server, default `https://letsbot.net`.
  /// - [locale]: chat language (`ar`, `en`, `es`, `pt`; others fall back to
  ///   English). `null` follows the app's current locale.
  /// - [theme]: [LetsBotTheme.auto] follows the app's light/dark theme.
  /// - [color]: brand colour `#rrggbb`; `null` uses the panel colour.
  /// - [navigatorKey]: your app's navigator key, so [handleNotification]
  ///   can open the chat without a `BuildContext` (cold start, background
  ///   tap).
  /// - [tokenStore]: where the visitor token is kept. Defaults to secure
  ///   storage (Keychain / Android Keystore).
  /// - [httpClient]: custom HTTP client (e.g. a proxy or pinning client).
  ///
  /// Throws [LetsBotException] for invalid arguments or an unsupported
  /// platform.
  static Future<void> configure({
    required String appKey,
    String? baseUrl,
    String? locale,
    LetsBotTheme theme = LetsBotTheme.auto,
    String? color,
    GlobalKey<NavigatorState>? navigatorKey,
    LetsBotTokenStore? tokenStore,
    http.Client? httpClient,
    @visibleForTesting LetsBotDeviceInfo? deviceInfo,
  }) async {
    final key = appKey.trim();
    if (key.isEmpty || key.contains('/')) {
      throw LetsBotException(
        LetsBotErrorCode.invalid,
        message: 'appKey is empty or malformed',
      );
    }
    final base = Uri.tryParse((baseUrl ?? _defaultBaseUrl).trim());
    if (base == null ||
        !(base.scheme == 'https' || base.scheme == 'http') ||
        base.host.isEmpty) {
      throw LetsBotException(
        LetsBotErrorCode.invalid,
        message: 'baseUrl must be an absolute http(s) URL',
      );
    }
    if (color != null && !_hexColor.hasMatch(color)) {
      throw LetsBotException(
        LetsBotErrorCode.invalid,
        message: 'color must look like #0e7c66',
      );
    }

    WidgetsFlutterBinding.ensureInitialized();
    _observer ??= _LifecycleObserver()..attach();
    LetsBotRuntime.navigatorKey = navigatorKey;

    final future = () async {
      final device = deviceInfo ?? await LetsBotDeviceInfo.load();
      final client = LetsBotClient(
        appKey: key,
        baseUrl: base,
        device: device,
        tokenStore: tokenStore,
        httpClient: httpClient,
        locale: _hasPendingLocale ? _pendingLocale : locale,
        theme: _pendingTheme ?? theme,
        color: color?.toLowerCase(),
      );
      final pendingContext = _pendingContext;
      if (pendingContext != null) client.setContext(pendingContext);
      _pendingContext = null;
      _pendingLocale = null;
      _hasPendingLocale = false;
      _pendingTheme = null;

      client.onError = LetsBotRuntime.reportError;
      final previous = LetsBotRuntime.client;
      final previousListener = _unreadListener;
      if (previous != null && previousListener != null) {
        previous.unread.removeListener(previousListener);
      }
      void listener() => LetsBotRuntime.publishUnread(client.unread.value);
      client.unread.addListener(listener);
      _unreadListener = listener;
      LetsBotRuntime.client = client;
      previous?.dispose();
      return client;
    }();
    LetsBotRuntime.ready = future;
    final client = await future;
    unawaited(client.refreshUnread());
  }

  /// Whether [configure] was called.
  static bool get isConfigured => LetsBotRuntime.ready != null;

  // ---- identity ----------------------------------------------------------

  /// Links the chat to your logged-in user, so they keep one conversation
  /// across devices and reinstalls and your team sees who they are.
  ///
  /// [identityToken] is a short-lived JWT (HS256) your backend signs with
  /// the LetsBot Identity Secret, `sub` = [userId]. Call this right after
  /// login and on every app start while logged in.
  ///
  /// Throws [LetsBotException]; on [LetsBotErrorCode.identityExpired] fetch
  /// a new token from your backend and call again.
  static Future<bool> identify({
    required String userId,
    required String identityToken,
    String? name,
    String? email,
    String? phone,
  }) async {
    final client = await LetsBotRuntime.requireClient();
    return client.identify(
      userId: userId,
      identityToken: identityToken,
      name: name,
      email: email,
      phone: phone,
    );
  }

  /// Call when the user logs out, before clearing your own session: closes
  /// the chat, unregisters this device's push token for the visitor and
  /// forgets the conversation on this device. Never throws.
  static Future<void> logout() async {
    hide();
    final client = await _clientOrReport();
    await client?.logout();
  }

  // ---- UI ----------------------------------------------------------------

  /// Opens the full-screen chat. Completes when it is closed. Does nothing
  /// if the chat is already open.
  static Future<void> show(BuildContext context) {
    final navigator = Navigator.of(context, rootNavigator: true);
    return _open(navigator);
  }

  static Future<void> _open(NavigatorState navigator) async {
    final current = _route;
    if (current != null && current.isActive) return;
    final route = MaterialPageRoute<void>(
      fullscreenDialog: true,
      settings: const RouteSettings(name: 'letsbot_chat'),
      builder: (_) => const LetsBotChatScreen(),
    );
    _route = route;
    try {
      await navigator.push(route);
    } finally {
      if (identical(_route, route)) _route = null;
    }
  }

  /// Closes the chat opened with [show] (no-op if it is not open).
  static void hide() {
    final route = _route;
    if (route == null || !route.isActive) return;
    final navigator = route.navigator;
    if (navigator == null) return;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
    _route = null;
  }

  /// Whether the chat screen opened with [show] (or an embedded
  /// [LetsBotChatView]) is visible.
  static bool get isOpen => LetsBotRuntime.openViews > 0;

  // ---- push --------------------------------------------------------------

  /// Registers this device's push token so LetsBot can notify the user of
  /// replies while the app is closed. Call on start and whenever the token
  /// refreshes.
  ///
  /// [provider]: [LetsBotPushProvider.fcm] for Firebase tokens (default),
  /// [LetsBotPushProvider.apns] for raw APNs device tokens. [sandbox]
  /// (APNs only) defaults to `true` in debug/profile builds.
  ///
  /// No session is created just for this: the token is registered with the
  /// user's first chat. Never throws; failures go to [onError].
  static Future<void> setPushToken(
    String token, {
    LetsBotPushProvider provider = LetsBotPushProvider.fcm,
    bool? sandbox,
  }) async {
    final client = await _clientOrReport();
    await client?.setPushToken(token, provider: provider, sandbox: sandbox);
  }

  /// Whether a push payload (FCM `message.data` or APNs `userInfo`) came
  /// from LetsBot. Leave every other notification to your own handling.
  static bool isLetsBotNotification(Map<Object?, Object?>? data) =>
      isLetsBotPayload(data);

  /// Handles a LetsBot notification tap: refreshes the unread count and
  /// opens the chat using [context] or the `navigatorKey` given to
  /// [configure]. Returns `false` (and does nothing) for other payloads.
  static Future<bool> handleNotification(
    BuildContext? context,
    Map<Object?, Object?>? data,
  ) async {
    if (!isLetsBotPayload(data)) return false;
    final navigator = context != null
        ? Navigator.maybeOf(context, rootNavigator: true)
        : LetsBotRuntime.navigatorKey?.currentState;
    unawaited(refreshUnread());
    if (navigator == null) {
      debugPrint(
        '[letsbot_chat] handleNotification: pass a BuildContext or give '
        'LetsBot.configure a navigatorKey to open the chat.',
      );
      return true;
    }
    if (!isOpen) unawaited(_open(navigator));
    return true;
  }

  // ---- unread ------------------------------------------------------------

  /// Unread team/AI messages, for a badge. Updated on app resume, after
  /// pushes, while the chat is open, and by [refreshUnread].
  static ValueListenable<int> get unreadCount => LetsBotRuntime.unread;

  /// [unreadCount] as a broadcast stream (emits on change).
  static Stream<int> get unreadCountStream =>
      LetsBotRuntime.unreadController.stream;

  /// Fetches the unread count now. Returns 0 if the user never chatted.
  /// Never throws.
  static Future<int> refreshUnread() async {
    final client = await _clientOrReport();
    if (client == null) return LetsBotRuntime.unread.value;
    return client.refreshUnread();
  }

  // ---- context & appearance ---------------------------------------------

  /// Tells the team and the AI what the user is looking at, e.g.
  /// `{'screen': 'order_details', 'orderId': '1234'}`. Values must be
  /// JSON-encodable. Replaces the previous context.
  static void setContext(Map<String, Object?> context) {
    final client = LetsBotRuntime.client;
    if (client == null) {
      _pendingContext = Map<String, Object?>.of(context);
    } else {
      client.setContext(context);
    }
  }

  /// Changes the chat language (`ar`, `en`, `es`, `pt`, ...). `null` follows
  /// the app's locale. An open chat reloads in the new language.
  static void setLocale(String? locale) {
    final client = LetsBotRuntime.client;
    if (client == null) {
      _pendingLocale = locale;
      _hasPendingLocale = true;
    } else {
      client.locale.value = locale;
    }
  }

  /// Changes the chat colour scheme.
  static void setTheme(LetsBotTheme theme) {
    final client = LetsBotRuntime.client;
    if (client == null) {
      _pendingTheme = theme;
    } else {
      client.theme.value = theme;
    }
  }

  // ---- callbacks ---------------------------------------------------------

  /// Called when the chat becomes visible.
  static VoidCallback? get onOpen => LetsBotRuntime.onOpen;
  static set onOpen(VoidCallback? callback) => LetsBotRuntime.onOpen = callback;

  /// Called when the chat is closed.
  static VoidCallback? get onClose => LetsBotRuntime.onClose;
  static set onClose(VoidCallback? callback) =>
      LetsBotRuntime.onClose = callback;

  /// Called with the text of each team/AI message received while the chat
  /// is open. Do not log it.
  static void Function(String text)? get onMessage => LetsBotRuntime.onMessage;
  static set onMessage(void Function(String text)? callback) =>
      LetsBotRuntime.onMessage = callback;

  /// Called whenever the unread count changes.
  static void Function(int count)? get onUnreadChanged =>
      LetsBotRuntime.onUnreadChanged;
  static set onUnreadChanged(void Function(int count)? callback) =>
      LetsBotRuntime.onUnreadChanged = callback;

  /// Called for errors that are not thrown to a caller: background
  /// refreshes, push registration, logout, and the chat screen itself.
  static void Function(LetsBotException error)? get onError =>
      LetsBotRuntime.onError;
  static set onError(void Function(LetsBotException error)? callback) =>
      LetsBotRuntime.onError = callback;

  // ---- internals ---------------------------------------------------------

  static Future<LetsBotClient?> _clientOrReport() async {
    try {
      return await LetsBotRuntime.requireClient();
    } on LetsBotException catch (e) {
      LetsBotRuntime.reportError(e);
      return null;
    }
  }

  /// Resets all SDK state. For tests only.
  @visibleForTesting
  static void resetForTesting() {
    hide();
    _observer?.detach();
    _observer = null;
    final client = LetsBotRuntime.client;
    final listener = _unreadListener;
    if (client != null && listener != null) {
      client.unread.removeListener(listener);
    }
    client?.dispose();
    _unreadListener = null;
    LetsBotRuntime.client = null;
    LetsBotRuntime.ready = null;
    LetsBotRuntime.navigatorKey = null;
    LetsBotRuntime.onOpen = null;
    LetsBotRuntime.onClose = null;
    LetsBotRuntime.onMessage = null;
    LetsBotRuntime.onUnreadChanged = null;
    LetsBotRuntime.onError = null;
    LetsBotRuntime.openViews = 0;
    LetsBotRuntime.unread.value = 0;
    _pendingContext = null;
    _pendingLocale = null;
    _hasPendingLocale = false;
    _pendingTheme = null;
  }
}

class _LifecycleObserver with WidgetsBindingObserver {
  void attach() => WidgetsBinding.instance.addObserver(this);

  void detach() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final client = LetsBotRuntime.client;
    if (client != null) unawaited(client.refreshUnread());
  }
}
