import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:letsbot_chat/letsbot_chat.dart';
import 'package:letsbot_chat/src/api_client.dart';

import 'support/fake_letsbot.dart';

LetsBotApi apiFor(http.Client client, {String base = 'https://letsbot.net'}) =>
    LetsBotApi(
      baseUrl: Uri.parse(base),
      appKey: kAppKey,
      device: kDevice,
      httpClient: client,
    );

void main() {
  group('endpoint', () {
    test('builds /api/sdk/v1/{appKey}/{route}', () {
      final api = apiFor(MockClient((_) async => http.Response('', 200)));
      expect(
        api.endpoint('session').toString(),
        'https://letsbot.net/api/sdk/v1/pk_test_app/session',
      );
    });

    test('keeps a base path and drops trailing slash, query and fragment', () {
      final api = apiFor(
        MockClient((_) async => http.Response('', 200)),
        base: 'http://localhost:8080/staging/?x=1#f',
      );
      expect(
        api.endpoint('unread').toString(),
        'http://localhost:8080/staging/api/sdk/v1/pk_test_app/unread',
      );
    });

    test('ui URL carries locale, theme and platform', () {
      final api = apiFor(MockClient((_) async => http.Response('', 200)));
      final ui = api.uiUri(locale: 'ar', theme: 'dark');
      expect(ui.path, '/api/sdk/v1/pk_test_app/ui');
      expect(ui.queryParameters, {'l': 'ar', 'theme': 'dark', 'p': 'android'});
    });
  });

  group('requests', () {
    test('session sends required headers and device body, no visitor',
        () async {
      final fake = FakeLetsBot();
      final api = apiFor(fake.client);
      final token =
          await api.session(locale: 'en', context: {'screen': 'home'});
      expect(token, isNotEmpty);
      final call = fake.calls('session').single;
      expect(call.method, 'POST');
      expect(call.headers['X-LB-App-Id'], kAppId);
      expect(call.headers['X-LB-Platform'], 'android');
      expect(call.headers['X-LB-SDK'], 'flutter/0.2.0');
      expect(call.headers['Accept'], 'application/json');
      expect(call.headers['Content-Type'], startsWith('application/json'));
      expect(call.visitor, isNull);
      expect(call.body, {
        'locale': 'en',
        'device': {
          'platform': 'android',
          'app_id': kAppId,
          'app_version': '2.3.0',
          'sdk': 'flutter/0.2.0',
          'os_version': '14',
        },
        'ctx': {'screen': 'home'},
      });
    });

    test('session echoes a valid visitor token', () async {
      final fake = FakeLetsBot();
      final api = apiFor(fake.client);
      final first = await api.session();
      final second = await api.session(visitor: first);
      expect(second, first);
      expect(fake.calls('session').last.visitor, first);
    });

    test('device, unread, logout and config follow the contract', () async {
      final fake = FakeLetsBot();
      final api = apiFor(fake.client);
      final visitor = await api.session();
      await api.putDevice(
        visitor,
        token: 'fcm-1',
        provider: LetsBotPushProvider.fcm,
        sandbox: false,
        locale: 'ar',
      );
      expect(fake.devices['fcm-1'], {
        'provider': 'fcm',
        'token': 'fcm-1',
        'platform': 'android',
        'app_id': kAppId,
        'app_version': '2.3.0',
        'sdk': 'flutter/0.2.0',
        'locale': 'ar',
        'sandbox': false,
        'visitor': visitor,
      });
      fake.unreadByVisitor[visitor] = 3;
      expect(await api.unread(visitor), 3);
      await api.logout(visitor);
      expect(fake.devices, isEmpty);
      await api.putDevice(visitor,
          token: 'fcm-2', provider: LetsBotPushProvider.fcm, sandbox: false);
      await api.deleteDevice(visitor, 'fcm-2');
      expect(fake.devices, isEmpty);
      expect((await api.config())['title'], 'Acme Support');
      expect(fake.calls('config').single.visitor, isNull);
    });
  });

  group('errors', () {
    final cases = <(int, String, LetsBotErrorCode)>[
      (404, 'not_found', LetsBotErrorCode.notFound),
      (403, 'app_not_registered', LetsBotErrorCode.appNotRegistered),
      (401, 'invalid_visitor', LetsBotErrorCode.invalidVisitor),
      (401, 'identity_invalid', LetsBotErrorCode.identityInvalid),
      (401, 'identity_expired', LetsBotErrorCode.identityExpired),
      (403, 'blocked', LetsBotErrorCode.blocked),
      (422, 'invalid', LetsBotErrorCode.invalid),
      (422, 'too_long', LetsBotErrorCode.tooLong),
      (422, 'invalid_contact', LetsBotErrorCode.invalidContact),
      (422, 'consent_required', LetsBotErrorCode.consentRequired),
      (422, 'file_too_big', LetsBotErrorCode.fileTooBig),
      (422, 'file_type', LetsBotErrorCode.fileType),
      (429, 'slow_down', LetsBotErrorCode.slowDown),
      (429, 'busy', LetsBotErrorCode.busy),
      (400, 'something_new', LetsBotErrorCode.unknown),
    ];
    for (final (status, code, expected) in cases) {
      test('$status $code → $expected', () async {
        final api = apiFor(MockClient(
            (_) async => http.Response(jsonEncode({'error': code}), status)));
        await expectLater(
          api.session(),
          throwsA(isA<LetsBotException>()
              .having((e) => e.code, 'code', expected)
              .having((e) => e.rawCode, 'rawCode', code)
              .having((e) => e.statusCode, 'statusCode', status)),
        );
      });
    }

    test('honours Retry-After seconds', () async {
      final api = apiFor(MockClient((_) async => http.Response(
            '{"error":"slow_down"}',
            429,
            headers: {'retry-after': '30'},
          )));
      await expectLater(
        api.session(),
        throwsA(isA<LetsBotException>()
            .having(
                (e) => e.retryAfter, 'retryAfter', const Duration(seconds: 30))
            .having((e) => e.isRetryable, 'isRetryable', true)),
      );
    });

    test('parses Retry-After HTTP dates', () {
      final now = DateTime.utc(2026, 10, 8, 12);
      expect(
        LetsBotApi.parseRetryAfter('Thu, 08 Oct 2026 12:00:10 GMT', now: now),
        const Duration(seconds: 10),
      );
      expect(LetsBotApi.parseRetryAfter('nonsense'), isNull);
      expect(LetsBotApi.parseRetryAfter(null), isNull);
    });

    test('non-JSON 5xx maps to server_error', () async {
      final api = apiFor(MockClient(
          (_) async => http.Response('<html>Bad gateway</html>', 502)));
      await expectLater(
        api.session(),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.server)),
      );
    });

    test('bodiless 404 maps to not_found', () async {
      final api = apiFor(MockClient((_) async => http.Response('', 404)));
      await expectLater(
        api.unread('t'),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.notFound)),
      );
    });

    test('client exceptions map to network_error', () async {
      final api = apiFor(
          MockClient((_) async => throw http.ClientException('offline')));
      await expectLater(
        api.session(),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.network)),
      );
    });

    test('timeouts map to network_error', () async {
      final api = LetsBotApi(
        baseUrl: Uri.parse('https://letsbot.net'),
        appKey: kAppKey,
        device: kDevice,
        timeout: const Duration(milliseconds: 20),
        httpClient: MockClient((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        api.session(),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.network)),
      );
    });

    test('2xx without a token is invalid_response', () async {
      final api = apiFor(MockClient((_) async => http.Response('{}', 200)));
      await expectLater(
        api.session(),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.invalidResponse)),
      );
    });

    test('exception text never contains the visitor token', () async {
      const secret = 'SECRET-TOKEN-VALUE';
      final api =
          apiFor(MockClient((_) async => throw http.ClientException(secret)));
      try {
        await api.unread(secret);
        fail('expected an exception');
      } on LetsBotException catch (e) {
        expect(e.toString(), isNot(contains(secret)));
      }
    });
  });
}
