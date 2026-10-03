import 'package:flutter/foundation.dart';

import 'package:stage5/core/release_canary_youtube_bridge_contract.dart';

VoidCallback registerReleaseCanaryYoutubeBridge({
  required bool enabled,
  required ReleaseCanaryYoutubeActionResult Function(
    String action,
    String videoId,
  ) onAction,
}) {
  return () {};
}
