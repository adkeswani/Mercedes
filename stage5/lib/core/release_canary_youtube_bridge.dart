import 'package:flutter/foundation.dart';

import 'package:stage5/core/release_canary_youtube_bridge_contract.dart';
import 'package:stage5/core/release_canary_youtube_bridge_stub.dart'
    if (dart.library.html) 'package:stage5/core/release_canary_youtube_bridge_web.dart'
    as implementation;

typedef ReleaseCanaryYoutubeActionHandler = ReleaseCanaryYoutubeActionResult
    Function(
  String action,
  String videoId,
);

VoidCallback registerReleaseCanaryYoutubeBridge({
  required bool enabled,
  required ReleaseCanaryYoutubeActionHandler onAction,
}) {
  return implementation.registerReleaseCanaryYoutubeBridge(
    enabled: enabled,
    onAction: onAction,
  );
}
