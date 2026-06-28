import 'package:flutter/widgets.dart';

import 'package:stage4/features/exercises/presentation/youtube_embed_mobile.dart'
    if (dart.library.js_interop) 'package:stage4/features/exercises/presentation/youtube_embed_web.dart';

/// Builds an embedded YouTube player for the given 11-character [videoId].
///
/// The implementation is platform-specific (see the conditional import):
/// - On web, a native `<iframe>` is embedded via `HtmlElementView`, which
///   renders the YouTube player reliably.
/// - On other platforms, the `youtube_player_iframe` package is used.
Widget buildYoutubeEmbed(String videoId) => buildYoutubeEmbedImpl(videoId);
