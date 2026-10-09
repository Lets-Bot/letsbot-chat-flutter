# Changelog

## 0.2.0

- Edge-to-edge chat screen: `LetsBot.show` no longer wraps the chat in a
  `SafeArea`. The chat page paints under the status bar / notch and the home
  indicator, with the header colour behind the status bar, and pads itself
  using the safe-area insets the SDK passes (`boot({insets})`, then
  `LetsBotHost.setInsets` whenever they change, e.g. on rotation or when the
  keyboard opens).
- Handles the page's new `chrome` event: the status-bar icon style follows
  the chat header (light icons on a dark header) and the screen / WebView
  background follows the page background, so no white flashes show on open,
  close, rotation or keyboard animations.
- The last chrome colours are remembered per theme and used before the page
  paints the next time; without them a neutral colour (your brand colour for
  the header, if set) is used.
- Your app's previous status-bar style is restored when the chat closes.
- The loading and error panes stay inside the safe area.
- `X-LB-SDK` is now `flutter/0.2.0`.

## 0.1.0

First release of the LetsBot In-App Chat SDK for Flutter.

- `LetsBot.configure` with App Key, optional base URL, locale, theme
  (`auto` follows the app's light/dark theme), brand colour and navigator key.
- Hosted chat screen: `LetsBot.show(context)` / `LetsBot.hide()` and the
  embeddable `LetsBotChatView` widget, with the «Powered by LetsBot» credit.
- Verified identity: `LetsBot.identify(userId:, identityToken:)` with a
  short-lived HS256 JWT from your backend; re-applied automatically when the
  visitor session is renewed. `LetsBot.logout()` unregisters push and resets
  the conversation on the device.
- Lazy visitor session stored in secure storage (Keychain / Android
  Keystore), renewed automatically on `invalid_visitor`.
- Push: `LetsBot.setPushToken` (FCM or APNs), `LetsBot.isLetsBotNotification`
  and `LetsBot.handleNotification`.
- Unread badge: `LetsBot.unreadCount` (`ValueListenable<int>`),
  `LetsBot.unreadCountStream`, `LetsBot.refreshUnread()`; refreshed on app
  resume, after notifications and when the chat closes.
- `LetsBot.setContext`, `LetsBot.setLocale`, `LetsBot.setTheme`.
- Callbacks: `onOpen`, `onClose`, `onMessage`, `onUnreadChanged`, `onError`.
- Typed errors: `LetsBotException` with `LetsBotErrorCode`.
- Android: file chooser for attachments and microphone permission for voice
  notes. iOS: handled natively by WKWebView.
- The chat WebView only loads the LetsBot chat screen; every other link
  opens in the system browser.
- Can be installed straight from GitHub with a `git` dependency on tag
  `0.1.0` (see README).
