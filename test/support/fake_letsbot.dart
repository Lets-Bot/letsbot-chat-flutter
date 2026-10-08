import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:letsbot_chat/letsbot_chat.dart';

const String kAppKey = 'pk_test_app';
const String kAppId = 'com.acme.app';

const LetsBotDeviceInfo kDevice = LetsBotDeviceInfo(
  appId: kAppId,
  appVersion: '2.3.0',
  platform: 'android',
  osVersion: '14',
);

/// Builds an unsigned-looking JWT with the given claims (the fake server
/// does not verify signatures; the real one does).
String makeJwt(Map<String, Object?> claims) {
  String enc(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${enc({'alg': 'HS256', 'typ': 'JWT'})}.${enc(claims)}.c2lnbmF0dXJl';
}

/// A recorded request.
class Recorded {
  Recorded(this.method, this.route, this.headers, this.body);

  final String method;
  final String route;
  final Map<String, String> headers;
  final Map<String, Object?>? body;

  String? get visitor => headers['x-lb-visitor'];
}

/// In-memory implementation of the LetsBot SDK API contract (API.md §2–§4),
/// usable through [client] (MockClient) or a real [HttpServer] via [serve].
class FakeLetsBot {
  FakeLetsBot({this.appKey = kAppKey, Set<String>? registeredAppIds})
      : registeredAppIds = registeredAppIds ?? {kAppId};

  final String appKey;
  final Set<String> registeredAppIds;

  final List<Recorded> requests = [];
  final Set<String> validTokens = {};
  final Map<String, String> identified = {};
  final Map<String, Map<String, Object?>> devices = {};
  final Map<String, int> unreadByVisitor = {};

  /// One-shot forced errors per route: route → (status, code, headers).
  final Map<String, ({int status, String code, Map<String, String> headers})>
      forcedErrors = {};

  int _counter = 0;
  bool locked = false;

  http.Client get client => MockClient(handle);

  List<Recorded> calls(String route) =>
      requests.where((r) => r.route == route).toList();

  void forceError(
    String route,
    int status,
    String code, {
    Map<String, String> headers = const {},
  }) {
    forcedErrors[route] = (status: status, code: code, headers: headers);
  }

  /// Invalidates every issued visitor token (e.g. idle > 90 days).
  void revokeAllTokens() => validTokens.clear();

  String _newToken() {
    _counter++;
    final left = 'v$_counter'.padRight(40, 'a');
    final right = 's$_counter'.padRight(43, 'b');
    final token = '$left.$right';
    validTokens.add(token);
    return token;
  }

  http.Response _json(int status, Object body) => http.Response(
        jsonEncode(body),
        status,
        headers: {
          'content-type': 'application/json',
          'cache-control': 'no-store, private',
        },
      );

  http.Response _error(int status, String code,
          [Map<String, String> headers = const {}]) =>
      http.Response(
        jsonEncode({'error': code}),
        status,
        headers: {'content-type': 'application/json', ...headers},
      );

  Future<http.Response> handle(http.Request request) async {
    final segments = request.url.pathSegments;
    // .../api/sdk/v1/{appKey}/{route}
    final i = segments.indexOf('api');
    if (i < 0 ||
        segments.length != i + 5 ||
        segments[i + 1] != 'sdk' ||
        segments[i + 2] != 'v1') {
      return _error(404, 'not_found');
    }
    final key = segments[i + 3];
    final route = segments[i + 4];
    Map<String, Object?>? body;
    if (request.body.isNotEmpty) {
      body = (jsonDecode(request.body) as Map).cast<String, Object?>();
    }
    requests.add(Recorded(request.method, route, request.headers, body));

    if (key != appKey || locked) return _error(404, 'not_found');
    final h = request.headers;
    if (h['accept'] != 'application/json' ||
        h['x-lb-sdk'] != 'flutter/$letsBotSdkVersion' ||
        !(h['x-lb-platform'] == 'ios' || h['x-lb-platform'] == 'android') ||
        !registeredAppIds.contains(h['x-lb-app-id'])) {
      return _error(403, 'app_not_registered');
    }
    if (body != null &&
        h['content-type']?.startsWith('application/json') != true) {
      return _error(422, 'invalid');
    }
    final forced = forcedErrors.remove(route);
    if (forced != null) {
      return _error(forced.status, forced.code, forced.headers);
    }

    final visitor = h['x-lb-visitor'];
    final visitorValid = visitor != null && validTokens.contains(visitor);

    switch ((request.method, route)) {
      case ('GET', 'config'):
        return _json(200, {
          'title': 'Acme Support',
          'color': '#0e7c66',
          'logo': null,
          'theme': 'auto',
          'locale': 'auto',
          'welcome': 'Hi!',
          'offline': false,
          'away': '',
          'reply': 'Usually replies in a few minutes',
          'brand': 'https://letsbot.net/?utm_source=app_chat',
          'push': {'configured': true},
          'identity': {'required': false},
        });
      case ('POST', 'session'):
        return _json(200, {'token': visitorValid ? visitor : _newToken()});
    }

    if (!visitorValid) return _error(401, 'invalid_visitor');

    switch ((request.method, route)) {
      case ('POST', 'identify'):
        final token = body?['identity_token'];
        if (token is! String) return _error(401, 'identity_invalid');
        final parts = token.split('.');
        if (parts.length != 3) return _error(401, 'identity_invalid');
        final claims = (jsonDecode(utf8.decode(
                base64Url.decode(base64Url.normalize(parts[1])))) as Map)
            .cast<String, Object?>();
        final exp = claims['exp'];
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        if (exp is! int || exp + 60 < now) {
          return _error(401, 'identity_expired');
        }
        identified[visitor] = claims['sub']! as String;
        return _json(200, {'verified': true});
      case ('POST', 'logout'):
        devices.removeWhere((_, d) => d['visitor'] == visitor);
        return _json(200, {'ok': true});
      case ('PUT', 'device'):
        final token = body!['token']! as String;
        devices[token] = {...body, 'visitor': visitor};
        return _json(200, {'ok': true});
      case ('DELETE', 'device'):
        devices.remove(body?['token']);
        return _json(200, {'ok': true});
      case ('GET', 'unread'):
        return _json(200, {
          'count': unreadByVisitor[visitor] ?? 0,
          'last': null,
        });
    }
    return _error(404, 'not_found');
  }

  /// Serves this fake over real HTTP on 127.0.0.1. Returns the server.
  Future<HttpServer> serve() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((io) async {
      final bytes = await io.fold<List<int>>(<int>[], (a, b) => a..addAll(b));
      final request = http.Request(io.method, io.requestedUri);
      io.headers.forEach((name, values) {
        request.headers[name] = values.join(',');
      });
      if (bytes.isNotEmpty) request.bodyBytes = bytes;
      final response = await handle(request);
      io.response.statusCode = response.statusCode;
      response.headers.forEach(io.response.headers.set);
      io.response.add(response.bodyBytes);
      await io.response.close();
    });
    return server;
  }
}
