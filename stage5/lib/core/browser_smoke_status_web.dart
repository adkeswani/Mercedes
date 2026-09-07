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
