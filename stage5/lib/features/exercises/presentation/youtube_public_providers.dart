import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/features/exercises/data/youtube_channel_preference.dart';
import 'package:stage5/features/exercises/data/youtube_public_api.dart';

const fakeYoutubeCatalogueEnabled = bool.fromEnvironment(
  'FAKE_PUBLIC_YOUTUBE_CATALOGUE',
);

final youtubePublicApiProvider = Provider<YoutubePublicApi>((ref) {
  return fakeYoutubeCatalogueEnabled
      ? const FakeYoutubePublicApi()
      : FirebaseYoutubePublicApi();
});

final youtubeChannelPreferenceProvider = Provider<YoutubeChannelPreference>(
  (ref) => createYoutubeChannelPreference(),
);
