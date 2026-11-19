/// Cola de avisos del monitor. No vuelve a reproducir eventos históricos
/// cuando el monitor se conecta, y deduplica por ID inmutable de Laravel.
class MonitorCompletionQueue24N5 {
  bool _initialized = false;
  int _maxSeen = 0;
  final List<Map<String, dynamic>> _pending = [];

  bool get initialized => _initialized;
  int get lastEventId => _maxSeen;
  int get pendingCount => _pending.length;

  void ingest(Object? raw) {
    if (raw is! List) return;
    final entries = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e))
        .where((e) => (e['event_id'] as num?) != null).toList()
      ..sort((a, b) => (a['event_id'] as num).toInt()
          .compareTo((b['event_id'] as num).toInt()));
    // El primer lote establece un punto de inicio; nunca replay del historial.
    if (!_initialized) {
      _initialized = true;
      for (final event in entries) {
        final id = (event['event_id'] as num).toInt();
        if (id > _maxSeen) _maxSeen = id;
      }
      return;
    }
    for (final event in entries) {
      final id = (event['event_id'] as num).toInt();
      if (id <= _maxSeen) continue;
      _maxSeen = id;
      _pending.add(event);
    }
  }

  Map<String, dynamic>? takeNext() => _pending.isEmpty ? null : _pending.removeAt(0);

  void clear() {
    _pending.clear();
    _initialized = false;
    _maxSeen = 0;
  }
}
