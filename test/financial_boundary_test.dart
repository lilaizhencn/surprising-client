import 'support/core_snapshot_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

String version(int sequence) =>
    '${sequence.toString().padLeft(19, '0')}:0000000000';
Map<String, dynamic> snapshot(int sequence) => {
  'op': 'snapshot',
  'userId': 1,
  'productLine': 'SPOT',
  'data': {
    'status': 'READY',
    'snapshotVersion': version(sequence),
    'account': {
      'positionMode': 'ONE_WAY',
      'balances': <dynamic>[],
      'reservations': <dynamic>[],
      'positions': <dynamic>[],
      'leverages': <dynamic>[],
    },
    'openOrders': <dynamic>[],
    'triggerOrders': <dynamic>[],
    'positionRisks': <dynamic>[],
  },
};
Map<String, dynamic> balance(Object? available) => {
  'asset': 'USDT',
  'availableUnits': available,
  'lockedUnits': 0,
};

void main() {
  test('financial int64 parsing is exact and does not round or saturate', () {
    expect(parseInt64('9223372036854775807'), 9223372036854775807);
    expect(parseInt64('-9223372036854775808'), -9223372036854775808);
    expect(parseInt64('9007199254740993'), 9007199254740993);
    expect(parseInt64(0), 0);
    for (final value in <Object?>[
      null,
      '',
      'invalid',
      '1.5',
      1.5,
      1.0,
      '1e3',
      'NaN',
      'Infinity',
      double.nan,
      double.infinity,
      true,
      '9223372036854775808',
      '-9223372036854775809',
      ' 1',
      '01',
    ]) {
      expect(parseInt64(value), isNull, reason: '$value');
      expect(() => requireInt64(value, 'amount'), throwsFormatException);
    }
    expect(() => asInt('1.5'), throwsFormatException);
  });

  test('generic number helpers never hide nonnull malformed data', () {
    expect(asInt(null, fallback: 7), 7);
    expect(asNullableInt(null), isNull);
    expect(asDouble(null, fallback: 1.25), 1.25);
    expect(asInt('9223372036854775807'), 9223372036854775807);
    expect(asNullableInt('-9223372036854775808'), -9223372036854775808);
    expect(asDouble('-1.25'), -1.25);
    for (final value in <Object>[
      '',
      'invalid',
      '1.5',
      1.5,
      double.nan,
      double.infinity,
      '9223372036854775808',
    ]) {
      expect(() => asInt(value), throwsFormatException);
      expect(() => asNullableInt(value), throwsFormatException);
    }
    for (final value in <Object>[
      '',
      'invalid',
      'NaN',
      'Infinity',
      double.nan,
      double.infinity,
    ]) {
      expect(() => asDouble(value), throwsFormatException);
    }
  });

  test(
    'product balances require identity, exact amounts and declared scale',
    () {
      for (final input in [
        <String, dynamic>{},
        {'accountType': 'SPOT', ...balance('invalid'), 'equityUnits': 0},
        {'accountType': 'SPOT', ...balance(0), 'equityUnits': null},
      ]) {
        expect(() => ProductBalance.fromJson(input), throwsFormatException);
      }
      final zero = ProductBalance.fromJson({
        'accountType': 'SPOT',
        ...balance(0),
        'equityUnits': 0,
      });
      expect(zero.available, isNull);
      expect(zero.locked, isNull);
      expect(zero.equity, isNull);
      final exact = ProductBalance.fromJson({
        'accountType': 'SPOT',
        ...balance('9007199254740993'),
        'equityUnits': '9007199254740993',
      }, scaleUnits: 1000000);
      expect(exact.availableUnits, 9007199254740993);
      expect(exact.available, isNotNull);
    },
  );

  test('unknown and conflicting instrument identities are never tradable', () {
    for (final json in [
      <String, dynamic>{},
      {'contractType': 'UNRECOGNIZED'},
      {'contractType': 'LINEAR_PERPETUAL', 'instrumentType': 'UNKNOWN'},
      {'contractType': 'LINEAR_DELIVERY', 'instrumentType': 'PERPETUAL'},
      {'contractType': 'SPOT', 'productLine': 'LINEAR_PERPETUAL'},
    ]) {
      expect(() => Instrument.fromJson(json), throwsFormatException);
    }
    for (final mode in ProductMode.values) {
      final market = Instrument.fromJson({'contractType': mode.contractType});
      expect(market.mode, mode);
      expect(market.canPlaceOrder(reduceOnly: false), isFalse);
      expect(market.status, 'UNAVAILABLE');
      expect(market.quoteAsset, isEmpty);
      expect(market.priceTickUnits, 0);
    }
    final unknownStatus = Instrument.fromJson({
      'contractType': 'LINEAR_PERPETUAL',
      'status': 'UNRECOGNIZED',
    });
    expect(unknownStatus.canPlaceOrder(reduceOnly: false), isFalse);
  });

  test('complete empty snapshot is legitimate but missing arrays are not', () {
    for (final missing in [
      'balances',
      'reservations',
      'positions',
      'leverages',
      'openOrders',
      'triggerOrders',
      'positionRisks',
      'positionMode',
    ]) {
      final message = snapshot(1);
      final data = message['data'] as Map<String, dynamic>;
      final account = data['account'] as Map<String, dynamic>;
      if (account.containsKey(missing)) {
        account.remove(missing);
      } else {
        data.remove(missing);
      }
      final view = PrivateView();
      expect(view.apply(message), isFalse, reason: missing);
      expect(view.ready, isFalse);
      expect(view.fence, isEmpty);
    }
    final view = PrivateView();
    expect(view.apply(snapshot(1)), isTrue);
    expect(view.ready, isTrue);
    expect(view.rows('balance'), isEmpty);
  });

  test('bad snapshots preserve last good state and fence, then recover', () {
    final view = PrivateView();
    final initial = snapshot(1);
    ((initial['data'] as Map)['account'] as Map)['balances'] = [balance(42)];
    expect(view.apply(initial), isTrue);
    final invalid = snapshot(5);
    ((invalid['data'] as Map)['account'] as Map)['balances'] = [
      balance(99),
      {'asset': 'BTC', 'availableUnits': 'invalid', 'lockedUnits': 0},
    ];
    expect(view.apply(invalid), isFalse);
    expect(view.status, 'STALE');
    expect(view.ready, isFalse);
    expect(view.fence, version(1));
    expect(view.rows('balance').single['availableUnits'], 42);
    final repaired = snapshot(5);
    ((repaired['data'] as Map)['account'] as Map)['balances'] = [balance(99)];
    expect(view.apply(repaired), isTrue);
    expect(view.ready, isTrue);
    expect(view.fence, version(5));
    expect(view.rows('balance').single['availableUnits'], 99);
  });

  test(
    'snapshot rejects duplicate keys and bad identity without advancing fence',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (data) =>
            (data['account'] as Map)['balances'] = [balance(1), balance(2)],
        (data) => (data['account'] as Map)['positionMode'] = 'UNKNOWN',
        (data) => (data['account'] as Map)['productLine'] = 'OPTION',
        (data) => (data['account'] as Map)['userId'] = 2,
        (data) => data['openOrders'] = [null],
        (data) => data['triggerOrders'] = {},
        (data) => (data['account'] as Map)['balances'] = [
          balance('9223372036854775808'),
        ],
      ]) {
        final view = PrivateView()..apply(snapshot(1));
        final next = snapshot(2);
        mutate(next['data'] as Map<String, dynamic>);
        expect(view.apply(next), isFalse);
        expect(view.ready, isFalse);
        expect(view.fence, version(1));
      }
    },
  );

  test(
    'every entity kind is validated before replacing an account snapshot',
    () {
      final rows = <String, Map<String, dynamic>>{
        'balances': {'asset': 'USDT', 'availableUnits': 1, 'lockedUnits': 0},
        'reservations': {
          'orderId': 1,
          'instrumentId': '42',
          'asset': 'USDT',
          'kind': 'SPOT_ASSET',
          'reservedUnits': 1,
          'releasedUnits': 0,
          'consumedUnits': 0,
          'orderQuantitySteps': 1,
        },
        'positions': completeCoreRow('position', {
          'instrumentId': '42',
          'signedQuantitySteps': 1,
        }),
        'leverages': {
          'instrumentId': '42',
          'marginMode': 'CROSS',
          'leveragePpm': 1000000,
        },
        'openOrders': completeCoreRow('order', {
          'instrumentId': '42',
          'orderId': 1,
          'status': 'OPEN',
        }),
        'triggerOrders': completeCoreRow('trigger', {
          'instrumentId': '42',
          'triggerOrderId': 2,
          'status': 'PENDING',
          'priceSource': 'INDEX',
        }),
        'positionRisks': completeCoreRow('risk', {
          'instrumentId': '42',
          'unrealizedPnlUnits': 0,
        }),
      };
      final financialField = {
        'balances': 'availableUnits',
        'reservations': 'reservedUnits',
        'positions': 'entryPriceTicks',
        'leverages': 'leveragePpm',
        'openOrders': 'priceTicks',
        'triggerOrders': 'triggerPriceTicks',
        'positionRisks': 'unrealizedPnlUnits',
      };
      for (final entry in rows.entries) {
        final view = PrivateView()..apply(snapshot(1));
        final next = snapshot(2);
        final data = next['data'] as Map<String, dynamic>;
        final account = data['account'] as Map<String, dynamic>;
        final target = account.containsKey(entry.key) ? account : data;
        target[entry.key] = [entry.value];
        expect(view.apply(next), isTrue, reason: entry.key);
        final invalid = snapshot(3);
        final invalidData = invalid['data'] as Map<String, dynamic>;
        final invalidTarget = account.containsKey(entry.key)
            ? invalidData['account'] as Map
            : invalidData;
        invalidTarget[entry.key] = [
          {...entry.value, financialField[entry.key]!: 'NaN'},
        ];
        expect(view.apply(invalid), isFalse, reason: entry.key);
        expect(view.fence, version(2));
        expect(view.ready, isFalse);
        expect(view.apply(next), isTrue);
        expect(view.ready, isTrue);
      }
    },
  );

  test('wallet unknown or malformed amounts never become a zero portfolio', () {
    expect(() => WalletPortfolio.fromJson({}), throwsFormatException);
    expect(WalletPortfolio.fromJson({'assets': []}).totalBalance, 0);
    final asset = <String, dynamic>{
      'symbol': 'USDT',
      'availableBalance': '1.25',
      'lockedBalance': '0',
      'totalBalance': '1.25',
    };
    expect(
      WalletPortfolio.fromJson({
        'assets': [asset],
      }).totalBalance,
      1.25,
    );
    for (final bad in [null, 'bad', 'NaN', 'Infinity']) {
      expect(
        () => WalletPortfolio.fromJson({
          'assets': [
            {...asset, 'availableBalance': bad},
          ],
        }),
        throwsFormatException,
      );
    }
    expect(
      () => WalletPortfolio.fromJson({
        'assets': [asset, asset],
      }),
      throwsFormatException,
    );
  });

  test('snapshot fences obey backend long and ordinal ranges', () {
    final view = PrivateView()..apply(snapshot(1));
    for (final invalid in [
      '9223372036854775808:0000000000',
      '0000000000000000002:2147483648',
    ]) {
      final frame = snapshot(2);
      (frame['data'] as Map)['snapshotVersion'] = invalid;
      expect(view.apply(frame), isFalse);
      expect(view.fence, version(1));
      expect(view.ready, isFalse);
    }
    final highest = snapshot(2);
    (highest['data'] as Map)['snapshotVersion'] =
        '9223372036854775807:2147483647';
    expect(view.apply(highest), isTrue);
    expect(view.ready, isTrue);
  });

  test('invalid account deltas do not turn known balances into zero', () {
    final view = PrivateView();
    final initial = snapshot(1);
    ((initial['data'] as Map)['account'] as Map)['balances'] = [balance(42)];
    expect(view.apply(initial), isTrue);
    final bad = {
      'op': 'event',
      'channel': 'accountState',
      'data': {
        'version': version(2),
        'entityId': 'user',
        'value': {
          'balances': [
            balance(100),
            {'asset': 'BTC', 'availableUnits': 'bad', 'lockedUnits': 0},
          ],
        },
      },
    };
    expect(view.apply(bad), isFalse);
    expect(view.ready, isFalse);
    expect(view.fence, version(1));
    expect(view.rows('balance').single['availableUnits'], 42);
    expect(view.apply(snapshot(3)), isTrue);
    expect(view.ready, isTrue);
  });

  test(
    'malformed delta version invalidates authority; legitimate old deltas do not',
    () {
      for (final invalid in [
        null,
        '',
        'bad',
        '9223372036854775808:0000000000',
        '0000000000000000002:2147483648',
      ]) {
        final initial = snapshot(3);
        ((initial['data'] as Map)['account'] as Map)['balances'] = [
          balance(42),
        ];
        final view = PrivateView()..apply(initial);
        Map<String, dynamic> update(Object? nextVersion) => {
          'op': 'event',
          'channel': 'accountState',
          'data': {
            'version': nextVersion,
            'entityId': 'user',
            'value': {
              'balances': [balance(99)],
            },
          },
        };
        for (final old in [version(2), version(3)]) {
          expect(view.apply(update(old)), isFalse);
          expect(view.ready, isTrue);
        }
        expect(view.apply(update(invalid)), isFalse);
        expect(view.status, 'STALE');
        expect(view.ready, isFalse);
        expect(view.fence, version(3));
        expect(view.rows('balance').single['availableUnits'], 42);
        expect(view.apply(snapshot(4)), isTrue);
        expect(view.ready, isTrue);
      }
    },
  );

  test(
    'candle input rejects bad timestamps and nonfinite or inconsistent prices',
    () {
      final normal = <String, dynamic>{
        'openTime': '2026-10-22T01:00:00Z',
        'openPrice': 100,
        'highPrice': 110,
        'lowPrice': 90,
        'closePrice': 105,
        'baseVolume': 4,
      };
      expect(Candle.fromJson(normal).close, 105);
      expect(
        Candle.fromJson({
          ...normal,
          'openPrice': 0,
          'highPrice': 0,
          'lowPrice': 0,
          'closePrice': 0,
          'baseVolume': 0,
        }).volume,
        0,
      );
      for (final patch in <Map<String, dynamic>>[
        {'openTime': null},
        {'openTime': 'invalid'},
        {'openPrice': 'NaN'},
        {'closePrice': 'Infinity'},
        {'baseVolume': -1},
        {'lowPrice': -1},
        {'highPrice': 1},
        {'lowPrice': 101},
        {'openPrice': null},
      ]) {
        expect(
          () => Candle.fromJson({...normal, ...patch}),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'order book boundaries reject malformed quantities and keep fifty levels',
    () {
      for (final invalid in [
        {'priceTicks': -1, 'quantitySteps': 1, 'orderCount': 1},
        {'priceTicks': 1, 'quantitySteps': -1, 'orderCount': 1},
        {'priceTicks': 1, 'quantitySteps': '1.5', 'orderCount': 1},
      ]) {
        expect(() => OrderBookLevel.fromJson(invalid), throwsFormatException);
      }
      final book = OrderBook.fromJson({
        'symbol': 'BTC-USDT',
        'sequence': 1,
        'bids': [
          for (var i = 1; i <= 100; i++)
            {'priceTicks': i, 'quantitySteps': 1, 'orderCount': 1},
        ],
        'asks': <dynamic>[],
      });
      expect(book.bids.length, 50);
      expect(book.bids.first.priceTicks, 100);
      expect(book.asks, isEmpty);
    },
  );
}
