// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:flutter/foundation.dart';

import 'package:stage5/core/release_canary_youtube_bridge_contract.dart';

const _eventName = 'mercedes-release-canary-youtube-action';
const _bridgeStateAttribute = 'data-release-canary-youtube-bridge';
const _actionAttribute = 'data-release-canary-youtube-action';
const _videoIdAttribute = 'data-release-canary-youtube-video-id';
const _resultAttribute = 'data-release-canary-youtube-action-result';
const _attachedVideoIdAttribute =
    'data-release-canary-youtube-attached-video-id';
final _registrations = ReleaseCanaryYoutubeBridgeRegistrations();

VoidCallback registerReleaseCanaryYoutubeBridge({
  required bool enabled,
  required ReleaseCanaryYoutubeActionResult Function(
    String action,
    String videoId,
  ) onAction,
}) {
  if (!enabled) {
    return () {};
  }

  final body = html.document.body;
  if (body == null) {
    return () {};
  }
  final registrationId = _registrations.activate();
  body.setAttribute(_bridgeStateAttribute, 'ready');

  void listener(html.Event _) {
    if (!_registrations.isActive(registrationId)) {
      return;
    }
    final action = body.getAttribute(_actionAttribute) ?? '';
    final videoId = body.getAttribute(_videoIdAttribute) ?? '';
    final result = onAction(action, videoId);
    body.setAttribute(
      _resultAttribute,
      result.accepted ? 'accepted' : 'rejected',
    );
    final attachedVideoId = result.attachedVideoId;
    if (result.accepted && attachedVideoId != null) {
      body.setAttribute(_attachedVideoIdAttribute, attachedVideoId);
    }
  }

  html.window.addEventListener(_eventName, listener);
  return () {
    html.window.removeEventListener(_eventName, listener);
    if (!_registrations.deactivate(registrationId)) {
      return;
    }
    body.attributes.remove(_bridgeStateAttribute);
    body.attributes.remove(_actionAttribute);
    body.attributes.remove(_videoIdAttribute);
    body.attributes.remove(_resultAttribute);
    body.attributes.remove(_attachedVideoIdAttribute);
  };
}
