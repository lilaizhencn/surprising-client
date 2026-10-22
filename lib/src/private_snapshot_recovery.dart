import 'dart:async';

import 'models.dart';

/// Bounded baseline recovery for the six private account subscriptions.
class PrivateSnapshotRecovery {
  PrivateSnapshotRecovery({
    required this.ready,
    required this.resubscribe,
    required this.reconnect,
    this.timeout = const Duration(seconds: 3),
  });

  final bool Function(ProductMode) ready;
  final void Function(ProductMode) resubscribe;
  final void Function() reconnect;
  final Duration timeout;
  final _timers = <ProductMode, Timer>{};
  final _attempts = <ProductMode, int>{};
  bool _closed = false;

  void observe(ProductMode product) {
    if (_closed) return;
    if (ready(product)) {
      _timers.remove(product)?.cancel();
      _attempts.remove(product);
    } else if (!_timers.containsKey(product)) {
      _request(product);
    }
  }

  void _request(ProductMode product) {
    if (_closed) return;
    final attempt = (_attempts[product] ?? 0) + 1;
    _attempts[product] = attempt;
    resubscribe(product);
    _deadline(product, attempt);
  }

  void awaitSnapshot(ProductMode product) {
    if (_closed || ready(product) || _timers.containsKey(product)) return;
    _attempts[product] = 1;
    _deadline(product, 1);
  }

  void pause(ProductMode product) {
    _timers.remove(product)?.cancel();
    _attempts.remove(product);
  }

  void _deadline(ProductMode product, int attempt) {
    _timers[product] = Timer(timeout * (1 << (attempt - 1)), () {
      _timers.remove(product);
      if (_closed) return;
      if (ready(product)) {
        _attempts.remove(product);
      } else if (attempt < 3) {
        _request(product);
      } else {
        // One reconnect invalidates all account baselines, not six parallel retries.
        reset();
        reconnect();
      }
    });
  }

  void reset() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _attempts.clear();
  }

  void dispose() {
    _closed = true;
    reset();
  }
}
