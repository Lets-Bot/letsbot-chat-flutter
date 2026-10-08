import 'package:flutter/material.dart';
import 'package:letsbot_chat/letsbot_chat.dart';

/// Pass your App Key with `--dart-define=LETSBOT_APP_KEY=...`.
const String appKey = String.fromEnvironment(
  'LETSBOT_APP_KEY',
  defaultValue: 'YOUR_APP_KEY',
);

/// Optional: point at another LetsBot server (e.g. staging).
const String baseUrl = String.fromEnvironment(
  'LETSBOT_BASE_URL',
  defaultValue: 'https://letsbot.net',
);

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LetsBot.configure(
    appKey: appKey,
    baseUrl: baseUrl,
    theme: LetsBotTheme.auto,
    navigatorKey: navigatorKey,
  );
  LetsBot.onError = (error) {
    // Error codes only: never log tokens or message text.
    debugPrint('LetsBot error: ${error.rawCode}');
  };

  // With Firebase Messaging you would add:
  //   final token = await FirebaseMessaging.instance.getToken();
  //   if (token != null) LetsBot.setPushToken(token);
  //   FirebaseMessaging.instance.onTokenRefresh.listen(LetsBot.setPushToken);
  //   FirebaseMessaging.onMessageOpenedApp.listen((m) {
  //     LetsBot.handleNotification(null, m.data);
  //   });

  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  Locale _locale = const Locale('en');

  void _setLocale(Locale locale) {
    setState(() => _locale = locale);
    LetsBot.setLocale(locale.languageCode);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LetsBot Chat',
      navigatorKey: navigatorKey,
      locale: _locale,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF0E7C66)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF0E7C66),
        brightness: Brightness.dark,
      ),
      home: HomePage(locale: _locale, onLocaleChanged: _setLocale),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.locale,
    required this.onLocaleChanged,
  });

  final Locale locale;
  final ValueChanged<Locale> onLocaleChanged;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _userId = TextEditingController();
  final _token = TextEditingController();
  String? _status;

  @override
  void dispose() {
    _userId.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _identify() async {
    try {
      await LetsBot.identify(
        userId: _userId.text.trim(),
        identityToken: _token.text.trim(),
      );
      setState(() => _status = 'Identified as ${_userId.text.trim()}');
    } on LetsBotException catch (e) {
      final hint = e.code == LetsBotErrorCode.identityExpired
          ? ' — fetch a fresh token from your backend'
          : '';
      setState(() => _status = 'identify failed: ${e.rawCode}$hint');
    }
  }

  Future<void> _logout() async {
    await LetsBot.logout();
    setState(() => _status = 'Logged out — the next chat starts fresh');
  }

  void _openFromOrder() {
    LetsBot.setContext({'screen': 'order_details', 'order_id': '1234'});
    LetsBot.show(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LetsBot Chat example'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.translate),
            onSelected: (code) => widget.onLocaleChanged(Locale(code)),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'en', child: Text('English')),
              PopupMenuItem(value: 'ar', child: Text('العربية')),
              PopupMenuItem(value: 'es', child: Text('Español')),
              PopupMenuItem(value: 'pt', child: Text('Português')),
            ],
          ),
        ],
      ),
      floatingActionButton: ValueListenableBuilder<int>(
        valueListenable: LetsBot.unreadCount,
        builder: (context, unread, _) => FloatingActionButton.extended(
          onPressed: () {
            LetsBot.setContext({'screen': 'home'});
            LetsBot.show(context);
          },
          icon: Badge(
            isLabelVisible: unread > 0,
            label: Text('$unread'),
            child: const Icon(Icons.support_agent),
          ),
          label: const Text('Contact support'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.receipt_long),
              title: const Text('Order #1234'),
              subtitle: const Text('Opens the chat with order context'),
              trailing: const Icon(Icons.chat_outlined),
              onTap: _openFromOrder,
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.view_sidebar_outlined),
              title: const Text('Embedded chat'),
              subtitle: const Text('LetsBotChatView inside your own page'),
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: const Text('Support')),
                  body: const LetsBotChatView(),
                ),
              )),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Refresh unread count'),
              onTap: () => LetsBot.refreshUnread(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Verified identity',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: _userId,
            decoration: const InputDecoration(labelText: 'User id (JWT sub)'),
          ),
          TextField(
            controller: _token,
            decoration: const InputDecoration(
              labelText: 'Identity token (JWT from your backend)',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              FilledButton(onPressed: _identify, child: const Text('Identify')),
              const SizedBox(width: 8),
              OutlinedButton(onPressed: _logout, child: const Text('Log out')),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_status!),
            ),
        ],
      ),
    );
  }
}
