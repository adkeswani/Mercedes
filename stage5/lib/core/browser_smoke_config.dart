import 'package:flutter/foundation.dart';

/// Compile-time configuration for the local browser login smoke test.
///
/// The test seam requires both a debug build and explicit emulator flags, so
/// it cannot be enabled in a production release build.
class BrowserSmokeConfig {
  const BrowserSmokeConfig({
    required this.email,
    required this.enableLogin,
    required this.isDebugBuild,
    required this.password,
    required this.useFirebaseEmulators,
  });

  final String email;
  final bool enableLogin;
  final bool isDebugBuild;
  final String password;
  final bool useFirebaseEmulators;

  bool get emulatorsEnabled => isDebugBuild && useFirebaseEmulators;

  bool get loginEnabled =>
      emulatorsEnabled &&
      enableLogin &&
      email.isNotEmpty &&
      password.isNotEmpty;
}

const browserSmokeConfig = BrowserSmokeConfig(
  email: String.fromEnvironment('BROWSER_SMOKE_EMAIL'),
  enableLogin: bool.fromEnvironment('BROWSER_LOGIN_SMOKE'),
  isDebugBuild: kDebugMode,
  password: String.fromEnvironment('BROWSER_SMOKE_PASSWORD'),
  useFirebaseEmulators: bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
);

const browserSmokeLoginButtonKey = Key('browser-smoke-login');
const authenticatedAppEntryKey = Key('authenticated-app-entry');
