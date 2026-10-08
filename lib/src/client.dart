import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_client.dart';
import 'device_info.dart';
import 'errors.dart';
import 'jwt.dart';
import 'options.dart';
import 'token_store.dart';
import 'version.dart';

/// Core of the SDK: session lifecycle, identity, push token, unread count and
/// chat context. Pure Dart (no widgets), so it is fully unit-testable.
///
/// Apps normally use the static `LetsBot` facade, which owns one instance.
///
/// Error policy: [identify] throws [LetsBotException] (the app must react to
/// `identity_expired`). Fire-and-forget calls ([setPushToken], [logout],
/// [refreshUnread]) never throw; failures go to [onError].
class LetsBotClient {
  /// Creates a client for [appKey].
  LetsBotClient({
    required this.appKey,
    required Uri baseUrl,
    required this.device,
    LetsBotTokenStore? tokenStore,
    http.Client? httpClient,
    String? locale,
    LetsBotTheme theme = LetsBotTheme.auto,
    this.color,
  })  : store = tokenStore ?? const SecureLetsBotTokenStore(),
        api = LetsBotApi(
          baseUrl: baseUrl,
          appKey: appKey,
          device: device,
          httpClient: httpClient,
        ),
        locale = ValueNotifier<String?>(locale),
        theme = ValueNotifier<LetsBotTheme>(theme);

  /// Public App Key.
  final String appKey;

  /// Host app / device identity.
  final LetsBotDeviceInfo device;

  /// Where the visitor token lives.
  final LetsBotTokenStore store;

  /// HTTP API client.
  final LetsBotApi api;

  /// Optional brand colour (`#rrggbb`) overriding the panel colour.
  final String? color;

  /// Chat language (`ar`, `en`, `es`, `pt`, ...); `null` = device language.
  final ValueNotifier<String?> locale;

  /// Chat colour scheme.
  final ValueNotifier<LetsBotTheme> theme;

  /// Context shown to the team and the AI (e.g. `{"screen": "order"}`).
  final ValueNotifier<Map<String, Object?>> context =
      ValueNotifier<Map<String, Object?>>(const {});

  /// Unread team/AI messages.
  final ValueNotifier<int> unread = ValueNotifier<int>(0);

  /// Called for errors of background work (never with secrets).
  void Function(LetsBotException error)? onError;

  String? _token;
  bool _loaded = false;
  bool _touched = false;
  Future<String>? _sessionInFlight;

  _Identity? _identity;
  String? _identifiedFor;

  _PushToken? _push;
  String? _pushRegisteredFor;

  bool _disposed = false;

  /// Storage key of the visitor token (one per server + App Key).
  String get storageKey => 'letsbot_chat.visitor.${api.baseUrl.host}.$appKey';

  /// Locale sent to the server: the configured one, else [deviceLocale].
  String effectiveLocale(String deviceLocale) {
    final value = locale.value;
    return (value == null || value.isEmpty) ? deviceLocale : value;
  }

  /// Whether a visitor token is stored (no network).
  Future<bool> hasSession() async => (await _loadToken()) != null;

  /// Returns a valid visitor token, creating or refreshing the session once
  /// per process. Concurrent callers share one request.
  Future<String> ensureSession() {
    return _sessionInFlight ??=
        _ensureSession().whenComplete(() => _sessionInFlight = null);
  }

  Future<String> _ensureSession() async {
    final existing = await _loadToken();
    if (existing != null && _touched) return existing;

    final ctx = context.value;
    String token;
    try {
      token = await api.session(
        visitor: existing,
        locale: locale.value,
        context: ctx,
      );
    } on LetsBotException catch (e) {
      if (existing == null || e.code != LetsBotErrorCode.invalidVisitor) {
        rethrow;
      }
      await _clearToken();
      token = await api.session(locale: locale.value, context: ctx);
    }
    _touched = true;
    if (token != existing) await _saveToken(token);
    await _afterSession(token);
    return token;
  }

  /// Discards the current visitor token and creates a new session (used when
  /// the hosted page reports `token_invalid`).
  Future<String> renewSession() async {
    await _clearToken();
    return ensureSession();
  }

  Future<void> _afterSession(String token) async {
    final identity = _identity;
    if (identity != null && _identifiedFor != token) {
      try {
        await identity.send(api, token);
        _identifiedFor = token;
      } on LetsBotException catch (e) {
        _report(e);
      }
    }
    final push = _push;
    if (push != null && _pushRegisteredFor != token) {
      try {
        await _registerPush(token, push);
      } on LetsBotException catch (e) {
        _report(e);
      }
    }
  }

  /// Runs [call] with a visitor token; on `invalid_visitor` creates a new
  /// session and retries once.
  Future<T> withVisitor<T>(Future<T> Function(String token) call) async {
    final token = await ensureSession();
    try {
      return await call(token);
    } on LetsBotException catch (e) {
      if (e.code != LetsBotErrorCode.invalidVisitor) rethrow;
      await _clearToken();
      return call(await ensureSession());
    }
  }

  /// Links this visitor to a logged-in user of the app.
  ///
  /// [identityToken] is a short-lived HS256 JWT minted by the app's backend
  /// with the LetsBot Identity Secret; its `sub` claim must equal [userId].
  /// Throws [LetsBotException] (`identity_invalid`, `identity_expired`,
  /// network errors, ...).
  Future<bool> identify({
    required String userId,
    required String identityToken,
    String? name,
    String? email,
    String? phone,
  }) async {
    final jwt = identityToken.trim();
    if (userId.isEmpty) {
      throw LetsBotException(
        LetsBotErrorCode.invalid,
        message: 'userId must not be empty',
      );
    }
    final sub = jwtSubject(jwt);
    if (sub == null) {
      throw LetsBotException(
        LetsBotErrorCode.identityInvalid,
        message: 'identityToken is not a JWT',
      );
    }
    if (sub != userId) {
      throw LetsBotException(
        LetsBotErrorCode.identityInvalid,
        message: 'identityToken sub does not match userId',
      );
    }
    final identity = _Identity(
      identityToken: jwt,
      name: name,
      email: email,
      phone: phone,
    );
    final verified = await withVisitor((token) async {
      final ok = await identity.send(api, token);
      _identifiedFor = token;
      return ok;
    });
    _identity = identity;
    return verified;
  }

  /// Forgets the user on this device: unregisters push devices on the
  /// server, deletes the stored visitor token and resets the unread count.
  /// The next chat starts a fresh anonymous session. Never throws.
  Future<void> logout() async {
    _identity = null;
    _identifiedFor = null;
    final token = await _loadToken();
    if (token != null) {
      try {
        await api.logout(token);
      } on LetsBotException catch (e) {
        if (e.code != LetsBotErrorCode.invalidVisitor) _report(e);
      }
    }
    await _clearToken();
    _setUnread(0);
  }

  /// Registers the push token for LetsBot replies.
  ///
  /// Sessions stay lazy: if this device has never opened the chat, the token
  /// is kept and registered right after the first session. Never throws.
  Future<void> setPushToken(
    String token, {
    LetsBotPushProvider provider = LetsBotPushProvider.fcm,
    bool? sandbox,
  }) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) return;
    final push = _PushToken(
      token: trimmed,
      provider: provider,
      sandbox:
          sandbox ?? (provider == LetsBotPushProvider.apns && !kReleaseMode),
    );
    final changed = _push != push;
    _push = push;
    if (changed) _pushRegisteredFor = null;
    if (await _loadToken() == null) return;
    try {
      final visitor = await ensureSession();
      if (_pushRegisteredFor != visitor) {
        await withVisitor((t) => _registerPush(t, push));
      }
    } on LetsBotException catch (e) {
      _report(e);
    }
  }

  Future<void> _registerPush(String visitor, _PushToken push) async {
    await api.putDevice(
      visitor,
      token: push.token,
      provider: push.provider,
      sandbox: push.sandbox,
      locale: locale.value,
    );
    _pushRegisteredFor = visitor;
  }

  /// Fetches the unread count. Does not create a session: without one the
  /// count is 0. Never throws; returns the last known count on failure.
  Future<int> refreshUnread() async {
    final token = await _loadToken();
    if (token == null) {
      _setUnread(0);
      return 0;
    }
    try {
      final count = await api.unread(token);
      _setUnread(count);
      return count;
    } on LetsBotException catch (e) {
      if (e.code == LetsBotErrorCode.invalidVisitor) {
        await _clearToken();
        _setUnread(0);
        return 0;
      }
      _report(e);
      return unread.value;
    }
  }

  /// Updates the unread count (e.g. from the hosted page).
  void setUnreadFromPage(int count) => _setUnread(count);

  /// Replaces the chat context.
  void setContext(Map<String, Object?> value) {
    context.value = Map<String, Object?>.unmodifiable(value);
  }

  /// Payload for `LetsBotHost.boot(...)`.
  Map<String, Object?> bootPayload(String token) => {
        'token': token,
        'appId': device.appId,
        'platform': device.platform,
        'sdk': letsBotSdkHeader,
        'context': context.value,
        if (color != null) 'color': color,
      };

  void _setUnread(int count) {
    if (_disposed) return;
    unread.value = count < 0 ? 0 : count;
  }

  void _report(LetsBotException error) {
    final handler = onError;
    if (handler == null) return;
    try {
      handler(error);
    } catch (_) {
      // A throwing app callback must not break the SDK.
    }
  }

  Future<String?> _loadToken() async {
    if (_loaded) return _token;
    final stored = await store.read(storageKey);
    if (!_loaded) {
      _token = (stored == null || stored.isEmpty) ? null : stored;
      _loaded = true;
    }
    return _token;
  }

  Future<void> _saveToken(String token) async {
    _token = token;
    _loaded = true;
    await store.write(storageKey, token);
  }

  Future<void> _clearToken() async {
    _token = null;
    _loaded = true;
    _touched = false;
    _identifiedFor = null;
    _pushRegisteredFor = null;
    await store.delete(storageKey);
  }

  /// Releases resources.
  void dispose() {
    _disposed = true;
    api.close();
    locale.dispose();
    theme.dispose();
    context.dispose();
    unread.dispose();
  }
}

@immutable
class _Identity {
  const _Identity({
    required this.identityToken,
    this.name,
    this.email,
    this.phone,
  });

  final String identityToken;
  final String? name;
  final String? email;
  final String? phone;

  Future<bool> send(LetsBotApi api, String visitor) => api.identify(
        visitor,
        identityToken: identityToken,
        name: name,
        email: email,
        phone: phone,
      );
}

@immutable
class _PushToken {
  const _PushToken({
    required this.token,
    required this.provider,
    required this.sandbox,
  });

  final String token;
  final LetsBotPushProvider provider;
  final bool sandbox;

  @override
  bool operator ==(Object other) =>
      other is _PushToken &&
      other.token == token &&
      other.provider == provider &&
      other.sandbox == sandbox;

  @override
  int get hashCode => Object.hash(token, provider, sandbox);
}
