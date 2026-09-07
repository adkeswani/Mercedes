import 'package:stage5/core/web_workspace/web_workspace_mode.dart';

class PendingWebWorkspaceRoute {
  PendingWebWorkspaceRoute([String? initialLocation]) {
    if (initialLocation != null) {
      remember(initialLocation);
    }
  }

  String? _location;

  void remember(String location) {
    if (WebWorkspaceMode.fromLocation(Uri.parse(location).path) != null) {
      _location = location;
    }
  }

  String? take() {
    final location = _location;
    _location = null;
    return location;
  }
}
