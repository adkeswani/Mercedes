import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

Widget buildYoutubeEmbedImpl(String videoId, {required bool interactive}) =>
    _YoutubeEmbedWeb(videoId: videoId, interactive: interactive);

class _YoutubeEmbedWeb extends StatefulWidget {
  const _YoutubeEmbedWeb({
    required this.videoId,
    required this.interactive,
  });

  final String videoId;
  final bool interactive;

  @override
  State<_YoutubeEmbedWeb> createState() => _YoutubeEmbedWebState();
}

class _YoutubeEmbedWebState extends State<_YoutubeEmbedWeb> {
  web.HTMLIFrameElement? _iframe;

  @override
  void didUpdateWidget(_YoutubeEmbedWeb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _iframe?.src = 'https://www.youtube.com/embed/${widget.videoId}';
    }
    _updatePointerInput();
  }

  void _updatePointerInput() {
    _iframe?.style.pointerEvents = widget.interactive ? 'auto' : 'none';
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: 16 / 9,
        child: HtmlElementView.fromTagName(
          tagName: 'iframe',
          onElementCreated: (element) {
            _iframe = (element as web.HTMLIFrameElement)
              ..src = 'https://www.youtube.com/embed/${widget.videoId}'
              ..allow =
                  'accelerometer; autoplay; clipboard-write; encrypted-media; '
                      'gyroscope; picture-in-picture'
              ..allowFullscreen = true
              ..style.border = 'none'
              ..style.width = '100%'
              ..style.height = '100%';
            _updatePointerInput();
          },
        ),
      );
}
