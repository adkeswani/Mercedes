class ReleaseCanaryAuthBridgeRegistrations {
  int _nextId = 0;
  int? _activeId;

  int activate() {
    final id = ++_nextId;
    _activeId = id;
    return id;
  }

  bool isActive(int id) => _activeId == id;

  bool deactivate(int id) {
    if (!isActive(id)) {
      return false;
    }
    _activeId = null;
    return true;
  }
}
