enum YoutubeChannelReferenceType { channelId, handle, username }

class YoutubeChannelReference {
  const YoutubeChannelReference({required this.type, required this.value});

  final YoutubeChannelReferenceType type;
  final String value;
}

YoutubeChannelReference? parseYoutubeChannelReference(String input) {
  final value = input.trim();
  if (RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(value)) {
    return YoutubeChannelReference(
      type: YoutubeChannelReferenceType.channelId,
      value: value,
    );
  }
  if (RegExp(r'^@[A-Za-z0-9._-]{3,30}$').hasMatch(value)) {
    return YoutubeChannelReference(
      type: YoutubeChannelReferenceType.handle,
      value: value.substring(1),
    );
  }

  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'https' && uri.scheme != 'http') ||
      !_isYoutubeHost(uri.host)) {
    return null;
  }
  final segments = uri.pathSegments.where((segment) => segment.isNotEmpty);
  if (segments.isEmpty) {
    return null;
  }
  final path = segments.toList();
  if (path.length == 2 &&
      path.first == 'channel' &&
      RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(path[1])) {
    return YoutubeChannelReference(
      type: YoutubeChannelReferenceType.channelId,
      value: path[1],
    );
  }
  if (path.length == 1 &&
      RegExp(r'^@[A-Za-z0-9._-]{3,30}$').hasMatch(path.first)) {
    return YoutubeChannelReference(
      type: YoutubeChannelReferenceType.handle,
      value: path.first.substring(1),
    );
  }
  if (path.length == 2 &&
      (path.first == 'user' || path.first == 'c') &&
      RegExp(r'^[A-Za-z0-9._-]{1,100}$').hasMatch(path[1])) {
    return YoutubeChannelReference(
      type: YoutubeChannelReferenceType.username,
      value: path[1],
    );
  }
  return null;
}

bool _isYoutubeHost(String host) {
  final normalized = host.toLowerCase();
  return normalized == 'youtube.com' ||
      normalized == 'www.youtube.com' ||
      normalized == 'm.youtube.com';
}

class PublicYoutubeChannel {
  const PublicYoutubeChannel({
    required this.id,
    required this.title,
    required this.uploadsPlaylistId,
    this.avatarUrl,
  });

  factory PublicYoutubeChannel.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? '';
    final title = map['title'] as String? ?? '';
    final uploadsPlaylistId = map['uploadsPlaylistId'] as String? ?? '';
    if (!RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(id) ||
        title.trim().isEmpty ||
        uploadsPlaylistId.trim().isEmpty) {
      throw const FormatException('Malformed YouTube channel response');
    }
    final avatarUrl = _validatedYoutubeImageUrl(
      map['avatarUrl'],
      allowAvatar: true,
    );
    return PublicYoutubeChannel(
      id: id,
      title: title.trim(),
      uploadsPlaylistId: uploadsPlaylistId,
      avatarUrl: avatarUrl,
    );
  }

  final String id;
  final String title;
  final String uploadsPlaylistId;
  final String? avatarUrl;
}

class PublicYoutubeVideo {
  const PublicYoutubeVideo({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.channelId,
    required this.channelTitle,
    required this.publishedAt,
    this.viewCount,
  });

  factory PublicYoutubeVideo.fromMap(Map<String, dynamic> map) {
    final id = map['id'] as String? ?? '';
    final title = map['title'] as String? ?? '';
    final channelId = map['channelId'] as String? ?? '';
    final channelTitle = map['channelTitle'] as String? ?? '';
    final publishedAt = DateTime.tryParse(map['publishedAt'] as String? ?? '');
    final rawViewCount = map['viewCount'];
    final thumbnailUrl = _validatedYoutubeImageUrl(map['thumbnailUrl']);
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id) ||
        title.trim().isEmpty ||
        !RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(channelId) ||
        channelTitle.trim().isEmpty ||
        publishedAt == null) {
      throw const FormatException('Malformed YouTube video response');
    }
    return PublicYoutubeVideo(
      id: id,
      title: title.trim(),
      thumbnailUrl: thumbnailUrl,
      channelId: channelId,
      channelTitle: channelTitle.trim(),
      publishedAt: publishedAt.toUtc(),
      viewCount: rawViewCount is int
          ? rawViewCount
          : int.tryParse(rawViewCount?.toString() ?? ''),
    );
  }

  final String id;
  final String title;
  final String thumbnailUrl;
  final String channelId;
  final String channelTitle;
  final DateTime publishedAt;
  final int? viewCount;

  String get canonicalUrl => 'https://www.youtube.com/watch?v=$id';

  YoutubeVideoMetadata get metadata => YoutubeVideoMetadata(
        videoId: id,
        title: title,
        thumbnailUrl: thumbnailUrl,
        channelId: channelId,
        channelTitle: channelTitle,
      );
}

class YoutubeVideoMetadata {
  const YoutubeVideoMetadata({
    required this.videoId,
    required this.title,
    required this.thumbnailUrl,
    required this.channelId,
    required this.channelTitle,
  });

  final String videoId;
  final String title;
  final String thumbnailUrl;
  final String channelId;
  final String channelTitle;
  String get canonicalUrl => 'https://www.youtube.com/watch?v=$videoId';

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(videoId) ||
        title.trim().isEmpty ||
        _validatedYoutubeImageUrl(thumbnailUrl) != thumbnailUrl ||
        !RegExp(r'^UC[A-Za-z0-9_-]{22}$').hasMatch(channelId) ||
        channelTitle.trim().isEmpty) {
      throw ArgumentError('Invalid YouTube video metadata');
    }
  }
}

String _validatedYoutubeImageUrl(
  Object? value, {
  bool allowAvatar = false,
}) {
  if (value == null || value == '') {
    return '';
  }
  if (value is! String) {
    throw const FormatException('Malformed YouTube image URL');
  }
  final uri = Uri.tryParse(value);
  final host = uri?.host.toLowerCase();
  if (uri?.scheme != 'https' ||
      (host != 'i.ytimg.com' &&
          !(allowAvatar &&
              (host == 'yt3.ggpht.com' ||
                  (host?.endsWith('.googleusercontent.com') ?? false))))) {
    throw const FormatException('Malformed YouTube image URL');
  }
  return uri.toString();
}

class PublicYoutubeVideoPage {
  const PublicYoutubeVideoPage({
    required this.videos,
    required this.nextPageToken,
    this.status = YoutubeCatalogueStatus.ready,
    this.indexedCount = 0,
    this.videoCount = 0,
    this.complete = true,
    this.stale = false,
    this.lastRefreshedAt,
    this.refreshAfter,
  });

  factory PublicYoutubeVideoPage.fromMap(Map<String, dynamic> map) {
    final rawVideos = map['videos'];
    if (rawVideos is! List) {
      throw const FormatException('Malformed YouTube videos response');
    }
    return PublicYoutubeVideoPage(
      videos: rawVideos
          .map(
            (video) => PublicYoutubeVideo.fromMap(
              Map<String, dynamic>.from(video as Map),
            ),
          )
          .toList(growable: false),
      nextPageToken: map['nextPageToken'] as String?,
      status: YoutubeCatalogueStatus.values.firstWhere(
        (status) => status.name == map['status'],
        orElse: () => YoutubeCatalogueStatus.ready,
      ),
      indexedCount: map['indexedCount'] as int? ?? 0,
      videoCount: map['videoCount'] as int? ?? 0,
      complete: map['complete'] as bool? ?? true,
      stale: map['stale'] as bool? ?? false,
      lastRefreshedAt: DateTime.tryParse(
        map['lastRefreshedAt'] as String? ?? '',
      )?.toUtc(),
      refreshAfter: DateTime.tryParse(
        map['refreshAfter'] as String? ?? '',
      )?.toUtc(),
    );
  }

  final List<PublicYoutubeVideo> videos;
  final String? nextPageToken;
  final YoutubeCatalogueStatus status;
  final int indexedCount;
  final int videoCount;
  final bool complete;
  final bool stale;
  final DateTime? lastRefreshedAt;
  final DateTime? refreshAfter;
}

enum YoutubeCatalogueStatus { indexing, ready, error }

enum YoutubeVideoSort { newest, oldest, title, viewCount }

List<PublicYoutubeVideo> filterAndSortYoutubeVideos(
  Iterable<PublicYoutubeVideo> videos, {
  String query = '',
  YoutubeVideoSort sort = YoutubeVideoSort.newest,
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final result = videos
      .where(
        (video) =>
            normalizedQuery.isEmpty ||
            video.title.toLowerCase().contains(normalizedQuery) ||
            video.channelTitle.toLowerCase().contains(normalizedQuery),
      )
      .toList();
  result.sort((left, right) {
    return switch (sort) {
      YoutubeVideoSort.newest => right.publishedAt.compareTo(left.publishedAt),
      YoutubeVideoSort.oldest => left.publishedAt.compareTo(right.publishedAt),
      YoutubeVideoSort.title => left.title.toLowerCase().compareTo(
            right.title.toLowerCase(),
          ),
      YoutubeVideoSort.viewCount => (right.viewCount ?? -1).compareTo(
          left.viewCount ?? -1,
        ),
    };
  });
  return result;
}

List<PublicYoutubeVideo> appendYoutubePage(
  Iterable<PublicYoutubeVideo> existing,
  Iterable<PublicYoutubeVideo> next,
) {
  final byId = <String, PublicYoutubeVideo>{
    for (final video in existing) video.id: video,
  };
  for (final video in next) {
    byId[video.id] = video;
  }
  return byId.values.toList(growable: false);
}
