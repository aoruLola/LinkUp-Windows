import 'package:LinkUp/utils/SrunLogin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'includes raw response details when login response cannot be classified',
    () async {
      final result = await SrunLogin.srucPortalLogin(
        'tester',
        'secret',
        '1',
        'token',
        '10.0.0.8',
        requestJson: (_, __) async => {
          'error': '',
          'error_msg': '',
          'res': '',
          'foo': 'bar',
        },
      );

      expect(result.success, isFalse);
      expect(result.errorType, LoginErrorType.unknown);
      expect(result.message, isNot('未知错误'));
      expect(result.detailedMessage, contains('"foo":"bar"'));
    },
  );
}
