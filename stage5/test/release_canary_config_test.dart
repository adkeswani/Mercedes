import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/core/release_canary_youtube_bridge_contract.dart';

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

  test('YouTube action bridge requires every debug emulator canary gate', () {
    final location = Uri.parse('http://127.0.0.1:8080/?release-canary=1');
    bool enabled({
      bool isDebugBuild = true,
      bool isWeb = true,
      bool useFirebaseEmulators = true,
      bool releaseCanaryCompiledIn = true,
      bool fakeCatalogueCompiledIn = true,
      Uri? uri,
    }) {
      return isReleaseCanaryYoutubeBridgeEnabled(
        isDebugBuild: isDebugBuild,
        isWeb: isWeb,
        useFirebaseEmulators: useFirebaseEmulators,
        releaseCanaryCompiledIn: releaseCanaryCompiledIn,
        fakeCatalogueCompiledIn: fakeCatalogueCompiledIn,
        location: uri ?? location,
      );
    }

    expect(enabled(), isTrue);
    expect(enabled(isDebugBuild: false), isFalse);
    expect(enabled(isWeb: false), isFalse);
    expect(enabled(useFirebaseEmulators: false), isFalse);
    expect(enabled(releaseCanaryCompiledIn: false), isFalse);
    expect(enabled(fakeCatalogueCompiledIn: false), isFalse);
    expect(enabled(uri: Uri.parse('http://127.0.0.1:8080/')), isFalse);
  });

  test('only active YouTube bridge registration can clear shared status', () {
    final registrations = ReleaseCanaryYoutubeBridgeRegistrations();
    final first = registrations.activate();
    final second = registrations.activate();

    expect(registrations.isActive(first), isFalse);
    expect(registrations.isActive(second), isTrue);
    expect(registrations.deactivate(first), isFalse);
    expect(registrations.isActive(second), isTrue);
    expect(registrations.deactivate(second), isTrue);
    expect(registrations.isActive(second), isFalse);
  });
}
