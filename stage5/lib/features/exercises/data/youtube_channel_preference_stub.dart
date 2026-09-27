import 'package:stage5/features/exercises/data/youtube_channel_preference_contract.dart';

YoutubeChannelPreference createYoutubeChannelPreference() {
  return MemoryYoutubeChannelPreference();
}

class MemoryYoutubeChannelPreference implements YoutubeChannelPreference {
  static String? _value;

  @override
  Future<String?> read() async => _value;

  @override
  Future<void> write(String value) async {
    _value = value.trim();
  }
}
