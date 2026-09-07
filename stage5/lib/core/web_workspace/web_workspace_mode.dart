import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:stage5/core/web_workspace/web_workspace_preference.dart';

enum WebWorkspaceMode {
  athlete,
  trainer;

  static WebWorkspaceMode? fromLocation(String location) {
    for (final mode in values) {
      if (location == '/${mode.name}' ||
          location.startsWith('/${mode.name}/')) {
        return mode;
      }
    }
    return null;
  }

  String get label => switch (this) {
        WebWorkspaceMode.athlete => 'Athlete',
        WebWorkspaceMode.trainer => 'Trainer',
      };

  String get initialLocation => switch (this) {
        WebWorkspaceMode.athlete => '/athlete/today',
        WebWorkspaceMode.trainer => '/trainer/dashboard',
      };
}

final webWorkspacePreferenceProvider = Provider<WebWorkspacePreference>((ref) {
  return createWebWorkspacePreference();
});

final webWorkspaceModeProvider =
    StateNotifierProvider<WebWorkspaceModeController, WebWorkspaceMode>((ref) {
  return WebWorkspaceModeController(
    ref.watch(webWorkspacePreferenceProvider),
  );
});

class WebWorkspaceModeController extends StateNotifier<WebWorkspaceMode> {
  WebWorkspaceModeController(this._preference) : super(_readMode(_preference));

  final WebWorkspacePreference _preference;

  static WebWorkspaceMode _readMode(WebWorkspacePreference preference) {
    final savedMode = preference.read();
    return WebWorkspaceMode.values.firstWhere(
      (mode) => mode.name == savedMode,
      orElse: () => WebWorkspaceMode.athlete,
    );
  }

  void select(WebWorkspaceMode mode) {
    if (state == mode) {
      return;
    }
    state = mode;
    _preference.write(mode.name);
  }
}
