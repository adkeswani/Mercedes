import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:stage5/core/browser_smoke_config.dart';

const releaseCanaryLoginCompiledIn = bool.fromEnvironment(
  'ENABLE_RELEASE_CANARY_LOGIN',
);

bool isReleaseCanaryRequest({
  required bool compiledIn,
  required bool isWeb,
  required Uri location,
}) {
  return compiledIn &&
      isWeb &&
      location.queryParameters['release-canary'] == '1';
}

bool get releaseCanaryMode => isReleaseCanaryRequest(
  compiledIn: releaseCanaryLoginCompiledIn,
  isWeb: kIsWeb,
  location: Uri.base,
);

bool get browserAutomationEnabled =>
    browserSmokeConfig.autoLoginEnabled || releaseCanaryMode;

bool isReleaseCanaryEmail(String email) {
  final normalized = email.trim().toLowerCase();
  final separator = normalized.indexOf('@');
  return separator > 0 &&
      normalized.substring(0, separator).startsWith('release-canary-');
}

const releaseCanaryEmailFieldKey = Key('release-canary-email');
const releaseCanaryPasswordFieldKey = Key('release-canary-password');
const releaseCanaryLoginButtonKey = Key('release-canary-login');
