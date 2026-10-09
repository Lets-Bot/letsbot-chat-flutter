import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsbot_chat/letsbot_chat.dart';
import 'package:letsbot_chat/src/client.dart';

import 'support/fake_letsbot.dart';

/// End-to-end over real HTTP: the default `http.Client` against a local
/// server implementing the API contract.
void main() {
  late HttpServer server;
  late FakeLetsBot fake;

  setUp(() async {
    fake = FakeLetsBot();
    server = await fake.serve();
  });

  tearDown(() => server.close(force: true));

  test('full lifecycle over a real socket', () async {
    final store = MemoryLetsBotTokenStore();
    final client = LetsBotClient(
      appKey: kAppKey,
      baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
      device: kDevice,
      tokenStore: store,
      locale: 'pt',
    );
    addTearDown(client.dispose);

    expect(await client.refreshUnread(), 0);
    expect(fake.requests, isEmpty);

    await client.setPushToken('fcm-xyz');
    final visitor = await client.ensureSession();
    expect(fake.devices['fcm-xyz']?['visitor'], visitor);
    expect(fake.calls('session').single.headers['x-lb-sdk'], 'flutter/0.2.0');

    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final ok = await client.identify(
      userId: 'user-7',
      identityToken: makeJwt({'sub': 'user-7', 'iat': now, 'exp': now + 600}),
      name: 'Ana',
    );
    expect(ok, isTrue);
    expect(fake.identified[visitor], 'user-7');

    fake.unreadByVisitor[visitor] = 4;
    expect(await client.refreshUnread(), 4);

    fake.forceError('unread', 429, 'slow_down', headers: {'retry-after': '7'});
    final errors = <LetsBotException>[];
    client.onError = errors.add;
    await client.refreshUnread();
    expect(errors.single.code, LetsBotErrorCode.slowDown);
    expect(errors.single.retryAfter, const Duration(seconds: 7));

    await client.logout();
    expect(fake.devices, isEmpty);
    expect(store.values, isEmpty);
  });

  test('wrong App Key → not_found', () async {
    final client = LetsBotClient(
      appKey: 'pk_unknown',
      baseUrl: Uri.parse('http://${server.address.host}:${server.port}'),
      device: kDevice,
      tokenStore: MemoryLetsBotTokenStore(),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.ensureSession(),
      throwsA(isA<LetsBotException>()
          .having((e) => e.code, 'code', LetsBotErrorCode.notFound)),
    );
  });

  test('server down → network_error', () async {
    final port = server.port;
    await server.close(force: true);
    final client = LetsBotClient(
      appKey: kAppKey,
      baseUrl: Uri.parse('http://127.0.0.1:$port'),
      device: kDevice,
      tokenStore: MemoryLetsBotTokenStore(),
    );
    addTearDown(client.dispose);
    await expectLater(
      client.ensureSession(),
      throwsA(isA<LetsBotException>()
          .having((e) => e.code, 'code', LetsBotErrorCode.network)),
    );
  });
}
