import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/api.dart';
import 'package:littlenet_native/widgets.dart';

void main() {
  test('native client helper formats API failures safely', () {
    expect(friendlyError(ApiException(401, 'invalid_credentials')),
        'Invalid username/email or password.');
    expect(friendlyError(ApiException(423, 'screen_time_limit')),
        'Screen time is finished for today.');
  });

  test('integer parsing is defensive', () {
    expect(asInt('42'), 42);
    expect(asInt(null, 7), 7);
  });
}
