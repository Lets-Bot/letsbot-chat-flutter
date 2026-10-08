import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:letsbot_chat/letsbot_chat.dart';
import 'package:letsbot_chat/src/jwt.dart';

void main() {
  test('SDK version matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version =
        RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(pubspec)!;
    expect(letsBotSdkVersion, version.group(1));
  });

  test('error codes round-trip from the wire', () {
    for (final code in LetsBotErrorCode.values) {
      expect(LetsBotErrorCode.fromWire(code.wire), code);
    }
    expect(LetsBotErrorCode.fromWire('brand_new'), LetsBotErrorCode.unknown);
    final e = LetsBotException.fromWire('brand_new', statusCode: 418);
    expect(e.rawCode, 'brand_new');
    expect(e.toString(), 'LetsBotException(brand_new, HTTP 418)');
  });

  test('parses iOS version strings', () {
    expect(LetsBotDeviceInfo.parseIosVersion('Version 17.5 (Build 21F79)'),
        '17.5');
    expect(LetsBotDeviceInfo.parseIosVersion(null), isNull);
  });

  test('reads the JWT subject without verifying', () {
    const token =
        'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ1LTEiLCJleHAiOjF9.c2ln'; // sub=u-1
    expect(jwtSubject(token), 'u-1');
    expect(jwtSubject('a.b'), isNull);
    expect(jwtSubject('a.!!!.c'), isNull);
  });

  test('memory token store', () async {
    final store = MemoryLetsBotTokenStore();
    await store.write('k', 'v');
    expect(await store.read('k'), 'v');
    await store.delete('k');
    expect(await store.read('k'), isNull);
  });
}
