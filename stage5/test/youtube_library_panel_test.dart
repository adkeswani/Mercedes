import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:stage5/features/exercises/data/youtube_channel_preference.dart';
import 'package:stage5/features/exercises/data/youtube_public_api.dart';
import 'package:stage5/features/exercises/domain/youtube_channel.dart';
import 'package:stage5/features/exercises/presentation/youtube_library_panel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  test('release canary bridge actions use the attachment command', () {
    final attached = <PublicYoutubeVideo>[];
    var cleared = false;
    var saved = false;

    final dragResult = handleReleaseCanaryYoutubeBridgeAction(
      action: 'drag-attach',
      videoId: _first.id,
      videos: [_first],
      onAttach: attached.add,
      onClearSearch: () => cleared = true,
      onSave: () => saved = true,
    );
    final selectResult = handleReleaseCanaryYoutubeBridgeAction(
      action: 'select-attach',
      videoId: _first.id,
      videos: [_first],
      onAttach: attached.add,
      onClearSearch: () => cleared = true,
      onSave: () => saved = true,
    );
    expect(dragResult.accepted, isTrue);
    expect(dragResult.attachedVideoId, _first.id);
    expect(selectResult.accepted, isTrue);
    expect(selectResult.attachedVideoId, _first.id);
    expect(attached, [_first, _first]);
    final clearResult = handleReleaseCanaryYoutubeBridgeAction(
      action: 'clear-search',
      videoId: '',
      videos: [_first],
      onAttach: attached.add,
      onClearSearch: () => cleared = true,
      onSave: () => saved = true,
    );
    expect(clearResult.accepted, isTrue);
    expect(clearResult.attachedVideoId, isNull);
    expect(cleared, isTrue);
    final saveResult = handleReleaseCanaryYoutubeBridgeAction(
      action: 'save',
      videoId: '',
      videos: [_first],
      onAttach: attached.add,
      onClearSearch: () => cleared = true,
      onSave: () => saved = true,
    );
    expect(saveResult.accepted, isTrue);
    expect(saveResult.attachedVideoId, isNull);
    expect(saved, isTrue);
    final rejectedResult = handleReleaseCanaryYoutubeBridgeAction(
      action: 'drag-attach',
      videoId: 'not-loaded',
      videos: [_first],
      onAttach: attached.add,
      onClearSearch: () => cleared = true,
      onSave: () => saved = true,
    );
    expect(rejectedResult.accepted, isFalse);
    expect(rejectedResult.attachedVideoId, isNull);
  });

  test('release canary select action accepts the filtered fake fixture', () {
    final attached = <PublicYoutubeVideo>[];
    final filtered = filterAndSortYoutubeVideos(
      FakeYoutubePublicApi.videos,
      query: 'Press',
      sort: YoutubeVideoSort.viewCount,
    );

    expect(filtered.map((video) => video.id), ['canaryVid03']);
    final result = handleReleaseCanaryYoutubeBridgeAction(
      action: 'select-attach',
      videoId: 'canaryVid03',
      videos: filtered,
      onAttach: attached.add,
    );
    expect(result.accepted, isTrue);
    expect(result.attachedVideoId, 'canaryVid03');
    expect(attached.single.title, 'Release Canary Press');
  });

  test('search reset clears the actual controller and catalogue filter', () {
    final controller = TextEditingController(text: 'Squat');
    addTearDown(controller.dispose);
    var updates = 0;

    resetYoutubeSearchController(controller, (callback) {
      updates += 1;
      callback();
    });

    expect(updates, 1);
    expect(controller.text, isEmpty);
    expect(
      filterAndSortYoutubeVideos(
        [_first, _second],
        query: controller.text,
        sort: YoutubeVideoSort.newest,
      ),
      hasLength(2),
    );
  });

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
    final source = find.byKey(const Key('youtube-video-videoId0001'));
    final target = find.byKey(youtubeMediaTargetKey);
    final gesture = await tester.startGesture(tester.getCenter(source));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await gesture.moveBy(const Offset(2, 0));
    await tester.pump();
    await gesture.up();
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

  testWidgets('remove action exposes explicit button semantics',
      (tester) async {
    var removed = false;
    await _pumpPanel(
      tester,
      api: _FakeApi(),
      attachedVideo: _first.metadata,
      onRemove: () => removed = true,
    );
    await tester.enterText(
      find.byKey(youtubeChannelFieldKey),
      '@public.trainer',
    );
    await tester.tap(find.byKey(youtubeLoadChannelKey));
    await tester.pumpAndSettle();
    final semantics = tester.ensureSemantics();

    final remove = find.bySemanticsLabel('Remove video');
    expect(remove, findsOneWidget);
    await tester.tap(remove);
    await tester.pump();
    expect(removed, isTrue);
    semantics.dispose();
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
  YoutubeVideoMetadata? attachedVideo,
  ValueChanged<PublicYoutubeVideo>? onAttach,
  VoidCallback? onRemove,
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
              attachedVideo: attachedVideo,
              onAttach: onAttach ?? (_) {},
              onRemove: onRemove ?? () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}
