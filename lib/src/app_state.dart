import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'api.dart';
import 'models.dart';
import 'session_store.dart';

class WithdrawalAssetRule {
  const WithdrawalAssetRule({
    required this.chain,
    required this.symbol,
    required this.network,
    required this.family,
    required this.withdrawalEnabled,
    this.decimals,
    this.configuredMinimum,
    this.fee,
  });

  final String chain;
  final String symbol;
  final String network;
  final String family;
  final bool withdrawalEnabled;
  final int? decimals;
  final String? configuredMinimum;
  final String? fee;

  String? get minimumAmount {
    final configured = configuredMinimum?.trim();
    if (configured != null && configured.isNotEmpty) return configured;
    final precision = decimals;
    if (precision == null || precision < 0) return null;
    if (precision == 0) return '1';
    return '0.${'0' * (precision - 1)}1';
  }

  String? receivedAmount(String amount) {
    final configuredFee = fee?.trim();
    if (configuredFee == null || configuredFee.isEmpty) return null;
    return _subtractDecimal(amount, configuredFee);
  }
}

class WithdrawalConfirmation {
  const WithdrawalConfirmation({
    required this.chain,
    required this.network,
    required this.symbol,
    required this.toAddress,
    required this.amount,
    required this.status,
    required this.reference,
    this.fee,
    this.receivedAmount,
  });

  final String chain;
  final String network;
  final String symbol;
  final String toAddress;
  final String amount;
  final String status;
  final String reference;
  final String? fee;
  final String? receivedAmount;
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

int? _nullableInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(asString(value));
}

String? _firstDecimal(Map<String, dynamic> values, List<String> keys) {
  for (final key in keys) {
    final value = values[key];
    if (value == null) continue;
    final normalized = asString(value).trim();
    if (RegExp(r'^\d+(?:\.\d+)?$').hasMatch(normalized)) {
      return normalized;
    }
  }
  return null;
}

String? _validateWithdrawalAddress(String value, String family) {
  final address = value.trim();
  if (address.isEmpty) return '请输入提币地址';
  if (address.length < 10 ||
      address.length > 256 ||
      RegExp(r'\s').hasMatch(address)) {
    return '提币地址格式不正确';
  }
  final normalizedFamily = family.trim().toUpperCase();
  if ((normalizedFamily.contains('EVM') ||
          normalizedFamily == 'ETH' ||
          normalizedFamily == 'BSC') &&
      !RegExp(r'^0x[0-9a-fA-F]{40}$').hasMatch(address)) {
    return '请输入有效的 EVM 地址';
  }
  if (normalizedFamily.contains('BITCOIN') || normalizedFamily == 'BTC') {
    final bech32 = RegExp(
      r'^(?:bc1|tb1|bcrt1)[023456789acdefghjklmnpqrstuvwxyz]{11,87}$',
    );
    final base58 = RegExp(r'^[123mn][1-9A-HJ-NP-Za-km-z]{25,61}$');
    if (!bech32.hasMatch(address.toLowerCase()) && !base58.hasMatch(address)) {
      return '请输入有效的 Bitcoin 地址';
    }
  }
  if (normalizedFamily.contains('TRON') &&
      !RegExp(r'^T[1-9A-HJ-NP-Za-km-z]{33}$').hasMatch(address)) {
    return '请输入有效的 Tron 地址';
  }
  if (normalizedFamily.contains('SOLANA') &&
      !RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(address)) {
    return '请输入有效的 Solana 地址';
  }
  return null;
}

class _DecimalParts {
  const _DecimalParts(this.units, this.scale);

  final BigInt units;
  final int scale;
}

_DecimalParts _decimalParts(String value) {
  final pieces = value.trim().split('.');
  final fraction = pieces.length == 2 ? pieces[1] : '';
  final digits = '${pieces[0]}$fraction';
  return _DecimalParts(BigInt.parse(digits), fraction.length);
}

int _compareDecimals(String left, String right) {
  final leftParts = _decimalParts(left);
  final rightParts = _decimalParts(right);
  final scale = math.max(leftParts.scale, rightParts.scale);
  final leftUnits =
      leftParts.units * BigInt.from(10).pow(scale - leftParts.scale);
  final rightUnits =
      rightParts.units * BigInt.from(10).pow(scale - rightParts.scale);
  return leftUnits.compareTo(rightUnits);
}

String _subtractDecimal(String left, String right) {
  final leftParts = _decimalParts(left);
  final rightParts = _decimalParts(right);
  final scale = math.max(leftParts.scale, rightParts.scale);
  final units =
      leftParts.units * BigInt.from(10).pow(scale - leftParts.scale) -
      rightParts.units * BigInt.from(10).pow(scale - rightParts.scale);
  final negative = units.isNegative;
  final digits = units.abs().toString().padLeft(scale + 1, '0');
  if (scale == 0) return '${negative ? '-' : ''}$digits';
  final integer = digits.substring(0, digits.length - scale);
  final fraction = digits
      .substring(digits.length - scale)
      .replaceFirst(RegExp(r'0+$'), '');
  return '${negative ? '-' : ''}$integer${fraction.isEmpty ? '' : '.$fraction'}';
}

class AppState extends ChangeNotifier {
  AppState({
    this.config = const AppConfig(),
    ApiClient? apiClient,
    RealtimeClient? publicRealtimeClient,
    RealtimeClient? privateRealtimeClient,
    SessionStore? sessionStore,
    ClientSettingsStore? settingsStore,
    this.offline = false,
  }) : api = apiClient ?? ApiClient(config),
       publicRealtime = publicRealtimeClient ?? RealtimeClient(config),
       privateRealtime = privateRealtimeClient ?? RealtimeClient(config),
       sessionStore = sessionStore ?? SecureSessionStore() {
    this.settingsStore = settingsStore ?? SecureClientSettingsStore();
    api.onSessionRefreshed = _persistRefreshedSession;
    api.onSessionExpired = _clearExpiredSession;
    instruments = fallbackInstruments();
    selectedSymbol = instruments.first.symbol;
    orderBook = fallbackOrderBook(instruments.first);
    candles = fallbackCandles();
  }

  final AppConfig config;
  final ApiClient api;
  final RealtimeClient publicRealtime;
  final RealtimeClient privateRealtime;
  final SessionStore sessionStore;
  late final ClientSettingsStore settingsStore;
  final bool offline;

  AuthSession? session;
  AuthSession? pendingVerificationSession;
  AuthSession? pendingBiometricSession;
  bool biometricLoginAvailable = false;
  bool biometricLoginEnabled = false;
  bool biometricLoginUpdating = false;
  late List<Instrument> instruments;
  late String selectedSymbol;
  ProductMode mode = ProductMode.linear;
  String period = '1m';
  late OrderBook orderBook;
  late List<Candle> candles;
  List<ProductBalance> balances = const [];
  List<Position> positions = const [];
  List<OrderModel> openOrders = const [];
  String? openOrdersNextCursor;
  bool openOrdersHasMore = false;
  bool loadingMoreOpenOrders = false;
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
  final Map<String, double> walletAssetPricesUsdt = {};
  ValuationCurrency valuationCurrency = ValuationCurrency.usdt;
  final Map<ValuationCurrency, double> valuationRates = {
    ValuationCurrency.usdt: 1,
  };
  ClientTheme clientTheme = ClientTheme.dark;
  ClientLanguage language = ClientLanguage.zhHans;
  bool valuationLoading = false;
  bool loadingPublic = false;
  bool loadingPrivate = false;
  bool transferSubmitting = false;
  bool transferOutcomeLocked = false;
  bool transferOutcomeTerminalFailure = false;
  bool transferVerificationRequired = false;
  bool withdrawalSubmitting = false;
  bool withdrawalOutcomeLocked = false;
  bool withdrawalOutcomeUnknown = false;
  bool withdrawalVerificationRequired = false;
  bool withdrawalTotpRequired = false;
  bool withdrawalRulesLoading = false;
  bool withdrawalRulesReady = false;
  List<WithdrawalAssetRule> withdrawalRules = const [];
  WithdrawalConfirmation? withdrawalConfirmation;
  String? lastError;
  String? lastNotice;
  final List<String> realtimeLog = [];
  Timer? _realtimeNotifyTimer;
  Timer? _publicReconnectTimer;
  Timer? _privateReconnectTimer;
  int _privateRealtimeGeneration = 0;
  int _publicReconnectAttempts = 0;
  int _privateReconnectAttempts = 0;
  int _openOrdersRequestVersion = 0;
  final Map<int, int> _triggerOrderEventVersions = {};
  String? _transferIdempotencyKey;
  String? _withdrawalIdempotencyKey;
  String? _withdrawalIntentFingerprint;
  int? _withdrawalIntentUserId;

  bool get isLoggedIn => session != null;

  int? get userId => session?.user.userId;

  Instrument get selectedInstrument {
    return _instrumentForSymbol(selectedSymbol);
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
    return offline ? fallbackPriceFor(instrument) : null;
  }

  double? get valuationRate => valuationRates[valuationCurrency];

  double? walletPortfolioUsdt(WalletPortfolio portfolio) {
    var total = 0.0;
    for (final asset in portfolio.assets) {
      if (asset.totalBalance == 0) continue;
      final price = walletAssetPricesUsdt[asset.symbol.toUpperCase()];
      if (price == null || !price.isFinite || price <= 0) return null;
      total += asset.totalBalance * price;
    }
    return total;
  }

  double? productBalancesUsdt() {
    var total = 0.0;
    for (final balance in balances) {
      if (balance.equity == 0) continue;
      final asset = balance.asset.toUpperCase();
      final price = asset == 'USDT' ? 1.0 : walletAssetPricesUsdt[asset];
      if (price == null || !price.isFinite || price <= 0) return null;
      total += balance.equity * price;
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
    await refreshValuation(silent: true);
    notifyListeners();
  }

  Future<void> refreshValuation({bool silent = false}) async {
    if (offline) return;
    valuationLoading = true;
    notifyListeners();
    try {
      final results = await Future.wait([
        api.exchangeRateConversion(
          fromCurrency: 'USDT',
          toCurrency: ValuationCurrency.usd.code,
        ),
        api.exchangeRateConversion(
          fromCurrency: 'USDT',
          toCurrency: ValuationCurrency.cny.code,
        ),
      ]);
      valuationRates
        ..[ValuationCurrency.usdt] = 1
        ..[ValuationCurrency.usd] = results[0]
        ..[ValuationCurrency.cny] = results[1];
      lastError = null;
    } catch (error) {
      if (!silent) lastError = '加载估值汇率失败：$error';
    } finally {
      valuationLoading = false;
      notifyListeners();
    }
  }

  Future<void> bootstrap() async {
    if (offline) return;
    await _restoreSettings();
    await _restoreSession();
    await refreshInstruments(silent: true);
    await refreshValuation(silent: true);
    await refreshPublicData(silent: true);
    await _connectPublicRealtime();
  }

  Future<void> _restoreSettings() async {
    try {
      final values = await settingsStore.read();
      clientTheme = ClientTheme.fromCode(values['theme'] ?? 'dark');
      language = ClientLanguage.fromCode(values['language'] ?? 'zh');
      valuationCurrency = ValuationCurrency.fromCode(
        values['valuationCurrency'] ?? 'USDT',
      );
      _withdrawalIdempotencyKey = _nonEmpty(values['withdrawalKey']);
      _withdrawalIntentFingerprint = _nonEmpty(values['withdrawalFingerprint']);
      _withdrawalIntentUserId = int.tryParse(values['withdrawalUserId'] ?? '');
      withdrawalOutcomeLocked = values['withdrawalLocked'] == 'true';
      withdrawalOutcomeUnknown = values['withdrawalUnknown'] == 'true';
    } catch (_) {
      clientTheme = ClientTheme.dark;
      language = ClientLanguage.zhHans;
      valuationCurrency = ValuationCurrency.usdt;
      _clearWithdrawalIntent();
    }
  }

  void _persistSettings() {
    unawaited(_writeSettings());
  }

  Future<bool> _writeSettings() async {
    try {
      final values = <String, String>{
        'theme': clientTheme.code,
        'language': language.code,
        'valuationCurrency': valuationCurrency.code,
      };
      final withdrawalKey = _withdrawalIdempotencyKey;
      if (withdrawalKey != null) values['withdrawalKey'] = withdrawalKey;
      final withdrawalFingerprint = _withdrawalIntentFingerprint;
      if (withdrawalFingerprint != null) {
        values['withdrawalFingerprint'] = withdrawalFingerprint;
      }
      final withdrawalUserId = _withdrawalIntentUserId;
      if (withdrawalUserId != null) {
        values['withdrawalUserId'] = '$withdrawalUserId';
      }
      if (withdrawalOutcomeLocked) values['withdrawalLocked'] = 'true';
      if (withdrawalOutcomeUnknown) values['withdrawalUnknown'] = 'true';
      await settingsStore.write(values);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _matchWithdrawalIntentOwner(int activeUserId) async {
    final intentUserId = _withdrawalIntentUserId;
    if (intentUserId == null || intentUserId == activeUserId) return;
    _clearWithdrawalIntent();
    await _writeSettings();
  }

  void _clearWithdrawalIntent({bool clearConfirmation = true}) {
    _withdrawalIdempotencyKey = null;
    _withdrawalIntentFingerprint = null;
    _withdrawalIntentUserId = null;
    withdrawalOutcomeLocked = false;
    withdrawalOutcomeUnknown = false;
    withdrawalVerificationRequired = false;
    withdrawalTotpRequired = false;
    if (clearConfirmation) withdrawalConfirmation = null;
  }

  void selectTheme(ClientTheme next) {
    clientTheme = next;
    _persistSettings();
    notifyListeners();
  }

  void selectLanguage(ClientLanguage next) {
    language = next;
    _persistSettings();
    notifyListeners();
  }

  Future<void> _restoreSession() async {
    biometricLoginAvailable = await sessionStore.canUseBiometrics();
    final stored = await sessionStore.readSession();
    if (stored == null) return;
    await _matchWithdrawalIntentOwner(stored.user.userId);
    biometricLoginEnabled = await sessionStore.biometricEnabled();
    if (biometricLoginEnabled) {
      pendingBiometricSession = stored;
      lastNotice = '请使用生物识别解锁交易账户';
      notifyListeners();
      return;
    }
    await _refreshStoredSession(stored);
  }

  Future<void> _refreshStoredSession(AuthSession stored) async {
    if (stored.refreshTokenExpired) {
      await sessionStore.clear();
      return;
    }
    try {
      final refreshed = await api.refresh(stored.refreshToken);
      await _activateSession(refreshed, persist: true);
      lastNotice = '已恢复登录状态';
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        await sessionStore.clear();
        lastError = '登录状态已失效，请重新登录';
      } else {
        lastNotice = '网络暂不可用，登录状态将在连接恢复后重试';
      }
    } catch (_) {
      lastNotice = '网络暂不可用，登录状态将在连接恢复后重试';
    }
  }

  Future<void> _activateSession(
    AuthSession next, {
    required bool persist,
  }) async {
    await _matchWithdrawalIntentOwner(next.user.userId);
    session = next;
    pendingBiometricSession = null;
    api.setSession(next);
    if (persist) await sessionStore.saveSession(next);
    await _connectPrivateRealtime();
    await refreshPrivateData();
  }

  Future<bool> unlockBiometricSession() async {
    final pending = pendingBiometricSession;
    if (pending == null) return false;
    try {
      if (!await sessionStore.authenticateBiometric()) {
        lastError = '生物识别未通过';
        notifyListeners();
        return false;
      }
      await _refreshStoredSession(pending);
      if (session == null) return false;
      lastError = null;
      lastNotice = '生物识别解锁成功';
      notifyListeners();
      return true;
    } catch (error) {
      lastError = '生物识别解锁失败：$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> enableBiometricLogin() async {
    if (session == null || biometricLoginUpdating) return false;
    biometricLoginUpdating = true;
    notifyListeners();
    try {
      await sessionStore.enableBiometric();
      biometricLoginAvailable = true;
      biometricLoginEnabled = true;
      lastError = null;
      lastNotice = '已启用生物识别登录';
      notifyListeners();
      return true;
    } catch (error) {
      lastError = '启用生物识别失败：$error';
      notifyListeners();
      return false;
    } finally {
      biometricLoginUpdating = false;
      notifyListeners();
    }
  }

  Future<bool> disableBiometricLogin() async {
    final active = session;
    if (active == null || !biometricLoginEnabled || biometricLoginUpdating) {
      return false;
    }
    biometricLoginUpdating = true;
    notifyListeners();
    try {
      await sessionStore.clear();
      await sessionStore.saveSession(active);
      biometricLoginEnabled = false;
      pendingBiometricSession = null;
      lastError = null;
      lastNotice = '已关闭生物识别登录';
      notifyListeners();
      return true;
    } catch (error) {
      try {
        biometricLoginEnabled = await sessionStore.biometricEnabled();
      } catch (_) {
        // Keep the last known state if secure storage cannot be read.
      }
      lastError = '关闭生物识别失败：$error';
      notifyListeners();
      return false;
    } finally {
      biometricLoginUpdating = false;
      notifyListeners();
    }
  }

  Future<void> _persistRefreshedSession(AuthSession next) async {
    _privateReconnectTimer?.cancel();
    _privateReconnectTimer = null;
    _privateRealtimeGeneration++;
    session = next;
    api.setSession(next);
    await sessionStore.saveSession(next);
    await privateRealtime.close();
    await _connectPrivateRealtime();
    notifyListeners();
  }

  Future<void> _clearExpiredSession() async {
    _privateReconnectTimer?.cancel();
    _privateReconnectTimer = null;
    _privateRealtimeGeneration++;
    await privateRealtime.close();
    await sessionStore.clear();
    session = null;
    pendingBiometricSession = null;
    biometricLoginEnabled = false;
    api.setSession(null);
    notifyListeners();
  }

  Future<void> refreshInstruments({bool silent = false}) async {
    if (offline) return;
    try {
      final loaded = await api.instruments();
      if (loaded.isNotEmpty) {
        instruments = loaded;
        final candidates = visibleInstruments;
        if (!candidates.any(
          (instrument) => instrument.symbol == selectedSymbol,
        )) {
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
      orderBook = loadedBook;
      final loadedCandles = results[1] as List<Candle>;
      candles = loadedCandles;
      if (candles.isNotEmpty) latestPrices[symbol] = candles.last.close;
      lastError = null;
    } catch (error) {
      if (!offline) {
        orderBook = OrderBook.empty(selectedSymbol);
        candles = const [];
        latestPrices.remove(selectedSymbol);
      }
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
    final openOrdersRequestVersion = ++_openOrdersRequestVersion;
    loadingPrivate = true;
    notifyListeners();
    try {
      final productLine = mode.productLine;
      final accountType = mode.accountType;
      final isDerivativeMode = mode.isDerivative;
      final results = await Future.wait([
        api.productBalances(
          id,
          accountType: accountType,
          productLine: productLine,
        ),
        isDerivativeMode
            ? api.positions(id, productLine: productLine)
            : Future<List<Position>>.value(const []),
        api.openOrders(id, symbol: selectedSymbol, productLine: productLine),
        isDerivativeMode
            ? api.openAlgoOrders(
                id,
                symbol: selectedSymbol,
                productLine: productLine,
              )
            : Future<List<AlgoOrderModel>>.value(const []),
        isDerivativeMode
            ? api.openTriggerOrders(
                id,
                symbol: selectedSymbol,
                productLine: productLine,
              )
            : Future<List<TriggerOrderModel>>.value(const []),
        isDerivativeMode
            ? api.positionMode(id, productLine: productLine)
            : Future<String>.value('ONE_WAY'),
        isDerivativeMode
            ? api.accountRisk(
                id,
                selectedInstrument.settleAsset,
                accountType: accountType,
                productLine: productLine,
              )
            : Future<AccountRisk?>.value(null),
        isDerivativeMode
            ? api.positionRisks(id, productLine: productLine)
            : Future<List<PositionRisk>>.value(const []),
        isDerivativeMode
            ? api.liquidationOrders(id, productLine: productLine)
            : Future<List<LiquidationOrder>>.value(const []),
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
      final openOrdersPage = results[2] as OpenOrdersPage;
      if (openOrdersRequestVersion == _openOrdersRequestVersion) {
        openOrders = openOrdersPage.orders;
        openOrdersNextCursor = openOrdersPage.nextCursor;
        openOrdersHasMore = openOrdersPage.hasMore;
        loadingMoreOpenOrders = false;
      }
      openAlgoOrders = results[3] as List<AlgoOrderModel>;
      openTriggerOrders = results[4] as List<TriggerOrderModel>;
      positionMode = results[5] as String;
      accountRisk = results[6] as AccountRisk?;
      positionRisks = results[7] as List<PositionRisk>;
      liquidationOrders = results[8] as List<LiquidationOrder>;
      walletPortfolio = results[9] as WalletPortfolio;
      walletOrders = results[10] as List<WalletOrderRecord>;
      await refreshWalletAssetPrices();
      lastError = null;
    } catch (error) {
      lastError = '加载账户失败：$error';
    } finally {
      loadingPrivate = false;
      notifyListeners();
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
      if (openOrdersRequestVersion != _openOrdersRequestVersion) return;
      final orderIds = openOrders.map((item) => item.orderId).toSet();
      openOrders = [
        ...openOrders,
        ...nextPage.orders.where((item) => orderIds.add(item.orderId)),
      ];
      openOrdersNextCursor = nextPage.nextCursor;
      openOrdersHasMore = nextPage.hasMore;
      lastError = null;
    } catch (error) {
      if (openOrdersRequestVersion == _openOrdersRequestVersion) {
        lastError = '加载更多委托失败：$error';
      }
    } finally {
      if (openOrdersRequestVersion == _openOrdersRequestVersion) {
        loadingMoreOpenOrders = false;
        notifyListeners();
      }
    }
  }

  Future<AuthSession?> login(String email, String password) async {
    if (offline) return null;
    loadingPrivate = true;
    lastError = null;
    lastNotice = null;
    notifyListeners();
    try {
      final authenticated = await api.login(
        username: email.trim(),
        password: password,
      );
      await _activateSession(authenticated, persist: true);
      lastNotice = '登录成功';
      return authenticated;
    } catch (error) {
      lastError = '登录失败：$error';
      return null;
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<AuthSession?> register(String email, String password) async {
    if (offline) return null;
    loadingPrivate = true;
    lastError = null;
    lastNotice = null;
    notifyListeners();
    try {
      final created = await api.register(
        password: password,
        email: email.trim(),
      );
      api.setSession(created);
      if (created.requiresEmailVerification) {
        pendingVerificationSession = created;
        lastNotice = '注册成功，请先完成邮箱验证';
        return created;
      }
      await _activateSession(created, persist: true);
      lastNotice = '注册成功';
      return session;
    } catch (error) {
      lastError = '注册失败：$error';
      return null;
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<bool> verifyPendingEmail(String code) async {
    final pending = pendingVerificationSession;
    if (pending == null) {
      lastError = '验证会话已失效，请重新注册';
      notifyListeners();
      return false;
    }
    loadingPrivate = true;
    lastError = null;
    lastNotice = null;
    notifyListeners();
    try {
      if (!await api.verifyEmail(pending, code.trim())) {
        throw StateError('验证码无效或已过期');
      }
      await _activateSession(pending, persist: true);
      pendingVerificationSession = null;
      lastNotice = '邮箱验证成功';
      return true;
    } catch (error) {
      lastError = '邮箱验证失败：$error';
      return false;
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<bool> resendPendingEmail() async {
    final pending = pendingVerificationSession;
    if (pending == null) {
      lastError = '验证会话已失效，请重新注册';
      notifyListeners();
      return false;
    }
    try {
      await api.resendEmailVerification(pending);
      lastError = null;
      lastNotice = '新的验证码已发送';
      notifyListeners();
      return true;
    } catch (error) {
      lastError = '验证码发送失败：$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> requestPasswordReset(String identifier) async {
    try {
      await api.forgotPassword(identifier.trim());
      lastError = null;
      lastNotice = '如果该邮箱已注册，验证码已发送';
      notifyListeners();
      return true;
    } catch (error) {
      lastError = '验证码发送失败：$error';
      notifyListeners();
      return false;
    }
  }

  Future<bool> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    try {
      await api.resetPassword(
        identifier: identifier.trim(),
        code: code.trim(),
        newPassword: newPassword,
      );
      lastError = null;
      lastNotice = '密码已更新，请使用新密码登录';
      notifyListeners();
      return true;
    } catch (error) {
      lastError = '密码更新失败：$error';
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    _privateReconnectTimer?.cancel();
    _privateReconnectTimer = null;
    _privateRealtimeGeneration++;
    await privateRealtime.close();
    api.setSession(null);
    await sessionStore.clear();
    session = null;
    _openOrdersRequestVersion++;
    pendingVerificationSession = null;
    pendingBiometricSession = null;
    biometricLoginEnabled = false;
    balances = const [];
    positions = const [];
    openOrders = const [];
    openOrdersNextCursor = null;
    openOrdersHasMore = false;
    loadingMoreOpenOrders = false;
    openAlgoOrders = const [];
    openTriggerOrders = const [];
    _triggerOrderEventVersions.clear();
    positionMode = 'ONE_WAY';
    walletPortfolio = WalletPortfolio.empty();
    walletOrders = const [];
    walletAssetPricesUsdt.clear();
    walletDepositAddress = null;
    accountRisk = null;
    positionRisks = const [];
    liquidationOrders = const [];
    _clearWithdrawalIntent();
    await _writeSettings();
    notifyListeners();
  }

  Future<void> selectMode(ProductMode nextMode) async {
    mode = nextMode;
    final candidates = visibleInstruments;
    if (candidates.isNotEmpty &&
        !candidates.any((instrument) => instrument.symbol == selectedSymbol)) {
      selectedSymbol = candidates.first.symbol;
    }
    orderBook = offline
        ? fallbackOrderBook(selectedInstrument)
        : OrderBook.empty(selectedSymbol);
    candles = offline ? fallbackCandles() : const [];
    notifyListeners();
    await refreshPublicData(silent: true);
    await refreshPrivateData();
    await _reconnectRealtimeForSelectedProduct();
  }

  Future<void> selectSymbol(String symbol) async {
    selectedSymbol = symbol;
    orderBook = offline
        ? fallbackOrderBook(selectedInstrument)
        : OrderBook.empty(selectedSymbol);
    candles = offline ? fallbackCandles() : const [];
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
      positionMode = await api.updatePositionMode(
        id,
        nextMode,
        productLine: mode.productLine,
      );
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
      positionSide: instrument.isSpot || positionMode == 'ONE_WAY'
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
    String? emailCode,
    String? totpCode,
  }) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再划转';
      notifyListeners();
      return;
    }
    if (transferSubmitting || transferOutcomeLocked) return;
    final idempotencyKey = _transferIdempotencyKey ??=
        'app-transfer-$id-${DateTime.now().microsecondsSinceEpoch}';
    transferSubmitting = true;
    lastError = null;
    lastNotice = null;
    notifyListeners();
    try {
      final result = await api.transfer(
        userId: id,
        sourceAccountType: sourceAccountType,
        targetAccountType: targetAccountType,
        asset: asset,
        amountUnits: decimalToUnits(amount),
        idempotencyKey: idempotencyKey,
        emailCode: emailCode,
        totpCode: totpCode,
      );
      final status = asString(
        result['status'],
        fallback: 'UNKNOWN',
      ).toUpperCase();
      final transferId = asString(result['transferId']).trim();
      if (status == 'COMPLETED') {
        _transferIdempotencyKey = null;
        transferVerificationRequired = false;
        lastNotice = '划转已完成${transferId.isEmpty ? '' : '，流水号 $transferId'}';
        await refreshPrivateData();
      } else {
        transferOutcomeLocked = true;
        transferOutcomeTerminalFailure = status == 'FAILED';
        lastError = status == 'FAILED'
            ? '划转未完成${transferId.isEmpty ? '' : '，流水号 $transferId'}，请查看资金记录'
            : '划转处理中${transferId.isEmpty ? '' : '，流水号 $transferId'}，请勿重复提交';
      }
    } catch (error) {
      if (error is ApiException && error.statusCode == 428) {
        transferVerificationRequired = true;
        try {
          final challenge = await api.issueSecurityChallenge('LARGE_TRANSFER');
          lastNotice = '大额划转需要验证，验证码已发送至 ${asString(challenge['destination'])}';
        } catch (_) {
          lastError = '验证码发送失败，请稍后重试';
        }
      } else {
        transferOutcomeLocked = true;
        transferOutcomeTerminalFailure = false;
        lastError =
            error is ApiException &&
                error.statusCode >= 400 &&
                error.statusCode < 500
            ? '划转未完成，请查看资金记录后再决定下一步'
            : '划转结果未知，请勿重复提交，请查看资金记录';
      }
    } finally {
      transferSubmitting = false;
    }
    notifyListeners();
  }

  void resetTransferIntent() {
    if (!transferOutcomeTerminalFailure || transferSubmitting) return;
    _transferIdempotencyKey = null;
    transferOutcomeLocked = false;
    transferOutcomeTerminalFailure = false;
    transferVerificationRequired = false;
    lastError = null;
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
      try {
        withdrawalRules = _withdrawalRulesFrom(await api.walletChains(id));
        withdrawalRulesReady = true;
      } catch (_) {
        withdrawalRules = const [];
        withdrawalRulesReady = false;
      }
      await refreshWalletAssetPrices();
      lastError = null;
    } catch (error) {
      lastError = '加载钱包失败：$error';
    } finally {
      loadingPrivate = false;
      notifyListeners();
    }
  }

  Future<void> refreshWalletAssetPrices() async {
    if (offline) return;
    final assets = walletPortfolio.assets
        .where((asset) => asset.totalBalance != 0)
        .map((asset) => asset.symbol.toUpperCase())
        .toSet();
    if (assets.isEmpty) {
      walletAssetPricesUsdt.clear();
      return;
    }
    final prices = await Future.wait(
      assets.map((asset) => _loadWalletAssetPrice(asset)),
    );
    walletAssetPricesUsdt
      ..clear()
      ..addEntries(prices.whereType<MapEntry<String, double>>());
  }

  Future<MapEntry<String, double>?> _loadWalletAssetPrice(String asset) async {
    if (asset == 'USDT') return const MapEntry<String, double>('USDT', 1);
    Instrument? spotInstrument;
    for (final instrument in instruments) {
      if (instrument.mode == ProductMode.spot &&
          instrument.baseAsset.toUpperCase() == asset &&
          instrument.quoteAsset.toUpperCase() == 'USDT' &&
          instrument.status == 'TRADING') {
        spotInstrument = instrument;
        break;
      }
    }
    if (spotInstrument == null) return null;
    final cached = latestPrices[spotInstrument.symbol];
    if (cached != null && cached.isFinite && cached > 0) {
      return MapEntry(asset, cached);
    }
    try {
      final loaded = await api.candles(
        spotInstrument.symbol,
        '1m',
        productLine: ProductMode.spot.productLine,
      );
      if (loaded.isEmpty || loaded.last.close <= 0) return null;
      final price = loaded.last.close;
      latestPrices[spotInstrument.symbol] = price;
      return MapEntry(asset, price);
    } catch (_) {
      return null;
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

  Future<void> refreshWithdrawalRules() async {
    final id = userId;
    if (offline || id == null || withdrawalRulesLoading) return;
    withdrawalRulesLoading = true;
    notifyListeners();
    try {
      withdrawalRules = _withdrawalRulesFrom(await api.walletChains(id));
      withdrawalRulesReady = true;
      lastError = null;
    } catch (error) {
      withdrawalRules = const [];
      withdrawalRulesReady = false;
      lastError = '加载提币规则失败：$error';
    } finally {
      withdrawalRulesLoading = false;
      notifyListeners();
    }
  }

  WithdrawalAssetRule? withdrawalRuleFor(String chain, String symbol) {
    final normalizedChain = chain.trim().toUpperCase();
    final normalizedSymbol = symbol.trim().toUpperCase();
    for (final rule in withdrawalRules) {
      if (rule.chain.toUpperCase() == normalizedChain &&
          rule.symbol.toUpperCase() == normalizedSymbol) {
        return rule;
      }
    }
    return null;
  }

  String? validateWithdrawal({
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
  }) {
    if (session == null) return '请先登录再提币';
    if (!withdrawalRulesReady) return '提币规则暂不可用，请刷新后重试';
    final normalizedChain = chain.trim().toUpperCase();
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedChain.isEmpty || normalizedSymbol.isEmpty) {
      return '请选择提币资产和网络';
    }
    final rule = withdrawalRuleFor(normalizedChain, normalizedSymbol);
    if (rule != null && !rule.withdrawalEnabled) return '当前网络暂不支持提币';
    final addressError = _validateWithdrawalAddress(
      toAddress,
      rule?.family ?? normalizedChain,
    );
    if (addressError != null) return addressError;

    final rawAmount = amount.trim();
    final match = RegExp(r'^(?:0|[1-9]\d*)(?:\.(\d+))?$').firstMatch(rawAmount);
    if (match == null) return '请输入有效的提币数量';
    if (_compareDecimals(rawAmount, '0') <= 0) {
      return '提币数量必须大于 0';
    }
    final fractionDigits = match.group(1)?.length ?? 0;
    final precision = rule?.decimals;
    if (precision != null && fractionDigits > precision) {
      return '$normalizedSymbol 最多支持 $precision 位小数';
    }
    if (precision == null && fractionDigits > 18) {
      return '提币数量最多支持 18 位小数';
    }
    final minimum = rule?.minimumAmount;
    if (minimum != null && _compareDecimals(rawAmount, minimum) < 0) {
      return '最低提币数量为 $minimum $normalizedSymbol';
    }
    final available = _withdrawalAvailableBalance(
      normalizedChain,
      normalizedSymbol,
    );
    if (available != null &&
        (!available.isFinite ||
            _compareDecimals(rawAmount, available.toString()) > 0)) {
      return '提币数量超过可用余额';
    }
    final received = rule?.receivedAmount(rawAmount);
    if (received != null && _compareDecimals(received, '0') <= 0) {
      return '提币数量必须大于手续费';
    }
    return null;
  }

  Future<void> withdrawWallet({
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
    String? emailCode,
    String? totpCode,
  }) async {
    final id = userId;
    if (id == null) {
      lastError = '请先登录再提币';
      notifyListeners();
      return;
    }
    if (withdrawalSubmitting || withdrawalOutcomeLocked) return;
    final validation = validateWithdrawal(
      chain: chain,
      symbol: symbol,
      toAddress: toAddress,
      amount: amount,
    );
    if (validation != null) {
      lastError = validation;
      notifyListeners();
      return;
    }
    final normalizedChain = chain.trim().toUpperCase();
    final normalizedSymbol = symbol.trim().toUpperCase();
    final normalizedAddress = toAddress.trim();
    final normalizedAmount = amount.trim();
    final fingerprint = [
      normalizedChain,
      normalizedSymbol,
      normalizedAddress,
      normalizedAmount,
    ].join('|');
    if (_withdrawalIntentUserId != id ||
        (_withdrawalIntentFingerprint != null &&
            _withdrawalIntentFingerprint != fingerprint)) {
      _clearWithdrawalIntent();
    }
    _withdrawalIntentUserId = id;
    _withdrawalIntentFingerprint = fingerprint;
    final idempotencyKey = _withdrawalIdempotencyKey ??=
        _newWithdrawalIdempotencyKey(id);
    if (!await _writeSettings()) {
      _clearWithdrawalIntent();
      lastError = '无法安全保存提币幂等凭证，请检查安全存储后重试';
      notifyListeners();
      return;
    }
    withdrawalSubmitting = true;
    lastError = null;
    lastNotice = null;
    notifyListeners();
    try {
      final result = await api.walletWithdraw(
        id,
        chain: normalizedChain,
        symbol: normalizedSymbol,
        toAddress: normalizedAddress,
        amount: normalizedAmount,
        idempotencyKey: idempotencyKey,
        emailCode: emailCode,
        totpCode: totpCode,
      );
      final status = asString(
        result['status'],
        fallback: 'PENDING',
      ).toUpperCase();
      final reference = asString(
        result['withdrawalId'] ?? result['id'] ?? result['orderNo'],
      ).trim();
      final rule = withdrawalRuleFor(normalizedChain, normalizedSymbol);
      final fee =
          _firstDecimal(result, const ['fee', 'withdrawalFee', 'networkFee']) ??
          rule?.fee;
      final received =
          _firstDecimal(result, const [
            'receivedAmount',
            'netAmount',
            'creditedAmount',
          ]) ??
          rule?.receivedAmount(normalizedAmount);
      withdrawalConfirmation = WithdrawalConfirmation(
        chain: normalizedChain,
        network: rule?.network ?? '',
        symbol: normalizedSymbol,
        toAddress: normalizedAddress,
        amount: normalizedAmount,
        status: status,
        reference: reference,
        fee: fee,
        receivedAmount: received,
      );
      withdrawalOutcomeLocked = true;
      withdrawalOutcomeUnknown = false;
      withdrawalVerificationRequired = false;
      withdrawalTotpRequired = false;
      await _writeSettings();
      lastNotice = '提币请求已受理${reference.isEmpty ? '' : '，编号 $reference'}';
      await refreshWallet();
    } catch (error) {
      if (error is ApiException && error.statusCode == 428) {
        if (error.message.toLowerCase().contains('kyc')) {
          _clearWithdrawalIntent();
          await _writeSettings();
          lastError = '提币前需要先完成有效的实名认证';
        } else {
          withdrawalVerificationRequired = true;
          await requestWithdrawalChallenge();
        }
      } else if (_withdrawalResultIsUnknown(error)) {
        withdrawalOutcomeLocked = true;
        withdrawalOutcomeUnknown = true;
        await _writeSettings();
        lastError = '提币结果未知，请勿重复提交；请先核对提币记录';
      } else {
        _clearWithdrawalIntent();
        await _writeSettings();
        lastError = '提币未受理：$error';
      }
    } finally {
      withdrawalSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> requestWithdrawalChallenge() async {
    if (session == null) return;
    try {
      final responses = await Future.wait([
        api.issueSecurityChallenge('WITHDRAWAL'),
        api.mfaStatus(),
      ]);
      final challenge = responses[0];
      final mfa = responses[1];
      final totp = asMap(mfa['totp']);
      withdrawalTotpRequired =
          mfa['enabled'] == true ||
          totp['bound'] == true ||
          totp['enabled'] == true;
      lastError = null;
      final destination = asString(challenge['destination']).trim();
      lastNotice = destination.isEmpty ? '邮箱验证码已发送' : '邮箱验证码已发送至 $destination';
    } catch (error) {
      lastError = '发送提币验证码失败：$error';
    }
    notifyListeners();
  }

  Future<void> resetWithdrawalIntent() async {
    if (withdrawalSubmitting || withdrawalOutcomeUnknown) return;
    _clearWithdrawalIntent();
    lastError = null;
    lastNotice = null;
    await _writeSettings();
    notifyListeners();
  }

  double? _withdrawalAvailableBalance(String chain, String symbol) {
    for (final asset in walletPortfolio.assets) {
      if (asset.symbol.toUpperCase() != symbol) continue;
      for (final item in asset.chains) {
        if (item.chain.toUpperCase() == chain) return item.availableBalance;
      }
      return asset.availableBalance;
    }
    return null;
  }

  List<WithdrawalAssetRule> _withdrawalRulesFrom(
    List<Map<String, dynamic>> chains,
  ) {
    final rules = <String, WithdrawalAssetRule>{};
    for (final chain in chains) {
      final chainCode = asString(chain['chain']).trim().toUpperCase();
      if (chainCode.isEmpty) continue;
      final network = asString(chain['network']).trim();
      final family = asString(chain['family']).trim();
      final enabled =
          chain['withdrawalEnabled'] == true ||
          chain['withdrawEnabled'] == true;
      final tokens = asList(chain['tokens']).map(asMap).toList();
      for (final token in tokens) {
        final symbol = asString(token['symbol']).trim().toUpperCase();
        if (symbol.isEmpty) continue;
        rules['$chainCode/$symbol'] = WithdrawalAssetRule(
          chain: chainCode,
          symbol: symbol,
          network: network,
          family: family,
          withdrawalEnabled: enabled && token['platformEnabled'] != false,
          decimals: _nullableInt(token['decimals']),
          configuredMinimum: _firstDecimal(token, const [
            'minWithdraw',
            'minimumWithdrawal',
            'minimumWithdrawalAmount',
          ]),
          fee: _firstDecimal(token, const [
            'withdrawalFee',
            'withdrawFee',
            'networkFee',
          ]),
        );
      }
      final assetSymbols = <String>{
        ...asList(chain['assetSymbols'])
            .map(asString)
            .map((value) => value.trim().toUpperCase())
            .where((value) => value.isNotEmpty),
        asString(chain['nativeSymbol']).trim().toUpperCase(),
      };
      for (final symbol in assetSymbols.where((value) => value.isNotEmpty)) {
        rules.putIfAbsent(
          '$chainCode/$symbol',
          () => WithdrawalAssetRule(
            chain: chainCode,
            symbol: symbol,
            network: network,
            family: family,
            withdrawalEnabled: enabled,
            decimals: _nullableInt(
              symbol == asString(chain['nativeSymbol']).trim().toUpperCase()
                  ? chain['nativeDecimals'] ?? chain['decimals']
                  : null,
            ),
            configuredMinimum: _firstDecimal(chain, const [
              'minWithdraw',
              'minimumWithdrawal',
              'minimumWithdrawalAmount',
            ]),
            fee: _firstDecimal(chain, const [
              'withdrawalFee',
              'withdrawFee',
              'networkFee',
            ]),
          ),
        );
      }
    }
    return rules.values.toList(growable: false);
  }

  bool _withdrawalResultIsUnknown(Object error) {
    if (error is! ApiException) return true;
    return error.statusCode == 408 || error.statusCode >= 500;
  }

  String _newWithdrawalIdempotencyKey(int id) {
    final random = math.Random.secure();
    final entropy = List<int>.generate(16, (_) => random.nextInt(256));
    final encoded = entropy
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'app-withdraw-$id-$encoded';
  }

  Future<void> _connectPublicRealtime() async {
    if (config.websocketUrl.trim().isEmpty) return;
    try {
      await publicRealtime.connect(
        onEvent: handleRealtimeMessage,
        onError: (error) {
          _recordRealtimeIssue('公共行情 WebSocket：$error');
          notifyListeners();
        },
        onDone: _schedulePublicReconnect,
      );
      _publicReconnectAttempts = 0;
      _subscribePublicSelected();
    } catch (error) {
      _recordRealtimeIssue('实时行情连接失败：$error');
      notifyListeners();
      _schedulePublicReconnect();
    }
  }

  Future<void> _connectPrivateRealtime() async {
    if (config.websocketUrl.trim().isEmpty) return;
    final connectGeneration = ++_privateRealtimeGeneration;
    final current = session;
    if (current == null) return;
    try {
      await privateRealtime.connect(
        userId: current.user.userId,
        accessToken: current.accessToken,
        onEvent: (message) {
          if (connectGeneration != _privateRealtimeGeneration ||
              current.accessToken != session?.accessToken) {
            return;
          }
          handleRealtimeMessage(message);
        },
        onError: (error) {
          if (connectGeneration != _privateRealtimeGeneration ||
              current.accessToken != session?.accessToken) {
            return;
          }
          _recordRealtimeIssue('账户 WebSocket：$error');
          notifyListeners();
        },
        onDone: () => _schedulePrivateReconnect(connectGeneration),
      );
      if (connectGeneration != _privateRealtimeGeneration ||
          current.accessToken != session?.accessToken) {
        return;
      }
      _privateReconnectAttempts = 0;
      _subscribePrivateSelected();
    } catch (error) {
      if (connectGeneration != _privateRealtimeGeneration ||
          current.accessToken != session?.accessToken) {
        return;
      }
      _recordRealtimeIssue('账户实时连接失败：$error');
      notifyListeners();
      _schedulePrivateReconnect(connectGeneration);
    }
  }

  void _recordRealtimeIssue(String message) {
    realtimeLog.insert(0, message);
    if (realtimeLog.length > 20) realtimeLog.removeLast();
  }

  void _schedulePublicReconnect() {
    if (offline || (_publicReconnectTimer?.isActive ?? false)) return;
    _publicReconnectAttempts++;
    _publicReconnectTimer = Timer(
      _reconnectDelay(_publicReconnectAttempts),
      () async {
        _publicReconnectTimer = null;
        await _connectPublicRealtime();
        await refreshPublicData(silent: true);
      },
    );
  }

  void _schedulePrivateReconnect([int? expectedGeneration]) {
    if (expectedGeneration != null &&
        expectedGeneration != _privateRealtimeGeneration) {
      return;
    }
    if (offline || !isLoggedIn || (_privateReconnectTimer?.isActive ?? false)) {
      return;
    }
    final reconnectGeneration = _privateRealtimeGeneration;
    _privateReconnectAttempts++;
    _privateReconnectTimer = Timer(
      _reconnectDelay(_privateReconnectAttempts),
      () async {
        _privateReconnectTimer = null;
        if (reconnectGeneration != _privateRealtimeGeneration || !isLoggedIn) {
          return;
        }
        await _connectPrivateRealtime();
        await refreshPrivateData();
      },
    );
  }

  Duration _reconnectDelay(int attempt) {
    final capped = attempt < 1 ? 1 : (attempt > 4 ? 4 : attempt);
    final seconds = 1 << (capped - 1);
    return Duration(seconds: seconds);
  }

  Future<void> _reconnectRealtimeForSelectedProduct() async {
    if (offline) return;
    await publicRealtime.close();
    await _connectPublicRealtime();
    _privateRealtimeGeneration++;
    await privateRealtime.close();
    await _connectPrivateRealtime();
  }

  void _subscribePublicSelected() {
    final selectedProductLine = _productLineForSymbol(selectedSymbol);
    final instrumentsBySymbol = <String, Instrument>{
      selectedSymbol: selectedInstrument,
      for (final instrument in visibleInstruments)
        instrument.symbol: instrument,
    };
    for (final entry in instrumentsBySymbol.entries) {
      publicRealtime.subscribe(
        'trades',
        symbol: entry.key,
        productLine: entry.value.mode.productLine,
      );
    }
    publicRealtime.subscribe(
      'depth',
      symbol: selectedSymbol,
      productLine: selectedProductLine,
    );
    publicRealtime.subscribe(
      'candles',
      symbol: selectedSymbol,
      period: period,
      productLine: selectedProductLine,
    );
  }

  void _subscribePrivateSelected() {
    if (!isLoggedIn) return;
    final productLine = _productLineForSymbol(selectedSymbol);
    final instrument = _instrumentForSymbol(selectedSymbol);
    privateRealtime.subscribe(
      'orders',
      symbol: selectedSymbol,
      productLine: productLine,
    );
    privateRealtime.subscribe(
      'matches',
      symbol: selectedSymbol,
      productLine: productLine,
    );
    privateRealtime.subscribe(
      'executionReports',
      symbol: selectedSymbol,
      productLine: productLine,
    );
    if (!instrument.isDerivative) return;
    privateRealtime.subscribe(
      'triggerOrders',
      symbol: selectedSymbol,
      productLine: productLine,
    );
    privateRealtime.subscribe(
      'positions',
      symbol: selectedSymbol,
      productLine: productLine,
    );
    privateRealtime.subscribe(
      'positionRisk',
      symbol: selectedSymbol,
      productLine: productLine,
    );
    privateRealtime.subscribe('accountRisk', productLine: productLine);
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
    final messageProductLine = asString(
      message['productLine'],
      fallback: asString(data['productLine']),
    );
    if (messageProductLine.isEmpty ||
        messageProductLine != _productLineForSymbol(symbol)) {
      return;
    }
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
    } else if (channel == 'triggerOrders') {
      final eventId = asInt(data['eventId']);
      final orderData = asMap(data['order']);
      final order = TriggerOrderModel.fromJson(orderData);
      final previousEventId =
          _triggerOrderEventVersions[order.triggerOrderId] ?? 0;
      if (eventId > previousEventId) {
        _triggerOrderEventVersions[order.triggerOrderId] = eventId;
        _upsertTriggerOrder(order);
      }
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
      (instrument) => instrument.symbol == symbol && instrument.mode == mode,
      orElse: () => instruments.firstWhere(
        (instrument) => instrument.symbol == symbol,
        orElse: () => fallbackInstruments().first,
      ),
    );
  }

  String _productLineForSymbol(String symbol) {
    return _instrumentForSymbol(symbol).mode.productLine;
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
    _publicReconnectTimer?.cancel();
    _privateReconnectTimer?.cancel();
    _privateRealtimeGeneration++;
    unawaited(publicRealtime.close());
    unawaited(privateRealtime.close());
    super.dispose();
  }
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
