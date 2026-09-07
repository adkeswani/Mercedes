import 'dart:html' as html;

import 'package:stage5/core/web_workspace/web_workspace_preference_contract.dart';

const _storageKey = 'mercedes.webWorkspaceMode';

WebWorkspacePreference createWebWorkspacePreference() {
  return _BrowserWebWorkspacePreference();
}

class _BrowserWebWorkspacePreference implements WebWorkspacePreference {
  @override
  String? read() => html.window.localStorage[_storageKey];

  @override
  void write(String mode) {
    html.window.localStorage[_storageKey] = mode;
  }
}
