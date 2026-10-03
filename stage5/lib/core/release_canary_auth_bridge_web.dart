// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import 'package:flutter/foundation.dart';

import 'package:stage5/core/release_canary_auth_bridge_contract.dart';

const _eventName = 'mercedes-release-canary-authenticate';
const _bridgeStateAttribute = 'data-release-canary-auth-bridge';
const _emailAttribute = 'data-release-canary-auth-email';
const _passwordAttribute = 'data-release-canary-auth-password';
const _resultAttribute = 'data-release-canary-auth-result';
final _registrations = ReleaseCanaryAuthBridgeRegistrations();

VoidCallback registerReleaseCanaryAuthBridge({
  required bool enabled,
  required bool Function(String email, String password) onSignIn,
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
    final email = body.getAttribute(_emailAttribute) ?? '';
    final password = body.getAttribute(_passwordAttribute) ?? '';
    body.attributes.remove(_emailAttribute);
    body.attributes.remove(_passwordAttribute);
    body.setAttribute(
      _resultAttribute,
      onSignIn(email, password) ? 'accepted' : 'rejected',
    );
  }

  html.window.addEventListener(_eventName, listener);
  return () {
    html.window.removeEventListener(_eventName, listener);
    if (!_registrations.deactivate(registrationId)) {
      return;
    }
    body.attributes.remove(_bridgeStateAttribute);
    body.attributes.remove(_emailAttribute);
    body.attributes.remove(_passwordAttribute);
    body.attributes.remove(_resultAttribute);
  };
}
