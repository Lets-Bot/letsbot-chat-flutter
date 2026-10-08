# letsbot_chat example

A small app showing every part of the LetsBot In-App Chat SDK: configure,
open the chat (full screen and embedded), unread badge, chat context, verified
identity and logout.

```bash
flutter run \
  --dart-define=LETSBOT_APP_KEY=your_app_key \
  --dart-define=LETSBOT_BASE_URL=https://letsbot.net
```

Before it can connect, add the example's ids to LetsBot panel → Channels →
In-App Chat → Platforms:

- Android package: `net.letsbot.chat.example`
- iOS bundle id: `net.letsbot.chat.example`

Identity: paste a JWT minted by your backend (HS256, signed with the app's
Identity Secret, `sub` = the user id you type). Never put the secret in the
app.

Push: the example does not include Firebase. In your app, pass the FCM / APNs
token with `LetsBot.setPushToken(token)` and route taps through
`LetsBot.handleNotification(context, data)` — see the package README.
