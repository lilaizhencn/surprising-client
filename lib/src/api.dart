import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'models.dart';

class ApiClient {
  ApiClient(this.config, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 5);
  }

  final AppConfig config;
  final HttpClient _httpClient;

  Future<AuthSession> register({
    required String username,
    required String password,
    required String email,
  }) async {
    final json = await post('/api/v1/auth/register', {
      'username': username,
      'password': password,
      'email': email,
    });
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final json = await post('/api/v1/auth/login', {
      'username': username,
      'password': password,
    });
    return AuthSession.fromJson(json);
  }

  Future<List<Instrument>> instruments() async {
    final json = await get('/api/v1/gateway/instrument/list');
    return asList(
      json['instruments'],
    ).map((item) => Instrument.fromJson(asMap(item))).toList();
  }

  Future<OrderBook> orderBook(
    String symbol, {
    int depth = 50,
    String? productLine,
  }) async {
    final json = await get(
      '/api/v1/gateway/trading-market/orderbook',
      query: {'symbol': symbol, 'depth': '$depth'},
      productLine: productLine,
    );
    return OrderBook.fromJson(json);
  }

  Future<List<Candle>> candles(
    String symbol,
    String period, {
    String? productLine,
  }) async {
    final end = DateTime.now().toUtc();
    final start = end.subtract(const Duration(hours: 8));
    final json = await get(
      '/api/v1/gateway/candlestick/candles',
      query: {
        'symbol': symbol,
        'period': period,
        'startTime': start.toIso8601String(),
        'endTime': end.toIso8601String(),
        'limit': '300',
      },
      productLine: productLine,
    );
    return asList(
      json['candles'],
    ).map((item) => Candle.fromJson(asMap(item))).toList();
  }

  Future<List<ProductBalance>> productBalances(
    int userId, {
    String? accountType,
    String? productLine,
  }) async {
    final query = {'userId': '$userId'};
    if (accountType != null) query['accountType'] = accountType;
    final json = await get(
      '/api/v1/gateway/account/product-balances',
      query: query,
      productLine: productLine,
    );
    return asList(
      json['balances'],
    ).map((item) => ProductBalance.fromJson(asMap(item))).toList();
  }

  Future<List<Position>> positions(
    int userId, {
    String? productLine,
  }) async {
    final json = await get(
      '/api/v1/gateway/account/positions',
      query: {'userId': '$userId'},
      productLine: productLine,
    );
    return asList(
      json['positions'],
    ).map((item) => Position.fromJson(asMap(item))).toList();
  }

  Future<String> positionMode(int userId) async {
    try {
      final json = await get(
        '/api/v1/gateway/account/position-mode',
        query: {'userId': '$userId'},
        userId: userId,
      );
      return asString(json['positionMode'], fallback: 'ONE_WAY');
    } catch (_) {
      return 'ONE_WAY';
    }
  }

  Future<String> updatePositionMode(int userId, String positionMode) async {
    final json = await post('/api/v1/gateway/account/position-mode', {
      'userId': userId,
      'positionMode': positionMode,
    }, userId: userId);
    return asString(json['positionMode'], fallback: positionMode);
  }

  Future<List<OrderModel>> openOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    final query = {'userId': '$userId', 'limit': '100'};
    if (symbol != null) query['symbol'] = symbol;
    final json = await get(
      '/api/v1/gateway/trading/open',
      query: query,
      productLine: productLine,
    );
    return asList(
      json['orders'],
    ).map((item) => OrderModel.fromJson(asMap(item))).toList();
  }

  Future<OrderModel> placeOrder({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading',
      _orderPayload(
        userId: userId,
        symbol: symbol,
        side: side,
        orderType: orderType,
        timeInForce: timeInForce,
        priceTicks: priceTicks,
        quantitySteps: quantitySteps,
        marginMode: marginMode,
        positionSide: positionSide,
        reduceOnly: reduceOnly,
        postOnly: postOnly,
      ),
      userId: userId,
      productLine: productLine,
    );
    return OrderModel.fromJson(json);
  }

  Future<TestOrderResult> testOrder({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/test',
      _orderPayload(
        userId: userId,
        symbol: symbol,
        side: side,
        orderType: orderType,
        timeInForce: timeInForce,
        priceTicks: priceTicks,
        quantitySteps: quantitySteps,
        marginMode: marginMode,
        positionSide: positionSide,
        reduceOnly: reduceOnly,
        postOnly: postOnly,
        clientOrderId: 'app-test-${DateTime.now().microsecondsSinceEpoch}',
      ),
      userId: userId,
      productLine: productLine,
    );
    return TestOrderResult.fromJson(json);
  }

  Future<OrderBatchResult> placeOrderBatch(
    int userId,
    List<Map<String, dynamic>> orders, {
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/batch', {
      'orders': orders,
    }, userId: userId, productLine: productLine);
    return OrderBatchResult.fromJson(json);
  }

  Future<AmendOrderResult> amendOrder({
    required int userId,
    required int orderId,
    int? priceTicks,
    int? quantitySteps,
    String? timeInForce,
    bool? postOnly,
    String? newClientOrderId,
    String? productLine,
  }) async {
    final payload = <String, dynamic>{
      'userId': userId,
      'orderId': orderId,
      'newClientOrderId':
          newClientOrderId ??
          'app-amend-$userId-${DateTime.now().microsecondsSinceEpoch}',
    };
    if (priceTicks != null) {
      payload['priceTicks'] = priceTicks;
    }
    if (quantitySteps != null) {
      payload['quantitySteps'] = quantitySteps;
    }
    if (timeInForce != null) {
      payload['timeInForce'] = timeInForce;
    }
    if (postOnly != null) {
      payload['postOnly'] = postOnly;
    }
    final json = await post(
      '/api/v1/gateway/trading/amend',
      payload,
      userId: userId,
      productLine: productLine,
    );
    return AmendOrderResult.fromJson(json);
  }

  Future<AmendOrderBatchResult> amendOrderBatch(
    int userId,
    List<Map<String, dynamic>> orders, {
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/batch-amend', {
      'orders': orders,
    }, userId: userId, productLine: productLine);
    return AmendOrderBatchResult.fromJson(json);
  }

  Future<OrderModel> cancelOrder(
    int userId,
    int orderId, {
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/cancel', {
      'userId': userId,
      'orderId': orderId,
    }, userId: userId, productLine: productLine);
    return OrderModel.fromJson(json);
  }

  Future<OrderBatchResult> cancelOrderBatch(
    int userId,
    List<int> orderIds, {
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/batch-cancel', {
      'orders': orderIds
          .map((orderId) => {'userId': userId, 'orderId': orderId})
          .toList(),
    }, userId: userId, productLine: productLine);
    return OrderBatchResult.fromJson(json);
  }

  Future<OrderBatchResult> cancelOpenOrders(
    int userId, {
    String? symbol,
    int limit = 1000,
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/cancel-open', {
      'userId': userId,
      ...?symbol == null ? null : {'symbol': symbol},
      'limit': limit,
    }, userId: userId, productLine: productLine);
    return OrderBatchResult.fromJson(json);
  }

  Future<List<AlgoOrderModel>> openAlgoOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    final query = {'userId': '$userId', 'limit': '100'};
    if (symbol != null) query['symbol'] = symbol;
    final json = await get(
      '/api/v1/gateway/trading/algo/open',
      query: query,
      productLine: productLine,
    );
    return asList(
      json['orders'],
    ).map((item) => AlgoOrderModel.fromJson(asMap(item))).toList();
  }

  Future<AlgoOrderModel> placeAlgoOrder({
    required int userId,
    required String symbol,
    required String algoType,
    required String side,
    required int priceTicks,
    required int quantitySteps,
    required int childQuantitySteps,
    required int intervalSeconds,
    required int durationSeconds,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/algo', {
      'userId': userId,
      'clientAlgoOrderId':
          'app-algo-$userId-${DateTime.now().microsecondsSinceEpoch}',
      'symbol': symbol,
      'algoType': algoType,
      'side': side,
      'priceTicks': algoType == 'TWAP' && priceTicks <= 0 ? 0 : priceTicks,
      'quantitySteps': quantitySteps,
      'childQuantitySteps': childQuantitySteps,
      'intervalSeconds': intervalSeconds,
      'durationSeconds': durationSeconds,
      'marginMode': marginMode,
      'positionSide': positionSide,
      'reduceOnly': reduceOnly,
      'postOnly': algoType == 'ICEBERG' && postOnly,
      'timeInForce': algoType == 'TWAP'
          ? 'IOC'
          : postOnly
          ? 'GTX'
          : 'GTC',
    }, userId: userId, productLine: productLine);
    return AlgoOrderModel.fromJson(json);
  }

  Future<AlgoOrderModel> cancelAlgoOrder(
    int userId,
    int algoOrderId, {
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/algo/cancel', {
      'userId': userId,
      'algoOrderId': algoOrderId,
    }, userId: userId, productLine: productLine);
    return AlgoOrderModel.fromJson(json);
  }

  Future<AlgoOrderBatchResult> cancelOpenAlgoOrders(
    int userId, {
    String? symbol,
    int limit = 1000,
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/algo/cancel-open', {
      'userId': userId,
      ...?symbol == null ? null : {'symbol': symbol},
      'limit': limit,
    }, userId: userId, productLine: productLine);
    return AlgoOrderBatchResult.fromJson(json);
  }

  Future<CancelAllAfterResult> cancelAllAfter(
    int userId, {
    String? symbol,
    required int countdownMs,
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/cancel-all-after', {
      'userId': userId,
      ...?symbol == null ? null : {'symbol': symbol},
      'countdownMs': countdownMs,
    }, userId: userId, productLine: productLine);
    return CancelAllAfterResult.fromJson(json);
  }

  Future<OrderModel> closePosition(
    int userId, {
    required String symbol,
    required String marginMode,
    required String positionSide,
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading/close-position', {
      'userId': userId,
      'clientOrderId':
          'app-close-$userId-${DateTime.now().microsecondsSinceEpoch}',
      'symbol': symbol,
      'marginMode': marginMode,
      'positionSide': positionSide,
    }, userId: userId, productLine: productLine);
    return OrderModel.fromJson(json);
  }

  Future<List<TriggerOrderModel>> openTriggerOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    final query = {'userId': '$userId', 'limit': '100'};
    if (symbol != null) query['symbol'] = symbol;
    final json = await get(
      '/api/v1/gateway/trading-trigger/open',
      query: query,
      userId: userId,
      productLine: productLine,
    );
    return asList(
      json['orders'] ?? json['items'],
    ).map((item) => TriggerOrderModel.fromJson(asMap(item))).toList();
  }

  Future<TriggerOrderModel> placeTriggerOrder({
    required int userId,
    required String symbol,
    required String side,
    required String triggerType,
    required int triggerPriceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    int? activationPriceTicks,
    int? callbackRatePpm,
    String triggerPriceType = 'MARK_PRICE',
    String? productLine,
  }) async {
    final payload = <String, Object?>{
      'userId': userId,
      'clientTriggerOrderId':
          'app-trigger-$userId-${DateTime.now().microsecondsSinceEpoch}',
      'symbol': symbol,
      'side': side,
      'triggerType': triggerType,
      'triggerPriceType': triggerPriceType,
      'triggerPriceTicks': triggerPriceTicks,
      'activationPriceTicks': activationPriceTicks,
      'callbackRatePpm': callbackRatePpm,
      'orderType': 'MARKET',
      'timeInForce': 'IOC',
      'priceTicks': 0,
      'quantitySteps': quantitySteps,
      'marginMode': marginMode,
      'positionSide': positionSide,
    }..removeWhere((_, value) => value == null);
    final json = await post(
      '/api/v1/gateway/trading-trigger',
      payload,
      userId: userId,
      productLine: productLine,
    );
    return TriggerOrderModel.fromJson(json);
  }

  Future<TriggerOrderBatchResult> placeTriggerOrderBatch(
    int userId,
    List<Map<String, dynamic>> orders, {
    bool atomic = false,
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading-trigger/batch', {
      'atomic': atomic,
      'orders': orders,
    }, userId: userId, productLine: productLine);
    return TriggerOrderBatchResult.fromJson(json);
  }

  Future<TriggerOrderModel> cancelTriggerOrder(
    int userId,
    int triggerOrderId, {
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading-trigger/cancel', {
      'userId': userId,
      'triggerOrderId': triggerOrderId,
    }, userId: userId, productLine: productLine);
    return TriggerOrderModel.fromJson(json);
  }

  Future<TriggerOrderBatchResult> cancelTriggerOrderBatch(
    int userId,
    List<int> triggerOrderIds, {
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading-trigger/batch-cancel', {
      'orders': triggerOrderIds
          .map(
            (triggerOrderId) => {
              'userId': userId,
              'triggerOrderId': triggerOrderId,
            },
          )
          .toList(),
    }, userId: userId, productLine: productLine);
    return TriggerOrderBatchResult.fromJson(json);
  }

  Future<TriggerOrderBatchResult> cancelOpenTriggerOrders(
    int userId, {
    String? symbol,
    int limit = 1000,
    String? productLine,
  }) async {
    final json = await post('/api/v1/gateway/trading-trigger/cancel-open', {
      'userId': userId,
      ...?symbol == null ? null : {'symbol': symbol},
      'limit': limit,
    }, userId: userId, productLine: productLine);
    return TriggerOrderBatchResult.fromJson(json);
  }

  Future<Map<String, dynamic>> transfer({
    required int userId,
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required int amountUnits,
  }) {
    return post('/api/v1/gateway/account/transfers', {
      'userId': userId,
      'sourceAccountType': sourceAccountType,
      'targetAccountType': targetAccountType,
      'asset': asset,
      'amountUnits': amountUnits,
      'referenceId': 'app-transfer-${DateTime.now().microsecondsSinceEpoch}',
      'reason': 'mobile client transfer',
    }, userId: userId);
  }

  Future<Map<String, dynamic>> walletAssets(int userId) {
    return get(
      '/api/v1/gateway/wallet/app/assets',
      userId: userId,
      unwrapResponseResult: true,
    );
  }

  Future<WalletPortfolio> walletPortfolio(
    int userId, {
    bool hideZero = false,
  }) async {
    final json = await get(
      '/api/v1/gateway/wallet/app/portfolio',
      query: {'hideZero': '$hideZero'},
      userId: userId,
      unwrapResponseResult: true,
    );
    return WalletPortfolio.fromJson(json);
  }

  Future<List<WalletOrderRecord>> walletOrders(
    int userId, {
    int limit = 30,
  }) async {
    final json = await get(
      '/api/v1/gateway/wallet/app/orders',
      query: {'limit': '$limit'},
      userId: userId,
      unwrapResponseResult: true,
    );
    return asList(
      json['items'] ?? json['orders'],
    ).map((item) => WalletOrderRecord.fromJson(asMap(item))).toList();
  }

  Future<WalletDepositAddress> walletDepositAddress(
    int userId, {
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) async {
    final json = forceNew
        ? await post(
            '/api/v1/gateway/wallet/app/deposit-address',
            {'chain': chain, 'symbol': symbol},
            userId: userId,
            unwrapResponseResult: true,
          )
        : await get(
            '/api/v1/gateway/wallet/app/deposit-address',
            query: {'chain': chain, 'symbol': symbol},
            userId: userId,
            unwrapResponseResult: true,
          );
    return WalletDepositAddress.fromJson(json);
  }

  Future<Map<String, dynamic>> walletWithdraw(
    int userId, {
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
  }) {
    return post(
      '/api/v1/gateway/wallet/app/withdraw',
      {
        'chain': chain,
        'symbol': symbol,
        'toAddress': toAddress,
        'amount': amount,
        'confirmed': true,
      },
      userId: userId,
      unwrapResponseResult: true,
    );
  }

  Future<AccountRisk?> accountRisk(
    int userId,
    String settleAsset, {
    String? accountType,
    String? productLine,
  }) async {
    try {
      final query = {'userId': '$userId', 'settleAsset': settleAsset};
      if (accountType != null) query['accountType'] = accountType;
      final json = await get(
        '/api/v1/gateway/risk/account/latest',
        query: query,
        userId: userId,
        productLine: productLine,
      );
      return AccountRisk.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<List<PositionRisk>> positionRisks(
    int userId, {
    String? productLine,
  }) async {
    try {
      final json = await get(
        '/api/v1/gateway/risk/positions/latest',
        query: {'userId': '$userId'},
        userId: userId,
        productLine: productLine,
      );
      return asList(
        json['positions'],
      ).map((item) => PositionRisk.fromJson(asMap(item))).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<LiquidationOrder>> liquidationOrders(
    int userId, {
    String? productLine,
  }) async {
    try {
      final json = await get(
        '/api/v1/gateway/liquidation/orders',
        query: {'userId': '$userId', 'limit': '30'},
        userId: userId,
        productLine: productLine,
      );
      return asList(
        json['orders'],
      ).map((item) => LiquidationOrder.fromJson(asMap(item))).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _orderPayload({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? clientOrderId,
  }) {
    return {
      'userId': userId,
      'clientOrderId':
          clientOrderId ?? 'app-${DateTime.now().microsecondsSinceEpoch}',
      'symbol': symbol,
      'side': side,
      'orderType': orderType,
      'timeInForce': timeInForce,
      'priceTicks': orderType == 'MARKET' ? 0 : priceTicks,
      'quantitySteps': quantitySteps,
      'marginMode': marginMode,
      'positionSide': positionSide,
      'reduceOnly': reduceOnly,
      'postOnly': postOnly,
    };
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) {
    return _send(
      'GET',
      path,
      query: query,
      userId: userId,
      productLine: productLine,
      unwrapResponseResult: unwrapResponseResult,
    );
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) {
    return _send(
      'POST',
      path,
      body: body,
      userId: userId,
      productLine: productLine,
      unwrapResponseResult: unwrapResponseResult,
    );
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    final base = Uri.parse(config.gatewayBaseUrl);
    final uri = base.replace(
      path: path,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final request = await _httpClient
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 6));
    request.headers.contentType = ContentType.json;
    request.headers.set(
      'X-Trace-Id',
      'mobile-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (userId != null) request.headers.set('X-User-Id', '$userId');
    if (productLine != null && productLine.isNotEmpty) {
      request.headers.set('X-Product-Line', productLine);
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final payload = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        payload.isEmpty ? response.reasonPhrase : payload,
      );
    }
    if (payload.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(payload);
    final json = asMap(decoded);
    if (unwrapResponseResult) {
      return _unwrapResponseResult(json);
    }
    return json;
  }

  Map<String, dynamic> _unwrapResponseResult(Map<String, dynamic> json) {
    if (!json.containsKey('code') ||
        !json.containsKey('message') ||
        !json.containsKey('data')) {
      return json;
    }
    final code = asInt(json['code']);
    if (code != 0) {
      throw ApiException(
        code,
        asString(json['message'], fallback: 'request failed'),
      );
    }
    final data = json['data'];
    if (data is List) return {'items': data};
    if (data == null) return <String, dynamic>{};
    return asMap(data);
  }
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'HTTP $statusCode $message';
}

class RealtimeClient {
  RealtimeClient(this.config);

  final AppConfig config;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;

  Future<void> connect({
    int? userId,
    String? accessToken,
    required void Function(Map<String, dynamic>) onEvent,
    required void Function(Object error) onError,
  }) async {
    await close();
    final base = Uri.parse(config.websocketUrl);
    final query = <String, String>{};
    if (userId != null) {
      if (config.localWebSocketUserFallback) {
        query['userId'] = '$userId';
      } else if (accessToken != null && accessToken.isNotEmpty) {
        query['token'] = accessToken;
      }
    }
    final uri = query.isEmpty ? base : base.replace(queryParameters: query);
    final socket = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 5));
    _socket = socket;
    _subscription = socket.listen(
      (message) {
        try {
          onEvent(asMap(jsonDecode(message as String)));
        } catch (error) {
          onError(error);
        }
      },
      onError: onError,
      onDone: () {},
      cancelOnError: false,
    );
  }

  void subscribeDefaults({
    String symbol = 'BTC-USDT',
    String period = '1m',
    String? productLine,
  }) {
    subscribe('depth', symbol: symbol, productLine: productLine);
    subscribe('trades', symbol: symbol, productLine: productLine);
    subscribe(
      'candles',
      symbol: symbol,
      period: period,
      productLine: productLine,
    );
    subscribe('orders', productLine: productLine);
    subscribe('matches', productLine: productLine);
    subscribe('executionReports', productLine: productLine);
    subscribe('positions', productLine: productLine);
    subscribe('accountRisk', productLine: productLine);
    subscribe('positionRisk', productLine: productLine);
  }

  void subscribe(
    String channel, {
    String? symbol,
    String? period,
    String? productLine,
  }) {
    final socket = _socket;
    if (socket == null) return;
    final command = {
      'op': 'subscribe',
      'id': '$channel-${DateTime.now().millisecondsSinceEpoch}',
      'channel': channel,
    };
    if (symbol != null) command['symbol'] = symbol;
    if (period != null) command['period'] = period;
    if (productLine != null && productLine.isNotEmpty) {
      command['productLine'] = productLine;
    }
    socket.add(jsonEncode(command));
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
  }
}
