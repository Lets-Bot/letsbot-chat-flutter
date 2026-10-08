/// Error codes of the LetsBot In-App Chat API plus a few SDK-side codes.
///
/// Server codes match the `{"error": "<code>"}` bodies documented for the
/// SDK API. Unknown future codes map to [unknown]; the raw string stays
/// available in [LetsBotException.rawCode].
enum LetsBotErrorCode {
  /// Unknown App Key, app disabled or deleted, workspace unavailable, or chat
  /// not enabled for this workspace (HTTP 404).
  notFound('not_found'),

  /// The app's bundle id / applicationId (or platform) is not registered in
  /// LetsBot panel → Channels → In-App Chat → Platforms (HTTP 403).
  appNotRegistered('app_not_registered'),

  /// The visitor token is missing, invalid or expired. The SDK handles this
  /// itself by creating a new session (HTTP 401).
  invalidVisitor('invalid_visitor'),

  /// The identity token has a bad signature, is malformed, or no Identity
  /// Secret is configured for the app (HTTP 401).
  identityInvalid('identity_invalid'),

  /// The identity token's `exp` has passed: fetch a new one from your backend
  /// and call `LetsBot.identify` again (HTTP 401).
  identityExpired('identity_expired'),

  /// The visitor or their IP address was blocked by the business (HTTP 403).
  blocked('blocked'),

  /// Validation failed (HTTP 422).
  invalid('invalid'),

  /// A value is too long (HTTP 422).
  tooLong('too_long'),

  /// The e-mail or phone number is not valid (HTTP 422).
  invalidContact('invalid_contact'),

  /// Consent is required before sending (HTTP 422).
  consentRequired('consent_required'),

  /// The uploaded file is too big (HTTP 422).
  fileTooBig('file_too_big'),

  /// The uploaded file type is not allowed (HTTP 422).
  fileType('file_type'),

  /// Rate limited: retry later, honouring [LetsBotException.retryAfter]
  /// (HTTP 429).
  slowDown('slow_down'),

  /// The workspace's chat budget is exhausted for now (HTTP 429).
  busy('busy'),

  /// `LetsBot.configure` was not called (SDK-side).
  notConfigured('not_configured'),

  /// The SDK runs only on iOS and Android (SDK-side).
  unsupportedPlatform('unsupported_platform'),

  /// No connection, DNS failure or timeout (SDK-side).
  network('network_error'),

  /// LetsBot answered with an unexpected 5xx error (SDK-side).
  server('server_error'),

  /// LetsBot answered with a body the SDK could not read (SDK-side).
  invalidResponse('invalid_response'),

  /// Any other error code.
  unknown('unknown');

  const LetsBotErrorCode(this.wire);

  /// The code as it appears on the wire, e.g. `identity_expired`.
  final String wire;

  /// Maps a wire code to its enum value ([unknown] if not recognised).
  static LetsBotErrorCode fromWire(String? code) {
    if (code == null) return LetsBotErrorCode.unknown;
    for (final value in LetsBotErrorCode.values) {
      if (value.wire == code) return value;
    }
    return LetsBotErrorCode.unknown;
  }
}

/// Error raised (or reported through `LetsBot.onError`) by the SDK.
class LetsBotException implements Exception {
  /// Creates an exception for [code]. [rawCode] defaults to `code.wire`.
  LetsBotException(
    this.code, {
    String? rawCode,
    this.statusCode,
    this.retryAfter,
    this.message,
  }) : rawCode = rawCode ?? code.wire;

  /// Creates an exception from a wire code such as `identity_expired`.
  factory LetsBotException.fromWire(
    String? code, {
    int? statusCode,
    Duration? retryAfter,
    String? message,
  }) {
    final parsed = LetsBotErrorCode.fromWire(code);
    return LetsBotException(
      parsed,
      rawCode: code ?? parsed.wire,
      statusCode: statusCode,
      retryAfter: retryAfter,
      message: message,
    );
  }

  /// Typed error code.
  final LetsBotErrorCode code;

  /// The exact code string received (useful when [code] is
  /// [LetsBotErrorCode.unknown]).
  final String rawCode;

  /// HTTP status, when the error came from the API.
  final int? statusCode;

  /// Server-suggested wait before retrying (`Retry-After`), if any.
  final Duration? retryAfter;

  /// Developer-facing detail. Never contains tokens or message text.
  final String? message;

  /// Whether retrying the same call later may succeed.
  bool get isRetryable => const {
        LetsBotErrorCode.network,
        LetsBotErrorCode.server,
        LetsBotErrorCode.slowDown,
        LetsBotErrorCode.busy,
      }.contains(code);

  @override
  String toString() {
    final buffer = StringBuffer('LetsBotException($rawCode');
    if (statusCode != null) buffer.write(', HTTP $statusCode');
    if (retryAfter != null) {
      buffer.write(', retry after ${retryAfter!.inSeconds}s');
    }
    buffer.write(')');
    if (message != null) buffer.write(': $message');
    return buffer.toString();
  }
}
