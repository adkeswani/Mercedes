import 'dart:html' as html;

String? readInitialWebWorkspaceLocation() {
  final hash = html.window.location.hash;
  if (hash.startsWith('#/')) {
    return hash.substring(1);
  }

  final path = html.window.location.pathname ?? '';
  if (path.isNotEmpty && path != '/') {
    return '$path${html.window.location.search ?? ''}';
  }
  return null;
}
