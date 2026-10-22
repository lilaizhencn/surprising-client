import 'dart:async';

import 'api.dart';
import 'portfolio_income.dart';

/// Owns income refresh and expiry. Income estimates cannot alter spendable funds.
class PortfolioIncomeState {
  PortfolioIncomeState(
    this.api, {
    required this.owner,
    required this.onChanged,
  });

  final ApiClient api;
  final ({int? userId, int epoch}) Function() owner;
  final void Function() onChanged;
  PortfolioIncomeSummary? _summary;
  int? _userId;
  Stopwatch? _elapsed;
  Timer? _refreshTimer, _expiryTimer;
  int _request = 0;
  bool _loading = false, _closed = false;

  PortfolioIncome? current(String scope) =>
      !_closed && _userId == owner().userId
      ? _summary?.fresh(scope, _elapsed?.elapsed ?? Duration.zero)
      : null;

  void reset() {
    ++_request;
    _loading = false;
    _summary = null;
    _userId = null;
    _elapsed?.stop();
    _elapsed = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _expiryTimer?.cancel();
    _expiryTimer = null;
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final remaining = _summary?.nextExpiry(_elapsed?.elapsed ?? Duration.zero);
    if (remaining == null || _closed) return;
    _expiryTimer = Timer(remaining, () {
      if (_closed) return;
      onChanged();
      _scheduleExpiry();
    });
  }

  Future<void> refresh() async {
    final initialOwner = owner();
    final id = initialOwner.userId;
    if (_closed || id == null || _loading) return;
    final request = ++_request;
    bool current() =>
        !_closed && request == _request && owner() == initialOwner;
    _loading = true;
    _refreshTimer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(refresh());
    });
    final elapsed = Stopwatch()..start();
    try {
      final result = await api.get('/api/v1/portfolio/income', userId: id);
      final summary = PortfolioIncomeSummary.fromJson(result);
      if (!current()) {
        elapsed.stop();
        return;
      }
      _elapsed?.stop();
      _elapsed = elapsed;
      _summary = summary;
      _userId = id;
      _scheduleExpiry();
    } catch (_) {
      elapsed.stop();
      if (!current()) return;
      _summary = null;
      _expiryTimer?.cancel();
    } finally {
      if (request == _request) _loading = false;
      if (current()) onChanged();
    }
  }

  void dispose() {
    _closed = true;
    reset();
  }
}
