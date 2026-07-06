import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';

class AppState extends ChangeNotifier {
  AppState({
    this.config = const AppConfig(),
    ApiClient? apiClient,
    RealtimeClient? publicRealtimeClient,
    RealtimeClient? privateRealtimeClient,
    this.offline = false,
  }) : api = apiClient ?? ApiClient(config),
       publicRealtime = publicRealtimeClient ?? RealtimeClient(config),
       privateRealtime = privateRealtimeClient ?? RealtimeClient(config) {
    instruments = fallbackInstruments();
    selectedSymbol = instruments.first.symbol;
    orderBook = fallbackOrderBook(instruments.first);
    candles = fallbackCandles();
  }

  final AppConfig config;
  final ApiClient api;
  final RealtimeClient publicRealtime;
  final RealtimeClient privateRealtime;
  final bool offline;

  AuthSession? session;
  late List<Instrument> instruments;
  late String selectedSymbol;
  ProductMode mode = ProductMode.linear;
  String period = '1m';
  late OrderBook orderBook;
  late List<Candle> candles;
  List<ProductBalance> balances = const [];
  List<Position> positions = const [];
  List<OrderModel> openOrders = const [];
  List<AlgoOrderModel> openAlgoOrders = const [];
  List<TriggerOrderModel> openTriggerOrders = const [];
  String positionMode = 'ONE_WAY';
  List<PositionRisk> positionRisks = const [];
  List<LiquidationOrder> liquidationOrders = const [];
  WalletPortfolio walletPortfolio = WalletPortfolio.empty();
  List<WalletOrderRecord> walletOrders = const [];
  WalletDepositAddress? walletDepositAddress;
  AccountRisk? accountRisk;
  final Map<String, double> latestPrices = {};
  bool loadingPublic = false;
  bool loadingPrivate = false;
  String? lastError;
  String? lastNotice;
  final List<String> realtimeLog = [];
  Timer? _realtimeNotifyTimer;

  bool get isLoggedIn => session != null;

  int? get userId => session?.user.userId;

  Instrument get selectedInstrument {
    return instruments.firstWhere(
      (instrument) => instrument.symbol == selectedSymbol,
      orElse: () => fallbackInstruments().first,
    );
  }

  List<Instrument> get visibleInstruments {
    final filtered = instruments
        .where((instrument) => instrument.mode == mode)
        .toList();
    if (filtered.isNotEmpty) return filtered;
    return instruments;
  }

  double? latestPriceFor(Instrument instrument) {
    final direct = latestPrices[instrument.symbol];
    if (direct != null && direct > 0) return direct;
    if (instrument.symbol == selectedSymbol && candles.isNotEmpty) {
      return candles.last.close;
    }
    if (instrument.symbol == orderBook.symbol) {
      final bestBid = orderBook.bids.isNotEmpty ? orderBook.bids.first : null;
      final bestAsk = orderBook.asks.isNotEmpty ? orderBook.asks.first : null;
      if (bestBid != null && bestAsk != null) {
        return instrument.priceFromTicks(
          ((bestBid.priceTicks + bestAsk.priceTicks) / 2).round(),
        );
      }
      if (bestBid != null) return instrument.priceFromTicks(bestBid.priceTicks);
      if (bestAsk != null) return instrument.priceFromTicks(bestAsk.priceTicks);
    }
    return fallbackPriceFor(instrument);
  }

  Future<void> bootstrap() async {
    if (offline) return;
    await refreshInstruments(silent: true);
    await refreshPublicData(silent: true);
    await _connectPublicRealtime();
  }

  Future<void> refreshInstruments({bool silent = false}) async {
    if (offline) return;
    try {
      final loaded = await api.instruments();
      if (loaded.isNotEmpty) {
        instruments = loaded;
        final candidates = visibleInstruments;
        if (!loaded.any((instrument) => instrument.symbol == selectedSymbol)) {
          selectedSymbol = candidates.isNotEmpty
              ? candidates.first.symbol
              : loaded.first.symbol;
        }
      }
      lastError = null;
    } catch (error) {
      if (silent) {
        _recordRealtimeIssue('加载交易对失败：$error');
      } else {
        lastError = '加载交易对失败：$error';
      }
    }
    _scheduleRealtimeNotify();
  }

  void _scheduleRealtimeNotify() {
    if (_realtimeNotifyTimer?.isActive ?? false) return;
    _realtimeNotifyTimer = Timer(const Duration(milliseconds: 200), () {
      _realtimeNotifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> refreshPublicData({bool silent = false}) async {
    if (offline) return;
    loadingPublic = true;
    notifyListeners();
    try {
      final symbol = selectedSymbol;
      final productLine = _productLineForSymbol(symbol);
      final results = await Future.wait([
        api.orderBook(symbol, productLine: productLine),
        api.candles(symbol, period, productLine: productLine),
      ]);
      final loadedBook = results[0] as OrderBook;
      orderBook = loadedBook.bids.isEmpty && loadedBook.asks.isEmpty
          ? fallbackOrderBook(selectedInstrument)
          : loadedBook;
      final loadedCandles = results[1] as List<Candle>;
      candles = loadedCandles.isEmpty ? fallbackCandles() : loadedCandles;
      if (candles.isNotEmpty) latestPrices[symbol] = candles.last.close;
      lastError = null;
    } catch (error) {
      if (silent) {
        _recordRealtimeIssue('加载行情失败：$error');
      } else {
        lastError = '加载行情失败：$error';
      }
    } finally {
      loadingPublic = false;
      notifyListeners();
    }
  }

  Future<void> refreshPrivateData() async {
    final id = userId;
    if (offline || id == null) return;
    loadingPrivate = true;
    notifyListeners();
    try {
      final productLine = mode.productLine;
      final accountType = mode.accountType;
      final results = await Future.wait([
        api.productBalances(
          id,
          accountType: accountType,
          productLine: productLine,
        ),
        api.positions(id, productLine: productLine),
        api.openOrders(id, symbol: selectedSymbol, productLine: productLine),
        mode.isSpot
            ? Future<List<AlgoOrderModel>>.value(const [])
            : api.openAlgoOrders(
                id,
                symbol: selectedSymbol,
                productLine: productLine,
              ),
        mode.isSpot
            ? Future<List<TriggerOrderModel>>.value(const [])
            : api.openTriggerOrders(
                id,
                symbol: selectedSymbol,
                productLine: productLine,
              ),
        api.positionMode(id),
        api.accountRisk(
          id,
          selectedInstrument.settleAsset,
          accountType: accountType,
          productLine: productLine,
        ),
        api.positionRisks(id, productLine: productLine),
        api.liquidationOrders(id, productLine: productLine),
        api.walletPortfolio(id),
        api.walletOrders(id),
      ]);
      balances = results[0] as List<ProductBalance>;
      final allPositions = results[1] as List<Position>;
      positions = allPositions.where((position) {
        final instrument = instruments.firstWhere(
          (item) => item.symbol == position.symbol,
          orElse: () => selectedInstrument,
        );
        return instrument.mode == mode;
      }).toList();
      openOrders = results[2] as List<OrderModel>;
      openAlgoOrders = results[3] as List<AlgoOrderModel>;
      openTriggerOrders = results[4] as List<TriggerOrderModel>;
      positionMode = results[5] as String;
      accountRisk = results[6] as AccountRisk?;
      positionRisks = results[7] as List<PositionRisk>;
      liquidationOrders = results[8] as List<LiquidationOrder>;
      walletPortfolio = results[9] as WalletPortfolio;
      walletOrders = results[10] as List<WalletOrderRecord>;
      lastError = null;
    } catch (error) {
      lastError = '加载账户失败：$error';
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<void> login(String username, String password) async {
    if (offline) return;
    loadingPrivate = true;
    notifyListeners();
    try {
      session = await api.login(username: username, password: password);
      lastNotice = '登录成功';
      await _connectPrivateRealtime();
      await refreshPrivateData();
    } catch (error) {
      lastError = '登录失败：$error';
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<void> register(String username, String password, String email) async {
    if (offline) return;
    loadingPrivate = true;
    notifyListeners();
    try {
      session = await api.register(
        username: username,
        password: password,
        email: email,
      );
      lastNotice = '注册成功';
      await _connectPrivateRealtime();
      await refreshPrivateData();
    } catch (error) {
      lastError = '注册失败：$error';
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await privateRealtime.close();
    session = null;
    balances = const [];
    positions = const [];
    openOrders = const [];
    openAlgoOrders = const [];
    openTriggerOrders = const [];
    positionMode = 'ONE_WAY';
    walletPortfolio = WalletPortfolio.empty();
    walletOrders = const [];
    walletDepositAddress = null;
    accountRisk = null;
    positionRisks = const [];
    liquidationOrders = const [];
    notifyListeners();
  }

  Future<void> selectMode(ProductMode nextMode) async {
    mode = nextMode;
    final candidates = visibleInstruments;
    if (candidates.isNotEmpty &&
        !candidates.any((instrument) => instrument.symbol == selectedSymbol)) {
      selectedSymbol = candidates.first.symbol;
    }
    orderBook = fallbackOrderBook(selectedInstrument);
    notifyListeners();
    await refreshPublicData(silent: true);
    await refreshPrivateData();
    _subscribePublicSelected();
    _subscribePrivateSelected();
  }

  Future<void> selectSymbol(String symbol) async {
    selectedSymbol = symbol;
    orderBook = fallbackOrderBook(selectedInstrument);
    notifyListeners();
    await refreshPublicData(silent: true);
    await refreshPrivateData();
    _subscribePublicSelected();
    _subscribePrivateSelected();
  }

  Future<void> selectPeriod(String nextPeriod) async {
    period = nextPeriod;
    notifyListeners();
    await refreshPublicData(silent: true);
    _subscribePublicSelected();
  }

  Future<void> placeOrder({
    required String side,
    required String orderType,
    required String timeInForce,
    required double price,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
  }) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再下单';
      notifyListeners();
      return;
    }
    try {
      final instrument = selectedInstrument;
      final productLine = instrument.mode.productLine;
      final effectivePositionSide =
          instrument.isSpot || positionMode == 'ONE_WAY'
          ? 'NET'
          : positionSide == 'NET'
          ? (side == 'SELL' ? 'SHORT' : 'LONG')
          : positionSide;
      final order = await api.placeOrder(
        userId: id,
        symbol: selectedSymbol,
        side: side,
        orderType: orderType,
        timeInForce: timeInForce,
        priceTicks: orderType == 'MARKET'
            ? 0
            : instrument.ticksFromPrice(price),
        quantitySteps: quantitySteps,
        marginMode: marginMode,
        positionSide: effectivePositionSide,
        reduceOnly: reduceOnly,
        postOnly: postOnly,
        productLine: productLine,
      );
      _upsertOrder(order);
      lastNotice = '订单已提交 #${order.orderId}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '下单失败：$error';
    }
    notifyListeners();
  }

  Future<void> cancelOrder(OrderModel order) async {
    final id = userId;
    if (id == null) return;
    try {
      final cancelled = await api.cancelOrder(
        id,
        order.orderId,
        productLine: _productLineForSymbol(order.symbol),
      );
      _upsertOrder(cancelled);
      lastNotice = '撤单已提交 #${order.orderId}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '撤单失败：$error';
    }
    notifyListeners();
  }

  Future<void> placeAlgoOrder(AlgoOrderDraft draft) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再提交算法单';
      notifyListeners();
      return;
    }
    if (!_validAlgoDraft(draft)) {
      lastError = '请先填写有效的算法单参数';
      notifyListeners();
      return;
    }
    try {
      final order = await api.placeAlgoOrder(
        userId: id,
        symbol: selectedSymbol,
        algoType: draft.algoType,
        side: draft.side,
        priceTicks: draft.priceTicks,
        quantitySteps: draft.quantitySteps,
        childQuantitySteps: draft.childQuantitySteps,
        intervalSeconds: draft.intervalSeconds,
        durationSeconds: draft.durationSeconds,
        marginMode: draft.marginMode,
        positionSide: draft.positionSide,
        reduceOnly: draft.reduceOnly,
        postOnly: draft.postOnly,
        productLine: _productLineForSymbol(selectedSymbol),
      );
      _upsertAlgoOrder(order);
      lastNotice = '算法单已提交 #${order.algoOrderId}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '提交算法单失败：$error';
    }
    notifyListeners();
  }

  bool _validAlgoDraft(AlgoOrderDraft draft) {
    if (draft.quantitySteps <= 0 || draft.childQuantitySteps <= 0) {
      return false;
    }
    if (draft.childQuantitySteps > draft.quantitySteps) return false;
    if (draft.intervalSeconds <= 0 || draft.durationSeconds <= 0) return false;
    if (draft.algoType == 'ICEBERG') return draft.priceTicks > 0;
    return draft.algoType == 'TWAP';
  }

  Future<void> cancelAlgoOrder(AlgoOrderModel order) async {
    final id = userId;
    if (id == null) return;
    try {
      final cancelled = await api.cancelAlgoOrder(
        id,
        order.algoOrderId,
        productLine: _productLineForSymbol(order.symbol),
      );
      _upsertAlgoOrder(cancelled);
      lastNotice = '算法单撤销已提交 #${order.algoOrderId}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '撤销算法单失败：$error';
    }
    notifyListeners();
  }

  Future<void> placeTriggerOrders(List<TriggerOrderDraft> drafts) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再提交止盈止损';
      notifyListeners();
      return;
    }
    final validDrafts = drafts.where(_validTriggerDraft).toList();
    if (validDrafts.isEmpty) {
      lastError = '请先填写有效的触发价和数量';
      notifyListeners();
      return;
    }
    try {
      final created = <TriggerOrderModel>[];
      for (final draft in validDrafts) {
        created.add(
          await api.placeTriggerOrder(
            userId: id,
            symbol: selectedSymbol,
            side: draft.side,
            triggerType: draft.triggerType,
            triggerPriceType: draft.triggerPriceType,
            triggerPriceTicks: draft.triggerPriceTicks,
            activationPriceTicks: draft.activationPriceTicks,
            callbackRatePpm: draft.callbackRatePpm,
            quantitySteps: draft.quantitySteps,
            marginMode: draft.marginMode,
            positionSide: draft.positionSide,
            productLine: _productLineForSymbol(selectedSymbol),
          ),
        );
      }
      for (final order in created) {
        _upsertTriggerOrder(order);
      }
      lastNotice = '止盈止损已提交 ${created.length} 档';
      await refreshPrivateData();
    } catch (error) {
      lastError = '提交止盈止损失败：$error';
    }
    notifyListeners();
  }

  bool _validTriggerDraft(TriggerOrderDraft draft) {
    if (draft.quantitySteps <= 0) return false;
    if (draft.triggerType == 'TRAILING_STOP') {
      final callbackRate = draft.callbackRatePpm;
      return draft.triggerPriceTicks >= 0 &&
          (draft.activationPriceTicks == null ||
              draft.activationPriceTicks! >= 0) &&
          callbackRate != null &&
          callbackRate >= 1000 &&
          callbackRate <= 100000;
    }
    return draft.triggerPriceTicks > 0;
  }

  Future<void> cancelTriggerOrder(TriggerOrderModel order) async {
    final id = userId;
    if (id == null) return;
    try {
      final cancelled = await api.cancelTriggerOrder(
        id,
        order.triggerOrderId,
        productLine: _productLineForSymbol(order.symbol),
      );
      _upsertTriggerOrder(cancelled);
      lastNotice = '条件单撤销已提交 #${order.triggerOrderId}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '撤销条件单失败：$error';
    }
    notifyListeners();
  }

  Future<void> changePositionMode(String nextMode) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再切换持仓模式';
      notifyListeners();
      return;
    }
    if (nextMode == positionMode) return;
    try {
      positionMode = await api.updatePositionMode(id, nextMode);
      lastNotice = '持仓模式已切换为${positionModeLabel(positionMode)}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '切换持仓模式失败：$error';
    }
    notifyListeners();
  }

  Future<void> closePosition(Position position) async {
    final instrument = instruments.firstWhere(
      (item) => item.symbol == position.symbol,
      orElse: () => selectedInstrument,
    );
    selectedSymbol = position.symbol;
    await placeOrder(
      side: position.signedQuantitySteps >= 0 ? 'SELL' : 'BUY',
      orderType: 'MARKET',
      timeInForce: 'IOC',
      price: 0,
      quantitySteps: position.signedQuantitySteps.abs(),
      marginMode: position.marginMode,
      positionSide:
          instrument.isSpot || positionMode == 'ONE_WAY'
          ? 'NET'
          : position.positionSide,
      reduceOnly: instrument.isDerivative,
      postOnly: false,
    );
  }

  Future<void> transfer({
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required double amount,
  }) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再划转';
      notifyListeners();
      return;
    }
    try {
      await api.transfer(
        userId: id,
        sourceAccountType: sourceAccountType,
        targetAccountType: targetAccountType,
        asset: asset,
        amountUnits: decimalToUnits(amount),
      );
      lastNotice = '划转已完成';
      await refreshPrivateData();
    } catch (error) {
      lastError = '划转失败：$error';
    }
    notifyListeners();
  }

  Future<void> refreshWallet() async {
    final id = userId;
    if (offline || id == null) return;
    loadingPrivate = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.walletPortfolio(id),
        api.walletOrders(id),
      ]);
      walletPortfolio = results[0] as WalletPortfolio;
      walletOrders = results[1] as List<WalletOrderRecord>;
      lastError = null;
    } catch (error) {
      lastError = '加载钱包失败：$error';
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<void> loadDepositAddress({
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再获取充值地址';
      notifyListeners();
      return;
    }
    try {
      walletDepositAddress = await api.walletDepositAddress(
        id,
        chain: chain,
        symbol: symbol,
        forceNew: forceNew,
      );
      lastNotice = forceNew ? '已生成新充值地址' : '充值地址已加载';
      await refreshWallet();
    } catch (error) {
      lastError = '获取充值地址失败：$error';
    }
    notifyListeners();
  }

  Future<void> withdrawWallet({
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
  }) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再提现';
      notifyListeners();
      return;
    }
    try {
      final result = await api.walletWithdraw(
        id,
        chain: chain,
        symbol: symbol,
        toAddress: toAddress,
        amount: amount,
      );
      lastNotice = '提现已提交 ${asString(result['orderNo'])}';
      await refreshWallet();
    } catch (error) {
      lastError = '提现失败：$error';
    }
    notifyListeners();
  }

  Future<void> _connectPublicRealtime() async {
    try {
      await publicRealtime.connect(
        onEvent: handleRealtimeMessage,
        onError: (error) {
          _recordRealtimeIssue('公共行情 WebSocket：$error');
          notifyListeners();
        },
      );
      _subscribePublicSelected();
    } catch (error) {
      _recordRealtimeIssue('实时行情连接失败：$error');
      notifyListeners();
    }
  }

  Future<void> _connectPrivateRealtime() async {
    final current = session;
    if (current == null) return;
    try {
      await privateRealtime.connect(
        userId: current.user.userId,
        accessToken: current.accessToken,
        onEvent: handleRealtimeMessage,
        onError: (error) {
          _recordRealtimeIssue('账户 WebSocket：$error');
          notifyListeners();
        },
      );
      _subscribePrivateSelected();
    } catch (error) {
      _recordRealtimeIssue('账户实时连接失败：$error');
      notifyListeners();
    }
  }

  void _recordRealtimeIssue(String message) {
    realtimeLog.insert(0, message);
    if (realtimeLog.length > 20) realtimeLog.removeLast();
  }

  void _subscribePublicSelected() {
    final symbols = <String>{
      selectedSymbol,
      for (final instrument in visibleInstruments) instrument.symbol,
    };
    for (final symbol in symbols) {
      publicRealtime.subscribe('trades', symbol: symbol);
    }
    publicRealtime.subscribe('depth', symbol: selectedSymbol);
    publicRealtime.subscribe('candles', symbol: selectedSymbol, period: period);
  }

  void _subscribePrivateSelected() {
    if (!isLoggedIn) return;
    privateRealtime.subscribe('orders', symbol: selectedSymbol);
    privateRealtime.subscribe('matches', symbol: selectedSymbol);
    privateRealtime.subscribe('executionReports', symbol: selectedSymbol);
    privateRealtime.subscribe('positions', symbol: selectedSymbol);
    privateRealtime.subscribe('positionRisk', symbol: selectedSymbol);
    privateRealtime.subscribe('accountRisk');
  }

  void handleRealtimeMessage(Map<String, dynamic> message) {
    final op = asString(message['op']);
    final channel = asString(message['channel']);
    final data = asMap(message['data']);
    if (op == 'error') {
      lastError = asString(message['error'], fallback: '实时消息错误');
      notifyListeners();
      return;
    }
    if (op != 'event') return;
    realtimeLog.insert(0, '$channel ${DateTime.now().toIso8601String()}');
    if (realtimeLog.length > 20) realtimeLog.removeLast();
    final symbol = asString(
      message['symbol'],
      fallback: asString(data['symbol'], fallback: selectedSymbol),
    );
    if (channel == 'depth') {
      if (symbol != selectedSymbol) return;
      _applyDepthUpdate(symbol, data);
    } else if (channel == 'trades') {
      final price = _tradePrice(symbol, data);
      if (price != null && price > 0) latestPrices[symbol] = price;
    } else if (channel == 'candles') {
      if (symbol != selectedSymbol) return;
      final messagePeriod = asString(
        message['period'],
        fallback: asString(data['period'], fallback: period),
      );
      if (messagePeriod != period) return;
      final candle = Candle.fromJson(data);
      final index = candles.indexWhere(
        (item) => item.openTime == candle.openTime,
      );
      if (index >= 0) {
        candles = [...candles]..[index] = candle;
      } else {
        candles = [...candles, candle]
          ..sort((a, b) => a.openTime.compareTo(b.openTime));
      }
      if (candles.length > 300) candles = candles.sublist(candles.length - 300);
      latestPrices[symbol] = candle.close;
    } else if (channel == 'orders') {
      _upsertOrder(OrderModel.fromJson(data));
    } else if (channel == 'positions') {
      final position = Position.fromJson(data);
      positions = [
        for (final item in positions)
          if (item.symbol != position.symbol ||
              item.marginMode != position.marginMode ||
              item.positionSide != position.positionSide)
            item,
        if (position.signedQuantitySteps != 0) position,
      ];
    } else if (channel == 'accountRisk') {
      accountRisk = AccountRisk.fromJson(data);
    } else if (channel == 'positionRisk') {
      final risk = PositionRisk.fromJson(data);
      positionRisks = [
        for (final item in positionRisks)
          if (item.symbol != risk.symbol ||
              item.positionSide != risk.positionSide)
            item,
        risk,
      ];
    }
    notifyListeners();
  }

  void _applyDepthUpdate(String symbol, Map<String, dynamic> data) {
    final sequence = asInt(
      data['sequence'] ?? data['lastSequence'] ?? data['eventSequence'],
    );
    final updateType = asString(data['updateType'], fallback: 'SNAPSHOT');
    final depth = asInt(data['depth'], fallback: 50);
    if (updateType != 'DELTA') {
      orderBook = OrderBook.fromJson({
        'symbol': symbol,
        'sequence': sequence,
        'bids': data['bids'] ?? data['bidLevels'] ?? const [],
        'asks': data['asks'] ?? data['askLevels'] ?? const [],
      });
      return;
    }
    final previousSequence = asInt(
      data['previousSequence'],
      fallback: orderBook.sequence,
    );
    if (orderBook.symbol != symbol ||
        orderBook.sequence == 0 ||
        previousSequence != orderBook.sequence) {
      unawaited(refreshPublicData(silent: true));
      return;
    }
    orderBook = OrderBook(
      symbol: symbol,
      sequence: sequence,
      bids: _mergeDepthLevels(
        orderBook.bids,
        data['bids'] ?? data['bidLevels'] ?? const [],
        descending: true,
        depth: depth,
      ),
      asks: _mergeDepthLevels(
        orderBook.asks,
        data['asks'] ?? data['askLevels'] ?? const [],
        descending: false,
        depth: depth,
      ),
    );
  }

  double? _tradePrice(String symbol, Map<String, dynamic> data) {
    final decimalPrice = asDouble(data['price']);
    if (decimalPrice > 0) return decimalPrice;
    final priceTicks = asInt(data['priceTicks']);
    if (priceTicks <= 0) return null;
    return _instrumentForSymbol(symbol).priceFromTicks(priceTicks);
  }

  Instrument _instrumentForSymbol(String symbol) {
    return instruments.firstWhere(
      (instrument) => instrument.symbol == symbol,
      orElse: () => selectedInstrument,
    );
  }

  String _productLineForSymbol(String symbol) {
    return _instrumentForSymbol(symbol).mode.productLine;
  }

  void _upsertOrder(OrderModel order) {
    final mutable = [...openOrders];
    final index = mutable.indexWhere((item) => item.orderId == order.orderId);
    if (index >= 0) {
      if (order.remainingQuantitySteps <= 0 ||
          order.status == 'CANCELED' ||
          order.status == 'FILLED') {
        mutable.removeAt(index);
      } else {
        mutable[index] = order;
      }
    } else if (order.remainingQuantitySteps > 0 &&
        order.status != 'CANCELED' &&
        order.status != 'FILLED') {
      mutable.insert(0, order);
    }
    openOrders = mutable;
  }

  void _upsertAlgoOrder(AlgoOrderModel order) {
    final mutable = [...openAlgoOrders];
    final index = mutable.indexWhere(
      (item) => item.algoOrderId == order.algoOrderId,
    );
    if (index >= 0) {
      if (!_isOpenAlgoStatus(order.status)) {
        mutable.removeAt(index);
      } else {
        mutable[index] = order;
      }
    } else if (_isOpenAlgoStatus(order.status)) {
      mutable.insert(0, order);
    }
    openAlgoOrders = mutable;
  }

  void _upsertTriggerOrder(TriggerOrderModel order) {
    final mutable = [...openTriggerOrders];
    final index = mutable.indexWhere(
      (item) => item.triggerOrderId == order.triggerOrderId,
    );
    if (index >= 0) {
      if (!_isOpenTriggerStatus(order.status)) {
        mutable.removeAt(index);
      } else {
        mutable[index] = order;
      }
    } else if (_isOpenTriggerStatus(order.status)) {
      mutable.insert(0, order);
    }
    openTriggerOrders = mutable;
  }

  @override
  void dispose() {
    _realtimeNotifyTimer?.cancel();
    unawaited(publicRealtime.close());
    unawaited(privateRealtime.close());
    super.dispose();
  }
}

bool _isOpenTriggerStatus(String status) {
  return status == 'NEW' || status == 'TRIGGERING';
}

bool _isOpenAlgoStatus(String status) {
  return status == 'PENDING' ||
      status == 'RUNNING' ||
      status == 'CANCEL_REQUESTED';
}

List<OrderBookLevel> _mergeDepthLevels(
  List<OrderBookLevel> current,
  Object? updates, {
  required bool descending,
  required int depth,
}) {
  final byPrice = <int, OrderBookLevel>{
    for (final level in current) level.priceTicks: level,
  };
  for (final item in asList(updates)) {
    final level = OrderBookLevel.fromJson(asMap(item));
    if (level.quantitySteps <= 0) {
      byPrice.remove(level.priceTicks);
    } else {
      byPrice[level.priceTicks] = level;
    }
  }
  final levels = byPrice.values.toList()
    ..sort(
      (left, right) => descending
          ? right.priceTicks.compareTo(left.priceTicks)
          : left.priceTicks.compareTo(right.priceTicks),
    );
  if (depth > 0 && levels.length > depth) return levels.take(depth).toList();
  return levels;
}
