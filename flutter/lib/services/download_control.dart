class DownloadCancelled implements Exception {
  final String reason;
  const DownloadCancelled([this.reason = 'cancelled']);
}

class DownloadPaused implements Exception {
  const DownloadPaused();
}

class DownloadControl {
  bool _cancelled = false;
  bool _paused = false;
  void cancel() { _cancelled = true; }
  void pause() { _paused = true; }
  bool get cancelled => _cancelled;
  bool get paused => _paused;
  void checkpoint() {
    if (_cancelled) throw const DownloadCancelled();
    if (_paused) throw const DownloadPaused();
  }
}
