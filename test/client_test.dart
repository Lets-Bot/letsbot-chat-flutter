import 'package:flutter_test/flutter_test.dart';
import 'package:letsbot_chat/letsbot_chat.dart';
import 'package:letsbot_chat/src/client.dart';

import 'support/fake_letsbot.dart';

int _now() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

String validJwt(String sub) =>
    makeJwt({'sub': sub, 'iat': _now(), 'exp': _now() + 3600});

void main() {
  late FakeLetsBot fake;
  late MemoryLetsBotTokenStore store;
  late LetsBotClient client;
  late List<LetsBotException> errors;

  LetsBotClient newClient() => LetsBotClient(
        appKey: kAppKey,
        baseUrl: Uri.parse('https://letsbot.net'),
        device: kDevice,
        tokenStore: store,
        httpClient: fake.client,
        locale: 'en',
      )..onError = errors.add;

  setUp(() {
    fake = FakeLetsBot();
    store = MemoryLetsBotTokenStore();
    errors = [];
    client = newClient();
  });

  group('session lifecycle', () {
    test('is lazy: unread without a session makes no request', () async {
      expect(await client.refreshUnread(), 0);
      expect(fake.requests, isEmpty);
      expect(await client.hasSession(), isFalse);
    });

    test('creates once, stores the token, shares concurrent calls', () async {
      final results = await Future.wait([
        client.ensureSession(),
        client.ensureSession(),
        client.ensureSession(),
      ]);
      expect(results.toSet().length, 1);
      expect(fake.calls('session'), hasLength(1));
      expect(store.values[client.storageKey], results.first);
      await client.ensureSession();
      expect(fake.calls('session'), hasLength(1));
    });

    test('sends locale and context when the session is created', () async {
      client.setContext({'screen': 'order_details', 'order_id': '1234'});
      await client.ensureSession();
      final body = fake.calls('session').single.body!;
      expect(body['locale'], 'en');
      expect(body['ctx'], {'screen': 'order_details', 'order_id': '1234'});
    });

    test('a stored token is echoed once per process', () async {
      final token = await client.ensureSession();
      final second = newClient();
      expect(await second.ensureSession(), token);
      expect(fake.calls('session').last.visitor, token);
      await second.ensureSession();
      expect(fake.calls('session'), hasLength(2));
    });

    test('a stored token the server rejects is replaced', () async {
      store.values[client.storageKey] = 'stale.token';
      fake.forceError('session', 401, 'invalid_visitor');
      final token = await client.ensureSession();
      expect(token, isNot('stale.token'));
      expect(store.values[client.storageKey], token);
    });

    test('invalid_visitor on a call re-sessions and retries once', () async {
      final first = await client.ensureSession();
      fake.revokeAllTokens();
      final verified = await client.identify(
        userId: 'user-1',
        identityToken: validJwt('user-1'),
      );
      expect(verified, isTrue);
      final current = store.values[client.storageKey];
      expect(current, isNot(first));
      expect(fake.identified[current], 'user-1');
    });

    test('renewSession (bridge token_invalid) replaces the token', () async {
      final first = await client.ensureSession();
      final renewed = await client.renewSession();
      expect(renewed, isNot(first));
      expect(store.values[client.storageKey], renewed);
    });

    test('a 404 (locked / unknown key) surfaces as not_found', () async {
      fake.locked = true;
      await expectLater(
        client.ensureSession(),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.notFound)),
      );
    });

    test('an unregistered app id surfaces as app_not_registered', () async {
      fake.registeredAppIds.clear();
      await expectLater(
        client.ensureSession(),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.appNotRegistered)),
      );
    });
  });

  group('identify', () {
    test('sends the JWT and profile fields with the visitor', () async {
      await client.identify(
        userId: 'user-42',
        identityToken: validJwt('user-42'),
        name: 'Sara',
        email: 'sara@example.com',
        phone: '+966500000000',
      );
      final call = fake.calls('identify').single;
      expect(call.visitor, isNotNull);
      expect(call.body!['name'], 'Sara');
      expect(call.body!['email'], 'sara@example.com');
      expect(call.body!['phone'], '+966500000000');
      expect(call.body!.containsKey('user_id'), isFalse);
      expect(fake.identified[call.visitor], 'user-42');
    });

    test('rejects a token whose sub differs from userId, offline', () async {
      await expectLater(
        client.identify(userId: 'a', identityToken: validJwt('b')),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.identityInvalid)),
      );
      await expectLater(
        client.identify(userId: 'a', identityToken: 'not-a-jwt'),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.identityInvalid)),
      );
      expect(fake.requests, isEmpty);
    });

    test('identity_expired is thrown to the caller', () async {
      final expired =
          makeJwt({'sub': 'u', 'iat': _now() - 7200, 'exp': _now() - 3600});
      await expectLater(
        client.identify(userId: 'u', identityToken: expired),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.identityExpired)),
      );
    });

    test('is re-applied to a replacement visitor', () async {
      await client.identify(userId: 'u1', identityToken: validJwt('u1'));
      final renewed = await client.renewSession();
      expect(fake.identified[renewed], 'u1');
    });
  });

  group('push', () {
    test('stays pending until the first session, then registers', () async {
      await client.setPushToken('fcm-token');
      expect(fake.requests, isEmpty);
      final visitor = await client.ensureSession();
      expect(fake.devices['fcm-token']?['visitor'], visitor);
      expect(fake.devices['fcm-token']?['provider'], 'fcm');
      expect(fake.devices['fcm-token']?['sandbox'], false);
    });

    test('registers immediately when a session exists', () async {
      final visitor = await client.ensureSession();
      await client.setPushToken('abcd', provider: LetsBotPushProvider.apns);
      expect(fake.devices['abcd']?['visitor'], visitor);
      expect(fake.devices['abcd']?['provider'], 'apns');
      // Tests run in debug mode: APNs defaults to the sandbox.
      expect(fake.devices['abcd']?['sandbox'], true);
      await client.setPushToken('abcd', provider: LetsBotPushProvider.apns);
      expect(fake.calls('device'), hasLength(1));
    });

    test('failures go to onError instead of throwing', () async {
      await client.ensureSession();
      fake.forceError('device', 422, 'invalid');
      await client.setPushToken('bad');
      expect(errors.single.code, LetsBotErrorCode.invalid);
    });
  });

  group('logout', () {
    test('unregisters devices, clears the token, next chat is new', () async {
      await client.identify(userId: 'u', identityToken: validJwt('u'));
      await client.setPushToken('fcm-token');
      final before = store.values[client.storageKey];
      client.setUnreadFromPage(4);

      await client.logout();
      expect(fake.calls('logout').single.visitor, before);
      expect(store.values.containsKey(client.storageKey), isFalse);
      expect(client.unread.value, 0);

      final after = await client.ensureSession();
      expect(after, isNot(before));
      expect(fake.identified[after], isNull, reason: 'identity is forgotten');
      expect(fake.devices['fcm-token']?['visitor'], after,
          reason: 'push token moves to the new visitor');
    });

    test('never throws, even offline', () async {
      await client.ensureSession();
      fake.forceError('logout', 500, 'server_error');
      await client.logout();
      expect(store.values, isEmpty);
      expect(errors.single.code, LetsBotErrorCode.server);
    });

    test('without a session makes no request', () async {
      await client.logout();
      expect(fake.requests, isEmpty);
    });
  });

  group('unread', () {
    test('refresh updates the notifier', () async {
      final visitor = await client.ensureSession();
      fake.unreadByVisitor[visitor] = 2;
      final seen = <int>[];
      client.unread.addListener(() => seen.add(client.unread.value));
      expect(await client.refreshUnread(), 2);
      expect(seen, [2]);
    });

    test('an invalid visitor resets to 0 without a new session', () async {
      await client.ensureSession();
      fake.revokeAllTokens();
      expect(await client.refreshUnread(), 0);
      expect(fake.calls('session'), hasLength(1));
      expect(store.values, isEmpty);
    });

    test('other failures keep the last count and report', () async {
      await client.ensureSession();
      client.setUnreadFromPage(5);
      fake.forceError('unread', 429, 'slow_down');
      expect(await client.refreshUnread(), 5);
      expect(errors.single.code, LetsBotErrorCode.slowDown);
    });
  });

  test('boot payload matches the bridge contract', () async {
    final token = await client.ensureSession();
    client.setContext({'screen': 'home'});
    expect(client.bootPayload(token), {
      'token': token,
      'appId': kAppId,
      'platform': 'android',
      'sdk': 'flutter/0.1.0',
      'context': {'screen': 'home'},
    });
  });
}
