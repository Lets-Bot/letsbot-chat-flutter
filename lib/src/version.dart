/// SDK version, sent as `X-LB-SDK: flutter/<version>`. Keep in step with
/// `pubspec.yaml` (a unit test enforces it).
const String letsBotSdkVersion = '0.2.0';

/// Value of the `X-LB-SDK` header and the `sdk` field in API bodies.
const String letsBotSdkHeader = 'flutter/$letsBotSdkVersion';
