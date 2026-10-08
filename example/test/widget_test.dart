import 'package:flutter_test/flutter_test.dart';
import 'package:letsbot_chat/letsbot_chat.dart';
import 'package:letsbot_chat_example/main.dart';

void main() {
  testWidgets('home renders the support entry point', (tester) async {
    await tester.runAsync(() => LetsBot.configure(
          appKey: 'pk_example',
          tokenStore: MemoryLetsBotTokenStore(),
          deviceInfo: const LetsBotDeviceInfo(
            appId: 'net.letsbot.chat.example',
            appVersion: '1.0.0',
            platform: 'android',
          ),
        ));
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Contact support'), findsOneWidget);
    expect(find.text('Order #1234'), findsOneWidget);
    LetsBot.resetForTesting();
  });
}
