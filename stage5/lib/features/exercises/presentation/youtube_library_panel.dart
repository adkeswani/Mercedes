import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:stage5/core/release_canary_config.dart';
import 'package:stage5/core/release_canary_youtube_bridge.dart';
import 'package:stage5/core/release_canary_youtube_bridge_contract.dart';
import 'package:stage5/features/exercises/data/youtube_channel_preference.dart';
import 'package:stage5/features/exercises/data/youtube_public_api.dart';
import 'package:stage5/features/exercises/domain/youtube_channel.dart';
import 'package:stage5/features/exercises/presentation/youtube_public_providers.dart';

const youtubeChannelFieldKey = Key('youtube-channel-field');
const youtubeLoadChannelKey = Key('youtube-load-channel');
const youtubeSearchFieldKey = Key('youtube-search-field');
const youtubeMediaTargetKey = Key('youtube-media-target');
const youtubeRemoveVideoKey = Key('youtube-remove-video');
const youtubeOpenVideoKey = Key('youtube-open-video');
const youtubeThumbnailFallbackKey = Key('youtube-thumbnail-fallback');

typedef YoutubeUrlOpener = Future<bool> Function(Uri uri);

void resetYoutubeSearchController(
  TextEditingController controller,
  void Function(VoidCallback callback) update,
) {
  update(controller.clear);
}

ReleaseCanaryYoutubeActionResult handleReleaseCanaryYoutubeBridgeAction({
  required String action,
  required String videoId,
  required Iterable<PublicYoutubeVideo> videos,
  required ValueChanged<PublicYoutubeVideo> onAttach,
  VoidCallback? onClearSearch,
  VoidCallback? onSave,
}) {
  if (action == 'clear-search') {
    if (onClearSearch == null) {
      return const ReleaseCanaryYoutubeActionResult.rejected();
    }
    onClearSearch();
    return const ReleaseCanaryYoutubeActionResult.accepted();
  }
  if (action == 'save') {
    if (onSave == null) {
      return const ReleaseCanaryYoutubeActionResult.rejected();
    }
    onSave();
    return const ReleaseCanaryYoutubeActionResult.accepted();
  }
  if (action != 'drag-attach' && action != 'select-attach') {
    return const ReleaseCanaryYoutubeActionResult.rejected();
  }
  final matches = videos.where((video) => video.id == videoId);
  if (matches.length != 1) {
    return const ReleaseCanaryYoutubeActionResult.rejected();
  }
  final video = matches.single;
  onAttach(video);
  return ReleaseCanaryYoutubeActionResult.accepted(
    attachedVideoId: video.id,
  );
}

class YoutubeLibraryPanel extends ConsumerStatefulWidget {
  const YoutubeLibraryPanel({
    required this.onAttach,
    required this.onRemove,
    this.attachedVideo,
    this.api,
    this.onReleaseCanarySave,
    this.preference,
    this.openUrl,
    super.key,
  });

  final ValueChanged<PublicYoutubeVideo> onAttach;
  final VoidCallback onRemove;
  final VoidCallback? onReleaseCanarySave;
  final YoutubeVideoMetadata? attachedVideo;
  final YoutubePublicApi? api;
  final YoutubeChannelPreference? preference;
  final YoutubeUrlOpener? openUrl;

  @override
  ConsumerState<YoutubeLibraryPanel> createState() =>
      _YoutubeLibraryPanelState();
}

class _YoutubeLibraryPanelState extends ConsumerState<YoutubeLibraryPanel> {
  final _channelController = TextEditingController();
  final _searchController = TextEditingController();
  PublicYoutubeChannel? _channel;
  List<PublicYoutubeVideo> _videos = const [];
  String? _nextPageToken;
  YoutubeVideoSort _sort = YoutubeVideoSort.newest;
  String? _error;
  bool _loading = false;
  bool _loadingMore = false;
  YoutubeCatalogueStatus _catalogueStatus = YoutubeCatalogueStatus.ready;
  int _indexedCount = 0;
  int _videoCount = 0;
  bool _catalogueComplete = true;
  bool _stale = false;
  DateTime? _lastRefreshedAt;
  int _requestGeneration = 0;
  Timer? _searchDebounce;
  VoidCallback _disposeReleaseCanaryBridge = () {};

  YoutubePublicApi get _api => widget.api ?? ref.read(youtubePublicApiProvider);

  YoutubeChannelPreference get _preference =>
      widget.preference ?? ref.read(youtubeChannelPreferenceProvider);

  @override
  void initState() {
    super.initState();
    _disposeReleaseCanaryBridge = registerReleaseCanaryYoutubeBridge(
      enabled: releaseCanaryYoutubeBridgeEnabled,
      onAction: _handleReleaseCanaryYoutubeAction,
    );
    _restoreLastChannel();
  }

  ReleaseCanaryYoutubeActionResult _handleReleaseCanaryYoutubeAction(
    String action,
    String videoId,
  ) {
    return handleReleaseCanaryYoutubeBridgeAction(
      action: action,
      videoId: videoId,
      videos: filterAndSortYoutubeVideos(
        _videos,
        query: _searchController.text,
        sort: _sort,
      ),
      onAttach: widget.onAttach,
      onClearSearch: _clearSearch,
      onSave: widget.onReleaseCanarySave,
    );
  }

  void _clearSearch() {
    _searchDebounce?.cancel();
    resetYoutubeSearchController(_searchController, setState);
    _reloadCatalogue();
  }

  void _scheduleCatalogueReload() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      _reloadCatalogue,
    );
  }

  Future<void> _restoreLastChannel() async {
    final value = await _preference.read();
    if (!mounted || value == null || value.isEmpty) {
      return;
    }
    _channelController.text = value;
  }

  @override
  void dispose() {
    _disposeReleaseCanaryBridge();
    _searchDebounce?.cancel();
    _channelController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChannel() async {
    if (_loading) {
      return;
    }
    final input = _channelController.text.trim();
    if (parseYoutubeChannelReference(input) == null &&
        !(releaseCanaryYoutubeCatalogueCompiledIn &&
            input == 'release-canary')) {
      setState(() {
        _error = 'Enter a YouTube channel URL, @handle, custom URL, or ID.';
      });
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
      _channel = null;
      _videos = const [];
      _nextPageToken = null;
      _indexedCount = 0;
      _videoCount = 0;
      _catalogueComplete = false;
      _stale = false;
      _lastRefreshedAt = null;
    });
    try {
      final channel = await _api.resolveChannel(input);
      final page = await _api.loadVideos(channelId: channel.id);
      await _preference.write(input);
      if (!mounted || generation != _requestGeneration) {
        return;
      }
      setState(() {
        _channel = channel;
        _applyPage(page, replace: true);
      });
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    final channel = _channel;
    final token = _nextPageToken;
    if (channel == null || token == null || _loadingMore) {
      return;
    }
    final generation = _requestGeneration;
    setState(() {
      _loadingMore = true;
      _error = null;
    });
    try {
      final page = await _api.loadVideos(
        channelId: channel.id,
        pageToken: token,
        query: _searchController.text,
        sort: _sort,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          _channel?.id != channel.id) {
        return;
      }
      setState(() {
        _videos = appendYoutubePage(_videos, page.videos);
        _applyPage(page, replace: false);
      });
    } catch (error) {
      if (mounted &&
          generation == _requestGeneration &&
          _channel?.id == channel.id) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted &&
          generation == _requestGeneration &&
          _channel?.id == channel.id) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _reloadCatalogue() async {
    final channel = _channel;
    if (channel == null) {
      return;
    }
    final generation = ++_requestGeneration;
    setState(() {
      _loadingMore = true;
      _error = null;
      _videos = const [];
      _nextPageToken = null;
    });
    try {
      final page = await _api.loadVideos(
        channelId: channel.id,
        query: _searchController.text,
        sort: _sort,
      );
      if (!mounted ||
          generation != _requestGeneration ||
          _channel?.id != channel.id) {
        return;
      }
      setState(() => _applyPage(page, replace: true));
    } catch (error) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _error = _friendlyError(error));
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _loadingMore = false);
      }
    }
  }

  void _applyPage(PublicYoutubeVideoPage page, {required bool replace}) {
    if (replace) {
      _videos = page.videos;
    }
    _nextPageToken = page.nextPageToken;
    _catalogueStatus = page.status;
    _indexedCount = page.indexedCount;
    _videoCount = page.videoCount;
    _catalogueComplete = page.complete;
    _stale = page.stale;
    _lastRefreshedAt = page.lastRefreshedAt;
  }

  Future<void> _openVideo(YoutubeVideoMetadata metadata) async {
    final uri = Uri.parse(metadata.canonicalUrl);
    final opened = await (widget.openUrl?.call(uri) ??
        launchUrl(uri, mode: LaunchMode.externalApplication));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open this YouTube video.')),
      );
    }
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('resource-exhausted')) {
      return 'YouTube quota or the per-user request limit was reached. '
          'Try again later.';
    }
    if (text.contains('not-found')) {
      return 'That public YouTube channel could not be found.';
    }
    if (text.contains('unavailable') || text.contains('deadline-exceeded')) {
      return 'YouTube is temporarily unavailable. Try again.';
    }
    return text.replaceFirst(RegExp(r'^[A-Za-z]+Exception: '), '');
  }

  @override
  Widget build(BuildContext context) {
    final visible = _videos;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'YouTube public channel',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            const Text(
              'Browse public uploads without connecting a Google account. '
              'Private and unlisted videos require future YouTube OAuth.',
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: youtubeChannelFieldKey,
                    controller: _channelController,
                    decoration: const InputDecoration(
                      labelText: 'Public channel',
                      hintText:
                          '@handle, channel URL, custom URL, or channel ID',
                    ),
                    onSubmitted: _loading ? null : (_) => _loadChannel(),
                  ),
                ),
                const SizedBox(width: 8),
                Semantics(
                  label: 'Load public YouTube channel',
                  button: true,
                  onTap: _loading ? null : _loadChannel,
                  child: ExcludeSemantics(
                    child: FilledButton(
                      key: youtubeLoadChannelKey,
                      onPressed: _loading ? null : _loadChannel,
                      child: const Text('Load channel'),
                    ),
                  ),
                ),
              ],
            ),
            if (_loading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                key: const Key('youtube-library-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_channel != null) ...[
              const SizedBox(height: 16),
              _ChannelIdentity(channel: _channel!),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      key: youtubeSearchFieldKey,
                      controller: _searchController,
                      decoration: const InputDecoration(
                        labelText: 'Search complete catalogue',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (_) => _scheduleCatalogueReload(),
                    ),
                  ),
                  for (final option in YoutubeVideoSort.values)
                    Semantics(
                      label: '${_sortLabel(option)} loaded sort',
                      button: true,
                      selected: _sort == option,
                      onTap: () {
                        setState(() => _sort = option);
                        _reloadCatalogue();
                      },
                      child: ExcludeSemantics(
                        child: ChoiceChip(
                          label: Text(_sortLabel(option)),
                          selected: _sort == option,
                          onSelected: (_) {
                            setState(() => _sort = option);
                            _reloadCatalogue();
                          },
                        ),
                      ),
                    ),
                  Text(
                    _catalogueComplete
                        ? '$_videoCount videos indexed'
                        : 'Indexing $_indexedCount videos...',
                    key: const Key('youtube-catalogue-progress'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _CatalogueFreshness(
                status: _catalogueStatus,
                stale: _stale,
                complete: _catalogueComplete,
                lastRefreshedAt: _lastRefreshedAt,
              ),
              const SizedBox(height: 12),
              _MediaTarget(
                metadata: widget.attachedVideo,
                onAttach: widget.onAttach,
                onRemove: widget.onRemove,
                onOpen: _openVideo,
              ),
              const SizedBox(height: 12),
              if (visible.isEmpty)
                const Text(
                  'No public videos match the loaded catalogue.',
                  key: Key('youtube-library-empty'),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final desktop = constraints.maxWidth >= 700;
                    return Column(
                      children: [
                        for (final video in visible)
                          _VideoCard(
                            video: video,
                            draggable: desktop,
                            onAttach: () => widget.onAttach(video),
                            replacing: widget.attachedVideo != null,
                          ),
                      ],
                    );
                  },
                ),
              if (_nextPageToken != null)
                OutlinedButton(
                  onPressed: _loadingMore ? null : _loadMore,
                  child: Text(_loadingMore ? 'Loading...' : 'Load next page'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _sortLabel(YoutubeVideoSort sort) {
    return switch (sort) {
      YoutubeVideoSort.newest => 'Newest',
      YoutubeVideoSort.oldest => 'Oldest',
      YoutubeVideoSort.title => 'Title',
      YoutubeVideoSort.viewCount => 'View count',
    };
  }
}

class _CatalogueFreshness extends StatelessWidget {
  const _CatalogueFreshness({
    required this.status,
    required this.stale,
    required this.complete,
    required this.lastRefreshedAt,
  });

  final YoutubeCatalogueStatus status;
  final bool stale;
  final bool complete;
  final DateTime? lastRefreshedAt;

  @override
  Widget build(BuildContext context) {
    final refreshed = lastRefreshedAt == null
        ? 'Not yet refreshed'
        : 'Last refreshed ${lastRefreshedAt!.toLocal().toIso8601String()}';
    final message = !complete
        ? 'Indexing is in progress. Results may be incomplete.'
        : stale || status == YoutubeCatalogueStatus.error
            ? 'Showing stale cached results. $refreshed'
            : 'Catalogue is fresh. $refreshed';
    return Text(
      message,
      key: const Key('youtube-catalogue-freshness'),
      style: TextStyle(
        color: stale || status == YoutubeCatalogueStatus.error
            ? Theme.of(context).colorScheme.error
            : null,
      ),
    );
  }
}

class _ChannelIdentity extends StatelessWidget {
  const _ChannelIdentity({required this.channel});

  final PublicYoutubeChannel channel;

  @override
  Widget build(BuildContext context) {
    final avatar = channel.avatarUrl;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        foregroundImage:
            avatar == null || avatar.isEmpty ? null : NetworkImage(avatar),
        child: const Icon(Icons.video_library_outlined),
      ),
      title: Text(channel.title),
      subtitle: Text(channel.id),
    );
  }
}

class _MediaTarget extends StatelessWidget {
  const _MediaTarget({
    required this.metadata,
    required this.onAttach,
    required this.onRemove,
    required this.onOpen,
  });

  final YoutubeVideoMetadata? metadata;
  final ValueChanged<PublicYoutubeVideo> onAttach;
  final VoidCallback onRemove;
  final ValueChanged<YoutubeVideoMetadata> onOpen;

  @override
  Widget build(BuildContext context) {
    return DragTarget<PublicYoutubeVideo>(
      key: youtubeMediaTargetKey,
      onAcceptWithDetails: (details) => onAttach(details.data),
      builder: (context, candidates, rejected) {
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(
              color: candidates.isEmpty
                  ? Theme.of(context).colorScheme.outline
                  : Theme.of(context).colorScheme.primary,
              width: candidates.isEmpty ? 1 : 2,
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          child: metadata == null
              ? const Text(
                  'Exercise video target — drag a video here or use Attach.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _YoutubeThumbnail(url: metadata!.thumbnailUrl),
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill,
                              size: 64,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      metadata!.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(metadata!.channelTitle),
                    Wrap(
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton.icon(
                          key: youtubeOpenVideoKey,
                          onPressed: () => onOpen(metadata!),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open on YouTube'),
                        ),
                        Semantics(
                          label: 'Remove video',
                          button: true,
                          onTap: onRemove,
                          child: ExcludeSemantics(
                            child: TextButton.icon(
                              key: youtubeRemoveVideoKey,
                              onPressed: onRemove,
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('Remove video'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }
}

class _YoutubeThumbnail extends StatelessWidget {
  const _YoutubeThumbnail({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      key: youtubeThumbnailFallbackKey,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.video_library_outlined, size: 48)),
    );
    if (url.isEmpty) {
      return fallback;
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => fallback,
    );
  }
}

class _VideoCard extends StatelessWidget {
  const _VideoCard({
    required this.video,
    required this.draggable,
    required this.onAttach,
    required this.replacing,
  });

  final PublicYoutubeVideo video;
  final bool draggable;
  final VoidCallback onAttach;
  final bool replacing;

  @override
  Widget build(BuildContext context) {
    final card = Semantics(
      label: 'YouTube video ${video.title}',
      container: true,
      explicitChildNodes: true,
      child: ListTile(
        key: Key('youtube-video-${video.id}'),
        leading: const Icon(Icons.play_circle_outline),
        title: Text(video.title),
        subtitle: Text(
          '${video.publishedAt.toLocal().toIso8601String().split('T').first}'
          '${video.viewCount == null ? '' : ' • ${video.viewCount} views'}',
        ),
        trailing: Semantics(
          label: 'Attach ${video.title}',
          button: true,
          onTap: onAttach,
          child: ExcludeSemantics(
            child: FilledButton.tonal(
              key: Key('youtube-attach-${video.id}'),
              onPressed: onAttach,
              child: Text(replacing ? 'Replace' : 'Attach'),
            ),
          ),
        ),
      ),
    );
    if (!draggable) {
      return card;
    }
    return Draggable<PublicYoutubeVideo>(
      data: video,
      feedback: Material(
        elevation: 8,
        child: SizedBox(width: 360, child: card),
      ),
      childWhenDragging: Opacity(opacity: 0.45, child: card),
      child: card,
    );
  }
}
