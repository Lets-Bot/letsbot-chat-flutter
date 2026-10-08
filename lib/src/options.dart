/// Colour scheme of the hosted chat screen.
enum LetsBotTheme {
  /// Follow the app: the chat uses the brightness of the surrounding
  /// `Theme` (so it matches the app's own light/dark setting).
  auto,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// Which push service issued the token passed to `LetsBot.setPushToken`.
enum LetsBotPushProvider {
  /// Firebase Cloud Messaging registration token (Android, and iOS apps that
  /// use Firebase Messaging).
  fcm,

  /// Raw APNs device token (hex) on iOS apps that do not use Firebase.
  apns,
}
