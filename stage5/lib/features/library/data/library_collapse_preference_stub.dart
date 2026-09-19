import 'package:stage5/features/library/data/library_collapse_preference_contract.dart';

LibraryCollapsePreference createLibraryCollapsePreference() {
  return MemoryLibraryCollapsePreference();
}

class MemoryLibraryCollapsePreference implements LibraryCollapsePreference {
  final Map<String, bool> _values = {};

  @override
  bool? read(String key) => _values[key];

  @override
  void write(String key, bool collapsed) {
    _values[key] = collapsed;
  }
}
