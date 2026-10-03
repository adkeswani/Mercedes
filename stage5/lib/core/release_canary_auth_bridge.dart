import 'package:flutter/foundation.dart';

import 'package:stage5/core/release_canary_auth_bridge_stub.dart'
    if (dart.library.html) 'package:stage5/core/release_canary_auth_bridge_web.dart'
    as implementation;

typedef ReleaseCanaryAuthHandler = bool Function(
  String email,
  String password,
);

VoidCallback registerReleaseCanaryAuthBridge({
  required bool enabled,
  required ReleaseCanaryAuthHandler onSignIn,
}) {
  return implementation.registerReleaseCanaryAuthBridge(
    enabled: enabled,
    onSignIn: onSignIn,
  );
}
