import 'package:flutter/material.dart';
import 'package:stage5/features/exercises/domain/youtube_url.dart';
import 'package:stage5/features/exercises/presentation/youtube_video_presentation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Renders an embedded YouTube player for supported URLs, or an "Open link"
/// fallback for any other URL.
///
/// Shared between the exercise detail screen and anywhere else an exercise's
/// video needs to be shown inline (e.g. the workout completion screen).
class ExerciseVideoPreview extends StatelessWidget {
  const ExerciseVideoPreview({required this.url, super.key});

  final String url;

  Future<void> _openExternally() async {
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final videoId = extractYoutubeId(url);
    if (videoId != null) {
      return YoutubeVideoPlayer(videoId: videoId);
    }

    // Unsupported URL — offer to open it externally.
    return Card(
      child: ListTile(
        leading: const Icon(Icons.open_in_new),
        title: const Text('Open video link'),
        subtitle: Text(url, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: _openExternally,
      ),
    );
  }
}

/// Renders a block of exercise instructions bounded to a fixed height
/// (roughly four lines) in a scrollable box, so a long instructions field
/// can't push the rest of the page out of view.
class BoundedScrollableText extends StatelessWidget {
  const BoundedScrollableText(
    this.text, {
    this.maxLines = 4,
    this.style,
    super.key,
  });

  final String text;
  final int maxLines;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    final lineHeight = (effectiveStyle?.fontSize ?? 14) *
        (effectiveStyle?.height ?? 1.3);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: lineHeight * maxLines),
      child: Scrollbar(
        child: SingleChildScrollView(
          child: Text(text, style: effectiveStyle),
        ),
      ),
    );
  }
}
