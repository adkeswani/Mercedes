class PendingWebWorkspaceRoute {
  PendingWebWorkspaceRoute([String? initialLocation]) {
    if (initialLocation != null) {
      remember(initialLocation);
    }
  }

  String? _location;

  void remember(String location) {
    final path = Uri.parse(location).path;
    if (path == '/login' ||
        path == '/loading' ||
        path == '/onboarding' ||
        path == '/error') {
      return;
    }
    _location = location;
  }

  String? take() {
    final location = _location;
    _location = null;
    return location;
  }
}
