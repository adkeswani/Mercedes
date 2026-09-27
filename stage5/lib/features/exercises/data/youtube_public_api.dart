import 'package:cloud_functions/cloud_functions.dart';

import 'package:stage5/features/exercises/domain/youtube_channel.dart';

abstract interface class YoutubePublicApi {
  Future<PublicYoutubeChannel> resolveChannel(String input);

  Future<PublicYoutubeVideoPage> loadVideos({
    required String channelId,
    String? pageToken,
    int maxResults = 25,
  });
}

class FirebaseYoutubePublicApi implements YoutubePublicApi {
  FirebaseYoutubePublicApi({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  @override
  Future<PublicYoutubeChannel> resolveChannel(String input) async {
    final callable = _functions.httpsCallable('youtubePublicLibrary');
    final result = await callable.call<Map<String, dynamic>>({
      'action': 'resolve',
      'channel': input.trim(),
    });
    return PublicYoutubeChannel.fromMap(
      Map<String, dynamic>.from(result.data['channel'] as Map),
    );
  }

  @override
  Future<PublicYoutubeVideoPage> loadVideos({
    required String channelId,
    String? pageToken,
    int maxResults = 25,
  }) async {
    final callable = _functions.httpsCallable('youtubePublicLibrary');
    final result = await callable.call<Map<String, dynamic>>({
      'action': 'videos',
      'channelId': channelId,
      'pageToken': pageToken,
      'maxResults': maxResults,
    });
    return PublicYoutubeVideoPage.fromMap(result.data);
  }
}

class FakeYoutubePublicApi implements YoutubePublicApi {
  const FakeYoutubePublicApi();

  static const channel = PublicYoutubeChannel(
    id: 'UCaaaaaaaaaaaaaaaaaaaaaa',
    title: 'Release Canary Public Channel',
    uploadsPlaylistId: 'UUaaaaaaaaaaaaaaaaaaaaaa',
    avatarUrl: null,
  );

  static final videos = <PublicYoutubeVideo>[
    PublicYoutubeVideo(
      id: 'canaryVid01',
      title: 'Release Canary Deadlift',
      thumbnailUrl: '',
      channelId: channel.id,
      channelTitle: channel.title,
      publishedAt: DateTime.utc(2026, 9, 20),
      viewCount: 4100,
    ),
    PublicYoutubeVideo(
      id: 'canaryVid02',
      title: 'Release Canary Squat',
      thumbnailUrl: '',
      channelId: channel.id,
      channelTitle: channel.title,
      publishedAt: DateTime.utc(2026, 9, 10),
      viewCount: 8200,
    ),
    PublicYoutubeVideo(
      id: 'canaryVid03',
      title: 'Release Canary Press',
      thumbnailUrl: '',
      channelId: channel.id,
      channelTitle: channel.title,
      publishedAt: DateTime.utc(2026, 8, 30),
      viewCount: 1200,
    ),
  ];

  @override
  Future<PublicYoutubeChannel> resolveChannel(String input) async {
    if (parseYoutubeChannelReference(input) == null &&
        input.trim() != 'release-canary') {
      throw StateError('Public YouTube channel was not found');
    }
    return channel;
  }

  @override
  Future<PublicYoutubeVideoPage> loadVideos({
    required String channelId,
    String? pageToken,
    int maxResults = 25,
  }) async {
    if (channelId != channel.id) {
      throw StateError('Public YouTube channel was not found');
    }
    return PublicYoutubeVideoPage(
      videos: pageToken == null ? videos : const [],
      nextPageToken: null,
    );
  }
}
