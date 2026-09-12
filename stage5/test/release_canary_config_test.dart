import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/release_canary_config.dart';

void main() {
  test('release canary requires compile flag, web, and URL opt-in', () {
    expect(
      isReleaseCanaryRequest(
        compiledIn: true,
        isWeb: true,
        location: Uri.parse('https://staging.example.test/?release-canary=1'),
      ),
      isTrue,
    );
    expect(
      isReleaseCanaryRequest(
        compiledIn: false,
        isWeb: true,
        location: Uri.parse('https://staging.example.test/?release-canary=1'),
      ),
      isFalse,
    );
    expect(
      isReleaseCanaryRequest(
        compiledIn: true,
        isWeb: false,
        location: Uri.parse('https://staging.example.test/?release-canary=1'),
      ),
      isFalse,
    );
    expect(
      isReleaseCanaryRequest(
        compiledIn: true,
        isWeb: true,
        location: Uri.parse('https://staging.example.test/'),
      ),
      isFalse,
    );
  });

  test('release canary email must use reserved namespace', () {
    expect(isReleaseCanaryEmail('release-canary-athlete@example.test'), isTrue);
    expect(
      isReleaseCanaryEmail(' Release-Canary-Trainer@example.test '),
      isTrue,
    );
    expect(isReleaseCanaryEmail('person@example.test'), isFalse);
    expect(isReleaseCanaryEmail('release-canary-without-domain'), isFalse);
  });
}
