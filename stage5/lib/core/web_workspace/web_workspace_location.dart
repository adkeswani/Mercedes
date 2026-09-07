import 'web_workspace_location_stub.dart'
    if (dart.library.html) 'web_workspace_location_web.dart' as implementation;

String? readInitialWebWorkspaceLocation() {
  return implementation.readInitialWebWorkspaceLocation();
}
