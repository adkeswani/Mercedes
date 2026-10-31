import 'package:stage5/features/exercises/domain/youtube_url.dart';

const maxClimbingVideoUrlLength = 2048;

String? normalizeClimbingVideoUrl(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return null;
  final uri = Uri.tryParse(text);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      text.length > maxClimbingVideoUrlLength) {
    throw ArgumentError('Enter a valid HTTPS video URL');
  }
  const youtubeHosts = {
    'youtube.com',
    'www.youtube.com',
    'm.youtube.com',
    'youtu.be',
    'www.youtu.be',
    'youtube-nocookie.com',
    'www.youtube-nocookie.com',
  };
  if (youtubeHosts.contains(uri.host.toLowerCase())) {
    final id = extractYoutubeId(text);
    if (id == null) throw ArgumentError('Enter a valid YouTube video URL');
    return 'https://www.youtube.com/watch?v=$id';
  }
  final normalized =
      uri.replace(host: uri.host.toLowerCase()).removeFragment().toString();
  if (!RegExp(
          r'^https://[A-Za-z0-9][A-Za-z0-9.-]*(?::[0-9]+)?(?:[/?][^\s#]*)?$')
      .hasMatch(normalized)) {
    throw ArgumentError('Enter a valid HTTPS video URL');
  }
  return normalized;
}

void validateClimbingVideoUrl(String? value) {
  if (normalizeClimbingVideoUrl(value) != value) {
    throw ArgumentError('Video URL must be canonical');
  }
}
