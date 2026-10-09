import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsbot_chat/letsbot_chat.dart';
import 'package:letsbot_chat/src/bridge.dart';
import 'package:letsbot_chat/src/chrome.dart';
import 'package:letsbot_chat/src/client.dart';

import 'support/fake_letsbot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LetsBotChrome', () {
    const chrome = LetsBotChrome(
      lightStatusBar: true,
      header: '#0e7c66',
      background: '#f5f7f9',
    );

    test('maps to a transparent status bar with matching icons', () {
      final style = chrome.overlayStyle;
      expect(style.statusBarColor, const Color(0x00000000));
      expect(style.statusBarIconBrightness, Brightness.light);
      expect(style.statusBarBrightness, Brightness.dark);
      expect(style.systemNavigationBarColor, const Color(0xFFF5F7F9));
      expect(style.systemNavigationBarIconBrightness, Brightness.dark);

      const darkIcons = LetsBotChrome(
        lightStatusBar: false,
        header: '#ffffff',
        background: '#111418',
      );
      expect(darkIcons.overlayStyle.statusBarIconBrightness, Brightness.dark);
      expect(darkIcons.overlayStyle.statusBarBrightness, Brightness.light);
      expect(darkIcons.overlayStyle.systemNavigationBarIconBrightness,
          Brightness.light);
    });

    test('round-trips through its cache encoding', () {
      expect(LetsBotChrome.decode(chrome.encode()), chrome);
      for (final raw in [
        null,
        '',
        'x',
        '[]',
        '{"statusBar":"light"}',
        '{"statusBar":"light","header":"red","background":"#ffffff"}'
      ]) {
        expect(LetsBotChrome.decode(raw), isNull, reason: raw);
      }
    });

    test('merges a chrome event over the current colours', () {
      final merged = chrome.merge(lightStatusBar: false, background: '#000000');
      expect(merged.lightStatusBar, isFalse);
      expect(merged.header, '#0e7c66');
      expect(merged.background, '#000000');
    });

    test('neutral chrome uses the brand colour for the header', () {
      final branded = LetsBotChrome.neutral(dark: false, brandColor: '#0e7c66');
      expect(branded.header, '#0e7c66');
      expect(branded.lightStatusBar, isTrue);
      expect(branded.background, '#ffffff');
      final light = LetsBotChrome.neutral(dark: false);
      expect(light.lightStatusBar, isFalse);
      final dark = LetsBotChrome.neutral(dark: true);
      expect(dark.lightStatusBar, isTrue);
      expect(dark.background, '#111418');
    });
  });

  test('insets serialise as CSS px for boot/setInsets', () {
    expect(
      insetsPayload(const EdgeInsets.fromLTRB(0, 47.333333, 12.5, 34)),
      {'top': 47.33, 'bottom': 34.0, 'left': 0.0, 'right': 12.5},
    );
    expect(insetsPayload(EdgeInsets.zero),
        {'top': 0.0, 'bottom': 0.0, 'left': 0.0, 'right': 0.0});
    expect(
      hostCallScript(
          'setInsets', insetsPayload(const EdgeInsets.only(top: 20))),
      contains('h.setInsets({"top":20.0,"bottom":0.0,"left":0.0,"right":0.0})'),
    );
  });

  test('restores the app status-bar style when the chat closes', () async {
    const appStyle = SystemUiOverlayStyle.dark;
    SystemChrome.setSystemUIOverlayStyle(appStyle);
    await Future<void>.delayed(Duration.zero);

    final keeper = StatusBarStyleKeeper()..capture();
    SystemChrome.setSystemUIOverlayStyle(const LetsBotChrome(
      lightStatusBar: true,
      header: '#0e7c66',
      background: '#ffffff',
    ).overlayStyle);
    await Future<void>.delayed(Duration.zero);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(SystemChrome.latestStyle?.statusBarIconBrightness, Brightness.light);

    keeper.restore();
    await Future<void>.delayed(Duration.zero);
    // ignore: invalid_use_of_visible_for_testing_member
    expect(SystemChrome.latestStyle, appStyle);
    expect(keeper.captured, isFalse);
    keeper.restore(); // idempotent
  });

  group('client', () {
    late MemoryLetsBotTokenStore store;
    late LetsBotClient client;

    setUp(() {
      store = MemoryLetsBotTokenStore();
      client = LetsBotClient(
        appKey: kAppKey,
        baseUrl: Uri.parse('https://letsbot.net'),
        device: kDevice,
        tokenStore: store,
        httpClient: FakeLetsBot().client,
      );
    });

    test('boot payload carries the insets', () {
      final payload = client.bootPayload('t',
          insets: insetsPayload(const EdgeInsets.only(top: 59, bottom: 34)));
      expect(payload['insets'],
          {'top': 59.0, 'bottom': 34.0, 'left': 0.0, 'right': 0.0});
      expect(client.bootPayload('t').containsKey('insets'), isFalse);
    });

    test('caches chrome per theme across client instances', () async {
      const chrome = LetsBotChrome(
        lightStatusBar: true,
        header: '#0e7c66',
        background: '#f5f7f9',
      );
      expect(await client.loadChrome('light'), isNull);
      await client.saveChrome('light', chrome);
      expect(client.cachedChrome('light'), chrome);
      expect(client.cachedChrome('dark'), isNull);

      final next = LetsBotClient(
        appKey: kAppKey,
        baseUrl: Uri.parse('https://letsbot.net'),
        device: kDevice,
        tokenStore: store,
      );
      expect(next.cachedChrome('light'), isNull);
      expect(await next.loadChrome('light'), chrome);
      expect(next.cachedChrome('light'), chrome);
      expect(await next.loadChrome('dark'), isNull);
    });
  });
}
