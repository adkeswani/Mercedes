import 'package:stage5/core/web_workspace/web_workspace_preference_contract.dart';

WebWorkspacePreference createWebWorkspacePreference() {
  return _MemoryWebWorkspacePreference();
}

class _MemoryWebWorkspacePreference implements WebWorkspacePreference {
  String? _mode;

  @override
  String? read() => _mode;

  @override
  void write(String mode) {
    _mode = mode;
  }
}
