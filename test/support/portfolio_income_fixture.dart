import 'dart:async';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/portfolio_income.dart';

Map<String, dynamic> incomeFixture({bool overviewAvailable = true}) {
  final generated = DateTime.utc(2026, 10, 20, 4, 0, 30);
  Map<String, dynamic> row(String equity, String pnl) => {
    'available': true,
    'status': 'AVAILABLE',
    'amountUsdt': pnl,
    'percent': '2.5',
    'currentEquityUsdt': equity,
    'openingEquityUsdt': '10',
    'asOf': '2026-10-20T04:00:00Z',
  };
  return {
    'currency': 'USDT',
    'timeZone': '+08:00',
    'periodStart': '2026-10-19T16:00:00Z',
    'generatedAt': generated.toIso8601String(),
    'groups': {
      for (final scope in PortfolioIncomeSummary.scopes) scope: row('0', '0'),
      'overview': overviewAvailable
          ? row('17', '3')
          : {
              'available': false,
              'status': 'SNAPSHOT_UNAVAILABLE',
              'amountUsdt': null,
              'percent': null,
              'currentEquityUsdt': null,
              'openingEquityUsdt': null,
              'asOf': null,
            },
      'funding': row('12', '1'),
      'SPOT': row('12', '1'),
      'trading': row('5', '2'),
      'USDT_PERPETUAL': row('5', '2'),
    },
  };
}

class IncomeApi extends ApiClient {
  IncomeApi({this.overviewAvailable = true}) : super(const AppConfig());
  bool overviewAvailable, fail = false;
  Completer<Map<String, dynamic>>? pending;
  final owners = <int?>[];
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    if (path != '/api/v1/portfolio/income') {
      throw StateError('unexpected request');
    }
    owners.add(userId);
    if (fail) throw ApiException(503, 'income unavailable');
    return pending == null
        ? incomeFixture(overviewAvailable: overviewAvailable)
        : pending!.future;
  }
}
