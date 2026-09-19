import 'dart:html' as html;

import 'package:stage5/features/library/data/library_collapse_preference_contract.dart';

LibraryCollapsePreference createLibraryCollapsePreference() {
  return _BrowserLibraryCollapsePreference();
}

class _BrowserLibraryCollapsePreference implements LibraryCollapsePreference {
  static const _prefix = 'mercedes.library.collapsed.';

  @override
  bool? read(String key) {
    final value = html.window.localStorage['$_prefix$key'];
    return switch (value) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  @override
  void write(String key, bool collapsed) {
    html.window.localStorage['$_prefix$key'] = collapsed.toString();
  }
}
