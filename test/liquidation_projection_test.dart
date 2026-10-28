import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'account_risk_loading_test.dart' show riskInstrument;
import 'linear_delivery_trading_test.dart' show actor;
import 'support/authentication.dart';
import 'transfer_page_test.dart' show MemorySettings;

const row = {
  'liquidationOrderId': '9007199254740993',
  'instrumentId': '73',
  'quantitySteps': '10',
  'status': 'FILLED',
};

void main() {
  test(
    'native liquidation identity is exact and does not need a symbol alias',
    () {
      final order = LiquidationOrder.fromJson(row);
      expect(order.orderId, 9007199254740993);
      expect(order.instrumentId, '73');
      expect(order.quantitySteps, 10);
      expect(
        () => LiquidationOrder.fromJson({
          'orderId': '1',
          'instrumentId': '73',
          'quantitySteps': '10',
          'status': 'FILLED',
        }),
        throwsFormatException,
      );
    },
  );

  test(
    'unready and malformed views cannot become healthy empty history',
    () async {
      final api = LiquidationApi();
      addTearDown(api.dispose);
      expect(
        await api.liquidationOrders(1, productLine: 'LINEAR_PERPETUAL'),
        isEmpty,
      );
      expect(api.requestedProduct, 'LINEAR_PERPETUAL');
      api.unavailable = true;
      await expectLater(api.liquidationOrders(1), throwsA(isA<ApiException>()));
      api.unavailable = false;
      api.reply = {};
      await expectLater(api.liquidationOrders(1), throwsFormatException);
    },
  );

  testWidgets(
    'failed refresh retains history and its error after parallel reads',
    (tester) async {
      final api = LiquidationApi()
        ..reply = {
          'orders': [row],
        };
      final state = LiquidationState(api);
      addTearDown(state.dispose);
      await tester.pump();
      state.mode = ProductMode.linear;
      await state.refreshPrivateData();
      expect(state.liquidationOrders.single.orderId, 9007199254740993);
      api.unavailable = true;
      final gate = Completer<void>();
      state.walletGate = gate;
      final loading = state.refreshPrivateData();
      await tester.pump();
      gate.complete();
      await loading;
      expect(state.liquidationOrders.single.orderId, 9007199254740993);
      expect(state.lastError, contains('服务暂时不可用'));
      expect(state.lastError, isNot(contains('projection unavailable')));
      expect(state.loadingPrivate, isFalse);
    },
  );
}

class LiquidationApi extends TestApiClient {
  LiquidationApi() : super(const AppConfig(websocketUrl: ''));
  Map<String, dynamic> reply = {'orders': <Map<String, dynamic>>[]};
  bool unavailable = false;
  String? requestedProduct;

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    if (path != '/api/v1/gateway/liquidation/orders') {
      throw StateError('unexpected endpoint $path');
    }
    requestedProduct = productLine;
    if (unavailable) throw ApiException(503, 'projection unavailable');
    return reply;
  }
}

class LiquidationState extends AppState {
  LiquidationState(LiquidationApi api)
    : super(
        apiClient: api,
        initialSession: actor,
        settingsStore: MemorySettings(),
        sessionStore: MemorySessionStore(),
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: [riskInstrument()],
      );
  Completer<void>? walletGate;

  @override
  Future<void> refreshWallet() async {
    final gate = walletGate;
    if (gate != null) await gate.future;
    lastError = null;
  }

  @override
  Future<void> refreshPortfolioIncome() async {}
  @override
  Future<void> refreshBalanceScales() async {}
  @override
  Future<void> refreshOrderTerms() async {}
  @override
  Future<void> refreshAlgoOrders() async {}
  @override
  Future<void> refreshRiskDetails() async {}
}
