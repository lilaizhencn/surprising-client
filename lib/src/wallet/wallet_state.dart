import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../api.dart';
import '../models.dart';
import '../market_data_state.dart';
import '../session_store.dart';

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

  String? get feeAmount => fee == null ? null : plainNonnegativeDecimal(fee!);
  bool get hasValidFee => fee == null || feeAmount != null;

  String? get minimumAmount {
    final configured = configuredMinimum?.trim();
    if (configured != null) return plainNonnegativeDecimal(configured);
    final precision = decimals;
    if (precision == null || precision < 0 || precision > 36) return null;
    if (precision == 0) return '1';
    return '0.${'0' * (precision - 1)}1';
  }

  String? receivedAmount(String amount) {
    final configuredFee = feeAmount;
    final input = amount.trim();
    if (configuredFee == null ||
        input.length > 256 ||
        !RegExp(r'^(?:0|[1-9]\d*)(?:\.\d+)?$').hasMatch(input)) {
      return null;
    }
    return _subtractDecimal(input, configuredFee);
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

int? _nullableInt(Object? value) {
  final parsed = parseInt64(value);
  return parsed != null && parsed >= 0 && parsed <= 36 ? parsed : null;
}

String? _firstDecimal(Map<String, dynamic> values, List<String> keys) {
  for (final key in keys) {
    if (values[key] == null) continue;
    final value = plainNonnegativeDecimal(asString(values[key]));
    if (value != null) return value;
  }
  return null;
}

// Retain malformed supplied metadata so validation cannot treat it as absent.
String? _decimalMetadata(Map<String, dynamic> values, List<String> keys) {
  for (final key in keys) {
    if (values[key] != null) return asString(values[key]).trim();
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

/// One user's original withdrawal command, retained across account switches.
class PendingWithdrawal {
  const PendingWithdrawal({
    required this.userId,
    required this.key,
    required this.chain,
    required this.symbol,
    required this.toAddress,
    required this.amount,
    this.status = 'PREPARED',
    this.totpRequired = false,
    this.confirmation,
  });
  final int userId;
  final String key, chain, symbol, toAddress, amount, status;
  final bool totpRequired;
  final WithdrawalConfirmation? confirmation;

  PendingWithdrawal withStatus(
    String status, {
    bool? totpRequired,
    WithdrawalConfirmation? confirmation,
  }) => PendingWithdrawal(
    userId: userId,
    key: key,
    chain: chain,
    symbol: symbol,
    toAddress: toAddress,
    amount: amount,
    status: status,
    totpRequired: totpRequired ?? this.totpRequired,
    confirmation: confirmation ?? this.confirmation,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'key': key,
    'chain': chain,
    'symbol': symbol,
    'toAddress': toAddress,
    'amount': amount,
    'status': status,
    'totpRequired': totpRequired,
    if (confirmation case final value?)
      'confirmation': {
        'network': value.network,
        'status': value.status,
        'reference': value.reference,
        'fee': value.fee,
        'receivedAmount': value.receivedAmount,
      },
  };

  factory PendingWithdrawal.fromJson(Map<String, dynamic> json) {
    final userId = requireInt64(json['userId'], 'withdrawal.userId');
    final key = asString(json['key']), chain = asString(json['chain']);
    final symbol = asString(json['symbol']),
        address = asString(json['toAddress']);
    final amount = asString(json['amount']), status = asString(json['status']);
    final normalized = plainNonnegativeDecimal(amount);
    if (userId <= 0 ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(key) ||
        !RegExp(r'^[A-Z0-9_-]{1,32}$').hasMatch(chain) ||
        !RegExp(r'^[A-Z0-9]{1,20}$').hasMatch(symbol) ||
        address.length < 10 ||
        address.length > 256 ||
        RegExp(r'\s').hasMatch(address) ||
        normalized == null ||
        _compareDecimals(normalized, '0') <= 0 ||
        !const {'PREPARED', 'VERIFY', 'UNKNOWN', 'ACCEPTED'}.contains(status)) {
      throw const FormatException('提币恢复资料无效');
    }
    WithdrawalConfirmation? confirmation;
    final raw = json['confirmation'];
    if (raw != null) {
      if (raw is! Map<String, dynamic>) throw const FormatException('提币确认资料无效');
      confirmation = WithdrawalConfirmation(
        chain: chain,
        symbol: symbol,
        toAddress: address,
        amount: amount,
        network: asString(raw['network']),
        status: asString(raw['status']),
        reference: asString(raw['reference']),
        fee: nullableString(raw['fee']),
        receivedAmount: nullableString(raw['receivedAmount']),
      );
    }
    if (confirmation != null &&
        (!RegExp(r'^[A-Z][A-Z0-9_]{0,63}$').hasMatch(confirmation.status) ||
            confirmation.reference.isEmpty ||
            confirmation.reference.length > 128 ||
            confirmation.network.length > 256 ||
            (confirmation.fee != null &&
                plainNonnegativeDecimal(confirmation.fee!) == null) ||
            (confirmation.receivedAmount != null &&
                plainNonnegativeDecimal(confirmation.receivedAmount!) ==
                    null))) {
      throw const FormatException('提币确认资料无效');
    }
    if (status == 'ACCEPTED' && confirmation == null) {
      // Old storage has an accepted marker but no receipt, so stay conservative.
      return PendingWithdrawal(
        userId: userId,
        key: key,
        chain: chain,
        symbol: symbol,
        toAddress: address,
        amount: amount,
        status: 'UNKNOWN',
      );
    }
    return PendingWithdrawal(
      userId: userId,
      key: key,
      chain: chain,
      symbol: symbol,
      toAddress: address,
      amount: amount,
      status: status,
      totpRequired: json['totpRequired'] == true,
      confirmation: confirmation,
    );
  }
}

/// Funding queries, network rules and durable withdrawal lifecycle.
class WalletState {
  WalletState({
    required this.api,
    required this.offline,
    required this.owner,
    required this.market,
    required this.catalog,
    required this.heldAssets,
    required this.settingsStore,
    required this.persist,
    required this.onChanged,
  });
  final ApiClient api;
  final bool offline;
  final ({int? userId, int epoch, String? accessToken}) Function() owner;
  final MarketDataState market;
  final Iterable<Instrument> Function() catalog;
  final Iterable<String> Function() heldAssets;
  final ClientSettingsStore settingsStore;
  final Future<bool> Function({PendingWithdrawal? completed}) persist;
  final void Function() onChanged;

  WalletPortfolio portfolio = WalletPortfolio.empty();
  List<WalletOrderRecord> orders = const [];
  final Map<String, double> pricesUsdt = {};
  WalletDepositAddress? depositAddress;
  bool ready = false, rulesLoading = false, rulesReady = false;
  String? loadError, ordersError;
  List<WithdrawalAssetRule> rules = const [];
  int _portfolioRequest = 0,
      _pricesRequest = 0,
      _depositRequest = 0,
      _rulesRequest = 0;
  bool _closed = false, _restored = false, _totpRequired = false;
  Future<bool>? _restoring;
  final _pending = <int, PendingWithdrawal>{};
  final _inFlight = <int>{};
  ({int? userId, int epoch, String? accessToken})? _feedbackOwner;
  String? _error, _notice;

  bool get restored => _restored;
  List<PendingWithdrawal> get pendingSnapshot =>
      List.unmodifiable(_pending.values);
  PendingWithdrawal? get pending => _pending[owner().userId];
  bool get withdrawalSubmitting => _inFlight.contains(owner().userId);
  bool get withdrawalOutcomeLocked =>
      const {'UNKNOWN', 'ACCEPTED'}.contains(pending?.status);
  bool get withdrawalOutcomeUnknown => pending?.status == 'UNKNOWN';
  bool get withdrawalVerificationRequired => pending?.status == 'VERIFY';
  bool get withdrawalTotpRequired => pending?.totpRequired ?? _totpRequired;
  WithdrawalConfirmation? get withdrawalConfirmation => pending?.confirmation;
  String? get error => _feedbackOwner == owner() ? _error : null;
  String? get notice => _feedbackOwner == owner() ? _notice : null;

  bool _current(({int? userId, int epoch, String? accessToken}) identity) =>
      !_closed && owner() == identity;
  void _feedback(
    ({int? userId, int epoch, String? accessToken}) identity, {
    String? error,
    String? notice,
  }) {
    if (!_current(identity)) return;
    _feedbackOwner = identity;
    _error = error;
    _notice = notice;
    onChanged();
  }

  bool matches(PendingWithdrawal intent) =>
      identical(_pending[intent.userId], intent);
  bool completeSaved(PendingWithdrawal intent) {
    if (!matches(intent)) return false;
    _pending.remove(intent.userId);
    return true;
  }

  Future<bool> _save({PendingWithdrawal? completed}) async {
    try {
      return await persist(completed: completed);
    } catch (_) {
      return false;
    }
  }

  void restoreFrom(Map<String, String> values) {
    if (_restored) return;
    final List<dynamic> rows;
    if (values.containsKey('pendingWithdrawals')) {
      final raw = jsonDecode(values['pendingWithdrawals']!);
      if (raw is! List || raw.length > 128) {
        throw const FormatException('提币恢复资料无效');
      }
      rows = raw;
    } else if ((values['withdrawalKey'] ?? '').isNotEmpty) {
      final parts = (values['withdrawalFingerprint'] ?? '').split('|');
      if (parts.length != 4) throw const FormatException('原提币恢复资料无效');
      // The old unlocked marker cannot prove a request was never sent.
      rows = [
        {
          'userId': values['withdrawalUserId'],
          'key': values['withdrawalKey'],
          'chain': parts[0],
          'symbol': parts[1],
          'toAddress': parts[2],
          'amount': parts[3],
          'status': 'UNKNOWN',
        },
      ];
    } else {
      if (values['withdrawalLocked'] == 'true' ||
          values['withdrawalUnknown'] == 'true') {
        throw const FormatException('原提币恢复资料缺少请求身份');
      }
      rows = const [];
    }
    final restored = <int, PendingWithdrawal>{};
    for (final row in rows) {
      if (row is! Map<String, dynamic>) throw const FormatException('提币恢复资料无效');
      final intent = PendingWithdrawal.fromJson(row);
      if (restored.containsKey(intent.userId)) {
        throw const FormatException('提币恢复资料重复');
      }
      restored[intent.userId] = intent;
    }
    _pending.addAll(restored);
    _restored = true;
  }

  Future<bool> restore() async {
    if (_closed) return false;
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
      if (_closed) return false;
      restoreFrom(values);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Clear account-visible data, never another user's unresolved monetary intent.
  void clearAccountView() {
    ++_portfolioRequest;
    ++_pricesRequest;
    ++_depositRequest;
    ++_rulesRequest;
    portfolio = WalletPortfolio.empty();
    orders = const [];
    pricesUsdt.clear();
    depositAddress = null;
    ready = rulesLoading = rulesReady = _totpRequired = false;
    rules = const [];
    loadError = ordersError = null;
    _feedbackOwner = null;
    _error = _notice = null;
  }

  Future<void> refresh() async {
    final identity = owner(), request = ++_portfolioRequest;
    final id = identity.userId;
    if (_closed || offline || id == null) return;
    bool current() => request == _portfolioRequest && _current(identity);
    ready = false;
    loadError = ordersError = null;
    onChanged();
    try {
      final results = await Future.wait([
        api.walletPortfolio(id),
        api
            .walletOrders(id)
            .then<List<WalletOrderRecord>?>((rows) => rows)
            .catchError((_) => null),
      ]);
      if (!current()) return;
      portfolio = results[0] as WalletPortfolio;
      orders = results[1] as List<WalletOrderRecord>? ?? const [];
      ordersError = results[1] == null ? '资金记录加载失败，请重试' : null;
      await refreshAssetPrices();
      if (current()) ready = true;
    } catch (_) {
      if (current()) loadError = '资金账户加载失败，请重试';
    } finally {
      if (current()) onChanged();
    }
  }

  Future<void> refreshAssetPrices() async {
    if (_closed || offline) return;
    final identity = owner(), request = ++_pricesRequest;
    final assets = {
      ...portfolio.assets
          .where((asset) => asset.totalBalance != 0)
          .map((asset) => asset.symbol.toUpperCase()),
      ...heldAssets().map((asset) => asset.toUpperCase()),
    };
    final prices = await Future.wait(
      assets.map((asset) => _loadAssetPrice(asset, identity)),
    );
    if (request != _pricesRequest || !_current(identity)) return;
    pricesUsdt
      ..clear()
      ..addEntries(prices.whereType<MapEntry<String, double>>());
  }

  Future<MapEntry<String, double>?> _loadAssetPrice(
    String asset,
    ({int? userId, int epoch, String? accessToken}) identity,
  ) async {
    if (asset == 'USDT') return const MapEntry('USDT', 1);
    final instrument = catalog()
        .where(
          (i) =>
              i.isSpot &&
              i.status == 'TRADING' &&
              i.baseAsset.toUpperCase() == asset &&
              i.quoteAsset.toUpperCase() == 'USDT',
        )
        .firstOrNull;
    if (instrument == null) return null;
    final key = market.key(ProductMode.spot, instrument.symbol);
    final cached = market.latestPrices[key];
    if (cached != null && cached.isFinite && cached > 0) {
      return MapEntry(asset, cached);
    }
    try {
      final candles = await api.candles(
        instrument.symbol,
        '1m',
        productLine: 'SPOT',
      );
      if (!_current(identity) || candles.isEmpty) return null;
      final price = candles.last.close;
      if (!price.isFinite || price <= 0) return null;
      market.latestPrices[key] = price;
      return MapEntry(asset, price);
    } catch (_) {
      return null;
    }
  }

  double? portfolioUsdt(WalletPortfolio value) {
    var total = 0.0;
    for (final asset in value.assets) {
      if (asset.totalBalance == 0) continue;
      final price = asset.symbol.toUpperCase() == 'USDT'
          ? 1.0
          : pricesUsdt[asset.symbol.toUpperCase()];
      if (price == null || !price.isFinite || price <= 0) return null;
      total += asset.totalBalance * price;
    }
    return total.isFinite ? total : null;
  }

  Future<void> loadDepositAddress({
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) async {
    if (_closed) return;
    final identity = owner(), request = ++_depositRequest;
    final id = identity.userId;
    if (id == null) {
      _feedback(identity, error: '请先登录再获取充值地址');
      return;
    }
    bool current() => request == _depositRequest && _current(identity);
    try {
      final address = await api.walletDepositAddress(
        id,
        chain: chain,
        symbol: symbol,
        forceNew: forceNew,
      );
      if (!current()) return;
      if (address.chain.toUpperCase() != chain.toUpperCase() ||
          address.symbol.toUpperCase() != symbol.toUpperCase()) {
        throw const FormatException('充值地址资产或网络不匹配');
      }
      depositAddress = address;
      _feedback(identity, notice: forceNew ? '已生成新充值地址' : '充值地址已加载');
      await refresh();
    } catch (error) {
      if (current()) {
        _feedback(identity, error: '获取充值地址失败：${clientErrorMessage(error)}');
      }
    }
  }

  Future<void> refreshWithdrawalRules() async {
    final identity = owner();
    final id = identity.userId;
    if (_closed || offline || id == null || rulesLoading) return;
    final request = ++_rulesRequest;
    bool current() => request == _rulesRequest && _current(identity);
    rulesLoading = true;
    onChanged();
    try {
      final loaded = _rulesFrom(await api.walletChains(id));
      if (!current()) return;
      rules = loaded;
      rulesReady = true;
      _feedback(identity);
    } catch (error) {
      if (!current()) return;
      rules = const [];
      rulesReady = false;
      _feedback(identity, error: '加载提币规则失败：${clientErrorMessage(error)}');
    } finally {
      // A token rotation invalidates the response, but must not leave loading stuck.
      if (request == _rulesRequest && !_closed) {
        rulesLoading = false;
        onChanged();
      }
    }
  }

  WithdrawalAssetRule? withdrawalRuleFor(String chain, String symbol) => rules
      .where(
        (rule) =>
            rule.chain.toUpperCase() == chain.trim().toUpperCase() &&
            rule.symbol.toUpperCase() == symbol.trim().toUpperCase(),
      )
      .firstOrNull;

  String? _available(String symbol) => portfolio.assets
      .where((asset) => asset.symbol.toUpperCase() == symbol.toUpperCase())
      .firstOrNull
      ?.availableAmount;

  String? validateWithdrawal({
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
  }) {
    if (owner().userId == null) return '请先登录再提币';
    if (!rulesReady) return '提币规则暂不可用，请刷新后重试';
    if (!ready) return '可用余额暂不可用，请刷新后重试';
    final currency = symbol.trim().toUpperCase();
    if (chain.trim().isEmpty || currency.isEmpty) return '请选择提币资产和网络';
    final rule = withdrawalRuleFor(chain, currency);
    if (rule == null || !rule.withdrawalEnabled) return '当前网络暂不支持提币';
    if (rule.family.trim().isEmpty) return '网络类型尚未同步，请刷新后重试';
    if (!rule.hasValidFee) return '提币手续费资料暂不可用，请刷新后重试';
    if (rule.configuredMinimum != null && rule.minimumAmount == null) {
      return '最低提币数量资料暂不可用，请刷新后重试';
    }
    final addressError = _validateWithdrawalAddress(toAddress, rule.family);
    if (addressError != null) return addressError;
    final raw = amount.trim();
    if (raw.length > 256) return '请输入有效的提币数量';
    final match = RegExp(r'^(?:0|[1-9]\d*)(?:\.(\d+))?$').firstMatch(raw);
    if (match == null) return '请输入有效的提币数量';
    if (_compareDecimals(raw, '0') <= 0) return '提币数量必须大于 0';
    final precision = rule.decimals;
    if (precision == null || precision < 0 || precision > 36) {
      return '提币精度尚未同步，请刷新后重试';
    }
    if ((match.group(1)?.length ?? 0) > precision) {
      return '$currency 最多支持 $precision 位小数';
    }
    final minimum = rule.minimumAmount;
    if (minimum != null && _compareDecimals(raw, minimum) < 0) {
      return '最低提币数量为 $minimum $currency';
    }
    final available = _available(currency);
    if (available == null) return '可用余额暂不可用，请刷新后重试';
    if (_compareDecimals(raw, available) > 0) return '提币数量超过可用余额';
    final received = rule.receivedAmount(raw);
    if (received != null && _compareDecimals(received, '0') <= 0) {
      return '提币数量必须大于手续费';
    }
    return null;
  }

  String? withdrawalMaximum(String chain, String symbol) {
    final decimals = withdrawalRuleFor(chain, symbol)?.decimals,
        available = _available(symbol);
    if (decimals == null ||
        decimals < 0 ||
        decimals > 36 ||
        available == null) {
      return null;
    }
    final parts = available.split('.'),
        fraction = parts.length == 1 ? '' : parts[1];
    final bounded = fraction.substring(0, math.min(fraction.length, decimals));
    return plainNonnegativeDecimal(
      '${parts.first}${bounded.isEmpty ? '' : '.$bounded'}',
    );
  }

  Future<void> withdrawWallet({
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
    String? emailCode,
    String? totpCode,
  }) async {
    if (_closed) return;
    final identity = owner();
    final id = identity.userId;
    if (id == null) {
      _feedback(identity, error: '请先登录再提币');
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
      _feedback(identity, error: validation);
      return;
    }
    _inFlight.add(id);
    _feedback(identity);
    try {
      if (!await restore()) throw StateError('无法读取原提币凭证，请检查安全存储后重试');
      if (!_current(identity)) return;
      final normalizedChain = chain.trim().toUpperCase(),
          currency = symbol.trim().toUpperCase();
      final address = toAddress.trim(), value = amount.trim();
      final original = _pending[id];
      PendingWithdrawal intent;
      if (original != null) {
        if (!const {'PREPARED', 'VERIFY'}.contains(original.status) ||
            original.chain != normalizedChain ||
            original.symbol != currency ||
            original.toAddress != address ||
            _compareDecimals(original.amount, value) != 0) {
          _feedback(identity, error: '请先核对原提币结果，不能更换原请求');
          return;
        }
        intent = original;
      } else {
        final random = math.Random.secure();
        final entropy = List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        intent = PendingWithdrawal(
          userId: id,
          key: 'app-withdraw-$id-$entropy',
          chain: normalizedChain,
          symbol: currency,
          toAddress: address,
          amount: value,
        );
        _pending[id] = intent;
      }
      if (!await _save()) {
        _feedback(identity, error: '无法安全保存提币幂等凭证，未发送请求，请检查安全存储后重试');
        return;
      }
      if (!_current(identity)) return;
      final prepared = intent;
      intent = intent.withStatus('UNKNOWN');
      _pending[id] = intent;
      // Persist uncertainty before network I/O so a crash cannot enable a second request.
      if (!await _save()) {
        _pending[id] = prepared;
        _feedback(identity, error: '无法安全保存提币幂等凭证，未发送请求，请检查安全存储后重试');
        return;
      }
      if (!_current(identity)) return;
      await _submitWithdrawal(
        intent,
        identity,
        withdrawalRuleFor(normalizedChain, currency),
        emailCode: emailCode,
        totpCode: totpCode,
      );
    } catch (error) {
      _feedback(identity, error: clientErrorMessage(error));
    } finally {
      _inFlight.remove(id);
      if (_current(identity)) onChanged();
    }
  }

  Future<void> _submitWithdrawal(
    PendingWithdrawal intent,
    ({int? userId, int epoch, String? accessToken}) identity,
    WithdrawalAssetRule? rule, {
    String? emailCode,
    String? totpCode,
  }) async {
    try {
      final result = await api.walletWithdraw(
        intent.userId,
        chain: intent.chain,
        symbol: intent.symbol,
        toAddress: intent.toAddress,
        amount: intent.amount,
        idempotencyKey: intent.key,
        emailCode: emailCode,
        totpCode: totpCode,
      );
      if (!matches(intent)) return;
      final status = asString(result['status']).toUpperCase();
      final reference = asString(
        result['withdrawalId'] ?? result['id'] ?? result['orderNo'],
      ).trim();
      if (!RegExp(r'^[A-Z][A-Z0-9_]{0,63}$').hasMatch(status) ||
          reference.isEmpty ||
          reference.length > 128) {
        throw const FormatException('提币确认资料不完整，请核对原请求');
      }
      final confirmation = WithdrawalConfirmation(
        chain: intent.chain,
        network: rule?.network ?? '',
        symbol: intent.symbol,
        toAddress: intent.toAddress,
        amount: intent.amount,
        status: status,
        reference: reference,
        fee:
            _firstDecimal(result, const [
              'fee',
              'withdrawalFee',
              'networkFee',
            ]) ??
            rule?.feeAmount,
        receivedAmount:
            _firstDecimal(result, const [
              'receivedAmount',
              'netAmount',
              'creditedAmount',
            ]) ??
            rule?.receivedAmount(intent.amount),
      );
      _pending[intent.userId] = intent.withStatus(
        'ACCEPTED',
        confirmation: confirmation,
      );
      if (!await _save()) {
        _feedback(identity, error: '提币已受理，但恢复凭证未能保存，请勿重复提交');
        return;
      }
      if (_current(identity)) {
        _totpRequired = false;
        _feedback(identity, notice: '提币请求已受理，编号 $reference');
        await refresh();
      }
    } catch (error) {
      if (!matches(intent)) return;
      if (error is ApiException &&
          error.statusCode == 428 &&
          !error.message.toLowerCase().contains('kyc')) {
        _pending[intent.userId] = intent.withStatus('VERIFY');
        await _save();
        if (_current(identity)) await requestWithdrawalChallenge();
      } else if (_resultUnknown(error)) {
        // Already persisted UNKNOWN before the write; never discard its identity.
        await _save();
        _feedback(identity, error: '提币结果未知，请勿重复提交；请先核对提币记录');
      } else {
        final cleared = await _save(completed: intent);
        if (!cleared || matches(intent)) {
          _pending[intent.userId] = intent.withStatus('PREPARED');
          _feedback(identity, error: '提币未受理，但原凭证未能清除，请检查安全存储');
          return;
        }
        _feedback(
          identity,
          error: error is ApiException && error.statusCode == 428
              ? '提币前需要先完成有效的实名认证'
              : '提币未受理：${clientErrorMessage(error)}',
        );
      }
    }
  }

  Future<void> requestWithdrawalChallenge() async {
    if (_closed) return;
    final identity = owner(), original = pending;
    if (identity.userId == null) return;
    try {
      final responses = await Future.wait([
        api.issueSecurityChallenge('WITHDRAWAL'),
        api.mfaStatus(),
      ]);
      if (!_current(identity)) return;
      final challenge = responses[0],
          mfa = responses[1],
          totp = asMap(responses[1]['totp']);
      _totpRequired =
          mfa['enabled'] == true ||
          totp['bound'] == true ||
          totp['enabled'] == true;
      if (original != null &&
          matches(original) &&
          original.status == 'VERIFY') {
        _pending[original.userId] = original.withStatus(
          'VERIFY',
          totpRequired: _totpRequired,
        );
        await _save();
      }
      final destination = asString(challenge['destination']).trim();
      _feedback(
        identity,
        notice: destination.isEmpty ? '邮箱验证码已发送' : '邮箱验证码已发送至 $destination',
      );
    } catch (error) {
      _feedback(identity, error: '发送提币验证码失败：${clientErrorMessage(error)}');
    }
  }

  Future<void> resetWithdrawalIntent() async {
    if (_closed || withdrawalSubmitting || withdrawalOutcomeUnknown) return;
    final identity = owner(), intent = pending;
    if (intent == null) {
      _feedback(identity);
      return;
    }
    if (!await _save(completed: intent) || matches(intent)) {
      _feedback(identity, error: '无法清除原提币凭证，请检查安全存储');
      return;
    }
    if (_current(identity)) _totpRequired = false;
    _feedback(identity);
  }

  bool _resultUnknown(Object error) =>
      error is! ApiException ||
      error.statusCode < 400 ||
      error.statusCode >= 500 ||
      const {408, 409, 425, 429}.contains(error.statusCode);

  void dispose() {
    _closed = true;
  }

  List<WithdrawalAssetRule> _rulesFrom(List<Map<String, dynamic>> chains) {
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
          configuredMinimum: _decimalMetadata(token, const [
            'minWithdraw',
            'minimumWithdrawal',
            'minimumWithdrawalAmount',
          ]),
          fee: _decimalMetadata(token, const [
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
            configuredMinimum: _decimalMetadata(chain, const [
              'minWithdraw',
              'minimumWithdrawal',
              'minimumWithdrawalAmount',
            ]),
            fee: _decimalMetadata(chain, const [
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
}
