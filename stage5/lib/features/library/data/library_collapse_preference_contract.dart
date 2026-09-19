abstract interface class LibraryCollapsePreference {
  bool? read(String key);

  void write(String key, bool collapsed);
}
