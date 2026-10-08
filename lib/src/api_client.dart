import 'dart:async';
import 'dart:convert';
import 'dart:io' show HttpDate;

import 'package:http/http.dart' as http;

import 'device_info.dart';
import 'errors.dart';
import 'options.dart';
import 'version.dart';

/// Low-level client for `{baseUrl}/api/sdk/v1/{appKey}`.
///
/// Internal: apps use the `LetsBot` facade. Every method throws
/// [LetsBotException]; nothing here logs tokens or message text.
class LetsBotApi {
  /// Creates the client. When [httpClient] is given the caller owns it.
  LetsBotApi({
    required Uri baseUrl,
    required this.appKey,
    required this.device,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 20),
  })  : baseUrl = normalizeBaseUrl(baseUrl),
        _http = httpClient ?? http.Client(),
        _ownsClient = httpClient == null;

  /// Origin (and optional path prefix) of the LetsBot server.
  final Uri baseUrl;

  /// Public App Key.
  final String appKey;

  /// Host app / device identity.
  final LetsBotDeviceInfo device;

  /// Per-request timeout.
  final Duration timeout;

  final http.Client _http;
  final bool _ownsClient;

  /// Strips query, fragment and trailing slashes from a base URL.
  static Uri normalizeBaseUrl(Uri uri) {
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    return Uri(
      scheme: uri.scheme,
      userInfo: uri.userInfo.isEmpty ? null : uri.userInfo,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
      pathSegments: segments.isEmpty ? null : segments,
    );
  }

  /// Full URL of [route] (e.g. `session`), with optional [query].
  Uri endpoint(String route, [Map<String, String>? query]) {
    return Uri(
      scheme: baseUrl.scheme,
      host: baseUrl.host,
      port: baseUrl.hasPort ? baseUrl.port : null,
      pathSegments: [
        ...baseUrl.pathSegments,
        'api',
        'sdk',
        'v1',
        appKey,
        route,
      ],
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  /// URL of the hosted chat screen (`GET ui`).
  Uri uiUri({required String locale, required String theme}) =>
      endpoint('ui', {'l': locale, 'theme': theme, 'p': device.platform});

  /// Headers shared by every request.
  Map<String, String> headers({String? visitor, bool json = false}) => {
        'Accept': 'application/json',
        'X-LB-App-Id': device.appId,
        'X-LB-Platform': device.platform,
        'X-LB-SDK': letsBotSdkHeader,
        if (json) 'Content-Type': 'application/json',
        if (visitor != null) 'X-LB-Visitor': visitor,
      };

  /// `GET config` — public widget configuration.
  Future<Map<String, Object?>> config() => _send('GET', 'config');

  /// `POST session` — returns a visitor token. With [visitor] the server
  /// echoes the same visitor when that token is still valid.
  Future<String> session({
    String? visitor,
    String? locale,
    Map<String, Object?>? context,
  }) async {
    final body = <String, Object?>{
      if (locale != null) 'locale': locale,
      'device': device.toJson(),
      if (context != null && context.isNotEmpty) 'ctx': context,
    };
    final res = await _send('POST', 'session', visitor: visitor, body: body);
    final token = res['token'];
    if (token is! String || token.isEmpty) {
      throw LetsBotException(
        LetsBotErrorCode.invalidResponse,
        message: 'session response has no token',
      );
    }
    return token;
  }

  /// `POST identify` with a JWT [identityToken]. Returns the `verified`
  /// flag. (The legacy `user_id` + `user_hash` form is intentionally not
  /// exposed by this SDK.)
  Future<bool> identify(
    String visitor, {
    required String identityToken,
    String? name,
    String? email,
    String? phone,
  }) async {
    final body = <String, Object?>{
      'identity_token': identityToken,
      if (name != null) 'name': name,
      if (email != null) 'email': email,
      if (phone != null) 'phone': phone,
    };
    final res = await _send('POST', 'identify', visitor: visitor, body: body);
    return res['verified'] == true;
  }

  /// `POST logout` — removes this visitor's push devices.
  Future<void> logout(String visitor) async {
    await _send('POST', 'logout', visitor: visitor, body: const {});
  }

  /// `PUT device` — registers / moves a push token to this visitor.
  Future<void> putDevice(
    String visitor, {
    required String token,
    required LetsBotPushProvider provider,
    required bool sandbox,
    String? locale,
  }) async {
    await _send('PUT', 'device', visitor: visitor, body: {
      'provider': provider.name,
      'token': token,
      'platform': device.platform,
      'app_id': device.appId,
      'app_version': device.appVersion,
      'sdk': letsBotSdkHeader,
      if (locale != null) 'locale': locale,
      'sandbox': sandbox,
    });
  }

  /// `DELETE device` — unregisters a push token.
  Future<void> deleteDevice(String visitor, String token) async {
    await _send('DELETE', 'device', visitor: visitor, body: {'token': token});
  }

  /// `GET unread` — unread team/AI messages for the badge.
  Future<int> unread(String visitor) async {
    final res = await _send('GET', 'unread', visitor: visitor);
    final count = res['count'];
    if (count is num && count >= 0) return count.toInt();
    throw LetsBotException(
      LetsBotErrorCode.invalidResponse,
      message: 'unread response has no count',
    );
  }

  /// Releases the underlying HTTP client if this instance created it.
  void close() {
    if (_ownsClient) _http.close();
  }

  Future<Map<String, Object?>> _send(
    String method,
    String route, {
    String? visitor,
    Object? body,
    Map<String, String>? query,
  }) async {
    final request = http.Request(method, endpoint(route, query))
      ..headers.addAll(headers(visitor: visitor, json: body != null))
      ..followRedirects = false;
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      final streamed = await _http.send(request).timeout(timeout);
      response = await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw LetsBotException(
        LetsBotErrorCode.network,
        message: '$method $route timed out',
      );
    } on LetsBotException {
      rethrow;
    } catch (e) {
      throw LetsBotException(
        LetsBotErrorCode.network,
        message: '$method $route failed: ${e.runtimeType}',
      );
    }

    final status = response.statusCode;
    final decoded = _decode(response);
    if (status >= 200 && status < 300) {
      if (decoded == null && response.bodyBytes.isNotEmpty) {
        throw LetsBotException(
          LetsBotErrorCode.invalidResponse,
          statusCode: status,
          message: '$method $route returned a non-JSON body',
        );
      }
      return decoded ?? const {};
    }
    throw _errorFor(status, decoded, response.headers['retry-after']);
  }

  static Map<String, Object?>? _decode(http.Response response) {
    if (response.bodyBytes.isEmpty) return null;
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map<String, Object?>) return value;
      if (value is Map) return value.cast<String, Object?>();
    } catch (_) {
      // Not JSON.
    }
    return null;
  }

  static LetsBotException _errorFor(
    int status,
    Map<String, Object?>? body,
    String? retryAfterHeader,
  ) {
    final retryAfter = parseRetryAfter(retryAfterHeader);
    final code = body?['error'];
    if (code is String && code.isNotEmpty) {
      return LetsBotException.fromWire(
        code,
        statusCode: status,
        retryAfter: retryAfter,
      );
    }
    final fallback = switch (status) {
      404 => LetsBotErrorCode.notFound,
      429 => LetsBotErrorCode.slowDown,
      >= 500 => LetsBotErrorCode.server,
      _ => LetsBotErrorCode.unknown,
    };
    return LetsBotException(
      fallback,
      rawCode: fallback == LetsBotErrorCode.unknown ? 'http_$status' : null,
      statusCode: status,
      retryAfter: retryAfter,
    );
  }

  /// Parses a `Retry-After` header given in seconds or as an HTTP date.
  static Duration? parseRetryAfter(String? value, {DateTime? now}) {
    if (value == null || value.trim().isEmpty) return null;
    final seconds = int.tryParse(value.trim());
    if (seconds != null) return seconds < 0 ? null : Duration(seconds: seconds);
    try {
      final date = HttpDate.parse(value.trim());
      final diff = date.difference(now ?? DateTime.now().toUtc());
      return diff.isNegative ? Duration.zero : diff;
    } catch (_) {
      return null;
    }
  }
}
