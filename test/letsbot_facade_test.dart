import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:letsbot_chat/letsbot_chat.dart';
import 'package:letsbot_chat/src/runtime.dart';

import 'support/fake_letsbot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeLetsBot fake;
  late MemoryLetsBotTokenStore store;

  Future<void> configure({String? locale, String? color}) => LetsBot.configure(
        appKey: kAppKey,
        locale: locale,
        color: color,
        tokenStore: store,
        httpClient: fake.client,
        deviceInfo: kDevice,
      );

  setUp(() {
    fake = FakeLetsBot();
    store = MemoryLetsBotTokenStore();
  });

  tearDown(LetsBot.resetForTesting);

  group('notifications', () {
    test('recognises LetsBot payloads only', () {
      expect(
          LetsBot.isLetsBotNotification({'lb': '1', 'lb_k': kAppKey}), isTrue);
      expect(LetsBot.isLetsBotNotification({'lb': 1}), isTrue);
      expect(LetsBot.isLetsBotNotification({'lb': '0'}), isFalse);
      expect(LetsBot.isLetsBotNotification({'type': 'promo'}), isFalse);
      expect(LetsBot.isLetsBotNotification(null), isFalse);
    });

    test('handleNotification ignores other payloads', () async {
      expect(
          await LetsBot.handleNotification(null, {'type': 'promo'}), isFalse);
    });

    test('handleNotification without a navigator refreshes only', () async {
      await configure();
      final visitor = await _session();
      fake.unreadByVisitor[visitor] = 2;
      expect(await LetsBot.handleNotification(null, {'lb': '1'}), isTrue);
      await pumpEventQueue();
      expect(LetsBot.unreadCount.value, 2);
    });
  });

  group('configure', () {
    test('validates arguments', () async {
      await expectLater(
        LetsBot.configure(appKey: ' ', deviceInfo: kDevice),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.invalid)),
      );
      await expectLater(
        LetsBot.configure(appKey: 'k', baseUrl: 'ftp://x', deviceInfo: kDevice),
        throwsA(isA<LetsBotException>()),
      );
      await expectLater(
        LetsBot.configure(appKey: 'k', color: 'teal', deviceInfo: kDevice),
        throwsA(isA<LetsBotException>()),
      );
    });

    test('calls before configure fail with not_configured', () async {
      expect(LetsBot.isConfigured, isFalse);
      await expectLater(
        LetsBot.identify(userId: 'u', identityToken: 'x.y.z'),
        throwsA(isA<LetsBotException>()
            .having((e) => e.code, 'code', LetsBotErrorCode.notConfigured)),
      );
      final errors = <LetsBotException>[];
      LetsBot.onError = errors.add;
      await LetsBot.setPushToken('t');
      expect(errors.single.code, LetsBotErrorCode.notConfigured);
    });

    test('does not create a session on startup', () async {
      await configure();
      await pumpEventQueue();
      expect(fake.requests, isEmpty);
    });

    test('context set before configure is applied', () async {
      LetsBot.setContext({'screen': 'cart'});
      await configure();
      await _session();
      expect(fake.calls('session').single.body!['ctx'], {'screen': 'cart'});
    });
  });

  group('unread', () {
    test('publishes to the listenable, the stream and the callback', () async {
      await configure();
      final visitor = await _session();
      fake.unreadByVisitor[visitor] = 3;
      final fromCallback = <int>[];
      LetsBot.onUnreadChanged = fromCallback.add;
      final fromStream = <int>[];
      final sub = LetsBot.unreadCountStream.listen(fromStream.add);
      expect(await LetsBot.refreshUnread(), 3);
      await pumpEventQueue();
      expect(LetsBot.unreadCount.value, 3);
      expect(fromStream, [3]);
      expect(fromCallback, [3]);
      await sub.cancel();
    });

    test('refreshes when the app resumes', () async {
      await configure();
      final visitor = await _session();
      fake.unreadByVisitor[visitor] = 5;
      TestWidgetsFlutterBinding.instance
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(LetsBot.unreadCount.value, 5);
    });

    test('logout resets the count and the stored visitor', () async {
      await configure();
      final visitor = await _session();
      fake.unreadByVisitor[visitor] = 1;
      await LetsBot.refreshUnread();
      await LetsBot.logout();
      expect(LetsBot.unreadCount.value, 0);
      expect(store.values, isEmpty);
    });
  });

  group('chat view', () {
    testWidgets('shows a localized error when the chat is unavailable',
        (tester) async {
      fake.locked = true;
      await tester.runAsync(() => configure(locale: 'en'));
      final errors = <LetsBotException>[];
      var opened = 0;
      var closed = 0;
      LetsBot.onError = errors.add;
      LetsBot.onOpen = () => opened++;
      LetsBot.onClose = () => closed++;

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LetsBotChatView()),
      ));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50),
          ));
      await tester.pump();

      expect(find.text('Chat is not available right now.'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(errors.single.code, LetsBotErrorCode.notFound);
      expect(opened, 1);
      expect(LetsBot.isOpen, isTrue);

      await tester.pumpWidget(const SizedBox());
      expect(closed, 1);
      expect(LetsBot.isOpen, isFalse);
    });

    testWidgets(
        'full screen is edge-to-edge, styles the status bar and restores it',
        (tester) async {
      fake.locked = true;
      await tester.runAsync(() => configure(locale: 'en', color: '#0e7c66'));
      SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.dark);
      await tester.pump();

      await tester.pumpWidget(const MaterialApp(home: LetsBotChatScreen()));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50),
          ));
      await tester.pump();

      // No SafeArea between the screen and the chat view.
      expect(
        find.ancestor(
          of: find.byType(LetsBotChatView),
          matching: find.byType(SafeArea),
        ),
        findsNothing,
      );
      final region = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
        find.descendant(
          of: find.byType(LetsBotChatView),
          matching: find.byType(AnnotatedRegion<SystemUiOverlayStyle>),
        ),
      );
      // Neutral chrome before the page reports its own: brand-coloured
      // header → light status-bar icons.
      expect(region.value.statusBarIconBrightness, Brightness.light);
      expect(region.value.statusBarBrightness, Brightness.dark);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).resizeToAvoidBottomInset,
        isTrue,
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      // ignore: invalid_use_of_visible_for_testing_member
      expect(SystemChrome.latestStyle, SystemUiOverlayStyle.dark);
    });

    testWidgets('error screen follows the chat locale (Arabic, RTL)',
        (tester) async {
      fake.registeredAppIds.clear();
      await tester.runAsync(() => configure(locale: 'ar'));
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LetsBotChatView()),
      ));
      await tester.runAsync(() => Future<void>.delayed(
            const Duration(milliseconds: 50),
          ));
      await tester.pump();
      final text = find.text('هذا التطبيق غير مسجّل بعد في محادثة LetsBot.');
      expect(text, findsOneWidget);
      expect(Directionality.of(tester.element(text)), TextDirection.rtl);
    });
  });
}

/// Creates a session the way opening the chat does (internal client).
Future<String> _session() async {
  final client = await LetsBotRuntime.requireClient();
  return client.ensureSession();
}
