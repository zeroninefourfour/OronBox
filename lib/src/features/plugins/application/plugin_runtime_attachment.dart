/// Tracks whether a plugin page is open and whether its runtime must stay up
/// after that page closes.
class PluginRuntimeAttachment {
  final _uiAttached = <String>{};
  final _background = <String>{};

  void attachUi(String id) => _uiAttached.add(id);

  void detachUi(String id) => _uiAttached.remove(id);

  void retain(String id) => _background.add(id);

  void release(String id) => _background.remove(id);

  void forget(String id) {
    _uiAttached.remove(id);
    _background.remove(id);
  }

  bool retains(String id) => _background.contains(id);

  bool hasUi(String id) => _uiAttached.contains(id);

  bool shouldStopAfterDetach(String id) => !retains(id);

  bool shouldStopAfterRelease(String id) => !hasUi(id);
}
