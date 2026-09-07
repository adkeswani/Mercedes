import 'package:stage5/core/web_workspace/web_workspace_preference_contract.dart';
import 'package:stage5/core/web_workspace/web_workspace_preference_stub.dart'
    if (dart.library.html) 'package:stage5/core/web_workspace/web_workspace_preference_web.dart'
    as implementation;

export 'package:stage5/core/web_workspace/web_workspace_preference_contract.dart';

WebWorkspacePreference createWebWorkspacePreference() {
  return implementation.createWebWorkspacePreference();
}
