import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'market_data_state.dart';
import 'account_projection.dart';
import 'trading/trading_order_state.dart';
import 'option_market.dart';
import 'realtime_state.dart';
import 'private_snapshot_recovery.dart';
import 'session_store.dart';
import 'telegram_login.dart';
import 'auth/auth_state.dart';
import 'pending_transfer.dart';
import 'wallet/account_transfer_state.dart';
import 'wallet/wallet_state.dart';

export 'wallet/wallet_state.dart'
    show WithdrawalAssetRule, WithdrawalConfirmation;
import 'portfolio_income.dart';
import 'portfolio_income_state.dart';

typedef _AccountRiskScope = ({
  int? userId,
  int epoch,
  String? token,
  ProductMode product,
  String asset,
});

class AppState extends ChangeNotifier {
  AppState({
    this.config = const AppConfig(),
    ApiClient? apiClient,
    AuthSession? initialSession,
    RealtimeClient? realtimeClient,
    SessionStore? sessionStore,
    TelegramLoginStore? telegramLoginStore,
    ClientSettingsStore? settingsStore,
    this.offline = false,
    this.seedInstruments,
  }) : api = apiClient ?? ApiClient(config),
       realtime = realtimeClient ?? RealtimeClient(config) {
    this.settingsStore = settingsStore ?? SecureClientSettingsStore();
    auth = AuthState(
      api: api,
      initialSession: initialSession,
      sessionStore: sessionStore ?? SecureSessionStore(),
      telegramLoginStore: telegramLoginStore ?? TelegramLoginStore(),
      offline: offline,
      onSessionChanged: _authSessionChanged,
      onSessionReady: _authSessionReady,
      onFeedback: (error, notice) {
        lastError = error;
        lastNotice = notice;
      },
    )..addListener(notifyListeners);
    if (apiClient == null) api.deviceIdLoader = _persistentDeviceId;
    final initialInstruments = offline
        ? fallbackInstruments()
        : seedInstruments ?? const <Instrument>[];
    instruments = initialInstruments;
    api.instrumentCatalog = initialInstruments;
    selectedSymbol = initialInstruments.isNotEmpty
        ? initialInstruments.first.symbol
        : '';
    orderBook = offline
        ? fallbackOrderBook(initialInstruments.first)
        : OrderBook.empty(selectedSymbol);
    candles = offline ? fallbackCandles() : const [];
    if (initialSession != null) {
      _authSessionChanged(null, initialSession, AuthSessionChange.signedIn);
    }
    market.requestDepthSnapshot = _requestDepthSnapshot;
    market.reconnectDepth = () => _scheduleRealtimeReconnect();
    market.onDepthUnavailable = _scheduleRealtimeNotify;
    market.onIssue = (message) {
      _recordRealtimeIssue(message);
      _scheduleRealtimeReconnect();
    };
  }

  final AppConfig config;
  final ApiClient api;
  final RealtimeClient realtime;
  late final AuthState auth;
  SessionStore get sessionStore => auth.sessionStore;
  TelegramLoginStore get telegramLoginStore => auth.telegramLoginStore;
  late final ClientSettingsStore settingsStore;
  final bool offline;
  final List<Instrument>? seedInstruments;

  AuthSession? get session => auth.current;
  LoginChallenge? get pendingLoginChallenge => auth.pendingLoginChallenge;
  set pendingLoginChallenge(LoginChallenge? value) =>
      auth.pendingLoginChallenge = value;
  List<Map<String, dynamic>> get recentTrades => market.recentTrades;
  set recentTrades(List<Map<String, dynamic>> values) =>
      market.recentTrades = values;
  late final TradingOrderState orders = TradingOrderState(
    api: api,
    settingsStore: settingsStore,
    offline: offline,
    context: () => (
      userId: userId,
      accessToken: session?.accessToken,
      epoch: _accountEpoch,
      selection: _selectionVersion,
      product: mode,
      symbol: selectedSymbol,
      instrument: selectedInstrument,
      positionMode: positionMode,
      positions: positions,
      instruments: instruments,
      onlyCurrentPair: onlyCurrentTradingPair,
      disabledProducts: disabledProducts,
    ),
    persist: ({PendingTradingOrder? completedTradingIntent}) =>
        _writeSettings(completedTradingIntent: completedTradingIntent),
    refreshPrivateData: refreshPrivateData,
    onFeedback: (error, notice) {
      lastError = error;
      lastNotice = notice;
    },
  )..addListener(notifyListeners);

  bool get submittingOrder => orders.submittingOrder;
  set submittingOrder(bool value) => orders.submittingOrder = value;
  CancellationSummary? get lastCancellationResult =>
      orders.lastCancellationResult;
  set lastCancellationResult(CancellationSummary? value) =>
      orders.lastCancellationResult = value;
  PendingTradingOrder? get pendingTradingCommand =>
      orders.pendingTradingCommand;
  bool get tradingCommandPending => orders.tradingCommandPending;
  Future<void> _settingsWriteTail = Future<void>.value();

  bool get submittingTriggers => orders.submittingTriggers;
  set submittingTriggers(bool value) => orders.submittingTriggers = value;
  int _selectionVersion = 0;
  int _instrumentRequestVersion = 0;
  AuthSession? get pendingVerificationSession =>
      auth.pendingVerificationSession;
  set pendingVerificationSession(AuthSession? value) =>
      auth.pendingVerificationSession = value;
  AuthSession? get pendingBiometricSession => auth.pendingBiometricSession;
  set pendingBiometricSession(AuthSession? value) =>
      auth.pendingBiometricSession = value;
  bool get biometricLoginAvailable => auth.biometricLoginAvailable;
  set biometricLoginAvailable(bool value) =>
      auth.biometricLoginAvailable = value;
  bool get biometricLoginEnabled => auth.biometricLoginEnabled;
  set biometricLoginEnabled(bool value) => auth.biometricLoginEnabled = value;
  bool get biometricLoginUpdating => auth.biometricLoginUpdating;
  set biometricLoginUpdating(bool value) => auth.biometricLoginUpdating = value;
  bool get biometricSessionLocked => auth.biometricSessionLocked;
  set biometricSessionLocked(bool value) => auth.biometricSessionLocked = value;
  bool get biometricUnlocking => auth.biometricUnlocking;
  set biometricUnlocking(bool value) => auth.biometricUnlocking = value;
  String? get biometricUnlockError => auth.biometricUnlockError;
  set biometricUnlockError(String? value) => auth.biometricUnlockError = value;
  bool get requiresBiometricUnlock => auth.requiresBiometricUnlock;
  bool get canUnlockBiometricSession => auth.canUnlockBiometricSession;
  void updateBiometricAppVisibility({
    required bool foreground,
    bool lockSession = false,
  }) => auth.updateBiometricAppVisibility(
    foreground: foreground,
    lockSession: lockSession,
  );

  late List<Instrument> instruments;
  late String selectedSymbol;
  ProductMode mode = ProductMode.linear;
  String period = '1m';
  final MarketDataState market = MarketDataState();
  OrderBook get orderBook => market.orderBook;
  set orderBook(OrderBook book) => market.resetBook(book);
  List<Candle> get candles => market.candles;
  set candles(List<Candle> values) => market.candles = values;
  List<ProductBalance> balances = const [];
  ({int takerFeeRatePpm, int marketMaxSlippagePpm})? _orderTerms;
  String? _orderTermsIdentity;
  int _orderTermsRequest = 0;
  String get _currentOrderTermsIdentity =>
      '$_accountEpoch:$userId:${mode.productLine}:${selectedInstrument.instrumentId}:${selectedInstrument.changeId}';
  ({int takerFeeRatePpm, int marketMaxSlippagePpm})? get spotOrderTerms =>
      mode.isSpot && _orderTermsIdentity == _currentOrderTermsIdentity
      ? _orderTerms
      : null;

  ({int takerFeeRatePpm, int marketMaxSlippagePpm})? get optionOrderTerms =>
      mode.isOption && _orderTermsIdentity == _currentOrderTermsIdentity
      ? _orderTerms
      : null;

  Future<void> refreshOrderTerms() async {
    final request = ++_orderTermsRequest;
    final identity = _currentOrderTermsIdentity;
    final id = userId;
    _orderTerms = null;
    _orderTermsIdentity = null;
    if (offline ||
        id == null ||
        !(mode.isSpot || mode.isOption) ||
        selectedInstrument.instrumentId.isEmpty) {
      return;
    }
    try {
      final terms = mode.isOption
          ? await api.optionOrderTerms(id, selectedInstrument)
          : await api.spotOrderTerms(id, selectedInstrument);
      if (request == _orderTermsRequest &&
          identity == _currentOrderTermsIdentity) {
        _orderTerms = terms;
        _orderTermsIdentity = identity;
      }
    } catch (_) {
      // Missing sizing metadata disables percentage controls; no default fees are invented.
    } finally {
      if (request == _orderTermsRequest) notifyListeners();
    }
  }

  OptionReference? _optionReference;
  bool _loadingOptionReference = false;
  int _optionReferenceRequest = 0;
  Timer? _optionReferenceTimer;
  OptionReference? get optionReference =>
      _optionReference?.matches(selectedInstrument) == true
      ? _optionReference
      : null;

  void _scheduleOptionReference() {
    _optionReferenceTimer?.cancel();
    _optionReferenceTimer = !offline && mode.isOption
        ? Timer.periodic(const Duration(seconds: 1), (timer) {
            if (_optionReference != null && optionReference == null) {
              _optionReference = null;
              notifyListeners();
            }
            if (timer.tick.isEven) unawaited(refreshOptionReference());
          })
        : null;
  }

  Future<void> refreshOptionReference() async {
    if (offline || !mode.isOption || _loadingOptionReference) return;
    final instrument = selectedInstrument;
    if (!canQueryOptionReference(instrument)) {
      _optionReference = null;
      notifyListeners();
      return;
    }
    final request = ++_optionReferenceRequest;
    final selection = _selectionVersion;
    _loadingOptionReference = true;
    try {
      final quote = await api.optionReference(instrument);
      if (request == _optionReferenceRequest &&
          selection == _selectionVersion &&
          quote.matches(selectedInstrument)) {
        _optionReference = quote;
      }
    } catch (_) {
      if (request == _optionReferenceRequest &&
          selection == _selectionVersion) {
        _optionReference = null;
      }
    } finally {
      _loadingOptionReference = false;
      if (request == _optionReferenceRequest &&
          selection == _selectionVersion) {
        notifyListeners();
      }
    }
  }

  List<Position> positions = const [];
  List<OrderModel> get openOrders => orders.openOrders;
  set openOrders(List<OrderModel> values) => orders.openOrders = values;
  String? get openOrdersNextCursor => orders.openOrdersNextCursor;
  set openOrdersNextCursor(String? value) =>
      orders.openOrdersNextCursor = value;
  bool get openOrdersHasMore => orders.openOrdersHasMore;
  set openOrdersHasMore(bool value) => orders.openOrdersHasMore = value;
  bool get loadingMoreOpenOrders => orders.loadingMoreOpenOrders;
  set loadingMoreOpenOrders(bool value) => orders.loadingMoreOpenOrders = value;
  List<AlgoOrderModel> get openAlgoOrders => orders.openAlgoOrders;
  set openAlgoOrders(List<AlgoOrderModel> values) =>
      orders.openAlgoOrders = values;
  bool get loadingAlgoOrders => orders.loadingAlgoOrders;
  String? get algoOrdersError => orders.algoOrdersError;
  List<TriggerOrderModel> get openTriggerOrders => orders.openTriggerOrders;
  set openTriggerOrders(List<TriggerOrderModel> values) =>
      orders.openTriggerOrders = values;
  Instrument? algoInstrumentFor(AlgoOrderModel order) =>
      orders.algoInstrumentFor(order);
  List<AlgoOrderModel> get visibleAlgoOrders => orders.visibleAlgoOrders;
  void _resetAlgoOrders() => orders.resetAlgoOrders();
  String positionMode = 'ONE_WAY';
  List<PositionRisk> positionRisks = const [];
  List<LiquidationOrder> liquidationOrders = const [];
  late final WalletState wallet = WalletState(
    api: api,
    offline: offline,
    owner: () => (
      userId: userId,
      epoch: _accountEpoch,
      accessToken: session?.accessToken,
    ),
    market: market,
    catalog: () => instruments,
    heldAssets: () => allProductBalances
        .where((balance) => balance.equityUnits != 0)
        .map((balance) => balance.asset),
    settingsStore: settingsStore,
    persist: ({PendingWithdrawal? completed}) =>
        _writeSettings(completedWithdrawalIntent: completed),
    onChanged: () {
      lastError = wallet.error;
      lastNotice = wallet.notice;
      notifyListeners();
    },
  );
  WalletPortfolio get walletPortfolio => wallet.portfolio;
  set walletPortfolio(WalletPortfolio value) => wallet.portfolio = value;
  bool get walletReady => wallet.ready;
  set walletReady(bool value) => wallet.ready = value;
  String? get walletError => wallet.loadError;
  set walletError(String? value) => wallet.loadError = value;
  String? get walletOrdersError => wallet.ordersError;
  set walletOrdersError(String? value) => wallet.ordersError = value;
  int _accountEpoch = 0;
  int _valuationVersion = 0;
  final Set<ProductMode> valuedProducts = {};
  List<WalletOrderRecord> get walletOrders => wallet.orders;
  set walletOrders(List<WalletOrderRecord> values) => wallet.orders = values;
  WalletDepositAddress? get walletDepositAddress => wallet.depositAddress;
  set walletDepositAddress(WalletDepositAddress? value) =>
      wallet.depositAddress = value;
  AccountRisk? _accountRisk;
  _AccountRiskScope? _loadedAccountRiskScope, _riskRequestScope;
  Stopwatch? _accountRiskElapsed;
  bool loadingAccountRisk = false;
  String? accountRiskError;
  _AccountRiskScope get _currentAccountRiskScope => (
    userId: userId,
    epoch: _accountEpoch,
    token: session?.accessToken,
    product: mode,
    asset: selectedInstrument.settleAsset,
  );
  bool get _canReadAccountRisk =>
      !offline &&
      isLoggedIn &&
      mode.isDerivative &&
      !disabledProducts.contains(mode) &&
      selectedInstrument.settleAsset.isNotEmpty &&
      _privateAuthenticated &&
      privateViews[mode]?.ready == true;
  AccountRisk? get accountRisk =>
      _canReadAccountRisk &&
          _loadedAccountRiskScope == _currentAccountRiskScope &&
          (_accountRiskElapsed?.elapsed ?? const Duration(seconds: 15)) <
              const Duration(seconds: 15)
      ? _accountRisk
      : null;
  void _clearAccountRisk() {
    _accountRisk = null;
    _loadedAccountRiskScope = null;
    _accountRiskElapsed?.stop();
    _accountRiskElapsed = null;
    loadingAccountRisk = false;
    accountRiskError = null;
  }

  Map<String, double> get latestPrices => market.latestPrices;
  Map<String, int> get markPrices => market.markPrices;
  Map<String, Map<String, dynamic>> get marketMetrics => market.metrics;
  final Map<ProductMode, PrivateView> privateViews = {};
  final Map<ProductMode, List<ProductBalance>> productBalances = {};
  Map<String, String> _balanceScales = {};
  int _balanceScalesVersion = 0;
  bool assetsReady = false;
  bool onlyCurrentTradingPair = true;
  final Map<String, int> positionPnlUnits = {};
  List<PositionRisk> queriedPositionRisks = [];
  int _riskDetailsVersion = 0;
  Timer? _riskDetailsTimer;
  String _riskInputKey = '';

  int? markTicksFor(Instrument instrument) =>
      markPrices[_priceKey(instrument.mode, instrument.symbol)];
  int? unrealizedPnlFor(Position position) =>
      positionPnlUnits['${mode.productLine}:${position.symbol}:${position.positionSide}'];
  List<OrderModel> get recentOrderUpdates =>
      (privateViews[mode]?.orderUpdates ?? [])
          .where(
            (row) => !onlyCurrentTradingPair || row['symbol'] == selectedSymbol,
          )
          .map(OrderModel.fromJson)
          .toList();
  void leverageUpdated() {
    lastNotice = '杠杆已更新，账户数据以最新推送为准';
    notifyListeners();
  }

  void setTradingPairFilter(bool enabled) {
    if (onlyCurrentTradingPair == enabled) return;
    onlyCurrentTradingPair = enabled;
    _resetAlgoOrders();
    _materializePrivate();
    notifyListeners();
    unawaited(refreshAlgoOrders());
  }

  Future<void> refreshRiskDetails() async {
    final scope = _currentAccountRiskScope;
    if (!_canReadAccountRisk) {
      _clearAccountRisk();
      return;
    }
    if (loadingAccountRisk && _riskRequestScope == scope) return;
    final request = ++_riskDetailsVersion;
    _riskRequestScope = scope;
    _riskDetailsTimer?.cancel();
    loadingAccountRisk = true;
    accountRiskError = null;
    bool current() =>
        !_disposed &&
        request == _riskDetailsVersion &&
        scope == _currentAccountRiskScope &&
        _canReadAccountRisk;
    notifyListeners();
    try {
      final results = await Future.wait<Object?>([
        api.accountRisk(
          scope.userId!,
          scope.asset,
          accountType: scope.product.accountType,
          productLine: scope.product.productLine,
        ),
        positions.isEmpty
            ? Future<List<PositionRisk>>.value(const [])
            : api.positionRisks(
                scope.userId!,
                productLine: scope.product.productLine,
              ),
      ]);
      if (!current()) return;
      final risk = results[0] as AccountRisk?;
      if (risk != null && risk.settleAsset != scope.asset) {
        throw const FormatException('账户风险结算资产不匹配');
      }
      _accountRisk = risk;
      _loadedAccountRiskScope = scope;
      _accountRiskElapsed?.stop();
      _accountRiskElapsed = risk == null ? null : (Stopwatch()..start());
      accountRiskError = risk == null ? '账户风险暂不可用，请刷新重试' : null;
      queriedPositionRisks = results[1] as List<PositionRisk>;
    } catch (_) {
      if (!current()) return;
      _accountRisk = null;
      accountRiskError = '账户风险暂不可用，请刷新重试';
    } finally {
      if (request == _riskDetailsVersion) {
        loadingAccountRisk = false;
        if (current()) {
          if (_realtimeConnected) {
            _riskDetailsTimer = Timer(
              const Duration(seconds: 5),
              () => unawaited(refreshRiskDetails()),
            );
          }
          notifyListeners();
        }
      }
    }
  }

  late final PrivateSnapshotRecovery _privateRecovery = PrivateSnapshotRecovery(
    ready: (product) => privateViews[product]?.ready == true,
    resubscribe: (product) {
      for (final subscription in _privateSubscriptions.values) {
        if (subscription['productLine'] == product.productLine &&
            subscription['channel'] == 'accountState') {
          realtime.resubscribe(subscription);
        }
      }
    },
    reconnect: () => _scheduleRealtimeReconnect(),
  );
  bool _privateAuthenticated = false;
  Timer? _freshnessTimer;
  Timer? _announcementRefreshTimer;
  int _publicRequestVersion = 0;
  String _priceKey(ProductMode product, String symbol) =>
      '${product.productLine}:$symbol';
  List<ProductBalance> get allProductBalances =>
      productBalances.values.expand((v) => v).toList();
  List<Instrument> get spotInstruments =>
      instruments.where((i) => i.isSpot).toList();
  Map<String, double> get walletAssetPricesUsdt => wallet.pricesUsdt;
  ValuationCurrency valuationCurrency = ValuationCurrency.usdt;
  final Map<ValuationCurrency, double> valuationRates = {
    ValuationCurrency.usdt: 1,
  };
  ClientTheme clientTheme = ClientTheme.dark;
  ClientLanguage language = ClientLanguage.zhHans;
  final ValueNotifier<(ClientTheme, ClientLanguage)> presentation =
      ValueNotifier((ClientTheme.dark, ClientLanguage.zhHans));
  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  void _updatePresentation() {
    if (!_disposed) presentation.value = (clientTheme, language);
  }

  List<Map<String, dynamic>> announcements = const [];
  List<Map<String, dynamic>> announcementBanners = const [];
  List<Map<String, dynamic>> announcementModals = const [];
  int unreadAnnouncementCount = 0;
  int announcementOffset = 0;
  bool announcementsHasMore = false;
  String? announcementError;
  bool announcementsLoading = false;
  bool valuationLoading = false;
  bool loadingPublic = false;
  bool _loadingPrivate = false;
  bool get loadingPrivate => _loadingPrivate || auth.loading;
  set loadingPrivate(bool value) => _loadingPrivate = value;
  int _privateDataRequestVersion = 0;
  late final AccountTransferState transfers = AccountTransferState(
    api: api,
    settingsStore: settingsStore,
    owner: () => (userId: userId, epoch: _accountEpoch),
    persist: ({PendingAccountTransfer? completed}) =>
        _writeSettings(completedTransferIntent: completed),
    refreshAssets: refreshPrivateData,
    onChanged: () {
      lastError = transfers.error;
      lastNotice = transfers.notice;
      notifyListeners();
    },
  );
  PendingAccountTransfer? get pendingTransfer => transfers.pending;
  bool get transferSubmitting => transfers.submitting;
  bool get transferOutcomeLocked => transfers.outcomeLocked;
  bool get transferOutcomeTerminalFailure => transfers.terminalFailure;
  bool get transferVerificationRequired => transfers.verificationRequired;
  bool get withdrawalSubmitting => wallet.withdrawalSubmitting;
  bool get withdrawalOutcomeLocked => wallet.withdrawalOutcomeLocked;
  bool get withdrawalOutcomeUnknown => wallet.withdrawalOutcomeUnknown;
  bool get withdrawalVerificationRequired =>
      wallet.withdrawalVerificationRequired;
  bool get withdrawalTotpRequired => wallet.withdrawalTotpRequired;
  bool get withdrawalRulesLoading => wallet.rulesLoading;
  bool get withdrawalRulesReady => wallet.rulesReady;
  set withdrawalRulesReady(bool value) => wallet.rulesReady = value;
  List<WithdrawalAssetRule> get withdrawalRules => wallet.rules;
  set withdrawalRules(List<WithdrawalAssetRule> values) =>
      wallet.rules = values;
  WithdrawalConfirmation? get withdrawalConfirmation =>
      wallet.withdrawalConfirmation;
  String? lastError;
  String? lastNotice;
  final List<String> realtimeLog = [];
  Timer? _realtimeNotifyTimer;
  Timer? _realtimeReconnectTimer;
  int _realtimeGeneration = 0;
  int _realtimeReconnectAttempts = 0;
  bool _realtimeConnected = false;
  bool _realtimeSessionPaused = false;
  int _realtimeAuthRetries = 0;
  Timer? _realtimeAuthRetryTimer;
  final _publicSubscriptions = <String, Map<String, String>>{};
  final _privateSubscriptions = <String, Map<String, String>>{};
  int _announcementsRequestVersion = 0;

  bool get isLoggedIn => auth.isLoggedIn;

  int? get userId => auth.userId;

  Instrument get selectedInstrument =>
      instruments
          .where((i) => i.mode == mode && i.symbol == selectedSymbol)
          .firstOrNull ??
      Instrument.empty(mode);

  List<Instrument> get visibleInstruments {
    final filtered = instruments
        .where((instrument) => instrument.mode == mode)
        .toList();
    return filtered;
  }

  double? latestPriceFor(Instrument instrument) {
    final direct = latestPrices[_priceKey(instrument.mode, instrument.symbol)];
    if (direct != null && direct.isFinite && direct > 0) return direct;
    if (instrument.mode == mode &&
        instrument.symbol == selectedSymbol &&
        candles.isNotEmpty) {
      return candles.last.close;
    }
    if (instrument.mode == mode && instrument.symbol == orderBook.symbol) {
      final bestBid = orderBook.bids.isNotEmpty ? orderBook.bids.first : null;
      final bestAsk = orderBook.asks.isNotEmpty ? orderBook.asks.first : null;
      if (bestBid != null && bestAsk != null) {
        return market.midpoint(
          instrument,
          bestBid.priceTicks,
          bestAsk.priceTicks,
        );
      }
      if (bestBid != null) return instrument.priceFromTicks(bestBid.priceTicks);
      if (bestAsk != null) return instrument.priceFromTicks(bestAsk.priceTicks);
    }
    return offline ? fallbackPriceFor(instrument) : null;
  }

  double? get valuationRate => valuationRates[valuationCurrency];

  double? walletPortfolioUsdt(WalletPortfolio portfolio) =>
      wallet.portfolioUsdt(portfolio);

  late final PortfolioIncomeState _income = PortfolioIncomeState(
    api,
    owner: () => (userId: userId, epoch: _accountEpoch),
    onChanged: notifyListeners,
  );

  PortfolioIncome? portfolioIncome([String scope = 'overview']) =>
      isLoggedIn ? _income.current(scope) : null;

  void _resetPortfolioIncome() => _income.reset();

  Future<void> refreshPortfolioIncome() async {
    if (!_disposed && !offline) await _income.refresh();
  }

  Set<ProductMode> disabledProducts = {};
  int _productAvailabilityVersion = 0;
  bool productAssetsReady(ProductMode product) =>
      isLoggedIn &&
      (disabledProducts.contains(product) ||
          (valuedProducts.contains(product) &&
              privateViews[product]?.ready == true));

  Future<void> refreshProductAvailability() async {
    if (offline) return;
    final epoch = _accountEpoch;
    final request = ++_productAvailabilityVersion;
    bool current() =>
        epoch == _accountEpoch && request == _productAvailabilityVersion;
    try {
      final next = await api.disabledProducts();
      if (!current()) return;
      disabledProducts = next;
      for (final product in next) {
        privateViews.remove(product);
        productBalances[product] = [];
      }
      _materializePrivate();
      _subscribePrivateSelected();
    } catch (_) {
      // A missing configuration response is unknown, never proof of a zero balance.
      if (!current()) return;
      disabledProducts = {};
      _materializePrivate();
      _subscribePrivateSelected();
    }
  }

  double? productBalancesUsdt({ProductMode? product, bool includeSpot = true}) {
    var total = 0.0;
    if (!isLoggedIn ||
        (product == null ? !assetsReady : !productAssetsReady(product))) {
      return null;
    }
    for (final balance
        in product == null
            ? productBalances.entries
                  .where(
                    (entry) => includeSpot || entry.key != ProductMode.spot,
                  )
                  .expand((entry) => entry.value)
            : (productBalances[product] ?? <ProductBalance>[])) {
      final equity = balance.equity;
      if (equity == null) return null;
      if (equity == 0) continue;
      final asset = balance.asset.toUpperCase();
      final price = asset == 'USDT' ? 1.0 : walletAssetPricesUsdt[asset];
      if (price == null || !price.isFinite || price <= 0) return null;
      total += equity * price;
    }
    return total;
  }

  double? valuationAmount(double? usdtAmount) {
    final rate = valuationRate;
    if (usdtAmount == null || rate == null || !rate.isFinite || rate <= 0) {
      return null;
    }
    return usdtAmount * rate;
  }

  Future<void> selectValuationCurrency(ValuationCurrency next) async {
    valuationCurrency = next;
    _persistSettings();
    notifyListeners();
    await refreshValuation(silent: true);
  }

  Future<void> refreshValuation({bool silent = false}) async {
    if (offline) return;
    final version = ++_valuationVersion;
    valuationLoading = true;
    notifyListeners();
    final results = await Future.wait(
      [ValuationCurrency.usd, ValuationCurrency.cny].map((currency) async {
        try {
          final rate = await api.exchangeRateConversion(
            fromCurrency: 'USDT',
            toCurrency: currency.code,
          );
          return MapEntry(currency, rate.isFinite && rate > 0 ? rate : null);
        } catch (_) {
          return MapEntry<ValuationCurrency, double?>(currency, null);
        }
      }),
    );
    if (version != _valuationVersion) return;
    for (final result in results) {
      if (result.value == null) {
        valuationRates.remove(result.key);
      } else {
        valuationRates[result.key] = result.value!;
      }
    }
    valuationLoading = false;
    notifyListeners();
  }

  Future<bool>? _settingsRestore;
  bool _settingsLoaded = false;
  Future<void> restoreAuthentication() async {
    if (_disposed || offline) return;
    if (!_settingsLoaded) {
      final restoring = _settingsRestore ??= _restoreSettings();
      final loaded = await restoring;
      if (identical(_settingsRestore, restoring)) _settingsRestore = null;
      if (!loaded || _disposed) return;
      _settingsLoaded = true;
    }
    if (!_disposed) await auth.restore();
  }

  Future<bool> resumeTelegramLogin(Uri link) async {
    await restoreAuthentication();
    return !_disposed && await auth.resumeTelegramLogin(link);
  }

  Future<void> bootstrap() async {
    if (offline) return;
    await restoreAuthentication();
    await refreshInstruments(silent: true);
    await refreshValuation(silent: true);
    _scheduleOptionReference();
    await refreshPublicData(silent: true);
    await refreshAnnouncements();
    await _connectPublicRealtime();
    _announcementRefreshTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => unawaited(refreshAnnouncements()),
    );
  }

  Future<String> _persistentDeviceId() async {
    final values = await settingsStore.read();
    final existing = values['deviceId'];
    if (existing != null && ApiClient.isDeviceId(existing)) {
      return existing.toLowerCase();
    }
    final created = ApiClient.newDeviceId();
    await settingsStore.write({...values, 'deviceId': created});
    return created;
  }

  Future<bool> _restoreSettings() async {
    try {
      final values = await settingsStore.read();
      clientTheme = ClientTheme.fromCode(values['theme'] ?? 'dark');
      language = ClientLanguage.fromCode(values['language'] ?? 'zh');
      valuationCurrency = ValuationCurrency.fromCode(
        values['valuationCurrency'] ?? 'USDT',
      );
      transfers.restoreFrom(values);
      wallet.restoreFrom(values);
      orders.restoreSettings(values);
      _updatePresentation();
      return true;
    } catch (_) {
      clientTheme = ClientTheme.dark;
      language = ClientLanguage.zhHans;
      valuationCurrency = ValuationCurrency.usdt;
      lastError = '无法读取安全设置与资金恢复凭证，请重试';
    }
    _updatePresentation();
    return false;
  }

  void _persistSettings() {
    unawaited(_writeSettings());
  }

  Future<bool> _writeSettings({
    PendingTradingOrder? completedTradingIntent,
    PendingAccountTransfer? completedTransferIntent,
    PendingWithdrawal? completedWithdrawalIntent,
  }) async {
    final previous = _settingsWriteTail;
    final completed = Completer<void>();
    _settingsWriteTail = completed.future;
    await previous;
    try {
      if (completedTradingIntent != null &&
          !orders.ownsIntent(completedTradingIntent)) {
        return false;
      }
      if (completedTransferIntent != null &&
          !transfers.matches(completedTransferIntent)) {
        return false;
      }
      final values = <String, String>{
        'deviceId': await api.resolveDeviceId(),
        'theme': clientTheme.code,
        'language': language.code,
        'valuationCurrency': valuationCurrency.code,
      };
      // Preserve recovery receipts if a settings action precedes restoration.
      if (!orders.restored && !await orders.restore()) return false;
      if (!transfers.restored && !await transfers.restore()) {
        return false;
      }
      values['pendingTransfers'] = jsonEncode(
        transfers.pendingSnapshot
            .where((pending) => !identical(pending, completedTransferIntent))
            .map((pending) => pending.toJson())
            .toList(),
      );
      if (!wallet.restored && !await wallet.restore()) return false;
      if (completedWithdrawalIntent != null &&
          !wallet.matches(completedWithdrawalIntent)) {
        return false;
      }
      values['pendingWithdrawals'] = jsonEncode(
        wallet.pendingSnapshot
            .where((intent) => !identical(intent, completedWithdrawalIntent))
            .map((intent) => intent.toJson())
            .toList(),
      );
      values['pendingTradingOrders'] = jsonEncode(
        orders.settingsRows(completed: completedTradingIntent),
      );
      await settingsStore.write(values);
      if (completedWithdrawalIntent != null &&
          !wallet.completeSaved(completedWithdrawalIntent)) {
        return false;
      }
      // Keep the original request locked until durable removal succeeds, before
      // allowing the next queued settings save to observe the confirmed state.
      if (completedTradingIntent != null) {
        if (!orders.ownsIntent(completedTradingIntent)) {
          return false;
        }
        orders.completeSaved(completedTradingIntent);
      }
      if (completedTransferIntent != null) {
        if (!transfers.matches(completedTransferIntent)) {
          return false;
        }
        transfers.completeSaved(completedTransferIntent);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      completed.complete();
    }
  }

  void selectTheme(ClientTheme next) {
    clientTheme = next;
    _updatePresentation();
    _persistSettings();
    notifyListeners();
  }

  void selectLanguage(ClientLanguage next) {
    language = next;
    _updatePresentation();
    _persistSettings();
    unawaited(refreshAnnouncements());
    notifyListeners();
  }

  Future<void> refreshAnnouncements() async {
    if (offline) return;
    final requestVersion = ++_announcementsRequestVersion;
    announcementsLoading = true;
    try {
      final locale = language == ClientLanguage.zhHans ? 'zh-CN' : 'en-US';
      final platform = defaultTargetPlatform == TargetPlatform.iOS
          ? 'IOS'
          : 'ANDROID';
      final responses = await Future.wait([
        api.announcements(
          locale: locale,
          productLine: 'ALL',
          platform: platform,
          placement: 'CENTER',
        ),
        api.announcements(
          locale: locale,
          productLine: 'ALL',
          platform: platform,
          placement: 'BANNER',
          limit: 10,
        ),
        api.announcements(
          locale: locale,
          productLine: 'ALL',
          platform: platform,
          placement: 'MODAL',
          limit: 20,
        ),
      ]);
      if (requestVersion != _announcementsRequestVersion) return;
      announcements = asList(responses[0]['announcements']).map(asMap).toList();
      announcementOffset = asInt(responses[0]['offset']);
      announcementsHasMore = responses[0]['hasMore'] == true;
      announcementBanners = asList(
        responses[1]['announcements'],
      ).map(asMap).toList();
      announcementModals = asList(
        responses[2]['announcements'],
      ).map(asMap).toList();
      unreadAnnouncementCount = asInt(responses[0]['unreadCount']);
      announcementError = null;
    } catch (error) {
      if (requestVersion != _announcementsRequestVersion) return;
      announcementError = language == ClientLanguage.en
          ? 'Announcements are temporarily unavailable: ${clientErrorMessage(error)}'
          : '公告暂时无法加载：${clientErrorMessage(error)}';
    } finally {
      if (requestVersion == _announcementsRequestVersion) {
        announcementsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadMoreAnnouncements() async {
    if (offline || announcementsLoading || !announcementsHasMore) return;
    announcementsLoading = true;
    final requestVersion = ++_announcementsRequestVersion;
    try {
      final locale = language == ClientLanguage.zhHans ? 'zh-CN' : 'en-US';
      final platform = defaultTargetPlatform == TargetPlatform.iOS
          ? 'IOS'
          : 'ANDROID';
      final response = await api.announcements(
        locale: locale,
        productLine: 'ALL',
        platform: platform,
        placement: 'CENTER',
        offset: announcementOffset + 50,
        limit: 50,
      );
      if (requestVersion != _announcementsRequestVersion) return;
      announcements = [
        ...announcements,
        ...asList(response['announcements']).map(asMap),
      ];
      announcementOffset = asInt(response['offset']);
      announcementsHasMore = response['hasMore'] == true;
      announcementError = null;
    } catch (error) {
      if (requestVersion == _announcementsRequestVersion) {
        announcementError = language == ClientLanguage.en
            ? 'Announcements are temporarily unavailable: ${clientErrorMessage(error)}'
            : '公告暂时无法加载：${clientErrorMessage(error)}';
      }
    } finally {
      if (requestVersion == _announcementsRequestVersion) {
        announcementsLoading = false;
        notifyListeners();
      }
    }
  }

  Future<bool> markAnnouncementRead(
    int announcementId, {
    String placement = 'CENTER',
  }) async {
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'IOS'
        : 'ANDROID';
    try {
      await api.markAnnouncementRead(
        announcementId: announcementId,
        productLine: 'ALL',
        platform: platform,
        placement: placement,
      );
      await refreshAnnouncements();
      return true;
    } catch (error) {
      announcementError = language == ClientLanguage.en
          ? 'Could not update announcement read status: ${clientErrorMessage(error)}'
          : '公告已读状态更新失败：${clientErrorMessage(error)}';
      notifyListeners();
      return false;
    }
  }

  Future<bool> markAllAnnouncementsRead() async {
    final platform = defaultTargetPlatform == TargetPlatform.iOS
        ? 'IOS'
        : 'ANDROID';
    try {
      await api.markAllAnnouncementsRead(
        productLine: 'ALL',
        platform: platform,
      );
      await refreshAnnouncements();
      return true;
    } catch (error) {
      announcementError = language == ClientLanguage.en
          ? 'Could not update announcement read status: ${clientErrorMessage(error)}'
          : '公告已读状态更新失败：${clientErrorMessage(error)}';
      notifyListeners();
      return false;
    }
  }

  void _clearWalletData() {
    _resetPortfolioIncome();
    ++_accountEpoch;
    orders.resetAccount();
    wallet.clearAccountView();
  }

  Future<void> refreshInstruments({bool silent = false}) async {
    if (offline) return;
    final request = ++_instrumentRequestVersion;
    final old = selectedInstrument;
    try {
      final base = await api.instruments();
      final loaded = mode.isExpiring
          ? [
              ...base.where((i) => i.mode != mode),
              ...await api.expiringInstruments(mode),
            ]
          : base;
      if (old.mode.isExpiring &&
          old.instrumentId.isNotEmpty &&
          !loaded.any(
            (i) => i.mode == old.mode && i.instrumentId == old.instrumentId,
          )) {
        final historical = await api.instrumentLatest(
          old.instrumentId,
          old.mode,
        );
        if (historical.status != 'CLOSED') {
          throw const FormatException('交割合约目录状态不匹配');
        }
        loaded.add(historical);
      }
      if (request != _instrumentRequestVersion) {
        api.instrumentCatalog = instruments;
        return;
      }
      instruments = loaded;
      api.instrumentCatalog = loaded;
      final candidates = visibleInstruments;
      if (!candidates.any((i) => i.symbol == selectedSymbol)) {
        selectedSymbol = candidates.firstOrNull?.symbol ?? '';
      }
      if (selectedSymbol != old.symbol ||
          selectedInstrument.instrumentId != old.instrumentId ||
          selectedInstrument.changeId != old.changeId) {
        ++_publicRequestVersion;
        orders.invalidateOpenOrders();
        orderBook = OrderBook.empty(selectedSymbol);
        candles = [];
        recentTrades = [];
        latestPrices.remove(_priceKey(mode, selectedSymbol));
        markPrices.remove(_priceKey(mode, selectedSymbol));
        _materializePrivate();
      }
      _subscribePublicSelected();
      lastError = null;
    } catch (error) {
      if (request != _instrumentRequestVersion) return;
      if (error is FormatException) {
        instruments = const [];
        selectedSymbol = '';
        api.instrumentCatalog = const [];
        orderBook = OrderBook.empty('');
        candles = const [];
        _subscribePublicSelected();
      } else {
        api.instrumentCatalog = instruments;
      }
      if (silent) {
        _recordRealtimeIssue('加载交易对失败：${clientErrorMessage(error)}');
      } else {
        lastError = '加载交易对失败：${clientErrorMessage(error)}';
      }
    }
    _scheduleRealtimeNotify();
  }

  void _scheduleRealtimeNotify() {
    if (_disposed || (_realtimeNotifyTimer?.isActive ?? false)) return;
    _realtimeNotifyTimer = Timer(const Duration(milliseconds: 200), () {
      _realtimeNotifyTimer = null;
      notifyListeners();
    });
  }

  Future<void> refreshPublicData({bool silent = false}) async {
    if (offline || selectedSymbol.isEmpty) return;
    unawaited(refreshOptionReference());
    final requestVersion = ++_publicRequestVersion;
    loadingPublic = true;
    notifyListeners();
    try {
      final symbol = selectedSymbol;
      final productLine = _productLineForSymbol(symbol);
      final beforeTrades = market.version('$productLine:$symbol:trades:');
      final beforeTicker = market.version('$productLine:$symbol:bookTicker:');
      final beforeBook = market.version('$productLine:$symbol:depth:');
      final beforeCandles = market.version(
        '$productLine:$symbol:candles:$period',
      );
      final results = await Future.wait([
        api
            .orderBook(symbol, productLine: productLine)
            .then<OrderBook?>((book) => book)
            .catchError((Object error) {
              _recordRealtimeIssue('加载盘口失败：${clientErrorMessage(error)}');
              return null;
            }),
        api.candles(symbol, period, productLine: productLine),
        api.recentTrades(symbol, productLine: productLine).catchError((
          Object error,
        ) {
          _recordRealtimeIssue('加载最新成交失败：${clientErrorMessage(error)}');
          return <Map<String, dynamic>>[];
        }),
      ]);
      if (requestVersion != _publicRequestVersion) return;
      final loadedTrades = results[2] as List<Map<String, dynamic>>;
      if (loadedTrades.any((trade) => !market.validTrade(trade))) {
        _recordRealtimeIssue('最新成交的价格或数量无效，已保留原成交记录');
      } else {
        recentTrades = mergeRecentTrades(loadedTrades, recentTrades);
      }
      final loadedBook = results[0] as OrderBook?;
      if (loadedBook != null &&
          identical(
            beforeBook,
            market.version('$productLine:$symbol:depth:'),
          )) {
        orderBook = loadedBook;
      }
      final loadedCandles = results[1] as List<Candle>;
      if (identical(
        beforeCandles,
        market.version('$productLine:$symbol:candles:$period'),
      )) {
        candles = loadedCandles;
      } else {
        candles = {
          for (final c in [...loadedCandles, ...candles]) c.openTime: c,
        }.values.toList()..sort((a, b) => a.openTime.compareTo(b.openTime));
      }
      if (candles.isNotEmpty &&
          identical(
            beforeTicker,
            market.version('$productLine:$symbol:bookTicker:'),
          ) &&
          identical(
            beforeTrades,
            market.version('$productLine:$symbol:trades:'),
          )) {
        latestPrices[_priceKey(mode, symbol)] = candles.last.close;
      }
      lastError = null;
    } catch (error) {
      if (requestVersion != _publicRequestVersion) return;
      if (silent) {
        _recordRealtimeIssue('加载行情失败：${clientErrorMessage(error)}');
      } else {
        lastError = '加载行情失败：${clientErrorMessage(error)}';
      }
    } finally {
      if (requestVersion == _publicRequestVersion) {
        loadingPublic = false;
        notifyListeners();
      }
    }
  }

  int? _balanceScaleFor(String asset) {
    final code = asset.toUpperCase();
    bool valid(int? scale) =>
        scale != null && RegExp(r'^10*$').hasMatch('$scale');
    if (_balanceScales.containsKey(code)) {
      final scale = int.tryParse(_balanceScales[code]!);
      return valid(scale) ? scale : null;
    }
    // Instrument scales also originate from the authoritative asset catalog.
    final known = <int>{};
    for (final instrument in instruments) {
      for (final entry in [
        (instrument.baseAsset, instrument.baseScaleUnits),
        (instrument.quoteAsset, instrument.quoteScaleUnits),
        (instrument.settleAsset, instrument.settleScaleUnits),
      ]) {
        if (entry.$1.toUpperCase() == code && valid(entry.$2)) {
          known.add(entry.$2!);
        }
      }
    }
    return known.length == 1 ? known.single : null;
  }

  int? assetScaleUnits(String asset) => _balanceScaleFor(asset);

  Future<void> refreshBalanceScales() async {
    final version = ++_balanceScalesVersion, epoch = _accountEpoch;
    try {
      final scales = await api.assetScales();
      if (version != _balanceScalesVersion || epoch != _accountEpoch) {
        return;
      }
      _balanceScales = Map.unmodifiable(scales);
      _materializePrivate();
    } catch (_) {
      // Unknown precision is represented by nullable amounts, never 1e8.
    }
  }

  Future<void> refreshPrivateData() async {
    final id = userId;
    if (offline || id == null) return;
    final generation = ++_privateDataRequestVersion;
    final selectedMode = mode;
    final epoch = _accountEpoch, selection = _selectionVersion;
    bool current() =>
        generation == _privateDataRequestVersion &&
        epoch == _accountEpoch &&
        selection == _selectionVersion &&
        id == userId &&
        selectedMode == mode;
    loadingPrivate = true;
    notifyListeners();
    await refreshProductAvailability();
    if (!current()) return;
    final walletRefresh = refreshWallet();
    final incomeRefresh = refreshPortfolioIncome();
    final scalesRefresh = refreshBalanceScales();
    final orderTermsRefresh = refreshOrderTerms();
    final algoRefresh = refreshAlgoOrders();
    final riskRefresh = refreshRiskDetails();
    String? liquidationError;
    try {
      final liquidations =
          await (selectedMode.isDerivative &&
                  !disabledProducts.contains(selectedMode)
              ? api.liquidationOrders(id, productLine: selectedMode.productLine)
              : Future<List<LiquidationOrder>>.value(const []));
      if (!current()) {
        return;
      }
      liquidationOrders = liquidations;
      lastError = null;
    } catch (error) {
      if (current()) {
        liquidationError = '加载强平记录失败：${clientErrorMessage(error)}';
      }
    } finally {
      await walletRefresh;
      await incomeRefresh;
      await scalesRefresh;
      await orderTermsRefresh;
      await algoRefresh;
      await riskRefresh;
      if (current()) {
        if (liquidationError != null) lastError = liquidationError;
        loadingPrivate = false;
        notifyListeners();
      }
    }
  }

  Future<AuthSession?> login(String identifier, String password) =>
      auth.login(identifier, password);
  Future<AuthSession?> loginTelegram(
    Future<AuthSession> Function() authenticate,
  ) => auth.loginTelegram(authenticate);
  Future<AuthSession?> register(
    String identifier,
    String password, {
    bool phone = false,
  }) => auth.register(identifier, password, phone: phone);
  Future<bool> verifyLogin(Map<String, String> codes) =>
      auth.verifyLogin(codes);
  Future<bool> verifyPendingEmail(String code) => auth.verifyPendingEmail(code);
  Future<bool> resendPendingEmail() => auth.resendPendingEmail();
  Future<bool> requestPasswordReset(String identifier) =>
      auth.requestPasswordReset(identifier);
  Future<bool> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) => auth.resetPassword(
    identifier: identifier,
    code: code,
    newPassword: newPassword,
  );
  Future<bool> unlockBiometricSession() => auth.unlockBiometricSession();
  Future<bool> enableBiometricLogin() => auth.enableBiometricLogin();
  Future<bool> disableBiometricLogin() => auth.disableBiometricLogin();
  Future<void> logout() => auth.logout();

  void _authSessionChanged(
    AuthSession? previous,
    AuthSession? next,
    AuthSessionChange change,
  ) {
    if (_disposed) return;
    _realtimeReconnectTimer?.cancel();
    _realtimeReconnectTimer = null;
    _realtimeAuthRetryTimer?.cancel();
    _realtimeSessionPaused = false;
    _realtimeAuthRetries = 0;
    ++_realtimeGeneration;
    _realtimeConnected = false;
    _privateAuthenticated = false;
    _privateRecovery.reset();
    _freshnessTimer?.cancel();
    _riskDetailsTimer?.cancel();
    for (final view in privateViews.values) {
      view.status = 'STALE';
    }
    if (previous?.user.userId != next?.user.userId || next == null) {
      _clearWalletData();
      ++_privateDataRequestVersion;
      privateViews.clear();
      _riskInputKey = '';
      positionPnlUnits.clear();
      queriedPositionRisks = const [];
      ++_riskDetailsVersion;
      productBalances.clear();
      valuedProducts.clear();
      assetsReady = false;
      balances = const [];
      positions = const [];
      positionRisks = const [];
      _clearAccountRisk();
      orders.resetAccount();
    } else {
      assetsReady = false;
      valuedProducts.clear();
    }
    if (change == AuthSessionChange.signedOut ||
        change == AuthSessionChange.expired) {
      loadingPrivate = false;
    }
  }

  Future<void> _authSessionReady(
    AuthSession? previous,
    AuthSession? next,
    AuthSessionChange change,
    int revision,
  ) async {
    bool current() =>
        !_disposed &&
        auth.isCurrentRevision(revision) &&
        identical(auth.current, next);
    if (!current()) return;
    if (next == null) {
      await realtime.close();
      if (!current()) return;
      await _connectRealtime();
      if (!current()) return;
      await refreshAnnouncements();
    } else if (change == AuthSessionChange.tokenRefreshed) {
      await _connectRealtime(forceReconnect: true);
    } else {
      await refreshProductAvailability();
      if (!current()) return;
      await _connectRealtime(forceReconnect: true);
      if (!current()) return;
      await refreshPrivateData();
      if (!current()) return;
      await refreshAnnouncements();
    }
    if (current()) notifyListeners();
  }

  Future<void> selectMode(ProductMode nextMode) {
    final candidates = instruments.where((i) => i.mode == nextMode);
    final symbol = candidates.any((i) => i.symbol == selectedSymbol)
        ? selectedSymbol
        : candidates.firstOrNull?.symbol ?? '';
    return _selectMarket(nextMode, symbol, reconnect: true);
  }

  Future<void> selectInstrument(Instrument instrument) {
    return _selectMarket(
      instrument.mode,
      instrument.symbol,
      reconnect: mode != instrument.mode,
    );
  }

  Future<void> selectSymbol(String symbol) {
    if (!visibleInstruments.any((i) => i.symbol == symbol)) {
      return Future.value();
    }
    return _selectMarket(mode, symbol, reconnect: false);
  }

  Future<void> _selectMarket(
    ProductMode nextMode,
    String symbol, {
    required bool reconnect,
  }) async {
    api.cancelPendingRequests();
    final selection = ++_selectionVersion;
    _riskInputKey = '';
    ++_riskDetailsVersion;
    queriedPositionRisks = [];
    ++_publicRequestVersion;
    orders.invalidateOpenOrders();
    mode = nextMode;
    selectedSymbol = symbol;
    _optionReference = null;
    _scheduleOptionReference();
    recentTrades = [];
    _clearAccountRisk();
    _resetAlgoOrders();
    liquidationOrders = [];
    balances = const [];
    positions = const [];
    openOrders = const [];
    openTriggerOrders = const [];
    positionRisks = const [];
    loadingPublic = false;
    loadingPrivate = false;
    _materializePrivate();
    orderBook = offline && selectedSymbol.isNotEmpty
        ? fallbackOrderBook(selectedInstrument)
        : OrderBook.empty(selectedSymbol);
    candles = offline && selectedSymbol.isNotEmpty
        ? fallbackCandles()
        : const [];
    _subscribePublicSelected();
    _subscribePrivateSelected();
    notifyListeners();
    await refreshInstruments(silent: true);
    if (selection != _selectionVersion) return;
    await refreshPublicData(silent: true);
    if (selection != _selectionVersion) return;
    await refreshPrivateData();
    if (selection != _selectionVersion) return;
    if (reconnect) await _reconnectRealtimeForSelectedProduct();
  }

  Future<void> selectPeriod(String nextPeriod) async {
    period = nextPeriod;
    candles = const [];
    _subscribePublicSelected();
    notifyListeners();
    await refreshPublicData(silent: true);
  }

  Future<void> checkPendingTradingCommand() =>
      orders.checkPendingTradingCommand();

  Future<void> refreshAlgoOrders() => orders.refreshAlgoOrders();

  Future<void> loadMoreOpenOrders() => orders.loadMoreOpenOrders();

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
  }) => orders.placeOrder(
    side: side,
    orderType: orderType,
    timeInForce: timeInForce,
    price: price,
    quantitySteps: quantitySteps,
    marginMode: marginMode,
    positionSide: positionSide,
    reduceOnly: reduceOnly,
    postOnly: postOnly,
    bboPriceMode: bboPriceMode,
    targetInstrument: targetInstrument,
    priceText: priceText,
  );

  Future<void> cancelOpenSpotOrders({required bool onlyCurrentPair}) =>
      orders.cancelOpenSpotOrders(onlyCurrentPair: onlyCurrentPair);

  Future<void> amendSpotOrder(
    OrderModel order,
    Instrument instrument,
    String price,
    String quantity,
  ) => orders.amendSpotOrder(order, instrument, price, quantity);

  Future<void> cancelOrder(OrderModel order) => orders.cancelOrder(order);

  Future<bool> placeAlgoOrder(AlgoOrderDraft draft) =>
      orders.placeAlgoOrder(draft);

  Future<void> cancelAlgoOrder(AlgoOrderModel order) =>
      orders.cancelAlgoOrder(order);

  Future<int> placeOco(List<TriggerOrderDraft> drafts) =>
      orders.placeOco(drafts);

  Future<int> placeTriggerOrders(List<TriggerOrderDraft> drafts) =>
      orders.placeTriggerOrders(drafts);

  Future<void> cancelTriggerOrder(TriggerOrderModel order) =>
      orders.cancelTriggerOrder(order);

  Future<void> changePositionMode(String nextMode) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再切换持仓模式';
      notifyListeners();
      return;
    }
    if (nextMode == positionMode) return;
    try {
      positionMode = await api.updatePositionMode(
        id,
        nextMode,
        productLine: mode.productLine,
      );
      lastNotice = '持仓模式已切换为${positionModeLabel(positionMode)}';
      await refreshPrivateData();
    } catch (error) {
      lastError = '切换持仓模式失败：${clientErrorMessage(error)}';
    }
    notifyListeners();
  }

  Future<void> closePosition(Position position) async {
    final instrument = instruments
        .where((item) => item.mode == mode && item.symbol == position.symbol)
        .firstOrNull;
    if (instrument == null) {
      lastError = '持仓合约信息不可用，请刷新后重试';
      notifyListeners();
      return;
    }
    final quantity = BigInt.from(position.signedQuantitySteps).abs();
    if (quantity > BigInt.from(9223372036854775807)) {
      lastError = '持仓数量超出单笔上限，请分批平仓';
      notifyListeners();
      return;
    }
    await placeOrder(
      targetInstrument: instrument,
      side: position.signedQuantitySteps >= 0 ? 'SELL' : 'BUY',
      orderType: 'MARKET',
      timeInForce: 'IOC',
      price: 0,
      quantitySteps: quantity.toInt(),
      marginMode: position.marginMode,
      positionSide: instrument.isSpot || positionMode == 'ONE_WAY'
          ? 'NET'
          : position.positionSide,
      reduceOnly: instrument.isDerivative,
      postOnly: false,
    );
  }

  Future<bool> restorePendingTransfers() => transfers.restore();

  Future<void> transfer({
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required double amount,
    String? amountText,
    String? emailCode,
    String? totpCode,
  }) => transfers.submit(
    sourceAccountType: sourceAccountType,
    targetAccountType: targetAccountType,
    asset: asset,
    amountText: amountText ?? '$amount',
    emailCode: emailCode,
    totpCode: totpCode,
  );

  Future<void> resumePendingTransfer({String? emailCode, String? totpCode}) =>
      transfers.resume(emailCode: emailCode, totpCode: totpCode);

  Future<void> resetTransferIntent() => transfers.resetFailedIntent();

  Future<void> refreshWallet() => wallet.refresh();
  Future<void> refreshWalletAssetPrices() => wallet.refreshAssetPrices();
  Future<void> loadDepositAddress({
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) => wallet.loadDepositAddress(
    chain: chain,
    symbol: symbol,
    forceNew: forceNew,
  );
  Future<void> refreshWithdrawalRules() => wallet.refreshWithdrawalRules();
  WithdrawalAssetRule? withdrawalRuleFor(String chain, String symbol) =>
      wallet.withdrawalRuleFor(chain, symbol);
  String? validateWithdrawal({
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
  }) => wallet.validateWithdrawal(
    chain: chain,
    symbol: symbol,
    toAddress: toAddress,
    amount: amount,
  );
  Future<void> withdrawWallet({
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
    String? emailCode,
    String? totpCode,
  }) => wallet.withdrawWallet(
    chain: chain,
    symbol: symbol,
    toAddress: toAddress,
    amount: amount,
    emailCode: emailCode,
    totpCode: totpCode,
  );
  Future<void> requestWithdrawalChallenge() =>
      wallet.requestWithdrawalChallenge();
  Future<void> resetWithdrawalIntent() => wallet.resetWithdrawalIntent();
  String? withdrawalMaximum(String chain, String symbol) =>
      wallet.withdrawalMaximum(chain, symbol);

  Future<void> _connectPublicRealtime() async {
    await _connectRealtime();
  }

  Future<void> _connectRealtime({bool forceReconnect = false}) async {
    if (_disposed || offline || config.websocketUrl.trim().isEmpty) return;
    if (_realtimeConnected && !forceReconnect) {
      _syncRealtimeSubscriptions();
      return;
    }
    final connectGeneration = ++_realtimeGeneration;
    _realtimeConnected = false;
    if (forceReconnect) await realtime.close();
    if (connectGeneration != _realtimeGeneration) return;
    market.resetVersions();
    _privateRecovery.reset();
    markPrices.clear();
    _privateAuthenticated = false;
    final current = _realtimeSessionPaused ? null : session;
    if (current != null) {
      privateViews.clear();
      _riskInputKey = '';
      positionPnlUnits.clear();
      queriedPositionRisks = [];
      ++_riskDetailsVersion;
      productBalances.clear();
      valuedProducts.clear();
      assetsReady = false;
      balances = const [];
      positions = const [];
      openOrders = const [];
      openTriggerOrders = const [];
      positionRisks = const [];
      _clearAccountRisk();
      _riskDetailsTimer?.cancel();
      _freshnessTimer?.cancel();
      _freshnessTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        _materializePrivate();
        _scheduleRealtimeNotify();
      });
    } else {
      _freshnessTimer?.cancel();
      _freshnessTimer = null;
    }
    try {
      await realtime.connect(
        userId: current?.user.userId,
        accessToken: current?.accessToken,
        onEvent: (message) {
          if (connectGeneration != _realtimeGeneration ||
              (current != null &&
                  current.accessToken != session?.accessToken)) {
            return;
          }
          if (current != null &&
              message['op'] == 'authenticated' &&
              parseInt64(message['userId']) == current.user.userId) {
            _privateAuthenticated = true;
          }
          handleRealtimeMessage(message);
        },
        onError: (error) {
          if (connectGeneration != _realtimeGeneration) return;
          _recordRealtimeIssue('实时 WebSocket：${clientErrorMessage(error)}');
          if (error is FormatException) {
            _scheduleRealtimeReconnect(connectGeneration);
          }
          notifyListeners();
        },
        onDone: () {
          if (realtime.closeCode == 1008 && current != null) {
            unawaited(_refreshRealtimeSession(connectGeneration));
          } else {
            _scheduleRealtimeReconnect(connectGeneration);
          }
        },
      );
      if (connectGeneration != _realtimeGeneration ||
          (current != null && current.accessToken != session?.accessToken)) {
        return;
      }
      _realtimeConnected = true;
      if (!_realtimeSessionPaused) _realtimeReconnectAttempts = 0;
      _subscribePrivateSelected();
      _subscribePublicSelected();
      _syncRealtimeSubscriptions();
      market.awaitDepthSnapshot(mode, selectedSymbol);
      if (current != null) {
        for (final product in ProductMode.values) {
          if (!disabledProducts.contains(product) &&
              privateViews[product]?.status != 'INITIALIZING') {
            _privateRecovery.awaitSnapshot(product);
          }
        }
      }
    } catch (error) {
      if (connectGeneration != _realtimeGeneration ||
          (current != null && current.accessToken != session?.accessToken)) {
        return;
      }
      _recordRealtimeIssue('实时连接失败：${clientErrorMessage(error)}');
      notifyListeners();
      _scheduleRealtimeReconnect(connectGeneration);
    }
  }

  Future<void> _refreshRealtimeSession(int generation) async {
    if (_disposed || generation != _realtimeGeneration) return;
    final previous = session;
    if (previous == null) return;
    _realtimeSessionPaused = true;
    _privateAuthenticated = false;
    _realtimeConnected = false;
    for (final view in privateViews.values) {
      view.status = 'STALE';
    }
    _materializePrivate();
    notifyListeners();
    try {
      if (previous.refreshTokenExpired) {
        await auth.expire();
        return;
      }
      final next = await api.refresh(previous.refreshToken);
      if (_disposed || !identical(session, previous)) return;
      await auth.persistRefreshedSession(next);
    } catch (error) {
      if (_disposed || !identical(session, previous)) return;
      if (error is ApiException && [401, 403].contains(error.statusCode)) {
        await auth.expire();
        return;
      }
      _recordRealtimeIssue('登录状态暂不可验证，私有实时已暂停：${clientErrorMessage(error)}');
      await _connectRealtime(forceReconnect: true);
      if (_disposed || !identical(session, previous)) return;
      if (++_realtimeAuthRetries <= 3) {
        _realtimeAuthRetryTimer?.cancel();
        _realtimeAuthRetryTimer = Timer(
          _reconnectDelay(_realtimeAuthRetries),
          () {
            if (!_disposed && identical(session, previous)) {
              unawaited(_refreshRealtimeSession(_realtimeGeneration));
            }
          },
        );
      } else {
        lastError = '登录状态验证失败，请连接恢复后重新登录；私有操作暂不可用';
        notifyListeners();
      }
    }
  }

  void _recordRealtimeIssue(String message) {
    realtimeLog.insert(0, message);
    if (realtimeLog.length > 20) realtimeLog.removeLast();
  }

  void _scheduleRealtimeReconnect([int? expectedGeneration]) {
    if (expectedGeneration != null &&
        expectedGeneration != _realtimeGeneration) {
      return;
    }
    if (_disposed || offline || (_realtimeReconnectTimer?.isActive ?? false)) {
      return;
    }
    _realtimeConnected = false;
    _privateAuthenticated = false;
    market.awaitDepthSnapshot(mode, selectedSymbol);
    for (final view in privateViews.values) {
      view.status = 'STALE';
    }
    if (isLoggedIn) _materializePrivate();
    final reconnectGeneration = _realtimeGeneration;
    _realtimeReconnectAttempts++;
    _realtimeReconnectTimer = Timer(
      _reconnectDelay(_realtimeReconnectAttempts),
      () async {
        _realtimeReconnectTimer = null;
        if (reconnectGeneration != _realtimeGeneration) return;
        await _connectRealtime(forceReconnect: true);
        await refreshPublicData(silent: true);
        if (isLoggedIn) await refreshPrivateData();
      },
    );
  }

  Duration _reconnectDelay(int attempt) {
    final capped = attempt < 1 ? 1 : (attempt > 4 ? 4 : attempt);
    final seconds = 1 << (capped - 1);
    return Duration(seconds: seconds);
  }

  Future<void> _reconnectRealtimeForSelectedProduct() async {
    await _connectRealtime();
  }

  void _subscribePublicSelected() {
    final subscriptions = <Map<String, String>>[];
    void add(
      String channel,
      ProductMode product,
      String symbol, [
      String? interval,
    ]) {
      if (symbol.isEmpty) return;
      subscriptions.add({
        'channel': channel,
        'productLine': product.productLine,
        if (instruments.any(
          (i) =>
              i.mode == product &&
              i.symbol == symbol &&
              i.instrumentId.isNotEmpty,
        ))
          'instrumentId': instruments
              .firstWhere((i) => i.mode == product && i.symbol == symbol)
              .instrumentId
        else
          'symbol': symbol,
        'period': ?interval,
      });
    }

    for (final instrument in spotInstruments) {
      add('trades', ProductMode.spot, instrument.symbol);
      add('bookTicker', ProductMode.spot, instrument.symbol);
    }
    for (final instrument in instruments.where((i) => i.mode.isDerivative)) {
      add('trades', instrument.mode, instrument.symbol);
    }
    add('depth', mode, selectedSymbol);
    add('candles', mode, selectedSymbol, period);
    if (mode.isDerivative) {
      add('mark', mode, selectedSymbol);
      add('index', mode, selectedSymbol);
      if (mode.isPerpetual) add('funding', mode, selectedSymbol);
    }
    for (final entry in privateViews.entries) {
      for (final position in entry.value.rows('position')) {
        final quantity = parseInt64(position['signedQuantitySteps']);
        if (quantity != null && quantity != 0) {
          add('mark', entry.key, asString(position['symbol']));
        }
      }
    }
    _publicSubscriptions
      ..clear()
      ..addEntries(subscriptions.map((s) => MapEntry(_subscriptionKey(s), s)));
    _syncRealtimeSubscriptions();
  }

  void _subscribePrivateSelected() {
    final subscriptions = !isLoggedIn
        ? <Map<String, String>>[]
        : [
            for (final product in ProductMode.values.where(
              (p) => !disabledProducts.contains(p),
            ))
              for (final channel in [
                'accountState',
                'orders',
                'triggerOrders',
                'positions',
                'positionRisk',
                'executionReports',
              ])
                {'channel': channel, 'productLine': product.productLine},
          ];
    _privateSubscriptions
      ..clear()
      ..addEntries(subscriptions.map((s) => MapEntry(_subscriptionKey(s), s)));
    _syncRealtimeSubscriptions();
  }

  String _subscriptionKey(Map<String, String> subscription) =>
      '${subscription['productLine']}:${subscription['channel']}:${subscription['instrumentId'] ?? subscription['symbol'] ?? '*'}:${subscription['period'] ?? ''}';

  void _syncRealtimeSubscriptions() {
    realtime.replaceSubscriptions([
      ..._publicSubscriptions.values,
      ..._privateSubscriptions.values,
    ]);
  }

  void _materializePrivate() {
    if (!isLoggedIn) return;
    var complete = _privateAuthenticated;
    valuedProducts.clear();
    positionPnlUnits.clear();
    for (final product in ProductMode.values) {
      if (disabledProducts.contains(product)) {
        productBalances[product] = [];
        if (product == mode) {
          balances = [];
          positions = [];
          openOrders = [];
          openTriggerOrders = [];
          positionRisks = [];
        }
        continue;
      }
      final view = privateViews[product];
      if (view?.status == 'INITIALIZING') _privateRecovery.pause(product);
      if (!offline &&
          view != null &&
          (view.status == 'STALE' || view.status == 'READY')) {
        _privateRecovery.observe(product);
      }
      if (view == null) {
        complete = false;
        continue;
      }
      final projection = AccountProjection.fromView(
        product: product,
        view: view,
        instruments: instruments,
        markTicks: markTicksFor,
        scaleFor: _balanceScaleFor,
      );
      if (projection == null) {
        if (view.status == 'READY') view.status = 'STALE';
        productBalances[product] = const [];
        complete = false;
        if (product == mode) {
          balances = const [];
          positions = const [];
          openOrders = const [];
          openTriggerOrders = const [];
          positionRisks = const [];
        }
        continue;
      }
      final productComplete = projection.complete;
      final activePositions = projection.positions;
      final risks = projection.risks;
      final pnlByPosition = projection.pnlByPosition;
      for (final position in activePositions) {
        final pnl = pnlByPosition[positionKey(position)];
        if (pnl != null) {
          positionPnlUnits['${product.productLine}:${position['symbol']}:${position['positionSide'] ?? 'NET'}'] =
              pnl;
        }
      }
      productBalances[product] = projection.balances;
      if (productComplete && _privateAuthenticated) valuedProducts.add(product);
      complete = complete && productComplete;
      if (product == mode) {
        balances = productBalances[product]!;
        positions = activePositions
            .where(
              (p) => !onlyCurrentTradingPair || p['symbol'] == selectedSymbol,
            )
            .map(Position.fromJson)
            .toList();
        openOrders = view
            .rows('order')
            .where(
              (o) =>
                  o['status'] == 'OPEN' &&
                  (!onlyCurrentTradingPair || o['symbol'] == selectedSymbol),
            )
            .map(
              (o) => OrderModel.fromJson({
                ...o,
                'status': asInt(o['executedQuantitySteps']) > 0
                    ? 'PARTIALLY_FILLED'
                    : 'NEW',
              }),
            )
            .toList();
        openTriggerOrders = view
            .rows('trigger')
            .where(
              (o) =>
                  ['PENDING', 'TRIGGERING'].contains(o['status']) &&
                  (!onlyCurrentTradingPair || o['symbol'] == selectedSymbol),
            )
            .map(TriggerOrderModel.fromJson)
            .toList();
        positionRisks = risks
            .where(
              (r) =>
                  activePositions.any((p) => positionKey(p) == positionKey(r)),
            )
            .map(
              (r) => PositionRisk.fromJson({
                ...r,
                if (pnlByPosition.containsKey(positionKey(r)))
                  'unrealizedPnlUnits': pnlByPosition[positionKey(r)],
              }),
            )
            .toList();
        positionMode = view.positionMode;
        openOrdersHasMore = false;
        openOrdersNextCursor = null;
      }
    }
    assetsReady = complete;
    final riskKey =
        '$userId:$_privateAuthenticated:${mode.productLine}:${selectedInstrument.settleAsset}:${privateViews[mode]?.ready}:${positions.map((p) => '${p.symbol}:${p.positionSide}:${p.marginMode}:${p.signedQuantitySteps}:${p.entryPriceTicks}:${p.positionMarginUnits}').join('|')}:${balances.map((b) => '${b.asset}:${b.availableUnits}:${b.lockedUnits}').join('|')}';
    if (!_canReadAccountRisk) _clearAccountRisk();
    if (riskKey != _riskInputKey) {
      _riskInputKey = riskKey;
      queriedPositionRisks = [];
      ++_riskDetailsVersion;
      _riskDetailsTimer?.cancel();
      if (!offline && mode.isDerivative && privateViews[mode]?.ready == true) {
        _riskDetailsTimer = Timer(
          const Duration(milliseconds: 350),
          () => unawaited(refreshRiskDetails()),
        );
      }
    }
    if (_canReadAccountRisk &&
        _realtimeConnected &&
        !loadingAccountRisk &&
        !(_riskDetailsTimer?.isActive ?? false)) {
      _riskDetailsTimer = Timer(
        const Duration(seconds: 5),
        () => unawaited(refreshRiskDetails()),
      );
    }
  }

  void handleRealtimeMessage(Map<String, dynamic> message) {
    api.instrumentCatalog = instruments;
    message = asMap(
      api.normalizeInstruments(message, asString(message['productLine'])),
    );
    final op = asString(message['op']);
    final channel = asString(message['channel']);
    if (op == 'authenticated' &&
        isLoggedIn &&
        parseInt64(message['userId']) == userId) {
      _privateAuthenticated = true;
      _materializePrivate();
      _scheduleRealtimeNotify();
      return;
    }
    if (op == 'error') {
      lastError = ApiException(
        400,
        jsonEncode({
          'code': message['code'],
          'message': asString(message['error'], fallback: '实时消息暂不可用，请刷新后重试'),
        }),
      ).toString();
      notifyListeners();
      return;
    }
    final product = ProductMode.values
        .where((p) => p.productLine == message['productLine'])
        .firstOrNull;
    if (product == null) return;
    if (op == 'snapshot' ||
        [
          'accountState',
          'orders',
          'triggerOrders',
          'positions',
          'positionRisk',
          'accountRisk',
          'executionReports',
        ].contains(channel)) {
      if (!isLoggedIn || parseInt64(message['userId']) != userId) return;
      final view = privateViews.putIfAbsent(product, PrivateView.new);
      final applied = view.apply(message);
      if (applied || !view.ready) {
        _materializePrivate();
        _subscribePublicSelected();
        _scheduleRealtimeNotify();
      }
      return;
    }
    if (op != 'event') return;
    final envelope = asMap(message['data']);
    final data = asMap(
      envelope.containsKey('value') ? envelope['value'] : envelope,
    );
    final symbol = asString(
      message['symbol'],
      fallback: asString(data['symbol']),
    );
    final instrument = instruments
        .where((i) => i.mode == product && i.symbol == symbol)
        .firstOrNull;
    if (instrument == null) return;
    final result = market.applyPublicEvent(
      message: message,
      instrument: instrument,
      selected: product == mode && symbol == selectedSymbol,
      period: period,
    );
    if (result == MarketUpdate.ignored) return;
    if (instrument.isSpot && instrument.quoteAsset == 'USDT') {
      final price = market.latestPrices[market.key(instrument.mode, symbol)];
      if (price != null && price.isFinite && price > 0) {
        wallet.pricesUsdt[instrument.baseAsset.toUpperCase()] = price;
      }
    }
    if (result == MarketUpdate.markChanged) _materializePrivate();
    _scheduleRealtimeNotify();
  }

  void _requestDepthSnapshot() {
    if (_disposed) return;
    for (final subscription in _publicSubscriptions.values) {
      if (subscription['channel'] == 'depth' &&
          subscription['productLine'] == mode.productLine) {
        realtime.resubscribe(subscription);
      }
    }
  }

  Instrument _instrumentForSymbol(String symbol) {
    return instruments.firstWhere(
      (instrument) => instrument.symbol == symbol && instrument.mode == mode,
      orElse: () => instruments.firstWhere(
        (instrument) => instrument.symbol == symbol,
        orElse: () => Instrument.empty(mode),
      ),
    );
  }

  String _productLineForSymbol(String symbol) {
    return _instrumentForSymbol(symbol).mode.productLine;
  }

  @override
  void dispose() {
    _disposed = true;
    _realtimeAuthRetryTimer?.cancel();
    auth.removeListener(notifyListeners);
    auth.dispose();
    api.dispose();
    market.dispose();
    orders.dispose();
    transfers.dispose();
    wallet.dispose();
    _privateRecovery.dispose();
    presentation.dispose();
    _income.dispose();
    ++_optionReferenceRequest;
    _optionReferenceTimer?.cancel();
    ++_orderTermsRequest;
    ++_accountEpoch;
    ++_valuationVersion;
    ++_riskDetailsVersion;
    ++_selectionVersion;
    ++_instrumentRequestVersion;
    ++_publicRequestVersion;
    orders.invalidateOpenOrders();
    _riskDetailsTimer?.cancel();
    _freshnessTimer?.cancel();
    _announcementRefreshTimer?.cancel();
    _realtimeNotifyTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    _realtimeAuthRetryTimer?.cancel();
    _realtimeGeneration++;
    unawaited(realtime.close());
    super.dispose();
  }
}
