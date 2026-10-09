// Internal helpers for the edge-to-edge chat screen (API §8.1).
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;
import 'package:flutter/services.dart';

/// Colours of the hosted page's chrome: status-bar icon style, header and
/// page background. Internal; not exported.
@immutable
class LetsBotChrome {
  const LetsBotChrome({
    required this.lightStatusBar,
    required this.header,
    required this.background,
  });

  /// Neutral chrome used before the page reports its own (and nothing is
  /// cached yet): the brand colour as header when the app passed one,
  /// otherwise the plain light/dark background.
  factory LetsBotChrome.neutral({required bool dark, String? brandColor}) {
    final background = dark ? '#111418' : '#ffffff';
    final header = brandColor ?? background;
    return LetsBotChrome(
      lightStatusBar: isDarkColor(header),
      header: header,
      background: background,
    );
  }

  /// `true` = light (white) status-bar icons.
  final bool lightStatusBar;

  /// `#rrggbb`.
  final String header;

  /// `#rrggbb`.
  final String background;

  /// Merges a `chrome` bridge event over this value (missing colours keep
  /// their current value).
  LetsBotChrome merge({
    required bool lightStatusBar,
    String? header,
    String? background,
  }) =>
      LetsBotChrome(
        lightStatusBar: lightStatusBar,
        header: header ?? this.header,
        background: background ?? this.background,
      );

  Color get headerColor => parseHexColor(header);

  Color get backgroundColor => parseHexColor(background);

  /// System UI style for this chrome: status-bar icons over the header,
  /// transparent status bar (the page paints under it) and a navigation bar
  /// matching the page background.
  SystemUiOverlayStyle get overlayStyle {
    final bg = backgroundColor;
    final darkBackground = isDarkColor(background);
    return SystemUiOverlayStyle(
      statusBarColor: const Color(0x00000000),
      // Android: brightness of the icons.
      statusBarIconBrightness:
          lightStatusBar ? Brightness.light : Brightness.dark,
      // iOS: brightness of what is behind the status bar.
      statusBarBrightness: lightStatusBar ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: bg,
      systemNavigationBarDividerColor: bg,
      systemNavigationBarIconBrightness:
          darkBackground ? Brightness.light : Brightness.dark,
      systemNavigationBarContrastEnforced: false,
      systemStatusBarContrastEnforced: false,
    );
  }

  String encode() => jsonEncode({
        'statusBar': lightStatusBar ? 'light' : 'dark',
        'header': header,
        'background': background,
      });

  /// Decodes [encode] output; `null` for anything malformed.
  static LetsBotChrome? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return null;
      final statusBar = map['statusBar'];
      final header = map['header'];
      final background = map['background'];
      if ((statusBar != 'light' && statusBar != 'dark') ||
          header is! String ||
          background is! String ||
          !isHexColor(header) ||
          !isHexColor(background)) {
        return null;
      }
      return LetsBotChrome(
        lightStatusBar: statusBar == 'light',
        header: header,
        background: background,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LetsBotChrome &&
      other.lightStatusBar == lightStatusBar &&
      other.header == header &&
      other.background == background;

  @override
  int get hashCode => Object.hash(lightStatusBar, header, background);
}

final RegExp _hex = RegExp(r'^#[0-9a-fA-F]{6}$');

bool isHexColor(String value) => _hex.hasMatch(value);

Color parseHexColor(String hex) =>
    Color(0xFF000000 | int.parse(hex.substring(1), radix: 16));

/// Whether [hex] is dark enough to need light text/icons on top.
bool isDarkColor(String hex) => parseHexColor(hex).computeLuminance() < 0.5;

/// Safe-area insets in CSS px for `boot({insets})` / `setInsets(...)`.
/// Flutter logical pixels equal CSS px in the WebView.
Map<String, double> insetsPayload(EdgeInsets padding) {
  double r(double v) =>
      v.isFinite && v > 0 ? (v * 100).roundToDouble() / 100 : 0;
  return {
    'top': r(padding.top),
    'bottom': r(padding.bottom),
    'left': r(padding.left),
    'right': r(padding.right),
  };
}

/// Remembers the app's system UI style when the chat opens and puts it back
/// when the chat closes, so the host's status bar never keeps the chat's
/// style.
class StatusBarStyleKeeper {
  SystemUiOverlayStyle? _previous;
  bool _captured = false;

  bool get captured => _captured;

  SystemUiOverlayStyle? get previous => _previous;

  void capture() {
    if (_captured) return;
    _captured = true;
    // The only way to read the style an app set with
    // SystemChrome.setSystemUIOverlayStyle; the getter works in all build
    // modes. Apps using AnnotatedRegion/AppBar get theirs back on the next
    // frame anyway.
    // ignore: invalid_use_of_visible_for_testing_member
    _previous = SystemChrome.latestStyle;
  }

  void restore() {
    if (!_captured) return;
    _captured = false;
    final previous = _previous;
    _previous = null;
    if (previous != null) SystemChrome.setSystemUIOverlayStyle(previous);
  }
}
