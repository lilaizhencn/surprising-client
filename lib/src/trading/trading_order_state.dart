import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../models.dart';
import '../spot_order.dart';
import '../session_store.dart';
import '../trading_receipt_resolver.dart';

/// Selection and committed account data are read from their existing owners.
typedef TradingOrderContext = ({
  int? userId,
  String? accessToken,
  int epoch,
  int selection,
  ProductMode product,
  String symbol,
  Instrument instrument,
  String positionMode,
  List<Position> positions,
  List<Instrument> instruments,
  bool onlyCurrentPair,
  Set<ProductMode> disabledProducts,
});

/// Owns order commands, durable unresolved intents, cancellation plans and queries.
class TradingOrderState extends ChangeNotifier {
  TradingOrderState({
    required this.api,
    required this.settingsStore,
    required this.context,
    required this.persist,
    required this.refreshPrivateData,
    required this.offline,
    required this.onFeedback,
  });

  final ApiClient api;
  final ClientSettingsStore settingsStore;
  bool _restored = false;
  Future<bool>? _restoring;
  bool get restored => _restored;
  final TradingOrderContext Function() context;
  final Future<bool> Function({PendingTradingOrder? completedTradingIntent})
  persist;
  final Future<void> Function() refreshPrivateData;
  final bool offline;
  final void Function(String? error, String? notice) onFeedback;
  bool _disposed = false;
  String? lastError, lastNotice;
  int? get userId => context().userId;
  int get _accountEpoch => context().epoch;
  ProductMode get mode => context().product;
  String get selectedSymbol => context().symbol;
  Instrument get selectedInstrument => context().instrument;
  String get positionMode => context().positionMode;
  List<Position> get positions => context().positions;
  List<Instrument> get instruments => context().instruments;
  bool get onlyCurrentTradingPair => context().onlyCurrentPair;
  Set<ProductMode> get disabledProducts => context().disabledProducts;

  bool submittingOrder = false;
  bool submittingTriggers = false;
  CancellationSummary? lastCancellationResult;
  final Map<int, PendingTradingOrder> _pendingTradingOrders = {};
  PendingTradingOrder? get pendingTradingCommand =>
      _pendingTradingOrders[userId];
  bool get tradingCommandPending => pendingTradingCommand != null;
  List<OrderModel> openOrders = const [];
  String? openOrdersNextCursor;
  bool openOrdersHasMore = false;
  bool loadingMoreOpenOrders = false;
  List<AlgoOrderModel> openAlgoOrders = const [];
  bool loadingAlgoOrders = false;
  String? algoOrdersError;
  int _algoOrdersRequestVersion = 0;
  int _openOrdersRequestVersion = 0;
  Map<String, Instrument> _algoOrderInstruments = const {};
  List<TriggerOrderModel> openTriggerOrders = const [];

  @override
  void notifyListeners() {
    if (_disposed) return;
    onFeedback(lastError, lastNotice);
    super.notifyListeners();
  }

  Future<bool> _writeSettings({
    PendingTradingOrder? completedTradingIntent,
  }) async {
    if (!await restore()) return false;
    return persist(completedTradingIntent: completedTradingIntent);
  }

  bool ownsIntent(PendingTradingOrder intent) =>
      identical(_pendingTradingOrders[intent.userId], intent);
  bool completeSaved(PendingTradingOrder intent) {
    if (!ownsIntent(intent)) return false;
    _pendingTradingOrders.remove(intent.userId);
    return true;
  }

  List<Map<String, dynamic>> settingsRows({PendingTradingOrder? completed}) {
    if (!_restored) throw StateError('委托恢复资料尚未加载');
    return _pendingTradingOrders.values
        .where((intent) => !identical(intent, completed))
        .map(
          (intent) => {
            'userId': intent.userId,
            'productLine': intent.product.productLine,
            'commandId': intent.commandId,
            'clientOrderId': intent.clientOrderId,
            'clientAlgoOrderId': intent.clientAlgoOrderId,
            'instrumentId': intent.instrumentId,
            'cancelOrderId': intent.cancelOrderId,
            'amendRequestId': intent.amendRequestId,
            'amendOrderId': intent.amendOrderId,
            'cancelPlan': intent.cancelPlan?.toJson(),
            'ocoTakeProfitClientId': intent.ocoTakeProfitClientId,
            'ocoStopLossClientId': intent.ocoStopLossClientId,
            'clientTriggerOrderId': intent.clientTriggerOrderId,
            'cancelTriggerOrderId': intent.cancelTriggerOrderId,
          },
        )
        .toList();
  }

  Instrument? algoInstrumentFor(AlgoOrderModel order) =>
      instruments
          .where(
            (i) =>
                i.mode == order.product && i.instrumentId == order.instrumentId,
          )
          .firstOrNull ??
      (order.product == mode
          ? _algoOrderInstruments[order.instrumentId]
          : null);
  List<AlgoOrderModel> get visibleAlgoOrders => openAlgoOrders
      .where(
        (order) =>
            order.userId == userId &&
            order.product == mode &&
            order.isOpen &&
            (!onlyCurrentTradingPair ||
                order.instrumentId == selectedInstrument.instrumentId),
      )
      .toList();

  void resetAlgoOrders() {
    ++_algoOrdersRequestVersion;
    openAlgoOrders = const [];
    _algoOrderInstruments = const {};
    loadingAlgoOrders = false;
    algoOrdersError = null;
  }

  void invalidateOpenOrders() {
    ++_openOrdersRequestVersion;
    loadingMoreOpenOrders = false;
  }

  void invalidateQueries() {
    ++_openOrdersRequestVersion;
    resetAlgoOrders();
  }

  void resetAccount() {
    submittingOrder = false;
    submittingTriggers = false;
    lastCancellationResult = null;
    openOrders = const [];
    openTriggerOrders = const [];
    openOrdersNextCursor = null;
    openOrdersHasMore = false;
    loadingMoreOpenOrders = false;
    lastError = null;
    lastNotice = null;
    invalidateQueries();
  }

  void restoreSettings(Map<String, String> values) {
    if (_disposed) throw StateError('委托状态已关闭');
    if (_restored) return;
    final restored = <int, PendingTradingOrder>{};
    void add(PendingTradingOrder intent) {
      if (restored.containsKey(intent.userId)) {
        throw const FormatException('委托恢复资料账户重复');
      }
      restored[intent.userId] = intent;
    }

    const legacyKeys = {
      'pendingTradingCommand',
      'pendingTradingUser',
      'pendingTradingProduct',
    };
    if (legacyKeys.any(values.containsKey)) {
      if (!legacyKeys.every(values.containsKey)) {
        throw const FormatException('原委托恢复资料不完整');
      }
      add(
        _pendingFromJson({
          'userId': values['pendingTradingUser'],
          'productLine': values['pendingTradingProduct'],
          'commandId': values['pendingTradingCommand'],
        }),
      );
    }
    final raw = jsonDecode(values['pendingTradingOrders'] ?? '[]');
    if (raw is! List || raw.length > 128) {
      throw const FormatException('委托恢复资料容器无效');
    }
    for (final row in raw) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('委托恢复资料条目无效');
      }
      add(_pendingFromJson(row));
    }
    if (restored.length > 128) throw const FormatException('未决委托账户数量过多');
    // Validation completes before any authoritative state or restoration flag changes.
    _pendingTradingOrders.addAll(restored);
    _restored = true;
  }

  Future<bool> restore() async {
    if (_disposed) return false;
    if (_restored) return true;
    final existing = _restoring;
    if (existing != null) return existing;
    final loading = _restoreOnce();
    _restoring = loading;
    try {
      return await loading;
    } finally {
      if (identical(_restoring, loading)) _restoring = null;
    }
  }

  Future<bool> _restoreOnce() async {
    try {
      final values = await settingsStore.read();
      if (_disposed) return false;
      restoreSettings(values);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _sameSelection(TradingOrderContext before) {
    final after = context();
    return !_disposed &&
        before.userId == after.userId &&
        before.accessToken == after.accessToken &&
        before.epoch == after.epoch &&
        before.selection == after.selection &&
        before.product == after.product &&
        before.symbol == after.symbol &&
        before.instrument.instrumentId == after.instrument.instrumentId &&
        before.instrument.changeId == after.instrument.changeId;
  }

  Future<bool> _restoreBeforeCommand() async {
    if (_disposed) return false;
    final before = context();
    if (!await restore()) {
      if (_sameSelection(before)) {
        lastError = '无法读取原委托凭证，未发送请求，请检查安全存储后重试';
        lastNotice = null;
        notifyListeners();
      }
      return false;
    }
    if (!_sameSelection(before)) return false;
    if (before.userId != null &&
        !_pendingTradingOrders.containsKey(before.userId) &&
        _pendingTradingOrders.length >= 128) {
      lastError = '未决委托账户数量过多，请先确认原请求';
      notifyListeners();
      return false;
    }
    return true;
  }

  Future<void> checkPendingTradingCommand() async {
    if (!await _restoreBeforeCommand()) return;
    final pending = pendingTradingCommand;
    if (pending == null || pending.userId != userId || submittingOrder) return;
    final epoch = _accountEpoch;
    bool current() =>
        !_disposed && epoch == _accountEpoch && userId == pending.userId;
    submittingOrder = true;
    lastError = null;
    notifyListeners();
    try {
      if (pending.cancelPlan != null) {
        await _driveCancellationPlan(pending);
        return;
      }
      final confirmed = await TradingReceiptResolver(api).resolve(pending);
      if (!current() || pendingTradingCommand != pending) return;
      if (confirmed != null) {
        if (!await _clearTradingIntent(pending)) {
          if (current()) lastError = '无法保存委托确认结果，请再次查询原请求';
          return;
        }
        if (!current()) return;
        if (confirmed) {
          lastNotice = pending.clientAlgoOrderId != null
              ? '算法单创建请求已确认，请查看策略和成交记录'
              : pending.clientTriggerOrderId != null ||
                    pending.cancelTriggerOrderId != null
              ? '条件单请求结果已确认，请查看最新条件单状态'
              : pending.amendRequestId != null
              ? '改单处理结果已确认，请查看原单和新委托状态'
              : pending.cancelOrderId != null
              ? '撤单处理结果已确认，请查看最新订单状态'
              : '委托处理结果已确认，订单状态以最新账户数据为准';
          await refreshPrivateData();
        } else {
          lastError = pending.clientAlgoOrderId != null
              ? '算法单创建请求被拒绝，请检查参数和账户状态'
              : pending.clientTriggerOrderId != null ||
                    pending.cancelTriggerOrderId != null
              ? '条件单请求被拒绝，请查看最新条件单状态'
              : pending.amendRequestId != null
              ? '改单请求被拒绝，请查看原单状态'
              : pending.cancelOrderId != null
              ? '撤单请求被拒绝，请查看最新订单状态'
              : '委托未被接受，请检查订单状态';
        }
      } else {
        lastNotice = '委托结果仍待确认，请勿重复提交';
      }
    } catch (error) {
      if (current()) lastError = '查询委托结果失败：${clientErrorMessage(error)}';
    } finally {
      if (current()) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  Future<void> refreshAlgoOrders() async {
    final id = userId, product = mode, epoch = _accountEpoch;
    if (offline || id == null) return;
    if (disabledProducts.contains(product)) {
      openAlgoOrders = [];
      algoOrdersError = null;
      loadingAlgoOrders = false;
      return;
    }
    final request = ++_algoOrdersRequestVersion;
    final filter = onlyCurrentTradingPair;
    final instrument = selectedInstrument;
    bool current() =>
        !_disposed &&
        request == _algoOrdersRequestVersion &&
        !_disposed &&
        epoch == _accountEpoch &&
        userId == id &&
        mode == product &&
        onlyCurrentTradingPair == filter &&
        (!filter || selectedInstrument.instrumentId == instrument.instrumentId);
    loadingAlgoOrders = true;
    algoOrdersError = null;
    notifyListeners();
    try {
      if (filter && instrument.instrumentId.isEmpty) {
        throw const FormatException('算法单交易对资料尚未就绪');
      }
      final rows = await api.openAlgoOrders(
        id,
        symbol: filter ? instrument.symbol : null,
        productLine: product.productLine,
      );
      if (!current()) return;
      if (rows.any(
        (o) =>
            o.userId != id ||
            o.product != product ||
            !o.isOpen ||
            (filter && o.instrumentId != instrument.instrumentId),
      )) {
        throw const FormatException('算法单查询归属不匹配');
      }
      openAlgoOrders = rows;
      final metadata = <String, Instrument>{};
      bool metadataMissing = false;
      for (final id in rows.map((o) => o.instrumentId).toSet()) {
        if (instruments.any((i) => i.mode == product && i.instrumentId == id)) {
          continue;
        }
        try {
          final value = await api.instrumentLatest(id, product);
          if (!current()) return;
          if (value.instrumentId != id || value.mode != product) {
            throw const FormatException('算法单合约资料归属不匹配');
          }
          metadata[id] = value;
        } catch (_) {
          if (!current()) return;
          metadataMissing = true;
        }
      }
      if (!current()) return;
      _algoOrderInstruments = metadata;
      if (metadataMissing) algoOrdersError = '部分合约资料未就绪，请刷新策略重试';
    } catch (error) {
      if (current()) {
        openAlgoOrders = const [];
        _algoOrderInstruments = const {};
        algoOrdersError = '加载算法单失败：${clientErrorMessage(error)}';
      }
    } finally {
      if (current()) {
        loadingAlgoOrders = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreOpenOrders() async {
    final id = userId;
    final cursor = openOrdersNextCursor;
    if (offline ||
        id == null ||
        cursor == null ||
        cursor.isEmpty ||
        !openOrdersHasMore ||
        loadingMoreOpenOrders) {
      return;
    }
    final openOrdersRequestVersion = ++_openOrdersRequestVersion;
    final symbol = selectedSymbol;
    final productLine = mode.productLine;
    loadingMoreOpenOrders = true;
    notifyListeners();
    try {
      final nextPage = await api.openOrders(
        id,
        symbol: symbol,
        productLine: productLine,
        cursor: cursor,
      );
      if (_disposed || openOrdersRequestVersion != _openOrdersRequestVersion) {
        return;
      }
      final orderIds = openOrders.map((item) => item.orderId).toSet();
      openOrders = [
        ...openOrders,
        ...nextPage.orders.where((item) => orderIds.add(item.orderId)),
      ];
      openOrdersNextCursor = nextPage.nextCursor;
      openOrdersHasMore = nextPage.hasMore;
      lastError = null;
    } catch (error) {
      if (!_disposed && openOrdersRequestVersion == _openOrdersRequestVersion) {
        lastError = '加载更多委托失败：${clientErrorMessage(error)}';
      }
    } finally {
      if (!_disposed && openOrdersRequestVersion == _openOrdersRequestVersion) {
        loadingMoreOpenOrders = false;
        notifyListeners();
      }
    }
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
    String? bboPriceMode,
    Instrument? targetInstrument,
    String? priceText,
  }) async {
    if (!await _restoreBeforeCommand()) return;
    if (_disposed || submittingOrder || tradingCommandPending) return;
    lastError = null;
    lastNotice = null;
    final instrument = targetInstrument ?? selectedInstrument;
    final effectiveReduceOnly = instrument.effectiveReduceOnly(
      reduceOnly: reduceOnly,
      side: side,
      positionMode: positionMode,
      positionSide: positionSide,
    );
    final exactPrice = orderType != 'MARKET' && bboPriceMode == null
        ? instrument.priceTicksFromText(priceText ?? '$price')
        : null;
    try {
      validateOrderPolicy(orderType, timeInForce, postOnly, bboPriceMode);
    } on FormatException catch (error) {
      lastError = error.message;
      notifyListeners();
      return;
    }
    if (!instrument.canPlaceOrder(reduceOnly: effectiveReduceOnly)) {
      lastError = instrument.isDelivery && instrument.status == 'SETTLING'
          ? '合约结算中，仅允许减仓'
          : instrument.status == 'PRE_TRADING'
          ? '该交易对尚未开放交易'
          : '该交易对已暂停交易';
      notifyListeners();
      return;
    }
    if (instrument.symbol.isEmpty ||
        (instrument.isSpot && instrument.instrumentId.isEmpty) ||
        quantitySteps <= 0 ||
        (orderType != 'MARKET' &&
            bboPriceMode == null &&
            (!price.isFinite || price <= 0 || exactPrice == null))) {
      lastError = '请输入有效的价格和数量';
      notifyListeners();
      return;
    }
    final effectivePositionSide = instrument.isSpot || positionMode == 'ONE_WAY'
        ? 'NET'
        : positionSide == 'NET'
        ? (side == 'SELL' ? 'SHORT' : 'LONG')
        : positionSide;
    if (instrument.isExpiring && effectiveReduceOnly) {
      final position = positions
          .where(
            (p) =>
                p.instrumentId == instrument.instrumentId &&
                p.marginMode == marginMode &&
                (positionMode == 'ONE_WAY' ||
                    p.positionSide == effectivePositionSide),
          )
          .firstOrNull;
      if (position == null ||
          position.signedQuantitySteps == 0 ||
          (position.signedQuantitySteps > 0 ? 'SELL' : 'BUY') != side ||
          BigInt.from(quantitySteps) >
              BigInt.from(position.signedQuantitySteps).abs()) {
        lastError = '减仓方向或数量与当前持仓不匹配，请刷新账户后重试';
        notifyListeners();
        return;
      }
    }
    final id = userId;
    if (id == null) {
      lastError = '请先登录再下单';
      notifyListeners();
      return;
    }
    final epoch = _accountEpoch;
    bool current() => !_disposed && epoch == _accountEpoch && userId == id;
    final random = math.Random.secure();
    final pendingIntent = instrument.mode.tracksSingleOrderIntent
        ? PendingTradingOrder(
            userId: id,
            product: instrument.mode,
            instrumentId: instrument.instrumentId,
            clientOrderId:
                'app-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
          )
        : null;
    var issued = false;
    var outcomeConfirmed = false;
    submittingOrder = true;
    notifyListeners();
    try {
      final productLine = instrument.mode.productLine;
      final intent = pendingIntent;
      if (intent != null) {
        _pendingTradingOrders[id] = intent;
        if (!await _writeSettings()) {
          _pendingTradingOrders.remove(id);
          if (current()) lastError = '无法保存委托恢复资料，未发送订单';
          return;
        }
        if (!current()) {
          _pendingTradingOrders.remove(id);
          await _writeSettings();
          return;
        }
      }
      issued = true;
      final order = await api.placeOrder(
        userId: id,
        symbol: instrument.symbol,
        side: side,
        orderType: orderType,
        timeInForce: timeInForce,
        priceTicks: orderType == 'MARKET' || bboPriceMode != null
            ? 0
            : exactPrice!,
        quantitySteps: quantitySteps,
        marginMode: instrument.isSpot ? 'CROSS' : marginMode,
        positionSide: effectivePositionSide,
        reduceOnly: !instrument.isSpot && effectiveReduceOnly,
        postOnly: postOnly,
        bboPriceMode: bboPriceMode,
        productLine: productLine,
        clientOrderId: intent?.clientOrderId,
      );
      if (order.orderId <= 0 ||
          (instrument.mode.tracksSingleOrderIntent &&
              ![
                'PENDING_RESERVE',
                'ACCEPTED',
                'REJECTED',
                'CANCEL_REQUESTED',
                'CANCELED',
                'PARTIALLY_FILLED',
                'FILLED',
              ].contains(order.status))) {
        throw const FormatException('委托响应不完整，请查询原委托结果');
      }
      outcomeConfirmed = true;
      if (intent != null && !await _clearTradingIntent(intent)) {
        if (current()) lastError = '无法保存委托确认结果，请查询原委托结果';
        return;
      }
      if (!current()) return;
      if (order.status == 'REJECTED') {
        lastError = '订单未被接受，请检查委托结果后重试';
        return;
      }
      if (mode == instrument.mode &&
          selectedSymbol == instrument.symbol &&
          userId == id) {
        _upsertOrder(order);
      }
      lastNotice = '订单已提交 #${order.orderId}';
      await refreshPrivateData();
    } on PendingTradingCommand catch (pending) {
      _pendingTradingOrders[id] = PendingTradingOrder(
        userId: id,
        product: instrument.mode,
        commandId: _nonEmpty(pending.commandId),
        clientOrderId: pendingIntent?.clientOrderId,
        instrumentId: pendingIntent?.instrumentId,
      );
      await _writeSettings();
      if (current()) lastNotice = pending.message;
    } catch (error) {
      if (pendingIntent != null &&
          issued &&
          !outcomeConfirmed &&
          !isDefinitiveOrderRejection(error)) {
        if (current()) lastNotice = '委托结果待确认，请勿重复提交';
      } else {
        if (pendingIntent != null &&
            identical(_pendingTradingOrders[id], pendingIntent) &&
            !await _clearTradingIntent(pendingIntent)) {
          if (current()) lastError = '无法保存委托确认结果，请查询原委托结果';
          return;
        }
        if (current()) lastError = '下单失败：${clientErrorMessage(error)}';
      }
    } finally {
      if (current()) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  String _newCancellationKey() {
    final random = math.Random.secure();
    return 'app-cancel-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<void> cancelOpenSpotOrders({required bool onlyCurrentPair}) async {
    if (!await _restoreBeforeCommand()) return;
    final id = userId;
    if (id == null ||
        mode != ProductMode.spot ||
        submittingOrder ||
        tradingCommandPending) {
      return;
    }
    final instrument = onlyCurrentPair ? selectedInstrument.instrumentId : null;
    if (onlyCurrentPair && (instrument == null || instrument.isEmpty)) {
      lastError = '交易对资料未就绪，未发送撤单';
      notifyListeners();
      return;
    }
    final epoch = _accountEpoch;
    bool current() => !_disposed && epoch == _accountEpoch && userId == id;
    submittingOrder = true;
    lastError = null;
    lastNotice = null;
    lastCancellationResult = null;
    notifyListeners();
    try {
      final ids = await api.cancellationPlan(id, instrumentId: instrument);
      if (!current()) return;
      if (ids.isEmpty) {
        lastNotice = '当前范围没有可撤销委托';
        return;
      }
      final batches = <CancellationBatch>[];
      for (var start = 0; start < ids.length; start += 50) {
        batches.add(
          CancellationBatch(
            _newCancellationKey(),
            ids.sublist(start, math.min(start + 50, ids.length)),
          ),
        );
      }
      final pending = PendingTradingOrder(
        userId: id,
        product: ProductMode.spot,
        cancelPlan: CancellationPlan(
          id: _newCancellationKey(),
          batches: batches,
          instrumentId: instrument,
        ),
      );
      _pendingTradingOrders[id] = pending;
      if (!await _writeSettings()) {
        _pendingTradingOrders.remove(id);
        if (current()) lastError = '无法保存批量撤单资料，未发送撤单';
        return;
      }
      if (!current()) {
        _pendingTradingOrders.remove(id);
        await _writeSettings();
        return;
      }
      await _driveCancellationPlan(pending);
    } catch (error) {
      if (current()) lastError = '批量撤单失败：${clientErrorMessage(error)}';
    } finally {
      if (current()) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  Future<void> _driveCancellationPlan(PendingTradingOrder initial) async {
    var pending = initial;
    final epoch = _accountEpoch;
    bool current() =>
        !_disposed && epoch == _accountEpoch && userId == pending.userId;
    bool owns() => identical(_pendingTradingOrders[pending.userId], pending);
    try {
      while (pending.cancelPlan!.index < pending.cancelPlan!.batches.length) {
        if (!current() || !owns()) return;
        final plan = pending.cancelPlan!, batch = plan.batches[plan.index];
        late OrderBatchResult result;
        if (plan.issued) {
          Map<String, dynamic> receipt;
          try {
            receipt = await api.get(
              '/api/v1/gateway/trading/cancellation-batches',
              userId: pending.userId,
              productLine: 'SPOT',
              query: {'userId': '${pending.userId}', 'batchKey': batch.key},
            );
          } on ApiException catch (error) {
            final parsed = asMap(jsonDecode(error.message));
            if (parsed['outcome'] != 'TERMINAL') rethrow;
            receipt = parsed;
          }
          if (receipt['commandId'] is! String ||
              asString(receipt['commandId']).isEmpty ||
              (pending.commandId != null &&
                  receipt['commandId'] != pending.commandId)) {
            throw const FormatException('批量撤单回执不匹配');
          }
          if (receipt['outcome'] == 'RESULT_UNKNOWN' ||
              receipt['outcome'] == 'MATCHING_PENDING') {
            if (current()) lastNotice = '批量撤单结果待确认，请确认后继续';
            return;
          }
          final ids = asList(
            receipt['prospectiveOrderIds'],
          ).map(asInt).toList();
          if (receipt['outcome'] != 'TERMINAL' ||
              ids.length != batch.orderIds.length ||
              !List.generate(
                ids.length,
                (i) => ids[i] == batch.orderIds[i],
              ).every((same) => same)) {
            throw const FormatException('批量撤单目标不匹配');
          }
          result = OrderBatchResult.fromCancellationJson(
            asMap(receipt['result']),
          );
        } else {
          final before = pending;
          pending = PendingTradingOrder(
            userId: pending.userId,
            product: ProductMode.spot,
            cancelPlan: plan.markIssued(),
          );
          if (!identical(_pendingTradingOrders[pending.userId], before)) return;
          _pendingTradingOrders[pending.userId] = pending;
          if (!await _writeSettings()) {
            _pendingTradingOrders[pending.userId] = before;
            throw const FormatException('未能保存批量撤单进度，未发送本批');
          }
          if (!current()) {
            if (owns()) {
              _pendingTradingOrders[pending.userId] = before;
              await _writeSettings();
            }
            return;
          }
          try {
            result = await api.cancelOrderBatch(
              pending.userId,
              batch.orderIds,
              productLine: 'SPOT',
              batchKey: batch.key,
            );
          } on PendingTradingCommand catch (command) {
            if (!owns()) return;
            pending = PendingTradingOrder(
              userId: pending.userId,
              product: ProductMode.spot,
              cancelPlan: pending.cancelPlan,
              commandId: _nonEmpty(command.commandId),
            );
            _pendingTradingOrders[pending.userId] = pending;
            await _writeSettings();
            if (current()) lastNotice = '批量撤单结果待确认，请确认后继续';
            return;
          } catch (error) {
            if (!isDefinitiveOrderRejection(error)) rethrow;
            String code = 'REQUEST_REJECTED';
            if (error is ApiException) {
              try {
                final raw = asMap(jsonDecode(error.message));
                code = _nonEmpty(asString(raw['code'])) ?? code;
              } catch (_) {}
            }
            result = OrderBatchResult(
              requested: batch.orderIds.length,
              completed: 0,
              failed: batch.orderIds.length,
              results: List.generate(
                batch.orderIds.length,
                (i) => OrderBatchItem(index: i, success: false, message: code),
              ),
            );
          }
        }
        if (!owns()) return;
        final previous = pending, advanced = plan.advance(result);
        pending = PendingTradingOrder(
          userId: pending.userId,
          product: ProductMode.spot,
          cancelPlan: advanced,
        );
        _pendingTradingOrders[pending.userId] = pending;
        if (!await _writeSettings()) {
          _pendingTradingOrders[pending.userId] = previous;
          throw const FormatException('未能保存已确认进度，请确认后继续');
        }
        if (current()) notifyListeners();
      }
      if (!owns()) return;
      final plan = pending.cancelPlan!;
      if (!await _clearTradingIntent(pending)) {
        throw const FormatException('无法保存批量撤单确认结果，请确认后继续');
      }
      if (!current()) return;
      lastCancellationResult = CancellationSummary(
        pending.userId,
        plan.requested,
        plan.completed,
        plan.failed,
        plan.failures,
      );
      lastNotice =
          '批量撤单已处理 ${plan.requested} 笔，成功 ${plan.completed} 笔，失败 ${plan.failed} 笔，请查看最新委托状态';
      await refreshPrivateData();
    } catch (error) {
      if (current()) lastError = '批量撤单尚未确认：${clientErrorMessage(error)}';
    }
  }

  Future<void> amendSpotOrder(
    OrderModel order,
    Instrument instrument,
    String price,
    String quantity,
  ) async {
    if (!await _restoreBeforeCommand()) return;
    final id = userId;
    if (id == null || submittingOrder || tradingCommandPending) return;
    lastError = null;
    lastNotice = null;
    late final ({int priceTicks, int quantitySteps}) terms;
    try {
      if (mode != ProductMode.spot) throw const FormatException('请切换至现货产品');
      terms = spotAmendmentTerms(instrument, order, price, quantity);
    } on FormatException catch (error) {
      lastError = error.message;
      notifyListeners();
      return;
    }
    final epoch = _accountEpoch;
    bool current() => !_disposed && epoch == _accountEpoch && userId == id;
    final random = math.Random.secure();
    final key =
        'app-amend-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
    final intent = PendingTradingOrder(
      userId: id,
      product: ProductMode.spot,
      amendRequestId: key,
      amendOrderId: order.orderId,
      clientOrderId: key,
      instrumentId: instrument.instrumentId,
    );
    bool issued = false, confirmed = false;
    submittingOrder = true;
    notifyListeners();
    try {
      _pendingTradingOrders[id] = intent;
      if (!await _writeSettings()) {
        if (_pendingTradingOrders[id] == intent) {
          _pendingTradingOrders.remove(id);
        }
        if (current()) lastError = '无法保存改单恢复资料，未发送改单';
        return;
      }
      if (!current()) {
        if (_pendingTradingOrders[id] == intent) {
          _pendingTradingOrders.remove(id);
        }
        await _writeSettings();
        return;
      }
      issued = true;
      final result = await api.amendOrder(
        userId: id,
        orderId: order.orderId,
        priceTicks: terms.priceTicks,
        quantitySteps: terms.quantitySteps,
        newClientOrderId: key,
        clientRequestId: key,
        timeInForce: order.timeInForce,
        postOnly: order.postOnly,
        productLine: 'SPOT',
      );
      if (result.originalOrder.orderId != order.orderId ||
          result.originalOrder.status != 'CANCELED' ||
          result.replacementOrder.orderId <= 0 ||
          result.replacementOrder.orderId == order.orderId ||
          !result.cancelRequested ||
          result.replacementOrder.symbol != instrument.symbol ||
          ![
            'ACCEPTED',
            'PARTIALLY_FILLED',
            'FILLED',
            'CANCELED',
            'REJECTED',
          ].contains(result.replacementOrder.status)) {
        throw const FormatException('改单响应不完整，请查询原改单结果');
      }
      confirmed = true;
      if (!await _clearTradingIntent(intent)) {
        if (current()) lastError = '无法保存改单确认结果，请查询原改单结果';
        return;
      }
      if (!current()) return;
      if (mode == ProductMode.spot && selectedSymbol == instrument.symbol) {
        _upsertOrder(result.originalOrder);
        _upsertOrder(result.replacementOrder);
      }
      if (result.replacementOrder.status == 'REJECTED') {
        lastError = '新委托被拒绝，请查看原单和新委托状态';
      } else {
        lastNotice = '改单已处理，新委托 #${result.replacementOrder.orderId}';
      }
      await refreshPrivateData();
    } on PendingTradingCommand catch (pending) {
      if (_pendingTradingOrders[id] == intent) {
        _pendingTradingOrders[id] = PendingTradingOrder(
          userId: id,
          product: ProductMode.spot,
          amendRequestId: key,
          amendOrderId: order.orderId,
          clientOrderId: key,
          instrumentId: instrument.instrumentId,
          commandId: _nonEmpty(pending.commandId),
        );
        await _writeSettings();
      }
      if (current()) lastNotice = '改单结果待确认，请勿重复提交';
    } catch (error) {
      if (issued && !confirmed && !isDefinitiveOrderRejection(error)) {
        if (current()) lastNotice = '改单结果待确认，请勿重复提交';
      } else {
        if (identical(_pendingTradingOrders[id], intent) &&
            !await _clearTradingIntent(intent)) {
          if (current()) lastError = '无法保存改单确认结果，请查询原改单结果';
          return;
        }
        if (current()) lastError = '改单失败：${clientErrorMessage(error)}';
      }
    } finally {
      if (current()) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  Future<void> cancelOrder(OrderModel order) async {
    if (!await _restoreBeforeCommand()) return;
    final id = userId;
    if (id == null ||
        order.orderId <= 0 ||
        submittingOrder ||
        tradingCommandPending) {
      return;
    }
    final product = mode;
    final epoch = _accountEpoch;
    bool current() => !_disposed && epoch == _accountEpoch && userId == id;
    final intent = product.tracksSingleOrderIntent
        ? PendingTradingOrder(
            userId: id,
            product: product,
            cancelOrderId: order.orderId,
          )
        : null;
    bool issued = false, confirmed = false;
    submittingOrder = true;
    lastError = null;
    lastNotice = null;
    notifyListeners();
    try {
      if (intent != null) {
        _pendingTradingOrders[id] = intent;
        if (!await _writeSettings()) {
          if (_pendingTradingOrders[id] == intent) {
            _pendingTradingOrders.remove(id);
          }
          if (current()) lastError = '无法保存撤单恢复资料，未发送撤单';
          return;
        }
        if (!current()) {
          if (_pendingTradingOrders[id] == intent) {
            _pendingTradingOrders.remove(id);
          }
          await _writeSettings();
          return;
        }
      }
      issued = true;
      final cancelled = await api.cancelOrder(
        id,
        order.orderId,
        productLine: product.productLine,
      );
      if (cancelled.orderId != order.orderId ||
          ![
            'CANCELED',
            'CANCEL_REQUESTED',
            'FILLED',
          ].contains(cancelled.status)) {
        throw const FormatException('撤单响应不完整，请查询原撤单结果');
      }
      confirmed = true;
      if (intent != null && !await _clearTradingIntent(intent)) {
        if (current()) lastError = '无法保存撤单确认结果，请查询原撤单结果';
        return;
      }
      if (!current()) return;
      if (mode == product && selectedSymbol == order.symbol) {
        _upsertOrder(cancelled);
      }
      lastNotice = '撤单处理结果已确认 #${order.orderId}';
      await refreshPrivateData();
    } on PendingTradingCommand catch (pending) {
      if (intent == null || _pendingTradingOrders[id] == intent) {
        _pendingTradingOrders[id] = PendingTradingOrder(
          userId: id,
          product: product,
          commandId: _nonEmpty(pending.commandId),
          cancelOrderId: intent?.cancelOrderId,
        );
        await _writeSettings();
      }
      if (current()) lastNotice = '撤单结果待确认，请勿重复提交';
    } catch (error) {
      if (intent != null &&
          issued &&
          !confirmed &&
          !isDefinitiveOrderRejection(error)) {
        if (current()) lastNotice = '撤单结果待确认，请勿重复提交';
      } else {
        if (intent != null &&
            identical(_pendingTradingOrders[id], intent) &&
            !await _clearTradingIntent(intent)) {
          if (current()) lastError = '无法保存撤单确认结果，请查询原撤单结果';
          return;
        }
        if (current()) lastError = '撤单失败：${clientErrorMessage(error)}';
      }
    } finally {
      if (current()) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  Future<bool> placeAlgoOrder(AlgoOrderDraft draft) async {
    if (!await _restoreBeforeCommand()) return false;
    final id = userId, instrument = selectedInstrument;
    if (id == null || submittingOrder || tradingCommandPending) return false;
    if (!_validAlgoDraft(draft) ||
        instrument.instrumentId.isEmpty ||
        instrument.status != 'TRADING' ||
        (instrument.isExpiring && !instrument.canPlaceTrigger()) ||
        (instrument.isSpot &&
            (draft.marginMode != 'CROSS' ||
                draft.positionSide != 'NET' ||
                draft.reduceOnly))) {
      lastError = '请检查算法单参数、交易对状态和数量步长';
      notifyListeners();
      return false;
    }
    final epoch = _accountEpoch, product = instrument.mode;
    bool current() => !_disposed && epoch == _accountEpoch && userId == id;
    final random = math.Random.secure();
    final intent = PendingTradingOrder(
      userId: id,
      product: product,
      instrumentId: instrument.instrumentId,
      clientAlgoOrderId:
          'app-algo-${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}',
    );
    bool issued = false, confirmed = false;
    submittingOrder = true;
    lastError = null;
    lastNotice = null;
    notifyListeners();
    try {
      _pendingTradingOrders[id] = intent;
      if (!await _writeSettings()) {
        _pendingTradingOrders.remove(id);
        if (current()) lastError = '无法保存算法单原请求，未发送订单';
        return false;
      }
      if (!current() ||
          mode != product ||
          selectedInstrument.instrumentId != instrument.instrumentId) {
        await _clearTradingIntent(intent);
        return false;
      }
      issued = true;
      final order = await api.placeAlgoOrder(
        userId: id,
        clientAlgoOrderId: intent.clientAlgoOrderId!,
        symbol: instrument.symbol,
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
        productLine: product.productLine,
      );
      if (order.userId != id ||
          order.product != product ||
          order.instrumentId != instrument.instrumentId ||
          order.clientAlgoOrderId != intent.clientAlgoOrderId ||
          order.algoType != draft.algoType ||
          order.side != draft.side ||
          order.priceTicks != draft.priceTicks ||
          order.quantitySteps != draft.quantitySteps ||
          order.childQuantitySteps != draft.childQuantitySteps ||
          order.intervalSeconds !=
              (draft.algoType == 'TWAP' ? draft.intervalSeconds : 0) ||
          order.durationSeconds != draft.durationSeconds ||
          order.marginMode != draft.marginMode ||
          order.positionSide != draft.positionSide ||
          order.reduceOnly != draft.reduceOnly ||
          order.postOnly != (draft.algoType == 'ICEBERG' && draft.postOnly) ||
          order.timeInForce !=
              (draft.algoType == 'TWAP'
                  ? 'IOC'
                  : draft.postOnly
                  ? 'GTX'
                  : 'GTC')) {
        throw const FormatException('算法单响应与原请求不匹配，请查询原请求');
      }
      confirmed = true;
      if (!await _clearTradingIntent(intent)) {
        if (current()) lastError = '无法保存算法单确认结果，请查询原请求';
        return false;
      }
      if (!current()) return false;
      if (mode == product) {
        ++_algoOrdersRequestVersion;
        loadingAlgoOrders = false;
        _upsertAlgoOrder(order);
      }
      lastNotice = '算法单创建已确认 #${order.algoOrderId}';
      return true;
    } catch (error) {
      if (issued && !confirmed && !isDefinitiveOrderRejection(error)) {
        if (current()) lastNotice = '算法单创建结果待确认，请查询原请求，勿重复提交';
      } else {
        if (identical(_pendingTradingOrders[id], intent) &&
            !await _clearTradingIntent(intent)) {
          if (current()) lastError = '无法保存算法单确认结果，请查询原请求';
          return false;
        }
        if (current()) lastError = '创建算法单失败：${clientErrorMessage(error)}';
      }
      return false;
    } finally {
      if (current()) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  bool _validAlgoDraft(AlgoOrderDraft draft) {
    if (!['BUY', 'SELL'].contains(draft.side) ||
        !['TWAP', 'ICEBERG'].contains(draft.algoType) ||
        draft.priceTicks < 0 ||
        draft.quantitySteps <= 0 ||
        draft.childQuantitySteps <= 0 ||
        draft.childQuantitySteps > draft.quantitySteps ||
        draft.durationSeconds < 5 ||
        draft.durationSeconds > 86400 ||
        (draft.algoType == 'ICEBERG' && draft.priceTicks == 0)) {
      return false;
    }
    if (draft.algoType != 'TWAP') return true;
    if (draft.intervalSeconds < 1 ||
        draft.intervalSeconds > 86400 ||
        draft.durationSeconds < draft.intervalSeconds) {
      return false;
    }
    final slices =
        draft.quantitySteps ~/ draft.childQuantitySteps +
        (draft.quantitySteps % draft.childQuantitySteps == 0 ? 0 : 1);
    final allowed =
        (draft.durationSeconds + draft.intervalSeconds - 1) ~/
        draft.intervalSeconds;
    return slices <= allowed;
  }

  Future<void> cancelAlgoOrder(AlgoOrderModel order) async {
    if (!await _restoreBeforeCommand()) return;
    final id = userId;
    final product = mode, epoch = _accountEpoch;
    if (id == null || submittingOrder || tradingCommandPending) return;
    if (order.userId != id ||
        order.product != product ||
        !order.isOpen ||
        !visibleAlgoOrders.any(
          (o) =>
              o.algoOrderId == order.algoOrderId &&
              o.instrumentId == order.instrumentId &&
              o.clientAlgoOrderId == order.clientAlgoOrderId,
        )) {
      lastError = '算法单不属于当前查询，请刷新后重试';
      notifyListeners();
      return;
    }
    bool current() =>
        !_disposed && epoch == _accountEpoch && userId == id && mode == product;
    submittingOrder = true;
    lastError = null;
    notifyListeners();
    try {
      final cancelled = await api.cancelAlgoOrder(
        id,
        order.algoOrderId,
        productLine: order.product.productLine,
      );
      if (!current()) return;
      if (cancelled.userId != id ||
          cancelled.product != product ||
          cancelled.algoOrderId != order.algoOrderId ||
          cancelled.instrumentId != order.instrumentId ||
          cancelled.clientAlgoOrderId != order.clientAlgoOrderId ||
          !const [
            'CANCEL_REQUESTED',
            'CANCELED',
            'COMPLETED',
            'FAILED',
          ].contains(cancelled.status) ||
          (cancelled.status != 'CANCEL_REQUESTED' &&
              cancelled.activeQuantitySteps != 0)) {
        throw const FormatException('算法单撤销结果不匹配，请刷新原策略');
      }
      // A read started before this command may still contain the pre-cancel parent.
      ++_algoOrdersRequestVersion;
      loadingAlgoOrders = false;
      _upsertAlgoOrder(cancelled);
      lastNotice = cancelled.status == 'CANCEL_REQUESTED'
          ? '算法单取消中，请刷新确认子单状态 #${order.algoOrderId}'
          : cancelled.status == 'CANCELED'
          ? '算法单撤销已确认 #${order.algoOrderId}'
          : '算法单已结束（${cancelled.status}）#${order.algoOrderId}';
    } catch (error) {
      if (current()) {
        lastError = '算法单撤销结果未确认，请刷新原策略：${clientErrorMessage(error)}';
      }
    } finally {
      // The same account may change product while this command is in flight.
      if (!_disposed && epoch == _accountEpoch && userId == id) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  /// 一次原子 OCO 意图：先保存两腿身份，再发送一次；未知结果只查 realtime 回执。
  Future<int> placeOco(List<TriggerOrderDraft> drafts) async {
    if (!await _restoreBeforeCommand()) return 0;
    if (submittingTriggers || submittingOrder || tradingCommandPending) {
      return 0;
    }
    lastError = null;
    lastNotice = null;
    final instrument = selectedInstrument;
    final id = userId;
    final tp = drafts.where((d) => d.triggerType == 'TAKE_PROFIT').firstOrNull;
    final sl = drafts.where((d) => d.triggerType == 'STOP_LOSS').firstOrNull;
    if (id == null ||
        !instrument.mode.isDerivative ||
        !instrument.canPlaceTrigger() ||
        drafts.length != 2 ||
        tp == null ||
        sl == null ||
        !_validTriggerDraft(tp) ||
        !_validTriggerDraft(sl) ||
        tp.side != sl.side ||
        tp.marginMode != sl.marginMode ||
        tp.positionSide != sl.positionSide ||
        tp.quantitySteps != sl.quantitySteps ||
        tp.priceSource != sl.priceSource ||
        (tp.side == 'SELL'
            ? tp.triggerPriceTicks <= sl.triggerPriceTicks
            : tp.triggerPriceTicks >= sl.triggerPriceTicks)) {
      lastError = '请填写当前可交易合约的有效 TP/SL 双腿参数';
      notifyListeners();
      return 0;
    }
    final position = positions
        .where(
          (p) =>
              p.instrumentId == instrument.instrumentId &&
              p.marginMode == tp.marginMode &&
              p.positionSide == tp.positionSide &&
              p.signedQuantitySteps != 0,
        )
        .firstOrNull;
    if (position == null ||
        (position.signedQuantitySteps > 0 ? 'SELL' : 'BUY') != tp.side ||
        BigInt.from(tp.quantitySteps) >
            BigInt.from(position.signedQuantitySteps).abs()) {
      lastError = '止盈止损必须对应当前仓位，数量不能超过可平仓数量';
      notifyListeners();
      return 0;
    }
    final epoch = _accountEpoch;
    bool current() => !_disposed && epoch == _accountEpoch && userId == id;
    final random = math.Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final intent = PendingTradingOrder(
      userId: id,
      product: instrument.mode,
      instrumentId: instrument.instrumentId,
      ocoTakeProfitClientId: 'app-tp-$key',
      ocoStopLossClientId: 'app-sl-$key',
    );
    Map<String, dynamic> leg(TriggerOrderDraft draft, String clientId) => {
      'userId': id,
      'instrumentId': instrument.instrumentId,
      'clientTriggerOrderId': clientId,
      'ocoGroupId': 'app-oco-$key',
      'side': draft.side,
      'triggerType': draft.triggerType,
      'triggerPriceTicks': draft.triggerPriceTicks,
      'priceSource': draft.priceSource,
      'orderType': draft.orderType,
      'timeInForce': draft.orderType == 'MARKET' ? 'IOC' : 'GTC',
      'priceTicks': draft.orderType == 'MARKET' ? 0 : draft.priceTicks,
      'quantitySteps': draft.quantitySteps,
      'marginMode': draft.marginMode,
      'positionSide': draft.positionSide,
    };
    final requested = [
      leg(tp, intent.ocoTakeProfitClientId!),
      leg(sl, intent.ocoStopLossClientId!),
    ];
    var issued = false;
    submittingTriggers = true;
    submittingOrder = true;
    notifyListeners();
    try {
      _pendingTradingOrders[id] = intent;
      if (!await _writeSettings()) {
        _pendingTradingOrders.remove(id);
        if (current()) lastError = '无法保存 OCO 恢复资料，未发送委托';
        return 0;
      }
      if (!current()) {
        _pendingTradingOrders.remove(id);
        await _writeSettings();
        return 0;
      }
      issued = true;
      final result = await api.placeTriggerOrderBatch(
        id,
        requested,
        atomic: true,
        productLine: instrument.mode.productLine,
      );
      if (result.requested != 2 ||
          result.completed != 2 ||
          result.failed != 0 ||
          result.results.length != 2 ||
          result.results.map((r) => r.index).toSet().length != 2) {
        throw const FormatException('OCO 响应不完整');
      }
      for (final item in result.results) {
        if (!item.success ||
            item.index < 0 ||
            item.index > 1 ||
            item.order == null ||
            item.order!.userId != id ||
            item.order!.triggerOrderId <= 0 ||
            item.order!.clientTriggerOrderId !=
                requested[item.index]['clientTriggerOrderId'] ||
            ![
              'PENDING',
              'TRIGGERING',
              'TRIGGERED',
              'TRIGGER_FAILED',
              'CANCELED',
              'EXPIRED',
            ].contains(item.order!.status) ||
            item.order!.instrumentId != instrument.instrumentId ||
            item.order!.ocoGroupId != 'app-oco-$key') {
          throw const FormatException('OCO 响应身份不匹配');
        }
      }
      if (!await _clearTradingIntent(intent)) throw StateError('无法保存 OCO 确认结果');
      if (!current()) return 2;
      if (mode == instrument.mode && selectedSymbol == instrument.symbol) {
        for (final item in result.results) {
          _upsertTriggerOrder(item.order!);
        }
      }
      lastNotice = '止盈止损双腿已一起接受，一腿触发后另一腿撤销';
      await refreshPrivateData();
      return 2;
    } catch (error) {
      if (!issued) {
        if (_pendingTradingOrders[id] == intent) {
          _pendingTradingOrders.remove(id);
          await _writeSettings();
        }
        if (current()) lastError = 'OCO 未发送：${clientErrorMessage(error)}';
      } else if (isDefinitiveOrderRejection(error)) {
        await _clearTradingIntent(intent);
        if (current()) lastError = 'OCO 未接受：${clientErrorMessage(error)}';
      } else if (current()) {
        lastNotice = 'OCO 结果待确认，请查询原请求，勿重复提交';
      }
      return 0;
    } finally {
      if (current()) {
        submittingTriggers = false;
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  Future<int> placeTriggerOrders(List<TriggerOrderDraft> drafts) async {
    if (!await _restoreBeforeCommand()) return 0;
    if (submittingTriggers) return 0;
    lastError = null;
    lastNotice = null;
    final symbol = selectedSymbol;
    final instrument = selectedInstrument;
    final product = mode;
    final id = userId;
    final token = context().accessToken;
    final epoch = _accountEpoch;
    bool current() => userId == id && !_disposed && epoch == _accountEpoch;
    if (id == null) {
      lastError = '请先登录再提交止盈止损';
      notifyListeners();
      return 0;
    }
    if (!instrument.canPlaceTrigger() ||
        tradingCommandPending ||
        submittingOrder) {
      lastError = '合约不可交易或存在待确认委托';
      notifyListeners();
      return 0;
    }
    final validDrafts = drafts.where(_validTriggerDraft).toList();
    if (validDrafts.isEmpty || validDrafts.length != drafts.length) {
      lastError = '请先填写有效的触发价和数量';
      notifyListeners();
      return 0;
    }
    for (final draft in validDrafts) {
      final position = positions
          .where(
            (p) =>
                (instrument.mode.tracksTriggerIntent
                    ? p.instrumentId == instrument.instrumentId
                    : p.symbol == symbol) &&
                p.marginMode == draft.marginMode &&
                p.positionSide == draft.positionSide &&
                p.signedQuantitySteps != 0,
          )
          .firstOrNull;
      if (position == null ||
          (position.signedQuantitySteps > 0 ? 'SELL' : 'BUY') != draft.side ||
          BigInt.from(draft.quantitySteps) >
              BigInt.from(position.signedQuantitySteps).abs()) {
        lastError = '止盈止损必须对应当前仓位，数量不能超过可平仓数量';
        notifyListeners();
        return 0;
      }
    }
    final created = <TriggerOrderModel>[];
    submittingTriggers = true;
    if (instrument.mode.tracksTriggerIntent) submittingOrder = true;
    notifyListeners();
    try {
      for (final draft in validDrafts) {
        if (!current()) {
          throw StateError('登录状态已变化，已停止后续提交');
        }
        created.add(
          instrument.mode.tracksTriggerIntent
              ? await _placeTrackedTrigger(id, instrument, draft, current)
              : await api.placeTriggerOrder(
                  userId: id,
                  instrumentId: instrument.instrumentId,
                  side: draft.side,
                  triggerType: draft.triggerType,
                  triggerPriceTicks: draft.triggerPriceTicks,
                  activationPriceTicks: draft.activationPriceTicks,
                  callbackRatePpm: draft.callbackRatePpm,
                  priceSource: draft.priceSource,
                  orderType: draft.orderType,
                  priceTicks: draft.priceTicks,
                  quantitySteps: draft.quantitySteps,
                  marginMode: draft.marginMode,
                  positionSide: draft.positionSide,
                  productLine: product.productLine,
                ),
        );
        if (userId == id &&
            context().accessToken == token &&
            mode == product &&
            selectedSymbol == symbol) {
          _upsertTriggerOrder(created.last);
          notifyListeners();
        }
      }
      if (current()) {
        lastNotice = '止盈止损已提交 ${created.length} 档';
        await refreshPrivateData();
      }
    } catch (error) {
      if (current()) {
        if (instrument.mode.tracksTriggerIntent && tradingCommandPending) {
          lastNotice = '已确认 ${created.length} 档；当前档结果待确认，其余未发送，请查询原请求';
        } else {
          lastError =
              '已提交 ${created.length} 档，其余未发送：${clientErrorMessage(error)}';
        }
        await refreshPrivateData();
      }
    } finally {
      if (current()) {
        submittingTriggers = false;
        if (instrument.mode.tracksTriggerIntent) submittingOrder = false;
      }
    }
    notifyListeners();
    return created.length;
  }

  Future<bool> _clearTradingIntent(PendingTradingOrder intent) =>
      _writeSettings(completedTradingIntent: intent);

  Future<TriggerOrderModel> _placeTrackedTrigger(
    int id,
    Instrument instrument,
    TriggerOrderDraft draft,
    bool Function() current,
  ) async {
    final random = math.Random.secure();
    final key = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final intent = PendingTradingOrder(
      userId: id,
      product: instrument.mode,
      instrumentId: instrument.instrumentId,
      clientTriggerOrderId: 'app-trigger-$key',
    );
    var issued = false;
    _pendingTradingOrders[id] = intent;
    try {
      if (!await _writeSettings()) throw StateError('无法保存条件单恢复资料，未发送委托');
      if (!current()) throw StateError('账户已变化，未发送委托');
      issued = true;
      final order = await api.placeTriggerOrder(
        userId: id,
        instrumentId: instrument.instrumentId,
        clientTriggerOrderId: intent.clientTriggerOrderId,
        side: draft.side,
        triggerType: draft.triggerType,
        triggerPriceTicks: draft.triggerPriceTicks,
        quantitySteps: draft.quantitySteps,
        marginMode: draft.marginMode,
        positionSide: draft.positionSide,
        activationPriceTicks: draft.activationPriceTicks,
        callbackRatePpm: draft.callbackRatePpm,
        priceSource: draft.priceSource,
        orderType: draft.orderType,
        priceTicks: draft.priceTicks,
        productLine: instrument.mode.productLine,
      );
      if (order.userId != id ||
          order.triggerOrderId <= 0 ||
          order.instrumentId != intent.instrumentId ||
          order.clientTriggerOrderId != intent.clientTriggerOrderId ||
          order.side != draft.side ||
          order.triggerType != draft.triggerType ||
          order.quantitySteps != draft.quantitySteps ||
          ![
            'PENDING',
            'TRIGGERING',
            'TRIGGERED',
            'TRIGGER_FAILED',
            'CANCELED',
            'EXPIRED',
          ].contains(order.status)) {
        throw const FormatException('条件单响应身份或状态不匹配');
      }
      if (!await _clearTradingIntent(intent)) throw StateError('无法保存条件单确认结果');
      return order;
    } catch (error) {
      if (!issued) {
        if (identical(_pendingTradingOrders[id], intent)) {
          _pendingTradingOrders.remove(id);
          await _writeSettings();
        }
      } else if (isDefinitiveOrderRejection(error)) {
        await _clearTradingIntent(intent);
      }
      rethrow;
    }
  }

  bool _validTriggerDraft(TriggerOrderDraft draft) {
    if (!['MARK', 'LAST', 'INDEX'].contains(draft.priceSource) ||
        !['MARKET', 'LIMIT'].contains(draft.orderType) ||
        (draft.orderType == 'LIMIT' && draft.priceTicks <= 0)) {
      return false;
    }
    if (![
          'TAKE_PROFIT',
          'STOP_LOSS',
          'TRAILING_STOP',
        ].contains(draft.triggerType) ||
        draft.quantitySteps <= 0) {
      return false;
    }
    if (draft.triggerType == 'TRAILING_STOP') {
      if (draft.orderType != 'MARKET') return false;
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
    if (!await _restoreBeforeCommand()) return;
    final id = userId;
    if (id == null) return;
    final product = mode;
    if (product.tracksTriggerIntent) {
      await _cancelTrackedTrigger(id, order);
      return;
    }
    final token = context().accessToken;
    try {
      final cancelled = await api.cancelTriggerOrder(
        id,
        order.triggerOrderId,
        productLine: product.productLine,
      );
      if (mode == product &&
          selectedSymbol == order.symbol &&
          context().accessToken == token &&
          userId == id) {
        _upsertTriggerOrder(cancelled);
      }
      lastNotice = '条件单撤销已提交 #${order.triggerOrderId}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '撤销条件单失败：${clientErrorMessage(error)}';
    }
    notifyListeners();
  }

  Future<void> _cancelTrackedTrigger(int id, TriggerOrderModel order) async {
    if (submittingOrder ||
        submittingTriggers ||
        tradingCommandPending ||
        order.triggerOrderId <= 0 ||
        order.instrumentId.isEmpty) {
      return;
    }
    final product = mode;
    final epoch = _accountEpoch;
    bool current() => userId == id && !_disposed && epoch == _accountEpoch;
    final intent = PendingTradingOrder(
      userId: id,
      product: product,
      instrumentId: order.instrumentId,
      cancelTriggerOrderId: order.triggerOrderId,
    );
    var issued = false;
    submittingOrder = true;
    lastError = null;
    lastNotice = null;
    _pendingTradingOrders[id] = intent;
    notifyListeners();
    try {
      if (!await _writeSettings()) throw StateError('无法保存撤销恢复资料，未发送请求');
      if (!current()) throw StateError('账户已变化，未发送请求');
      issued = true;
      final cancelled = await api.cancelTriggerOrder(
        id,
        order.triggerOrderId,
        productLine: product.productLine,
      );
      if (cancelled.userId != id ||
          cancelled.triggerOrderId != order.triggerOrderId ||
          cancelled.instrumentId != order.instrumentId ||
          cancelled.status != 'CANCELED') {
        throw const FormatException('条件单撤销响应不匹配');
      }
      if (!await _clearTradingIntent(intent)) throw StateError('无法保存撤销确认结果');
      if (current()) {
        if (mode == product) _upsertTriggerOrder(cancelled);
        lastNotice = '条件单撤销已确认 #${order.triggerOrderId}';
        await refreshPrivateData();
      }
    } catch (error) {
      if (!issued) {
        if (identical(_pendingTradingOrders[id], intent)) {
          _pendingTradingOrders.remove(id);
          await _writeSettings();
        }
      } else if (isDefinitiveOrderRejection(error)) {
        await _clearTradingIntent(intent);
      }
      if (current()) {
        if (tradingCommandPending) {
          lastNotice = '条件单撤销结果待确认，请查询原请求，勿重复撤销';
        } else {
          lastError = '撤销条件单未接受：${clientErrorMessage(error)}';
        }
      }
    } finally {
      if (current()) {
        submittingOrder = false;
        notifyListeners();
      }
    }
  }

  void _upsertOrder(OrderModel order) {
    final mutable = [...openOrders];
    final index = mutable.indexWhere((item) => item.orderId == order.orderId);
    if (index >= 0) {
      if (!_isOpenOrder(order)) {
        mutable.removeAt(index);
      } else {
        mutable[index] = order;
      }
    } else if (_isOpenOrder(order)) {
      mutable.insert(0, order);
    }
    openOrders = mutable;
  }

  void _upsertAlgoOrder(AlgoOrderModel order) {
    if (order.userId != userId || order.product != mode) return;
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
    _disposed = true;
    invalidateQueries();
    super.dispose();
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

bool _isOpenTriggerStatus(String status) {
  return status == 'PENDING' || status == 'TRIGGERING';
}

bool _isOpenOrder(OrderModel order) {
  return order.remainingQuantitySteps > 0 &&
      (order.status == 'ACCEPTED' || order.status == 'PARTIALLY_FILLED');
}

bool _isOpenAlgoStatus(String status) {
  return status == 'PENDING' ||
      status == 'RUNNING' ||
      status == 'CANCEL_REQUESTED';
}

String? _pendingText(Object? value, String field, {int maxLength = 128}) {
  if (value == null) return null;
  if (value is! String || value.trim().isEmpty || value.length > maxLength) {
    throw FormatException('委托恢复字段 $field 无效');
  }
  return value;
}

int? _pendingId(Object? value, String field) {
  if (value == null) return null;
  final parsed = requireInt64(value, field);
  if (parsed <= 0) throw FormatException('委托恢复字段 $field 无效');
  return parsed;
}

PendingTradingOrder _pendingFromJson(Map<String, dynamic> value) {
  final id = _pendingId(value['userId'], 'userId');
  final product = ProductMode.values
      .where((p) => p.productLine == value['productLine'])
      .firstOrNull;
  if (id == null || product == null) {
    throw const FormatException('委托恢复账户或产品线无效');
  }
  final commandId = _pendingText(value['commandId'], 'commandId');
  final clientOrderId = _pendingText(
    value['clientOrderId'],
    'clientOrderId',
    maxLength: 64,
  );
  final instrumentId = _pendingText(value['instrumentId'], 'instrumentId');
  final cancelOrderId = _pendingId(value['cancelOrderId'], 'cancelOrderId');
  final amendRequestId = _pendingText(
    value['amendRequestId'],
    'amendRequestId',
    maxLength: 64,
  );
  final amendOrderId = _pendingId(value['amendOrderId'], 'amendOrderId');
  final tp = _pendingText(
    value['ocoTakeProfitClientId'],
    'ocoTakeProfitClientId',
    maxLength: 64,
  );
  final sl = _pendingText(
    value['ocoStopLossClientId'],
    'ocoStopLossClientId',
    maxLength: 64,
  );
  final triggerId = _pendingText(
    value['clientTriggerOrderId'],
    'clientTriggerOrderId',
    maxLength: 64,
  );
  final cancelTriggerId = _pendingId(
    value['cancelTriggerOrderId'],
    'cancelTriggerOrderId',
  );
  final algoId = _pendingText(
    value['clientAlgoOrderId'],
    'clientAlgoOrderId',
    maxLength: 64,
  );
  final rawPlan = value['cancelPlan'];
  final plan = rawPlan == null ? null : _pendingCancellation(rawPlan);
  final amendment = amendRequestId != null || amendOrderId != null;
  final oco = tp != null || sl != null;
  final kinds = [
    plan != null,
    algoId != null,
    triggerId != null,
    cancelTriggerId != null,
    oco,
    amendment,
    cancelOrderId != null,
    clientOrderId != null && !amendment,
  ].where((present) => present).length;
  if (kinds > 1 ||
      (kinds == 0 && commandId == null) ||
      (plan != null &&
          (!product.isSpot ||
              (instrumentId != null &&
                  plan.instrumentId != null &&
                  instrumentId != plan.instrumentId))) ||
      (algoId != null && instrumentId == null) ||
      (triggerId != null && (!product.isDerivative || instrumentId == null)) ||
      (cancelTriggerId != null && instrumentId == null) ||
      (oco &&
          (!product.isDerivative ||
              instrumentId == null ||
              tp == null ||
              sl == null ||
              tp == sl)) ||
      (amendment &&
          (!product.isSpot ||
              amendRequestId == null ||
              amendOrderId == null ||
              clientOrderId == null ||
              instrumentId == null)) ||
      (clientOrderId != null && instrumentId == null)) {
    throw const FormatException('委托恢复意图组合无效');
  }
  return PendingTradingOrder(
    userId: id,
    product: product,
    commandId: commandId,
    clientOrderId: clientOrderId,
    instrumentId: instrumentId,
    cancelOrderId: cancelOrderId,
    amendRequestId: amendRequestId,
    amendOrderId: amendOrderId,
    cancelPlan: plan,
    ocoTakeProfitClientId: tp,
    ocoStopLossClientId: sl,
    clientTriggerOrderId: triggerId,
    cancelTriggerOrderId: cancelTriggerId,
    clientAlgoOrderId: algoId,
  );
}

CancellationPlan _pendingCancellation(Object raw) {
  if (raw is! Map<String, dynamic> ||
      raw['batches'] is! List ||
      raw['failures'] is! List ||
      raw['issued'] is! bool) {
    throw const FormatException('批量撤单恢复资料无效');
  }
  final planId = _pendingText(raw['id'], 'cancelPlan.id');
  if (planId == null) throw const FormatException('批量撤单恢复身份无效');
  final batches = <CancellationBatch>[];
  for (final batch in raw['batches'] as List) {
    if (batch is! Map<String, dynamic> || batch['orderIds'] is! List) {
      throw const FormatException('批量撤单恢复批次无效');
    }
    final key = _pendingText(batch['key'], 'batch.key', maxLength: 64);
    if (key == null) throw const FormatException('批量撤单恢复批次身份无效');
    final ids = (batch['orderIds'] as List).map((value) {
      final id = _pendingId(value, 'batch.orderId');
      if (id == null) throw const FormatException('批量撤单恢复订单身份无效');
      return id;
    }).toList();
    batches.add(CancellationBatch(key, ids));
  }
  int count(String key) {
    final parsed = requireInt64(raw[key], 'cancelPlan.$key');
    if (parsed < 0) throw const FormatException('批量撤单恢复计数无效');
    return parsed;
  }

  final failures = <({int orderId, String code})>[];
  for (final failure in raw['failures'] as List) {
    if (failure is! Map<String, dynamic>) {
      throw const FormatException('批量撤单恢复失败记录无效');
    }
    final id = _pendingId(failure['orderId'], 'failure.orderId');
    final code = _pendingText(failure['code'], 'failure.code');
    if (id == null || code == null) throw const FormatException('批量撤单恢复失败身份无效');
    failures.add((orderId: id, code: code));
  }
  return CancellationPlan(
    id: planId,
    batches: batches,
    index: count('index'),
    completed: count('completed'),
    failed: count('failed'),
    issued: raw['issued'] as bool,
    failures: failures,
    instrumentId: _pendingText(raw['instrumentId'], 'cancelPlan.instrumentId'),
  );
}
