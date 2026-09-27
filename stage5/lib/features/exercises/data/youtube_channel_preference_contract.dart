abstract interface class YoutubeChannelPreference {
  Future<String?> read();

  Future<void> write(String value);
}
