import 'dart:async';
import 'dart:collection';

/// Serial task queue so rapid multi-document uploads never trigger
/// overlapping inference calls competing for the same model resources.
///
/// Both model slots stay resident (see model_manager.dart); this queue only
/// serializes *calls*, it never swaps models in/out.
class InferenceQueue {
  InferenceQueue();

  final Queue<Future<void> Function()> _pending = Queue();
  bool _running = false;
  int depth = 0;
  int maxDepthObserved = 0;

  /// Enqueue [task] and return a future completing with the task result.
  Future<T> add<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _pending.add(() async {
      try {
        completer.complete(await task());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    depth = _pending.length;
    if (depth > maxDepthObserved) maxDepthObserved = depth;
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_running || _pending.isEmpty) return;
    _running = true;
    () async {
      while (_pending.isNotEmpty) {
        final next = _pending.removeFirst();
        depth = _pending.length;
        await next();
      }
      _running = false;
    }();
  }
}
