import 'package:flutter_test/flutter_test.dart';
import 'package:stage5/core/browser_smoke_config.dart';
import 'package:stage5/core/release_canary_config.dart';

void main() {
  test('surface diagnostics support manual login without enabling auto login',
      () {
    for (final autoLogin in [false, true]) {
      final config = BrowserSmokeConfig(
        autoLogin: autoLogin,
        email: 'browser-smoke-trainer@mercedes.test',
        enableLogin: true,
        identityRoleName: 'trainer',
        isDebugBuild: true,
        password: 'BrowserSmoke123!',
        useFirebaseEmulators: true,
      );
      expect(
        isBrowserAutomationEnabled(smokeConfig: config, releaseCanary: false),
        isTrue,
      );
      expect(config.autoLoginEnabled, autoLogin);
    }
  });

  test('surface diagnostics retain debug, emulator, and login boundaries', () {
    for (final disabledFlag in ['debug', 'emulators', 'login']) {
      final config = BrowserSmokeConfig(
        autoLogin: false,
        email: 'browser-smoke-trainer@mercedes.test',
        enableLogin: disabledFlag != 'login',
        identityRoleName: 'trainer',
        isDebugBuild: disabledFlag != 'debug',
        password: 'BrowserSmoke123!',
        useFirebaseEmulators: disabledFlag != 'emulators',
      );
      expect(
        isBrowserAutomationEnabled(smokeConfig: config, releaseCanary: false),
        isFalse,
      );
      expect(
        isBrowserAutomationEnabled(smokeConfig: config, releaseCanary: true),
        isTrue,
      );
    }
  });
}
