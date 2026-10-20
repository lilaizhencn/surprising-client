/// Read-only estimates from committed portfolio history. Never spendable funds.
class PortfolioIncome {
  const PortfolioIncome._({
    required this.available,
    required this.status,
    required this.asOf,
    required this.amount,
    required this.percent,
    required this.currentEquity,
  });
  final bool available;
  final String status;
  final DateTime? asOf;
  final String? amount, percent, currentEquity;
  double? get amountValue => amount == null ? null : double.parse(amount!);
  double? get percentValue => percent == null ? null : double.parse(percent!);
  double? get equityValue =>
      currentEquity == null ? null : double.parse(currentEquity!);

  factory PortfolioIncome.fromJson(Map<String, dynamic> json) {
    final available = json['available'];
    final status = json['status'];
    if (available is! bool ||
        status is! String ||
        !const {
          'AVAILABLE',
          'SNAPSHOT_UNAVAILABLE',
          'TRANSFER_PENDING',
          'PRICE_UNAVAILABLE',
          'PERIOD_START',
          'HISTORY_UNAVAILABLE',
        }.contains(status) ||
        available != (status == 'AVAILABLE')) {
      throw const FormatException('收益状态不完整');
    }
    final at = json['asOf'] == null ? null : _instant(json['asOf']);
    final amount = _decimal(json['amountUsdt']);
    final percent = _decimal(json['percent']);
    final equity = _decimal(json['currentEquityUsdt']);
    _decimal(json['openingEquityUsdt']);
    if (available &&
            (at == null ||
                amount == null ||
                equity == null ||
                json['openingEquityUsdt'] == null) ||
        !available && (amount != null || percent != null)) {
      throw const FormatException('收益金额不完整');
    }
    return PortfolioIncome._(
      available: available,
      status: status,
      asOf: at,
      amount: amount,
      percent: percent,
      currentEquity: equity,
    );
  }
}

class PortfolioIncomeSummary {
  PortfolioIncomeSummary._(this.periodStart, this.generatedAt, this.groups);
  final DateTime periodStart, generatedAt;
  final Map<String, PortfolioIncome> groups;
  static const maximumAge = Duration(minutes: 2);
  static const scopes = {
    'overview',
    'funding',
    'trading',
    'SPOT',
    'USDT_PERPETUAL',
    'COIN_PERPETUAL',
    'USDT_DELIVERY',
    'COIN_DELIVERY',
    'OPTION',
  };

  factory PortfolioIncomeSummary.fromJson(Map<String, dynamic> json) {
    if (json['currency'] != 'USDT' || json['timeZone'] != '+08:00') {
      throw const FormatException('收益计价或业务日不匹配');
    }
    final generated = _instant(json['generatedAt']);
    final opening = _instant(json['periodStart']);
    final exchangeDate = generated.add(const Duration(hours: 8));
    final expected = DateTime.utc(
      exchangeDate.year,
      exchangeDate.month,
      exchangeDate.day,
    ).subtract(const Duration(hours: 8));
    final raw = json['groups'];
    if (opening != expected ||
        raw is! Map ||
        raw.keys.toSet().difference(scopes).isNotEmpty ||
        scopes.difference(raw.keys.toSet()).isNotEmpty) {
      throw const FormatException('收益业务日或账户不完整');
    }
    final groups = <String, PortfolioIncome>{};
    for (final scope in scopes) {
      final row = raw[scope];
      if (row is! Map<String, dynamic>) throw const FormatException('收益账户不完整');
      final income = PortfolioIncome.fromJson(row);
      final at = income.asOf;
      if (at != null &&
          (at.isBefore(opening) ||
              at.isAfter(generated) ||
              at.millisecondsSinceEpoch % 60000 != 0)) {
        throw const FormatException('收益切点无效');
      }
      groups[scope] = income;
    }
    return PortfolioIncomeSummary._(
      opening,
      generated,
      Map.unmodifiable(groups),
    );
  }

  PortfolioIncome? fresh(String scope, Duration elapsed) {
    final row = groups[scope], at = groups[scope]?.asOf;
    if (at == null ||
        elapsed.isNegative ||
        generatedAt.difference(at) + elapsed >= maximumAge ||
        !generatedAt
            .add(elapsed)
            .isBefore(periodStart.add(const Duration(days: 1)))) {
      return null;
    }
    return row;
  }

  /// Next transition uses server time plus monotonic elapsed time, independent
  /// of a phone's wall clock, timezone, or a local clock adjustment.
  Duration? nextExpiry(Duration elapsed) {
    final remaining = <Duration>[];
    for (final scope in scopes) {
      if (fresh(scope, elapsed) == null) continue;
      remaining.add(
        maximumAge - generatedAt.difference(groups[scope]!.asOf!) - elapsed,
      );
    }
    if (remaining.isEmpty) return null;
    remaining.add(
      periodStart.add(const Duration(days: 1)).difference(generatedAt) -
          elapsed,
    );
    return remaining.reduce((a, b) => a < b ? a : b);
  }
}

DateTime _instant(dynamic value) {
  if (value is! String || !RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(value)) {
    throw const FormatException('收益时间无效');
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) throw const FormatException('收益时间无效');
  return parsed.toUtc();
}

String? _decimal(dynamic value) {
  if (value == null) return null;
  if (value is! String ||
      !RegExp(r'^-?(?:0|[1-9]\d{0,79})(?:\.\d{1,80})?$').hasMatch(value) ||
      !(double.tryParse(value)?.isFinite ?? false)) {
    throw const FormatException('收益金额无效');
  }
  return value;
}
