import 'package:flutter/material.dart';
import 'package:stage5/features/exercises/presentation/youtube_embed.dart';

const youtubeVideoAspectRatio = 16 / 9;
const youtubeVideoMaxWidth = 640.0;

const youtubeAttachedPreviewKey = Key('youtube-attached-preview');
const youtubeVideoFrameSurfaceKey = Key('youtube-video-frame-surface');

typedef YoutubeEmbedBuilder = Widget Function(String videoId);

class YoutubeVideoPlayer extends StatelessWidget {
  const YoutubeVideoPlayer({
    required this.videoId,
    this.embedBuilder = buildYoutubeEmbed,
    super.key,
  });

  final String videoId;
  final YoutubeEmbedBuilder embedBuilder;

  @override
  Widget build(BuildContext context) {
    return YoutubeVideoFrame(child: embedBuilder(videoId));
  }
}

class YoutubeVideoFrame extends StatelessWidget {
  const YoutubeVideoFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: youtubeVideoMaxWidth),
        child: AspectRatio(
          aspectRatio: youtubeVideoAspectRatio,
          child: ClipRRect(
            key: youtubeVideoFrameSurfaceKey,
            borderRadius: BorderRadius.circular(8),
            child: child,
          ),
        ),
      ),
    );
  }
}

class YoutubeThumbnail extends StatelessWidget {
  const YoutubeThumbnail({
    required this.url,
    required this.semanticLabel,
    required this.fallbackKey,
    super.key,
  });

  final String url;
  final String semanticLabel;
  final Key fallbackKey;

  @override
  Widget build(BuildContext context) {
    final fallback = ColoredBox(
      key: fallbackKey,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.video_library_outlined, size: 48)),
    );
    if (url.isEmpty) {
      return Semantics(image: true, label: semanticLabel, child: fallback);
    }
    return Semantics(
      image: true,
      label: semanticLabel,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              fallback,
              const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          );
        },
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}
