import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/features/exercises/data/youtube_channel_preference.dart';
import 'package:stage5/features/exercises/data/youtube_public_api.dart';

final youtubePublicApiProvider = Provider<YoutubePublicApi>((ref) {
  return releaseCanaryYoutubeCatalogueCompiledIn
      ? const FakeYoutubePublicApi()
      : FirebaseYoutubePublicApi();
});

final youtubeChannelPreferenceProvider = Provider<YoutubeChannelPreference>(
  (ref) => createYoutubeChannelPreference(),
);
