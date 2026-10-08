import 'package:flutter_test/flutter_test.dart';
import 'package:letsbot_chat/src/bridge.dart';
import 'package:letsbot_chat/src/navigation_policy.dart';

void main() {
  group('parseBridgeEvent', () {
    test('parses every page → native event', () {
      expect(parseBridgeEvent('{"lb":"ready"}'), isA<BridgeReady>());
      expect(parseBridgeEvent('{"lb":"token_invalid"}'),
          isA<BridgeTokenInvalid>());
      expect(parseBridgeEvent('{"lb":"close"}'), isA<BridgeClose>());
      expect(
        parseBridgeEvent('{"lb":"open_url","url":"https://acme.com/o/1"}'),
        isA<BridgeOpenUrl>()
            .having((e) => e.url.toString(), 'url', 'https://acme.com/o/1'),
      );
      expect(parseBridgeEvent('{"lb":"unread","count":3}'),
          isA<BridgeUnread>().having((e) => e.count, 'count', 3));
      expect(parseBridgeEvent('{"lb":"message","t":"Hello"}'),
          isA<BridgeMessage>().having((e) => e.text, 'text', 'Hello'));
      expect(parseBridgeEvent('{"lb":"error","code":"identity_expired"}'),
          isA<BridgeError>().having((e) => e.code, 'code', 'identity_expired'));
    });

    test('ignores malformed or unsafe messages', () {
      for (final raw in [
        '',
        'not json',
        '[]',
        '{"event":"ready"}',
        '{"lb":42}',
        '{"lb":"unknown_event"}',
        '{"lb":"open_url","url":"javascript:alert(1)"}',
        '{"lb":"open_url","url":"file:///etc/passwd"}',
        '{"lb":"open_url","url":"intent://x#Intent;end"}',
        '{"lb":"open_url"}',
        '{"lb":"unread","count":-1}',
        '{"lb":"unread","count":"3"}',
      ]) {
        expect(parseBridgeEvent(raw), isNull, reason: raw);
      }
    });
  });

  group('hostCallScript', () {
    test('calls LetsBotHost safely with a JSON literal', () {
      final script = hostCallScript('boot', {'token': 't', 'context': {}});
      expect(script, contains('window.LetsBotHost'));
      expect(script, contains('h.boot({"token":"t","context":{}})'));
    });

    test('escapes line separators and cannot break out of the literal', () {
      final script =
          hostCallScript('setContext', {'note': "a\u2028b'</script>\"); x("});
      expect(script, isNot(contains('\u2028')));
      expect(script, contains(r'\u2028'));
      expect(script, contains(r'</script>\"); x("}'));
    });
  });

  group('navigation policy', () {
    final ui = Uri.parse(
        'https://letsbot.net/api/sdk/v1/pk_test_app/ui?l=en&theme=light&p=ios');

    test('allows only the hosted chat page', () {
      expect(
          decideNavigation(ui, ui.toString()), LetsBotNavigationAction.allow);
      expect(
        decideNavigation(
            ui, 'https://letsbot.net/api/sdk/v1/pk_test_app/ui?l=ar'),
        LetsBotNavigationAction.allow,
      );
      expect(
          decideNavigation(ui, 'about:blank'), LetsBotNavigationAction.allow);
    });

    test('sends other http(s) links to the system browser', () {
      expect(decideNavigation(ui, 'https://acme.com/orders/1'),
          LetsBotNavigationAction.openExternally);
      expect(decideNavigation(ui, 'https://letsbot.net/pricing'),
          LetsBotNavigationAction.openExternally);
      expect(
          decideNavigation(ui, 'http://letsbot.net/api/sdk/v1/pk_test_app/ui'),
          LetsBotNavigationAction.openExternally,
          reason: 'different scheme = different origin');
    });

    test('blocks other schemes and foreign sub-frames', () {
      for (final url in [
        'javascript:alert(1)',
        'file:///etc/hosts',
        'intent://scan/#Intent;scheme=zxing;end',
        'tel:+123',
        'data:text/html,hi',
      ]) {
        expect(decideNavigation(ui, url), LetsBotNavigationAction.block,
            reason: url);
      }
      expect(
        decideNavigation(ui, 'https://evil.example/frame', isMainFrame: false),
        LetsBotNavigationAction.block,
      );
      expect(
        decideNavigation(ui, 'https://letsbot.net/embed', isMainFrame: false),
        LetsBotNavigationAction.allow,
      );
    });

    test('trusts bridge messages only from the chat page', () {
      expect(isTrustedPage(ui, ui.toString()), isTrue);
      expect(
          isTrustedPage(
              ui, 'https://letsbot.net:443/api/sdk/v1/pk_test_app/ui'),
          isTrue);
      expect(isTrustedPage(ui, 'https://letsbot.net/other'), isFalse);
      expect(
          isTrustedPage(ui, 'https://evil.example/api/sdk/v1/pk_test_app/ui'),
          isFalse);
      expect(isTrustedPage(ui, null), isFalse);
    });
  });
}
