import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'errors.dart';
import 'native.dart';
import 'version.dart';

/// Identity of the host app and device, sent in headers and session bodies.
@immutable
class LetsBotDeviceInfo {
  /// Creates device info. Normally loaded with [LetsBotDeviceInfo.load].
  const LetsBotDeviceInfo({
    required this.appId,
    required this.appVersion,
    required this.platform,
    this.osVersion,
  });

  /// iOS bundle id or Android applicationId (`X-LB-App-Id`).
  final String appId;

  /// App version name, e.g. `2.3.0`.
  final String appVersion;

  /// `ios` or `android` (`X-LB-Platform`).
  final String platform;

  /// OS version, e.g. `17.5` or `14`, when known.
  final String? osVersion;

  /// The `device` object of `POST session`.
  Map<String, Object?> toJson() => {
        'platform': platform,
        'app_id': appId,
        'app_version': appVersion,
        'sdk': letsBotSdkHeader,
        if (osVersion != null) 'os_version': osVersion,
      };

  /// Reads the app id/version from the platform.
  ///
  /// Throws [LetsBotException] with [LetsBotErrorCode.unsupportedPlatform]
  /// outside iOS and Android.
  static Future<LetsBotDeviceInfo> load() async {
    final String platform;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        platform = 'android';
      case TargetPlatform.iOS:
        platform = 'ios';
      default:
        throw LetsBotException(
          LetsBotErrorCode.unsupportedPlatform,
          message: 'LetsBot In-App Chat supports iOS and Android only.',
        );
    }
    final info = await PackageInfo.fromPlatform();
    final osVersion = platform == 'android'
        ? await LetsBotNative.androidVersion()
        : parseIosVersion(_safeOsVersionString());
    return LetsBotDeviceInfo(
      appId: info.packageName,
      appVersion: info.version,
      platform: platform,
      osVersion: osVersion,
    );
  }

  static String? _safeOsVersionString() {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return null;
    }
  }

  /// Extracts `17.5` from strings such as `Version 17.5 (Build 21F79)`.
  @visibleForTesting
  static String? parseIosVersion(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'(\d+(?:\.\d+){0,2})').firstMatch(raw);
    return match?.group(1);
  }
}
