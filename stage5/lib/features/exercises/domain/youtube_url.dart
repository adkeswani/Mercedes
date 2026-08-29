/// Pure-Dart helpers for recognizing YouTube video URLs.
library;

/// Extracts the 11-character YouTube video id from a [url], or returns null
/// when [url] is not a recognizable YouTube link.
///
/// Supports the common forms:
/// - `https://www.youtube.com/watch?v=<id>`
/// - `https://youtu.be/<id>`
/// - `https://www.youtube.com/embed/<id>`
/// - `https://www.youtube.com/shorts/<id>`
/// - `https://www.youtube.com/v/<id>`
String? extractYoutubeId(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;

  final host = uri.host.toLowerCase();

  if (host.endsWith('youtu.be')) {
    final id = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    return _validId(id);
  }

  if (host.endsWith('youtube.com') || host.endsWith('youtube-nocookie.com')) {
    final v = uri.queryParameters['v'];
    if (v != null) return _validId(v);

    final segments = uri.pathSegments;
    final keywordIndex = segments.indexWhere(
      (s) => s == 'embed' || s == 'shorts' || s == 'v',
    );
    if (keywordIndex != -1 && keywordIndex + 1 < segments.length) {
      return _validId(segments[keywordIndex + 1]);
    }
  }

  return null;
}

/// Returns true when [url] is a recognizable YouTube link.
bool isYoutubeUrl(String url) => extractYoutubeId(url) != null;

String? _validId(String? id) {
  if (id == null) return null;
  return RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ? id : null;
}
