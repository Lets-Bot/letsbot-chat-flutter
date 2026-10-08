/// Whether a push payload was sent by LetsBot (`data["lb"] == "1"`).
///
/// Works with FCM `RemoteMessage.data` and APNs `userInfo` maps.
bool isLetsBotPayload(Map<Object?, Object?>? data) {
  if (data == null) return false;
  final value = data['lb'];
  return value == '1' || value == 1 || value == true;
}
