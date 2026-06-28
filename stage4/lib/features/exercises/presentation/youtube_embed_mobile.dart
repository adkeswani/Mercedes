import 'package:flutter/widgets.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// Mobile/desktop YouTube embed backed by `youtube_player_iframe`.
Widget buildYoutubeEmbedImpl(String videoId) =>
    _YoutubeEmbedMobile(videoId: videoId);

class _YoutubeEmbedMobile extends StatefulWidget {
  const _YoutubeEmbedMobile({required this.videoId});

  final String videoId;

  @override
  State<_YoutubeEmbedMobile> createState() => _YoutubeEmbedMobileState();
}

class _YoutubeEmbedMobileState extends State<_YoutubeEmbedMobile> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: false,
      params: const YoutubePlayerParams(showFullscreenButton: true),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return YoutubePlayer(
      controller: _controller,
      aspectRatio: 16 / 9,
    );
  }
}
