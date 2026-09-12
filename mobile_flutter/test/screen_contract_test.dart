import 'package:flutter_test/flutter_test.dart';
import 'package:littlenet_native/screen_contract.dart';

void main() {
  test('canonical Stitch contract contains exactly 61 unique states', () {
    expect(littleNetScreenContract, hasLength(61));
    expect(littleNetScreenContract.map((screen) => screen.id).toSet(), hasLength(61));
    expect(littleNetScreenContract.first.id, 1);
    expect(littleNetScreenContract.last.id, 61);
  });

  test('intentional inline/reused states stay explicit', () {
    expect(littleNetScreen(9).inlineWith, 8);
    expect(littleNetScreen(21).inlineWith, 11);
  });

  test('all three product experiences remain represented', () {
    expect(
      littleNetScreenContract.any((s) => s.experience == LittleNetExperience.kids),
      isTrue,
    );
    expect(
      littleNetScreenContract.any((s) => s.experience == LittleNetExperience.parent),
      isTrue,
    );
    expect(
      littleNetScreenContract.any((s) => s.experience == LittleNetExperience.admin),
      isTrue,
    );
  });
}
