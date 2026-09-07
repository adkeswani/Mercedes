import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/core/browser_smoke_config.dart';

void main() {
  const email = 'browser-smoke@mercedes.test';
  const password = 'BrowserSmoke123!';

  test('login seam is disabled in production builds', () {
    const config = BrowserSmokeConfig(
      autoLogin: true,
      email: email,
      enableLogin: true,
      identityRoleName: 'trainer',
      isDebugBuild: false,
      password: password,
      useFirebaseEmulators: true,
    );

    expect(config.emulatorsEnabled, isFalse);
    expect(config.loginEnabled, isFalse);
  });

  test('login seam requires explicit emulator and login flags', () {
    const noEmulator = BrowserSmokeConfig(
      autoLogin: true,
      email: email,
      enableLogin: true,
      identityRoleName: 'trainer',
      isDebugBuild: true,
      password: password,
      useFirebaseEmulators: false,
    );
    const noLoginFlag = BrowserSmokeConfig(
      autoLogin: true,
      email: email,
      enableLogin: false,
      identityRoleName: 'trainer',
      isDebugBuild: true,
      password: password,
      useFirebaseEmulators: true,
    );

    expect(noEmulator.loginEnabled, isFalse);
    expect(noLoginFlag.loginEnabled, isFalse);
  });

  test('login seam requires non-empty deterministic credentials', () {
    const config = BrowserSmokeConfig(
      autoLogin: true,
      email: '',
      enableLogin: true,
      identityRoleName: 'trainer',
      isDebugBuild: true,
      password: '',
      useFirebaseEmulators: true,
    );

    expect(config.loginEnabled, isFalse);
  });

  test('debug emulator configuration enables the login seam', () {
    const config = BrowserSmokeConfig(
      autoLogin: true,
      email: email,
      enableLogin: true,
      identityRoleName: 'trainer',
      isDebugBuild: true,
      password: password,
      useFirebaseEmulators: true,
    );

    expect(config.emulatorsEnabled, isTrue);
    expect(config.loginEnabled, isTrue);
    expect(config.identityRole, BrowserSmokeIdentityRole.trainer);
  });

  test('athlete role enables the same emulator-only seam', () {
    const config = BrowserSmokeConfig(
      autoLogin: true,
      email: 'browser-smoke-athlete@mercedes.test',
      enableLogin: true,
      identityRoleName: 'athlete',
      isDebugBuild: true,
      password: password,
      useFirebaseEmulators: true,
    );

    expect(config.loginEnabled, isTrue);
    expect(config.identityRole, BrowserSmokeIdentityRole.athlete);
  });

  test('unknown identity role disables the login seam', () {
    const config = BrowserSmokeConfig(
      autoLogin: true,
      email: email,
      enableLogin: true,
      identityRoleName: 'admin',
      isDebugBuild: true,
      password: password,
      useFirebaseEmulators: true,
    );

    expect(config.identityRole, isNull);
    expect(config.loginEnabled, isFalse);
  });

  test('automatic login requires the fully enabled smoke seam', () {
    const enabled = BrowserSmokeConfig(
      autoLogin: true,
      email: email,
      enableLogin: true,
      identityRoleName: 'trainer',
      isDebugBuild: true,
      password: password,
      useFirebaseEmulators: true,
    );
    const disabled = BrowserSmokeConfig(
      autoLogin: false,
      email: email,
      enableLogin: true,
      identityRoleName: 'trainer',
      isDebugBuild: true,
      password: password,
      useFirebaseEmulators: true,
    );

    expect(enabled.autoLoginEnabled, isTrue);
    expect(disabled.autoLoginEnabled, isFalse);
  });
}
