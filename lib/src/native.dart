import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper over the plugin's Android method channel. On iOS everything
/// is handled by WKWebView itself, so these calls short-circuit.
class LetsBotNative {
  LetsBotNative._();

  static const MethodChannel _channel =
      MethodChannel('net.letsbot.chat/native');

  static bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  /// Asks for the RECORD_AUDIO runtime permission (Android). Returns whether
  /// it is granted. On iOS returns `true`: WKWebView shows the system prompt.
  static Future<bool> requestMicrophone() async {
    if (!_isAndroid) return true;
    try {
      return await _channel.invokeMethod<bool>('requestMicrophone') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Opens the system file chooser (Android) and returns `content://` URIs.
  static Future<List<String>> pickFiles({
    required List<String> accept,
    required bool multiple,
  }) async {
    if (!_isAndroid) return const [];
    try {
      final result = await _channel.invokeListMethod<String>(
        'pickFiles',
        {'accept': accept, 'multiple': multiple},
      );
      return result ?? const [];
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Android release version (e.g. `14`), or `null` when unavailable.
  static Future<String?> androidVersion() async {
    if (!_isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('osVersion');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
