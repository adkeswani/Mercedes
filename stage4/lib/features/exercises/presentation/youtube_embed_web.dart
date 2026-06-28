import 'dart:ui_web' as ui_web;

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

/// Tracks which view types have already been registered to avoid
/// re-registering the same factory (which throws).
final Set<String> _registeredViewTypes = <String>{};

/// Web YouTube embed backed by a native `<iframe>` rendered through an
/// [HtmlElementView]. This loads the standard YouTube embedded player and is
/// far more reliable on Flutter web than a webview-based player.
Widget buildYoutubeEmbedImpl(String videoId) {
  final viewType = 'youtube-iframe-$videoId';

  if (!_registeredViewTypes.contains(viewType)) {
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final iframe = web.HTMLIFrameElement()
        ..src = 'https://www.youtube.com/embed/$videoId'
        ..allow = 'accelerometer; autoplay; clipboard-write; encrypted-media; '
            'gyroscope; picture-in-picture'
        ..allowFullscreen = true
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%';
      return iframe;
    });
    _registeredViewTypes.add(viewType);
  }

  return AspectRatio(
    aspectRatio: 16 / 9,
    child: HtmlElementView(viewType: viewType),
  );
}
