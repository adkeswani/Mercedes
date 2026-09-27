import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/exercises/data/youtube_channel_preference.dart';
import 'package:stage5/features/exercises/data/youtube_public_api.dart';
import 'package:stage5/features/exercises/domain/youtube_channel.dart';
import 'package:stage5/features/exercises/presentation/youtube_library_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders loading, error, empty, and populated channel states',
      (tester) async {
    final completer = Completer<PublicYoutubeChannel>();
    final api = _FakeApi(resolve: (_) => completer.future);
    await _pumpPanel(tester, api: api);
    await tester.enterText(
      find.byKey(youtubeChannelFieldKey),
      '@public.trainer',
    );
    await tester.tap(find.byKey(youtubeLoadChannelKey));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    completer.complete(_channel);
    await tester.pumpAndSettle();
    expect(find.text(_channel.title), findsOneWidget);
    expect(find.byKey(const Key('youtube-library-empty')), findsOneWidget);

    api.videos = [_first, _second];
    await tester.tap(find.byKey(youtubeLoadChannelKey));
    await tester.pumpAndSettle();
    expect(find.text('2 videos loaded'), findsOneWidget);
    expect(find.text(_first.title), findsOneWidget);

    await tester.enterText(find.byKey(youtubeSearchFieldKey), 'press');
    await tester.pump();
    expect(find.text(_first.title), findsNothing);
    expect(find.text(_second.title), findsOneWidget);

    api.failure = StateError('Public YouTube channel was not found');
    await tester.tap(find.byKey(youtubeLoadChannelKey));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('youtube-library-error')), findsOneWidget);
  });

  testWidgets('pages and applies loaded-only view-count sorting',
      (tester) async {
    final api = _FakeApi(
      videos: [_first],
      nextPageToken: 'NEXT',
      secondPage: [_second],
    );
    await _pumpPanel(tester, api: api);
    await tester.enterText(
      find.byKey(youtubeChannelFieldKey),
      '@public.trainer',
    );
    await tester.tap(find.byKey(youtubeLoadChannelKey));
    await tester.pumpAndSettle();
    expect(find.text('1 videos loaded'), findsOneWidget);

    await tester.tap(find.text('Load next page'));
    await tester.pumpAndSettle();
    expect(find.text('2 videos loaded'), findsOneWidget);
    await tester.tap(find.text('View count'));
    await tester.pumpAndSettle();
    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles[1].title! as Text).data, _first.title);
  });

  testWidgets('drag and Attach invoke the same attachment command',
      (tester) async {
    final api = _FakeApi(videos: [_first]);
    final attached = <YoutubeVideoMetadata>[];
    await _pumpPanel(
      tester,
      api: api,
      onAttach: (video) => attached.add(video.metadata),
      size: const Size(1000, 1000),
    );
    await tester.enterText(
      find.byKey(youtubeChannelFieldKey),
      '@public.trainer',
    );
    await tester.tap(find.byKey(youtubeLoadChannelKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('youtube-attach-videoId0001')));
    await tester.pump();
    await tester.drag(
      find.byKey(const Key('youtube-video-videoId0001')),
      tester.getCenter(find.byKey(youtubeMediaTargetKey)) -
          tester.getCenter(
            find.byKey(const Key('youtube-video-videoId0001')),
          ),
    );
    await tester.pumpAndSettle();

    expect(attached.length, 2);
    expect(attached[0].videoId, attached[1].videoId);
    expect(attached[0].title, attached[1].title);
    expect(attached[0].channelId, attached[1].channelId);
  });

  testWidgets('compact layout offers Attach without drag', (tester) async {
    final api = _FakeApi(videos: [_first]);
    await _pumpPanel(
      tester,
      api: api,
      size: const Size(500, 1000),
    );
    await tester.enterText(
      find.byKey(youtubeChannelFieldKey),
      '@public.trainer',
    );
    await tester.tap(find.byKey(youtubeLoadChannelKey));
    await tester.pumpAndSettle();
    expect(find.byType(Draggable<PublicYoutubeVideo>), findsNothing);
    expect(
      find.byKey(const Key('youtube-attach-videoId0001')),
      findsOneWidget,
    );
  });
}

const _channel = PublicYoutubeChannel(
  id: 'UCaaaaaaaaaaaaaaaaaaaaaa',
  title: 'Public Trainer',
  uploadsPlaylistId: 'UUaaaaaaaaaaaaaaaaaaaaaa',
);

final _first = PublicYoutubeVideo(
  id: 'videoId0001',
  title: 'Squat tutorial',
  thumbnailUrl: '',
  channelId: _channel.id,
  channelTitle: _channel.title,
  publishedAt: DateTime.utc(2026, 9, 20),
  viewCount: 100,
);

final _second = PublicYoutubeVideo(
  id: 'videoId0002',
  title: 'Press tutorial',
  thumbnailUrl: '',
  channelId: _channel.id,
  channelTitle: _channel.title,
  publishedAt: DateTime.utc(2026, 9, 21),
  viewCount: 50,
);

class _FakeApi implements YoutubePublicApi {
  _FakeApi({
    Future<PublicYoutubeChannel> Function(String)? resolve,
    this.videos = const [],
    this.nextPageToken,
    this.secondPage = const [],
  }) : _resolve = resolve;

  final Future<PublicYoutubeChannel> Function(String)? _resolve;
  List<PublicYoutubeVideo> videos;
  final String? nextPageToken;
  final List<PublicYoutubeVideo> secondPage;
  Object? failure;

  @override
  Future<PublicYoutubeVideoPage> loadVideos({
    required String channelId,
    String? pageToken,
    int maxResults = 25,
  }) async {
    if (failure != null) throw failure!;
    return PublicYoutubeVideoPage(
      videos: pageToken == null ? videos : secondPage,
      nextPageToken: pageToken == null ? nextPageToken : null,
    );
  }

  @override
  Future<PublicYoutubeChannel> resolveChannel(String input) async {
    if (failure != null) throw failure!;
    final resolve = _resolve;
    if (resolve != null) {
      return resolve(input);
    }
    return _channel;
  }
}

class _MemoryPreference implements YoutubeChannelPreference {
  String? value;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

Future<void> _pumpPanel(
  WidgetTester tester, {
  required YoutubePublicApi api,
  ValueChanged<PublicYoutubeVideo>? onAttach,
  Size size = const Size(900, 1000),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: YoutubeLibraryPanel(
              api: api,
              preference: _MemoryPreference(),
              onAttach: onAttach ?? (_) {},
              onRemove: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
