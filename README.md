# LetsBot In-App Chat for Flutter

[![pub package](https://img.shields.io/pub/v/letsbot_chat.svg)](https://pub.dev/packages/letsbot_chat)
[![CI](https://github.com/Lets-Bot/letsbot-chat-flutter/actions/workflows/ci.yml/badge.svg)](https://github.com/Lets-Bot/letsbot-chat-flutter/actions/workflows/ci.yml)

Give your app's users a support chat answered by the same LetsBot AI assistant
and team that already answer your business on WhatsApp and on your website.
Every conversation lands in the LetsBot inbox (web panel and the LetsBot iOS /
Android apps).

- Ready-made chat screen: text, reply buttons, cards, images and PDFs, voice
  notes, typing and seen indicators, pre-chat and out-of-hours forms, RTL,
  dark mode, Arabic / English / Spanish / Portuguese.
- Verified identity: logged-in users keep one conversation across devices.
- Push notifications through your own Firebase / APNs setup.
- Unread badge, chat context, typed errors.

Docs: <https://letsbot.net/developers/in-app-chat>

| | Minimum |
|---|---|
| Flutter | 3.22 |
| iOS | 13 |
| Android | 6.0 (API 23) |

---

## 1. Install

```bash
flutter pub add letsbot_chat:0.1.0
cd ios && pod install
```

Pin the exact version in production apps.

### Install directly from GitHub

No package registry needed: point `pubspec.yaml` at the tagged release on GitHub.

```yaml
dependencies:
  letsbot_chat:
    git:
      url: https://github.com/Lets-Bot/letsbot-chat-flutter.git
      ref: 0.1.0
```

Then run:

```bash
flutter pub get
cd ios && pod install
```

`ref` pins the exact release tag; `pubspec.lock` records the resolved commit.

### iOS — Info.plist

Add these keys (with text in every language your app supports). The SDK does
not track users: do **not** add App Tracking Transparency.

```xml
<key>NSCameraUsageDescription</key>
<string>Take a photo to send in the support chat.</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Choose photos to send in the support chat.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Record voice notes for the support chat.</string>
```

### Android

The SDK's manifest merges `INTERNET`, `POST_NOTIFICATIONS`, `RECORD_AUDIO` and
`MODIFY_AUDIO_SETTINGS`. The microphone permission is requested at runtime only
when the user records a voice note. On Android 13+ request
`POST_NOTIFICATIONS` at a sensible moment in your own flow.

Don't want voice notes? Remove the permission in your app manifest:

```xml
<uses-permission android:name="android.permission.RECORD_AUDIO" tools:node="remove" />
```

### Register your app ids

LetsBot only answers apps it knows. In **LetsBot panel → Channels → In-App
Chat → Platforms**, add your iOS bundle id and Android applicationId. Until
then the SDK reports `app_not_registered`.

---

## 2. Quick start

```dart
import 'package:flutter/material.dart';
import 'package:letsbot_chat/letsbot_chat.dart';

final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await LetsBot.configure(
    appKey: 'YOUR_APP_KEY',      // public, safe to ship
    locale: 'en',                // ar | en | es | pt (null = app locale)
    theme: LetsBotTheme.auto,    // follows your app's light/dark theme
    navigatorKey: navigatorKey,  // lets notification taps open the chat
  );
  runApp(MaterialApp(navigatorKey: navigatorKey, home: const HomePage()));
}
```

Open the chat from a Help / Contact us button:

```dart
ElevatedButton(
  onPressed: () => LetsBot.show(context),
  child: const Text('Contact support'),
)
```

Or embed it in your own page:

```dart
Scaffold(
  appBar: AppBar(title: const Text('Support')),
  body: const LetsBotChatView(),
)
```

`LetsBot.hide()` closes the screen opened by `show`.

### Unread badge

```dart
ValueListenableBuilder<int>(
  valueListenable: LetsBot.unreadCount,
  builder: (context, unread, _) => Badge(
    isLabelVisible: unread > 0,
    label: Text('$unread'),
    child: const Icon(Icons.support_agent),
  ),
)
```

Prefer streams? Use `LetsBot.unreadCountStream` (cancel the subscription in
`dispose`). The count refreshes when the app resumes, after a LetsBot
notification and when the chat closes; call `LetsBot.refreshUnread()` any
time.

### Context

Tell the AI and your team what the user is looking at:

```dart
LetsBot.setContext({'screen': 'order_details', 'orderId': '1234'});
LetsBot.show(context);
```

### Language and theme

```dart
LetsBot.setLocale('ar');            // the chat renders right-to-left
LetsBot.setTheme(LetsBotTheme.dark);
```

---

## 3. Logged-in users: verified identity

A verified user keeps one conversation across devices and reinstalls, and your
team sees who they are.

**Backend** (never in the app): add an authenticated endpoint that returns a
short-lived JWT for the current user, signed HS256 with the app's **Identity
Secret** (`LETSBOT_IDENTITY_SECRET`):

```json
{ "sub": "<stable user id>", "iat": 1760000000, "exp": 1760086400,
  "name": "Sara", "email": "sara@example.com" }
```

`exp` may be at most 7 days after `iat`; 24 hours is recommended. Use a stable
internal user id (not an e-mail address that can change).

**App** — after login and on every app start while logged in:

```dart
try {
  await LetsBot.identify(
    userId: user.id,                       // must equal the JWT `sub`
    identityToken: await api.letsBotIdentityToken(),
    name: user.name,
    email: user.email,
    phone: user.phone,
  );
} on LetsBotException catch (e) {
  if (e.code == LetsBotErrorCode.identityExpired) {
    // fetch a fresh token from your backend and call identify again
  }
}
```

**Logout** — call before clearing your own session, so the next person on the
device does not see the previous user's conversation:

```dart
await LetsBot.logout();
```

Guests can chat anonymously; when they log in, `identify` links them.

---

## 4. Push notifications

LetsBot sends a notification with **your** Firebase / APNs credentials when
the team or the AI replies while the chat is closed. Upload them in **LetsBot
panel → Channels → In-App Chat → Notifications** and press «Send test
notification».

Use your existing push setup. With Firebase Cloud Messaging:

```dart
final token = await FirebaseMessaging.instance.getToken();
if (token != null) LetsBot.setPushToken(token);
FirebaseMessaging.instance.onTokenRefresh.listen(LetsBot.setPushToken);
```

With raw APNs tokens on iOS:

```dart
LetsBot.setPushToken(apnsHexToken, provider: LetsBotPushProvider.apns);
// sandbox defaults to true in debug/profile builds; pass sandbox: explicitly
// if your signing differs.
```

The SDK does not create a chat session just to register the token: it is
registered when the user first opens the chat.

Route taps (foreground, background and cold start) — leave everything else to
your own handling:

```dart
void onNotificationTap(Map<String, dynamic> data) {
  if (LetsBot.isLetsBotNotification(data)) {
    LetsBot.handleNotification(null, data); // uses navigatorKey, or pass a context
    return;
  }
  // ...your app's notifications
}

FirebaseMessaging.onMessageOpenedApp.listen((m) => onNotificationTap(m.data));
final initial = await FirebaseMessaging.instance.getInitialMessage();
if (initial != null) onNotificationTap(initial.data);

// Foreground message: just refresh the badge.
FirebaseMessaging.onMessage.listen((m) {
  if (LetsBot.isLetsBotNotification(m.data)) LetsBot.refreshUnread();
});
```

LetsBot payloads carry `lb: "1"`, `lb_k: <App Key>` and `lb_c: <cursor>`.

---

## 5. Callbacks

```dart
LetsBot.onOpen = () => analytics.log('support_open');
LetsBot.onClose = () {};
LetsBot.onMessage = (text) {};          // reply arrived while open; don't log text
LetsBot.onUnreadChanged = (count) {};
LetsBot.onError = (e) => debugPrint('LetsBot: ${e.rawCode}');
```

`identify` throws `LetsBotException`. Background work (`setPushToken`,
`refreshUnread`, `logout`, the chat screen) never throws and reports to
`onError` instead.

---

## 6. Troubleshooting

| Code (`e.rawCode`) | Meaning | Fix |
|---|---|---|
| `not_found` | Unknown App Key, app disabled/deleted, or In-App Chat unavailable for the workspace. | Check the App Key in the panel; make sure the app is enabled. |
| `app_not_registered` | The bundle id / applicationId (or platform) is not in the app's list. | Add it in panel → In-App Chat → Platforms. Check flavors (`.dev` suffixes). |
| `identity_invalid` | JWT signature/format wrong, no Identity Secret configured, or `sub` ≠ `userId`. | Sign HS256 with the current Identity Secret; pass the same user id. |
| `identity_expired` | The JWT's `exp` has passed. | Fetch a new token from your backend and call `identify` again. |
| `invalid_visitor` | Visitor token invalid or idle > 90 days. | Handled by the SDK (new session). |
| `blocked` | The visitor or IP was blocked by your team. | Unblock from the inbox if it was a mistake. |
| `slow_down` / `busy` | Rate limit / workspace budget. | Retry later; `e.retryAfter` tells you when. |
| `network_error` | No connection or timeout. | The chat screen shows a retry button. |
| `not_configured` | `LetsBot.configure` was not called. | Call it in `main()` before `runApp`. |
| `unsupported_platform` | Not iOS or Android. | The SDK supports iOS and Android only. |

Other checks:

- **Blank screen on Android release builds** — make sure nothing strips the
  `INTERNET` permission from your merged manifest.
- **Voice notes don't record** — iOS: `NSMicrophoneUsageDescription` is
  missing. Android: the user denied the microphone permission (Settings → App
  → Permissions).
- **No notifications** — upload credentials in the panel, send the test
  notification, confirm `setPushToken` is called after the user opened the
  chat at least once, and that iOS has the Push Notifications capability.
- **Links open in the browser** — by design: the chat WebView only shows the
  LetsBot chat screen.

---

## Security

- The App Key is public. The Identity Secret and push credentials must never
  be in the app or in source control.
- The visitor token is stored in the iOS Keychain (this device only) or
  Android Keystore-backed storage, never in plain preferences.
- The SDK never logs tokens or message text.
- The chat WebView only loads the LetsBot chat screen and only accepts bridge
  messages from it; other links open in the system browser (http/https only).

## License

MIT © 2026 LetsBot. Questions: support@letsbot.net ·
Issues: <https://github.com/Lets-Bot/letsbot-chat-flutter/issues>
