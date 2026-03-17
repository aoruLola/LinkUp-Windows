import 'package:LinkUp/utils/PortalStatusResolver.dart';
import 'package:LinkUp/utils/RadUserInfo.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'does not treat generic internet access as portal online when user info is unreachable',
    () async {
      final snapshot = await PortalStatusResolver.resolve(
        detectReality: () async => ('1', true, null),
        fetchUserInfo: () async => throw Exception('auth server unreachable'),
      );

      expect(snapshot.isOnline, isFalse);
      expect(snapshot.detectedAcid, '1');
      expect(snapshot.userInfo, isNull);
      expect(snapshot.userInfoError, contains('auth server unreachable'));
    },
  );

  test(
    'requires auth server confirmation before marking portal online',
    () async {
      final snapshot = await PortalStatusResolver.resolve(
        detectReality: () async => ('2', true, null),
        fetchUserInfo: () async =>
            RadUserInfo(error: 'ok', onlineIp: '10.0.0.8'),
      );

      expect(snapshot.isOnline, isTrue);
      expect(snapshot.detectedAcid, '2');
      expect(snapshot.userInfo?.onlineIp, '10.0.0.8');
    },
  );

  test('falls back to auth server check when reality probing fails', () async {
    final snapshot = await PortalStatusResolver.resolve(
      detectReality: () async => (null, false, 'timeout'),
      fetchUserInfo: () async => RadUserInfo(error: 'ok', onlineIp: '10.0.0.9'),
    );

    expect(snapshot.isOnline, isTrue);
    expect(snapshot.error, 'timeout');
    expect(snapshot.userInfo?.onlineIp, '10.0.0.9');
  });
}
