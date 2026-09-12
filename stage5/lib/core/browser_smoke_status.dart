import 'package:stage5/core/browser_smoke_status_stub.dart'
    if (dart.library.html) 'package:stage5/core/browser_smoke_status_web.dart'
    as implementation;

void markBrowserSmokeAuthenticated(String email, String workspaceMode) {
  implementation.markBrowserSmokeAuthenticated(email, workspaceMode);
}

void markBrowserSmokeAccountIdentity(String identity) {
  implementation.markBrowserSmokeAccountIdentity(identity);
}

void markBrowserSmokeSurfaceReady(String surface) {
  implementation.markBrowserSmokeSurfaceReady(surface);
}
