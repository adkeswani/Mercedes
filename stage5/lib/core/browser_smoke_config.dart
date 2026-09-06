import 'package:flutter/foundation.dart';

enum BrowserSmokeIdentityRole {
  trainer,
  athlete;

  static BrowserSmokeIdentityRole? parse(String value) {
    return switch (value) {
      'trainer' => trainer,
      'athlete' => athlete,
      _ => null,
    };
  }
}

/// Compile-time configuration for the local browser login smoke test.
///
/// The test seam requires both a debug build and explicit emulator flags, so
/// it cannot be enabled in a production release build.
class BrowserSmokeConfig {
  const BrowserSmokeConfig({
    required this.email,
    required this.enableLogin,
    required this.identityRoleName,
    required this.isDebugBuild,
    required this.password,
    required this.useFirebaseEmulators,
  });

  final String email;
  final bool enableLogin;
  final String identityRoleName;
  final bool isDebugBuild;
  final String password;
  final bool useFirebaseEmulators;

  bool get emulatorsEnabled => isDebugBuild && useFirebaseEmulators;

  BrowserSmokeIdentityRole? get identityRole =>
      BrowserSmokeIdentityRole.parse(identityRoleName);

  bool get loginEnabled =>
      emulatorsEnabled &&
      enableLogin &&
      identityRole != null &&
      email.isNotEmpty &&
      password.isNotEmpty;
}

const browserSmokeConfig = BrowserSmokeConfig(
  email: String.fromEnvironment('BROWSER_SMOKE_EMAIL'),
  enableLogin: bool.fromEnvironment('BROWSER_LOGIN_SMOKE'),
  identityRoleName: String.fromEnvironment('BROWSER_SMOKE_ROLE'),
  isDebugBuild: kDebugMode,
  password: String.fromEnvironment('BROWSER_SMOKE_PASSWORD'),
  useFirebaseEmulators: bool.fromEnvironment('USE_FIREBASE_EMULATORS'),
);

const browserSmokeLoginButtonKey = Key('browser-smoke-login');
const authenticatedAppEntryKey = Key('authenticated-app-entry');
