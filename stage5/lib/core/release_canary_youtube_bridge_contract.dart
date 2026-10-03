class ReleaseCanaryYoutubeActionResult {
  const ReleaseCanaryYoutubeActionResult.accepted({
    this.attachedVideoId,
  }) : accepted = true;

  const ReleaseCanaryYoutubeActionResult.rejected()
      : accepted = false,
        attachedVideoId = null;

  final bool accepted;
  final String? attachedVideoId;
}

class ReleaseCanaryYoutubeBridgeRegistrations {
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
