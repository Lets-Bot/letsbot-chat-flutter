import 'errors.dart';

/// Short UI strings for the native loading/error states (the conversation
/// itself is localized by the hosted screen).
class LetsBotStrings {
  const LetsBotStrings._({
    required this.unavailable,
    required this.notRegistered,
    required this.offline,
    required this.generic,
    required this.retry,
    required this.close,
    required this.rtl,
  });

  /// Chat not available (404 / locked / disabled).
  final String unavailable;

  /// App id not registered (a developer configuration problem).
  final String notRegistered;

  /// No connection.
  final String offline;

  /// Anything else.
  final String generic;

  /// Retry button.
  final String retry;

  /// Close button.
  final String close;

  /// Right-to-left language.
  final bool rtl;

  /// Message for [error].
  String messageFor(LetsBotException? error) {
    switch (error?.code) {
      case LetsBotErrorCode.notFound:
        return unavailable;
      case LetsBotErrorCode.appNotRegistered:
        return notRegistered;
      case LetsBotErrorCode.network:
        return offline;
      default:
        return generic;
    }
  }

  /// Strings for a language code (falls back to English).
  static LetsBotStrings of(String? languageCode) {
    final code =
        (languageCode ?? 'en').toLowerCase().split(RegExp('[-_]')).first;
    return _all[code] ?? _all['en']!;
  }

  static const Map<String, LetsBotStrings> _all = {
    'en': LetsBotStrings._(
      unavailable: 'Chat is not available right now.',
      notRegistered: 'This app is not registered for LetsBot chat yet.',
      offline: 'No connection. Check your internet and try again.',
      generic: 'We couldn\'t load the chat. Please try again.',
      retry: 'Try again',
      close: 'Close',
      rtl: false,
    ),
    'ar': LetsBotStrings._(
      unavailable: 'المحادثة غير متاحة الآن.',
      notRegistered: 'هذا التطبيق غير مسجّل بعد في محادثة LetsBot.',
      offline: 'لا يوجد اتصال. تحقّق من الإنترنت وحاول مرة أخرى.',
      generic: 'تعذّر تحميل المحادثة. حاول مرة أخرى.',
      retry: 'حاول مرة أخرى',
      close: 'إغلاق',
      rtl: true,
    ),
    'es': LetsBotStrings._(
      unavailable: 'El chat no está disponible en este momento.',
      notRegistered: 'Esta app aún no está registrada en el chat de LetsBot.',
      offline: 'Sin conexión. Revisa tu internet e inténtalo de nuevo.',
      generic: 'No pudimos cargar el chat. Inténtalo de nuevo.',
      retry: 'Reintentar',
      close: 'Cerrar',
      rtl: false,
    ),
    'pt': LetsBotStrings._(
      unavailable: 'O chat não está disponível agora.',
      notRegistered: 'Este app ainda não está registrado no chat da LetsBot.',
      offline: 'Sem conexão. Verifique sua internet e tente novamente.',
      generic: 'Não foi possível carregar o chat. Tente novamente.',
      retry: 'Tentar novamente',
      close: 'Fechar',
      rtl: false,
    ),
  };
}
