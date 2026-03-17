import 'package:LinkUp/utils/RadUserInfo.dart';

class PortalStatusSnapshot {
  const PortalStatusSnapshot({
    required this.detectedAcid,
    required this.isOnline,
    required this.error,
    required this.userInfo,
  });

  final String? detectedAcid;
  final bool isOnline;
  final String? error;
  final RadUserInfo? userInfo;
}

class PortalStatusResolver {
  static Future<PortalStatusSnapshot> resolve({
    required Future<(String?, bool, String?)> Function() detectReality,
    required Future<RadUserInfo> Function() fetchUserInfo,
  }) async {
    final (detectedAcid, _, detectorError) = await detectReality();

    try {
      final userInfo = await fetchUserInfo();
      return PortalStatusSnapshot(
        detectedAcid: detectedAcid,
        isOnline: userInfo.isOnline,
        error: detectorError,
        userInfo: userInfo,
      );
    } catch (_) {
      return PortalStatusSnapshot(
        detectedAcid: detectedAcid,
        isOnline: false,
        error: detectorError,
        userInfo: null,
      );
    }
  }
}
