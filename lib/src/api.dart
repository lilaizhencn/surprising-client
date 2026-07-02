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

  Future<OrderBook> orderBook(String symbol, {int depth = 50}) async {
    final json = await get(
      '/api/v1/gateway/trading-market/orderbook',
      query: {'symbol': symbol, 'depth': '$depth'},
    );
    return OrderBook.fromJson(json);
  }

  Future<List<Candle>> candles(String symbol, String period) async {
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
    );
    return asList(
      json['candles'],
    ).map((item) => Candle.fromJson(asMap(item))).toList();
  }

  Future<List<ProductBalance>> productBalances(
    int userId, {
    String? accountType,
  }) async {
    final query = {'userId': '$userId'};
    if (accountType != null) query['accountType'] = accountType;
    final json = await get(
      '/api/v1/gateway/account/product-balances',
      query: query,
    );
    return asList(
      json['balances'],
    ).map((item) => ProductBalance.fromJson(asMap(item))).toList();
  }

  Future<List<Position>> positions(int userId) async {
    final json = await get(
      '/api/v1/gateway/account/positions',
      query: {'userId': '$userId'},
    );
    return asList(
      json['positions'],
    ).map((item) => Position.fromJson(asMap(item))).toList();
  }

  Future<List<OrderModel>> openOrders(int userId, {String? symbol}) async {
    final query = {'userId': '$userId', 'limit': '100'};
    if (symbol != null) query['symbol'] = symbol;
    final json = await get('/api/v1/gateway/trading/open', query: query);
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
  }) async {
    final json = await post('/api/v1/gateway/trading', {
      'userId': userId,
      'clientOrderId': 'app-${DateTime.now().microsecondsSinceEpoch}',
      'symbol': symbol,
      'side': side,
      'orderType': orderType,
      'timeInForce': timeInForce,
      'priceTicks': priceTicks,
      'quantitySteps': quantitySteps,
      'marginMode': marginMode,
      'positionSide': positionSide,
      'reduceOnly': reduceOnly,
      'postOnly': postOnly,
    }, userId: userId);
    return OrderModel.fromJson(json);
  }

  Future<OrderModel> cancelOrder(int userId, int orderId) async {
    final json = await post('/api/v1/gateway/trading/cancel', {
      'userId': userId,
      'orderId': orderId,
    }, userId: userId);
    return OrderModel.fromJson(json);
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

  Future<AccountRisk?> accountRisk(int userId, String settleAsset) async {
    try {
      final json = await get(
        '/api/v1/gateway/risk/account/latest',
        query: {'userId': '$userId', 'settleAsset': settleAsset},
        userId: userId,
      );
      return AccountRisk.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<List<PositionRisk>> positionRisks(int userId) async {
    try {
      final json = await get(
        '/api/v1/gateway/risk/positions/latest',
        query: {'userId': '$userId'},
        userId: userId,
      );
      return asList(
        json['positions'],
      ).map((item) => PositionRisk.fromJson(asMap(item))).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<LiquidationOrder>> liquidationOrders(int userId) async {
    try {
      final json = await get(
        '/api/v1/gateway/liquidation/orders',
        query: {'userId': '$userId', 'limit': '30'},
        userId: userId,
      );
      return asList(
        json['orders'],
      ).map((item) => LiquidationOrder.fromJson(asMap(item))).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    int? userId,
  }) {
    return _send('GET', path, query: query, userId: userId);
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
  }) {
    return _send('POST', path, body: body, userId: userId);
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    int? userId,
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
    return asMap(decoded);
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

  void subscribeDefaults({String symbol = 'BTC-USDT', String period = '1m'}) {
    subscribe('depth', symbol: symbol);
    subscribe('trades', symbol: symbol);
    subscribe('candles', symbol: symbol, period: period);
    subscribe('orders');
    subscribe('matches');
    subscribe('positions');
    subscribe('accountRisk');
    subscribe('positionRisk');
  }

  void subscribe(String channel, {String? symbol, String? period}) {
    final socket = _socket;
    if (socket == null) return;
    final command = {
      'op': 'subscribe',
      'id': '$channel-${DateTime.now().millisecondsSinceEpoch}',
      'channel': channel,
    };
    if (symbol != null) command['symbol'] = symbol;
    if (period != null) command['period'] = period;
    socket.add(jsonEncode(command));
  }

  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    await _socket?.close();
    _socket = null;
  }
}
