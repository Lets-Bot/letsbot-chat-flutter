// Internal state holder; documented at class level only.
// ignore_for_file: public_member_api_docs

import 'dart:async';

import 'package:flutter/widgets.dart';

import 'chrome.dart';
import 'client.dart';
import 'errors.dart';

/// Process-wide SDK state shared by the `LetsBot` facade and the chat view.
/// Internal; not exported.
class LetsBotRuntime {
  LetsBotRuntime._();

  static LetsBotClient? client;
  static Future<LetsBotClient>? ready;
  static GlobalKey<NavigatorState>? navigatorKey;

  static VoidCallback? onOpen;
  static VoidCallback? onClose;
  static void Function(String text)? onMessage;
  static void Function(int count)? onUnreadChanged;
  static void Function(LetsBotException error)? onError;

  static final ValueNotifier<int> unread = ValueNotifier<int>(0);
  static final StreamController<int> unreadController =
      StreamController<int>.broadcast();

  static int openViews = 0;

  /// Chrome colours of the visible chat (drives the full-screen route's
  /// background, so no white shows during keyboard/rotation animations).
  static final ValueNotifier<LetsBotChrome?> chrome =
      ValueNotifier<LetsBotChrome?>(null);

  /// The configured client, waiting for `configure` to finish.
  static Future<LetsBotClient> requireClient() {
    final future = ready;
    if (future == null) {
      return Future.error(
        LetsBotException(
          LetsBotErrorCode.notConfigured,
          message: 'Call LetsBot.configure(appKey: ...) first.',
        ),
      );
    }
    return future;
  }

  /// Mirrors a client unread value to the public listenable/stream.
  static void publishUnread(int count) {
    if (unread.value == count) return;
    unread.value = count;
    unreadController.add(count);
    _guard(() => onUnreadChanged?.call(count));
  }

  static void reportError(LetsBotException error) {
    _guard(() => onError?.call(error));
  }

  static void reportMessage(String text) {
    _guard(() => onMessage?.call(text));
  }

  static void viewOpened() {
    openViews++;
    _guard(() => onOpen?.call());
  }

  static void viewClosed() {
    if (openViews > 0) openViews--;
    _guard(() => onClose?.call());
    final c = client;
    if (c != null) unawaited(c.refreshUnread());
  }

  static void _guard(void Function() callback) {
    try {
      callback();
    } catch (error, stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'letsbot_chat',
        context: ErrorDescription('while calling an app callback'),
      ));
    }
  }
}
