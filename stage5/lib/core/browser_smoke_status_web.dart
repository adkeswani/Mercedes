// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

void markBrowserSmokeAuthenticated(String email, String workspaceMode) {
  html.document.body?.setAttribute(
    'data-browser-smoke-authenticated',
    email,
  );
  html.document.body?.setAttribute(
    'data-browser-smoke-workspace',
    workspaceMode,
  );
}

void markBrowserSmokeAccountIdentity(String identity) {
  html.document.body?.setAttribute(
    'data-browser-smoke-account-identity',
    identity,
  );
}

void markBrowserSmokeSurfaceReady(String surface) {
  html.document.body?.setAttribute(
    'data-browser-smoke-surface-$surface',
    'ready',
  );
}
