import 'dart:html' as html;

import 'package:stage5/features/exercises/data/youtube_channel_preference_contract.dart';

YoutubeChannelPreference createYoutubeChannelPreference() {
  return BrowserYoutubeChannelPreference();
}

class BrowserYoutubeChannelPreference implements YoutubeChannelPreference {
  static const _key = 'mercedes.youtube.publicChannel.lastReference';

  @override
  Future<String?> read() async => html.window.localStorage[_key];

  @override
  Future<void> write(String value) async {
    html.window.localStorage[_key] = value.trim();
  }
}
