import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/trading/trading_order_state.dart';

final _instrument = Instrument.fromJson({
  'instrumentId': '42',
  'symbol': 'BTC-USDT',
  'instrumentType': 'PERPETUAL',
  'contractType': 'LINEAR_PERPETUAL',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': 'USDT',
  'priceTickUnits': 1,
  'quantityStepUnits': 1,
  'quoteScaleUnits': 1,
  'status': 'TRADING',
});
Map<String, dynamic> _row(Map<String, dynamic> fields) => {
  'userId': 7,
  'productLine': 'LINEAR_PERPETUAL',
  'commandId': null,
  'clientOrderId': null,
  'instrumentId': null,
  'cancelOrderId': null,
  'amendRequestId': null,
  'amendOrderId': null,
  'cancelPlan': null,
  'clientAlgoOrderId': null,
  'ocoTakeProfitClientId': null,
  'ocoStopLossClientId': null,
  'clientTriggerOrderId': null,
  'cancelTriggerOrderId': null,
  ...fields,
};
Map<String, dynamic> _command({Object? userId = 7}) =>
    _row({'userId': userId, 'commandId': 'original-command'});

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  Completer<Map<String, String>>? gate;
  int reads = 0, writes = 0;
  bool failReads = false;
  @override
  Future<Map<String, String>> read() async {
    reads++;
    if (failReads) throw StateError('storage unavailable');
    return gate?.future ?? Future.value({...values});
  }

  @override
  Future<void> write(Map<String, String> next) async {
    writes++;
    values = {...next};
  }
}

class _Api extends ApiClient {
  _Api() : super(const AppConfig());
  final posts = <String>[];
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = false,
  }) async {
    posts.add(path);
    throw const SocketException('response lost after write');
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async => throw StateError('unexpected network read: $path');
}

class _Fixture {
  final settings = _Settings(), api = _Api();
  int? userId = 7;
  int epoch = 0, selection = 0;
  String? token = 'original';
  ProductMode product = ProductMode.linear;
  String symbol = 'BTC-USDT';
  List<Position> positions = const [];
  late final orders = TradingOrderState(
    api: api,
    settingsStore: settings,
    offline: false,
    context: () => (
      userId: userId,
      accessToken: token,
      epoch: epoch,
      selection: selection,
      product: product,
      symbol: symbol,
      instrument: _instrument,
      positionMode: 'ONE_WAY',
      positions: positions,
      instruments: [_instrument],
      onlyCurrentPair: true,
      disabledProducts: <ProductMode>{},
    ),
    persist: persist,
    refreshPrivateData: () async {},
    onFeedback: (_, _) {},
  );
  Future<void> _tail = Future.value();
  Future<bool> persist({PendingTradingOrder? completedTradingIntent}) async {
    final previous = _tail, done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (!orders.restored && !await orders.restore()) return false;
      if (completedTradingIntent != null &&
          !orders.ownsIntent(completedTradingIntent)) {
        return false;
      }
      await settings.write({
        'theme': 'light',
        'pendingTradingOrders': jsonEncode(
          orders.settingsRows(completed: completedTradingIntent),
        ),
      });
      return completedTradingIntent == null ||
          orders.completeSaved(completedTradingIntent);
    } catch (_) {
      return false;
    } finally {
      done.complete();
    }
  }

  Future<void> place() => orders.placeOrder(
    side: 'BUY',
    orderType: 'LIMIT',
    timeInForce: 'GTC',
    price: 1,
    priceText: '1',
    quantitySteps: 1,
    marginMode: 'CROSS',
    positionSide: 'NET',
    reduceOnly: false,
    postOnly: false,
  );
  void dispose() {
    orders.dispose();
    api.dispose();
  }
}

// A failed restore must return before reading command parameters or sending I/O.
class _UnreadOrder implements OrderModel {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('command was evaluated before restore');
}

class _UnreadAlgo implements AlgoOrderModel {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('command was evaluated before restore');
}

class _UnreadTrigger implements TriggerOrderModel {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('command was evaluated before restore');
}

void main() {
  for (final id in [
    null,
    0,
    -1,
    'invalid',
    '1.5',
    1.5,
    '9223372036854775808',
    true,
    <String, dynamic>{},
  ]) {
    test('invalid stored account identity is rejected: $id', () {
      final f = _Fixture();
      addTearDown(f.dispose);
      expect(
        () => f.orders.restoreSettings({
          'pendingTradingOrders': jsonEncode([_command(userId: id)]),
        }),
        throwsFormatException,
      );
      expect(f.orders.restored, isFalse);
      expect(f.orders.pendingTradingCommand, isNull);
    });
  }
  for (final raw in ['{}', 'null', '"not-array"', '[null]', '[1]', '[[]]']) {
    test(
      'malformed pending container or row cannot become an empty account: $raw',
      () {
        final f = _Fixture();
        addTearDown(f.dispose);
        expect(
          () => f.orders.restoreSettings({'pendingTradingOrders': raw}),
          throwsFormatException,
        );
        expect(f.orders.restored, isFalse);
        expect(f.orders.pendingTradingCommand, isNull);
      },
    );
  }
  test(
    'validation is atomic when a later row is malformed or duplicates an earlier account',
    () {
      for (final later in [_command(userId: 'bad'), _command()]) {
        final f = _Fixture();
        try {
          expect(
            () => f.orders.restoreSettings({
              'pendingTradingOrders': jsonEncode([_command(), later]),
            }),
            throwsFormatException,
          );
          expect(f.orders.pendingTradingCommand, isNull);
          expect(f.orders.restored, isFalse);
          expect(() => f.orders.settingsRows(), throwsStateError);
        } finally {
          f.dispose();
        }
      }
    },
  );
  for (final values in [
    {'pendingTradingUser': '7'},
    {
      'pendingTradingCommand': 'old',
      'pendingTradingUser': '-1',
      'pendingTradingProduct': 'SPOT',
    },
    {
      'pendingTradingCommand': 'old',
      'pendingTradingUser': 'bad',
      'pendingTradingProduct': 'SPOT',
    },
    {
      'pendingTradingCommand': '',
      'pendingTradingUser': '7',
      'pendingTradingProduct': 'SPOT',
    },
    {
      'pendingTradingCommand': 'old',
      'pendingTradingUser': '7',
      'pendingTradingProduct': 'UNKNOWN',
    },
  ]) {
    test('incomplete or invalid legacy fields block restoration: $values', () {
      final f = _Fixture();
      addTearDown(f.dispose);
      expect(() => f.orders.restoreSettings(values), throwsFormatException);
      expect(f.orders.restored, isFalse);
    });
  }
  test(
    'legacy command remains recoverable and migrates to modern settings',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.settings.values = {
        'pendingTradingCommand': 'old-command',
        'pendingTradingUser': '7',
        'pendingTradingProduct': 'SPOT',
      };
      expect(await f.persist(), isTrue);
      expect(f.orders.pendingTradingCommand!.commandId, 'old-command');
      expect(f.orders.pendingTradingCommand!.product, ProductMode.spot);
      expect(f.settings.values.containsKey('pendingTradingCommand'), isFalse);
      expect(
        jsonDecode(
          f.settings.values['pendingTradingOrders']!,
        ).single['commandId'],
        'old-command',
      );
    },
  );

  final plan = CancellationPlan(
    id: 'original-plan',
    batches: [
      CancellationBatch('original-batch', [
        9007199254740993,
        9223372036854775807,
      ]),
    ],
    issued: true,
  );
  final valid = <String, Map<String, dynamic>>{
    'command': _command(),
    'order': _row({'clientOrderId': 'original-order', 'instrumentId': '42'}),
    'cancel': _row({'cancelOrderId': '9007199254740993'}),
    'amend': _row({
      'productLine': 'SPOT',
      'amendRequestId': 'original-amend',
      'amendOrderId': '9223372036854775807',
      'clientOrderId': 'replacement',
      'instrumentId': '42',
    }),
    'algo': _row({'clientAlgoOrderId': 'original-algo', 'instrumentId': '42'}),
    'trigger': _row({
      'clientTriggerOrderId': 'original-trigger',
      'instrumentId': '42',
    }),
    'trigger cancel': _row({
      'cancelTriggerOrderId': '9007199254740993',
      'instrumentId': '42',
    }),
    'spot trigger cancel': _row({
      'productLine': 'SPOT',
      'cancelTriggerOrderId': '9007199254740993',
      'instrumentId': '42',
    }),
    'oco': _row({
      'ocoTakeProfitClientId': 'original-tp',
      'ocoStopLossClientId': 'original-sl',
      'instrumentId': '42',
    }),
    'batch': _row({
      'productLine': 'SPOT',
      'cancelPlan': plan.toJson(),
      'commandId': 'in-flight-batch',
    }),
  };
  for (final entry in valid.entries) {
    test('nullable modern fields preserve ${entry.key} intent exactly', () {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.orders.restoreSettings({
        'pendingTradingOrders': jsonEncode([entry.value]),
      });
      expect(f.orders.restored, isTrue);
      expect(f.orders.pendingTradingCommand!.userId, 7);
      final restored = f.orders.settingsRows().single;
      for (final field in entry.value.entries) {
        if (field.value != null &&
            ![
              'cancelOrderId',
              'amendOrderId',
              'cancelTriggerOrderId',
            ].contains(field.key)) {
          expect(restored[field.key], field.value, reason: field.key);
        }
      }
      if (entry.key == 'batch') {
        expect(f.orders.pendingTradingCommand!.cancelPlan!.issued, isTrue);
        expect(
          f.orders.pendingTradingCommand!.cancelPlan!.batches.single.orderIds,
          [9007199254740993, 9223372036854775807],
        );
      }
      f.orders.resetAccount();
      expect(f.orders.pendingTradingCommand, isNotNull);
    });
  }
  for (final row in [
    _row({}),
    _row({'productLine': 'UNKNOWN', 'commandId': 'old'}),
    _row({'cancelOrderId': 0}),
    _row({'cancelOrderId': '9223372036854775808'}),
    _row({'clientAlgoOrderId': 'algo'}),
    _row({'amendRequestId': 'amend', 'amendOrderId': 4, 'instrumentId': '42'}),
    _row({'ocoTakeProfitClientId': 'tp', 'instrumentId': '42'}),
    _row({
      'clientOrderId': 'order',
      'clientAlgoOrderId': 'algo',
      'instrumentId': '42',
    }),
    _row({
      'productLine': 'SPOT',
      'clientTriggerOrderId': 'trigger',
      'instrumentId': '42',
    }),
    _row({
      'productLine': 'SPOT',
      'cancelPlan': {...plan.toJson(), 'failures': {}},
    }),
  ]) {
    test('invalid recovery intention cannot be silently skipped: $row', () {
      final f = _Fixture();
      addTearDown(f.dispose);
      expect(
        () => f.orders.restoreSettings({
          'pendingTradingOrders': jsonEncode([row]),
        }),
        throwsFormatException,
      );
      expect(f.orders.restored, isFalse);
    });
  }
  test(
    'more than 128 unresolved accounts is rejected without partial mutation',
    () {
      final f = _Fixture();
      addTearDown(f.dispose);
      expect(
        () => f.orders.restoreSettings({
          'pendingTradingOrders': jsonEncode([
            for (var id = 1; id <= 129; id++) _command(userId: id),
          ]),
        }),
        throwsFormatException,
      );
      expect(f.orders.restored, isFalse);
      expect(f.orders.pendingTradingCommand, isNull);
    },
  );
  test(
    'a pre-bootstrap theme save restores and preserves existing monetary identity',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.settings.values['pendingTradingOrders'] = jsonEncode([_command()]);
      expect(await f.persist(), isTrue);
      expect(
        jsonDecode(
          f.settings.values['pendingTradingOrders']!,
        ).single['commandId'],
        'original-command',
      );
      expect(f.api.posts, isEmpty);
    },
  );
  test(
    'a pre-bootstrap order cannot replace an existing unresolved command',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.settings.values['pendingTradingOrders'] = jsonEncode([_command()]);
      await f.place();
      expect(f.api.posts, isEmpty);
      expect(f.settings.writes, 0);
      expect(f.orders.pendingTradingCommand!.commandId, 'original-command');
    },
  );
  test(
    'all public monetary entries stop before invalid restored data or input evaluation',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.settings.values['pendingTradingOrders'] = '{}';
      await f.place();
      await f.orders.checkPendingTradingCommand();
      await f.orders.cancelOpenSpotOrders(onlyCurrentPair: true);
      await f.orders.amendSpotOrder(_UnreadOrder(), _instrument, '1', '1');
      await f.orders.cancelOrder(_UnreadOrder());
      await f.orders.placeAlgoOrder(
        const AlgoOrderDraft(
          algoType: 'TWAP',
          side: 'BUY',
          priceTicks: 1,
          quantitySteps: 1,
          childQuantitySteps: 1,
          intervalSeconds: 1,
          durationSeconds: 5,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
        ),
      );
      await f.orders.cancelAlgoOrder(_UnreadAlgo());
      await f.orders.placeOco(const []);
      await f.orders.placeTriggerOrders(const []);
      await f.orders.cancelTriggerOrder(_UnreadTrigger());
      expect(f.api.posts, isEmpty);
      expect(f.settings.writes, 0);
      expect(f.orders.lastError, contains('未发送请求'));
    },
  );
  for (final changed in [
    'account',
    'token',
    'product',
    'selection round trip',
  ]) {
    test(
      'late restore across $changed change cannot submit a command for the next selection',
      () async {
        final f = _Fixture();
        addTearDown(f.dispose);
        final gate = Completer<Map<String, String>>();
        f.settings.gate = gate;
        final issuing = f.place();
        if (changed == 'account') {
          f.userId = 8;
          f.epoch++;
        }
        if (changed == 'token') f.token = 'rotated';
        if (changed == 'product') f.product = ProductMode.inverse;
        if (changed == 'selection round trip') f.selection += 2;
        gate.complete({});
        await issuing;
        expect(f.api.posts, isEmpty);
        expect(f.settings.writes, 0);
      },
    );
  }
  test(
    'restore is singleflight and storage errors can be retried without empty-state acknowledgement',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final gate = Completer<Map<String, String>>();
      f.settings.gate = gate;
      final first = f.orders.restore(), second = f.orders.restore();
      expect(f.settings.reads, 1);
      gate.complete({'pendingTradingOrders': '{}'});
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(f.orders.restored, isFalse);
      f.settings.gate = null;
      f.settings.values['pendingTradingOrders'] = jsonEncode([_command()]);
      expect(await f.orders.restore(), isTrue);
      expect(f.settings.reads, 2);
    },
  );
  test(
    'fresh restored empty storage permits one explicit write and persists identity before sending',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      await f.place();
      expect(f.orders.restored, isTrue);
      expect(f.api.posts, hasLength(1));
      expect(f.orders.pendingTradingCommand!.clientOrderId, isNotNull);
      expect(
        jsonDecode(
          f.settings.values['pendingTradingOrders']!,
        ).single['clientOrderId'],
        f.orders.pendingTradingCommand!.clientOrderId,
      );
    },
  );
  for (final oco in [false, true]) {
    test(
      'long-min short position accepts a small ${oco ? 'OCO' : 'trigger'} without abs overflow',
      () async {
        final f = _Fixture();
        addTearDown(f.dispose);
        f.positions = const [
          Position(
            symbol: 'BTC-USDT',
            instrumentId: '42',
            marginMode: 'CROSS',
            positionSide: 'NET',
            signedQuantitySteps: -9223372036854775808,
            entryPriceTicks: 100,
            realizedPnlUnits: 0,
          ),
        ];
        const tp = TriggerOrderDraft(
          side: 'BUY',
          triggerType: 'TAKE_PROFIT',
          triggerPriceTicks: 90,
          quantitySteps: 1,
          marginMode: 'CROSS',
          positionSide: 'NET',
        );
        const sl = TriggerOrderDraft(
          side: 'BUY',
          triggerType: 'STOP_LOSS',
          triggerPriceTicks: 110,
          quantitySteps: 1,
          marginMode: 'CROSS',
          positionSide: 'NET',
        );
        if (oco) {
          await f.orders.placeOco([tp, sl]);
        } else {
          await f.orders.placeTriggerOrders([tp]);
        }
        expect(f.api.posts, hasLength(1));
        expect(f.orders.lastError, isNot(contains('数量不能超过')));
      },
    );
  }
}
