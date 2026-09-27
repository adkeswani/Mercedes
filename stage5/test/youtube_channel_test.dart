import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/exercises/domain/youtube_channel.dart';

void main() {
  const channelId = 'UCaaaaaaaaaaaaaaaaaaaaaa';

  test('normalizes supported channel IDs, handles, and URLs', () {
    expect(
      parseYoutubeChannelReference(channelId)!.type,
      YoutubeChannelReferenceType.channelId,
    );
    expect(
      parseYoutubeChannelReference('@public.trainer')!.value,
      'public.trainer',
    );
    expect(
      parseYoutubeChannelReference(
        'https://www.youtube.com/channel/$channelId',
      )!
          .value,
      channelId,
    );
    expect(
      parseYoutubeChannelReference('https://youtube.com/c/LegacyTrainer')!.type,
      YoutubeChannelReferenceType.username,
    );
  });

  test('rejects invalid hosts and malformed channel inputs', () {
    expect(
      parseYoutubeChannelReference(
        'https://youtube.example.com/channel/$channelId',
      ),
      isNull,
    );
    expect(
      parseYoutubeChannelReference('https://example.com/@public.trainer'),
      isNull,
    );
    expect(parseYoutubeChannelReference('@a'), isNull);
  });

  test('maps validated pages and rejects malformed upstream values', () {
    final page = PublicYoutubeVideoPage.fromMap({
      'videos': [
        {
          'id': 'videoId0001',
          'title': 'Squat',
          'thumbnailUrl': 'https://img.example/squat.jpg',
          'channelId': channelId,
          'channelTitle': 'Public Trainer',
          'publishedAt': '2026-09-20T00:00:00.000Z',
          'viewCount': 42,
        },
      ],
      'nextPageToken': 'NEXT',
    });
    expect(page.videos.single.canonicalUrl,
        'https://www.youtube.com/watch?v=videoId0001');
    expect(page.nextPageToken, 'NEXT');
    expect(
      () => PublicYoutubeVideoPage.fromMap({
        'videos': [
          {
            'id': '../invalid',
            'title': 'Bad',
            'channelId': channelId,
            'channelTitle': 'Public Trainer',
            'publishedAt': '2026-09-20T00:00:00Z',
          },
        ],
      }),
      throwsFormatException,
    );
  });

  test('searches and sorts the complete loaded catalogue', () {
    final videos = [
      _video(
        id: 'videoId0001',
        title: 'Zebra Squat',
        publishedAt: DateTime.utc(2026, 9, 1),
        views: 20,
      ),
      _video(
        id: 'videoId0002',
        title: 'Alpha Press',
        publishedAt: DateTime.utc(2026, 9, 2),
        views: 10,
      ),
      _video(
        id: 'videoId0003',
        title: 'Middle Row',
        publishedAt: DateTime.utc(2026, 9, 3),
      ),
    ];
    expect(
      filterAndSortYoutubeVideos(videos).map((video) => video.id),
      ['videoId0003', 'videoId0002', 'videoId0001'],
    );
    expect(
      filterAndSortYoutubeVideos(
        videos,
        sort: YoutubeVideoSort.title,
      ).map((video) => video.title),
      ['Alpha Press', 'Middle Row', 'Zebra Squat'],
    );
    expect(
      filterAndSortYoutubeVideos(
        videos,
        sort: YoutubeVideoSort.viewCount,
      ).map((video) => video.id),
      ['videoId0001', 'videoId0002', 'videoId0003'],
    );
    expect(
      filterAndSortYoutubeVideos(videos, query: 'press').single.id,
      'videoId0002',
    );
  });

  test('appends pages without duplicating videos', () {
    final first = _video(
      id: 'videoId0001',
      title: 'First',
      publishedAt: DateTime.utc(2026),
    );
    final replacement = _video(
      id: 'videoId0001',
      title: 'Updated',
      publishedAt: DateTime.utc(2026),
    );
    final second = _video(
      id: 'videoId0002',
      title: 'Second',
      publishedAt: DateTime.utc(2026),
    );
    final merged = appendYoutubePage([first], [replacement, second]);
    expect(merged.length, 2);
    expect(merged.first.title, 'Updated');
  });
}

PublicYoutubeVideo _video({
  required String id,
  required String title,
  required DateTime publishedAt,
  int? views,
}) {
  return PublicYoutubeVideo(
    id: id,
    title: title,
    thumbnailUrl: '',
    channelId: 'UCaaaaaaaaaaaaaaaaaaaaaa',
    channelTitle: 'Public Trainer',
    publishedAt: publishedAt,
    viewCount: views,
  );
}
