import 'package:flutter/widgets.dart';
import '../domain/report_query.dart';

/// One owner for remote request state. Old requests cannot replace a newer filter.
class ReportController<T> extends ChangeNotifier {
  final Future<T> Function(ReportQuery) _load;
  final DateTime Function() _clock;
  late ReportQuery _query;
  ReportQuery get query => _query;
  AsyncSnapshot<T> _snapshot = AsyncSnapshot<T>.nothing();
  AsyncSnapshot<T> get snapshot => _snapshot;
  Future<void>? _inFlight;
  int _generation = 0;
  bool _disposed = false;

  ReportController(this._load, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now {
    _query = ReportQuery(now: _clock());
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    if (_inFlight != null) return _inFlight!;
    _query = ReportQuery(
      range: _query.range,
      month: _query.month,
      now: _clock(),
    );
    final generation = ++_generation;
    final query = _query;
    _snapshot = AsyncSnapshot<T>.waiting();
    // Install the request before notifying listeners to prevent reentrant reloads.
    final request = Future<T>.sync(() => _load(query))
        .then<void>(
          (data) {
            if (!_disposed && generation == _generation) {
              _snapshot = AsyncSnapshot<T>.withData(ConnectionState.done, data);
            }
          },
          onError: (Object error, StackTrace stack) {
            if (!_disposed && generation == _generation) {
              _snapshot = AsyncSnapshot<T>.withError(
                ConnectionState.done,
                error,
                stack,
              );
            }
          },
        )
        .whenComplete(() {
          if (!_disposed && generation == _generation) {
            _inFlight = null;
            notifyListeners();
          }
        });
    _inFlight = request;
    notifyListeners();
    return request;
  }

  Future<void> setRange(ReportRange range) {
    if (_disposed || range == _query.range) return _inFlight ?? Future.value();
    _query = ReportQuery(range: range, month: _query.month, now: _clock());
    _inFlight = null;
    return refresh();
  }

  Future<void> changeMonth(int offset) {
    if (_disposed) return Future.value();
    _query = ReportQuery(
      range: ReportRange.month,
      month: DateTime(_query.month.year, _query.month.month + offset),
      now: _clock(),
    );
    _inFlight = null;
    return refresh();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
