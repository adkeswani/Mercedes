import 'package:stage5/core/browser_smoke_status_stub.dart'
    if (dart.library.html) 'package:stage5/core/browser_smoke_status_web.dart'
    as implementation;

void markBrowserSmokeAuthenticated(String email, String workspaceMode) {
  implementation.markBrowserSmokeAuthenticated(email, workspaceMode);
}

void markBrowserSmokeAccountIdentity(String identity) {
  implementation.markBrowserSmokeAccountIdentity(identity);
}

void markBrowserSmokeFirebaseProject(String projectId) {
  implementation.markBrowserSmokeFirebaseProject(projectId);
}

void markReleaseCanarySignInState(String state) {
  implementation.markReleaseCanarySignInState(state);
}

void markBrowserSmokeSurfaceReady(String surface, {String? content}) {
  implementation.markBrowserSmokeSurfaceReady(surface, content: content);
}

void markBrowserSmokeSurfaceFailure(String surface, String state) {
  implementation.markBrowserSmokeSurfaceFailure(surface, state);
}
