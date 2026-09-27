import 'package:stage5/features/exercises/data/youtube_channel_preference_contract.dart';
import 'package:stage5/features/exercises/data/youtube_channel_preference_stub.dart'
    if (dart.library.html) 'package:stage5/features/exercises/data/youtube_channel_preference_web.dart'
    as implementation;

export 'package:stage5/features/exercises/data/youtube_channel_preference_contract.dart';

YoutubeChannelPreference createYoutubeChannelPreference() {
  return implementation.createYoutubeChannelPreference();
}
