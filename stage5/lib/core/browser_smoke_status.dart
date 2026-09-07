import 'package:stage5/core/browser_smoke_status_stub.dart'
    if (dart.library.html) 'package:stage5/core/browser_smoke_status_web.dart'
    as implementation;

void markBrowserSmokeAuthenticated(String email, String workspaceMode) {
  implementation.markBrowserSmokeAuthenticated(email, workspaceMode);
}
