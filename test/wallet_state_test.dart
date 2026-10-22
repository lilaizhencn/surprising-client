import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/market_data_state.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/wallet/wallet_state.dart';

const _address = '0x1111111111111111111111111111111111111111';
WalletPortfolio _portfolio(String amount) => WalletPortfolio.fromJson({
  'assets': [
    {
      'symbol': 'USDT',
      'availableBalance': amount,
      'lockedBalance': '0',
      'totalBalance': amount,
    },
  ],
});
const _rule = WithdrawalAssetRule(
  chain: 'ETH',
  symbol: 'USDT',
  network: 'Ethereum',
  family: 'EVM',
  withdrawalEnabled: true,
  decimals: 6,
  configuredMinimum: '0.1',
  fee: '0',
);

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  final history = <String>[];
  bool failWrites = false;
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> next) async {
    if (failWrites) throw StateError('storage unavailable');
    values = {...next};
    history.add(jsonEncode(next));
  }
}

class _Api extends ApiClient {
  _Api(this.settings) : super(const AppConfig());
  final _Settings settings;
  final requests = <Map<String, dynamic>>[];
  int challenges = 0;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) withdrawReply =
      (_) async => {'withdrawalId': 'withdrawal-1', 'status': 'PENDING'};
  Future<Map<String, dynamic>> Function() challengeReply = () async => {
    'destination': 'test-only',
  };
  Future<Map<String, dynamic>> Function() mfaReply = () async => {
    'enabled': true,
  };
  Future<WalletPortfolio> Function(int) portfolioReply = (_) async =>
      _portfolio('12.5');
  Future<WalletDepositAddress> Function(String, String)? depositReply;
  Future<List<Map<String, dynamic>>> Function()? chainsReply;

  @override
  Future<Map<String, dynamic>> walletWithdraw(
    int userId, {
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
    required String idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) {
    final rows = jsonDecode(settings.values['pendingWithdrawals']!) as List;
    final stored = rows.where((row) => row['userId'] == userId).single;
    expect(stored['status'], 'UNKNOWN');
    expect(stored['key'], idempotencyKey);
    expect(stored['amount'], amount);
    final request = {
      'userId': userId,
      'chain': chain,
      'symbol': symbol,
      'toAddress': toAddress,
      'amount': amount,
      'key': idempotencyKey,
      'emailCode': emailCode,
      'totpCode': totpCode,
    };
    requests.add(request);
    return withdrawReply(request);
  }

  @override
  Future<Map<String, dynamic>> issueSecurityChallenge(String sceneCode) {
    expect(sceneCode, 'WITHDRAWAL');
    challenges++;
    return challengeReply();
  }

  @override
  Future<Map<String, dynamic>> mfaStatus() => mfaReply();
  @override
  Future<WalletPortfolio> walletPortfolio(
    int userId, {
    bool hideZero = false,
  }) => portfolioReply(userId);
  @override
  Future<List<WalletOrderRecord>> walletOrders(
    int userId, {
    int limit = 30,
  }) async => [];
  @override
  Future<WalletDepositAddress> walletDepositAddress(
    int userId, {
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) => depositReply!(chain, symbol);
  @override
  Future<List<Map<String, dynamic>>> walletChains(int userId) => chainsReply!();
}

class _Fixture {
  _Fixture({this.offline = true, _Settings? settings})
    : settings = settings ?? _Settings();
  final bool offline;
  final _Settings settings;
  int? userId = 7;
  int epoch = 0, notifications = 0;
  String? token = 'original';
  final market = MarketDataState();
  late final api = _Api(settings);
  late final wallet = WalletState(
    api: api,
    offline: offline,
    owner: () => (userId: userId, epoch: epoch, accessToken: token),
    market: market,
    catalog: () => const [],
    heldAssets: () => const [],
    settingsStore: settings,
    persist: persist,
    onChanged: () {
      notifications++;
    },
  );
  Future<void> _tail = Future.value();
  Future<bool> persist({PendingWithdrawal? completed}) async {
    final previous = _tail, done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (completed != null && !wallet.matches(completed)) return false;
      if (!wallet.restored && !await wallet.restore()) return false;
      await settings.write({
        'theme': 'dark',
        'pendingWithdrawals': jsonEncode(
          wallet.pendingSnapshot
              .where((intent) => !identical(intent, completed))
              .map((intent) => intent.toJson())
              .toList(),
        ),
      });
      return completed == null || wallet.completeSaved(completed);
    } catch (_) {
      return false;
    } finally {
      done.complete();
    }
  }

  void seed() {
    wallet
      ..ready = true
      ..portfolio = _portfolio('12.5')
      ..rulesReady = true
      ..rules = [_rule];
  }

  Future<void> send({
    String amount = '1',
    String address = _address,
    String? emailCode,
    String? totpCode,
  }) => wallet.withdrawWallet(
    chain: 'ETH',
    symbol: 'USDT',
    toAddress: address,
    amount: amount,
    emailCode: emailCode,
    totpCode: totpCode,
  );
  void dispose() {
    wallet.dispose();
    market.dispose();
    api.dispose();
  }
}

void main() {
  test(
    '428 verification persists one original command without storing security codes',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      f.api.withdrawReply = (_) async =>
          throw ApiException(428, 'verification required');
      await f.send();
      expect(f.wallet.withdrawalVerificationRequired, isTrue);
      expect(f.wallet.withdrawalTotpRequired, isTrue);
      final key = f.wallet.pending!.key;
      await f.send(amount: '2');
      expect(f.api.requests, hasLength(1));
      expect(f.wallet.error, contains('原提币'));
      f.api.withdrawReply = (_) async => {
        'withdrawalId': 'withdrawal-2',
        'status': 'PENDING',
        'fee': '0.01',
        'netAmount': '0.99',
      };
      await f.send(emailCode: '123456', totpCode: '654321');
      expect(f.api.requests.map((row) => row['key']).toSet(), {key});
      expect(f.wallet.withdrawalConfirmation!.receivedAmount, '0.99');
      expect(f.wallet.withdrawalOutcomeLocked, isTrue);
      expect(f.settings.history.join(), isNot(contains('123456')));
      expect(f.settings.history.join(), isNot(contains('654321')));
    },
  );

  test(
    'unknown result survives restart and neither submit nor reset can forget it',
    () async {
      final settings = _Settings();
      final original = _Fixture(settings: settings)..seed();
      original.api.withdrawReply = (_) async =>
          throw const SocketException('reply lost');
      await original.send();
      final key = original.wallet.pending!.key;
      original.dispose();
      final restarted = _Fixture(settings: settings)..seed();
      addTearDown(restarted.dispose);
      expect(await restarted.wallet.restore(), isTrue);
      expect(restarted.wallet.withdrawalOutcomeUnknown, isTrue);
      await restarted.send();
      await restarted.wallet.resetWithdrawalIntent();
      expect(restarted.api.requests, isEmpty);
      expect(restarted.wallet.pending!.key, key);
      expect(
        jsonDecode(settings.values['pendingWithdrawals']!).single['key'],
        key,
      );
    },
  );

  test(
    'failure to save an original intent sends no write and retains its identity',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      f.settings.failWrites = true;
      await f.send();
      expect(f.api.requests, isEmpty);
      expect(f.wallet.error, contains('未发送'));
      final key = f.wallet.pending!.key;
      f.settings.failWrites = false;
      await f.send();
      expect(f.api.requests.single['key'], key);
    },
  );

  test(
    'late withdrawal success is durable for its owner and never updates the next account',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      final result = Completer<Map<String, dynamic>>();
      f.api.withdrawReply = (_) => result.future;
      final submitting = f.send();
      while (f.api.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final key = f.wallet.pending!.key;
      f.userId = 8;
      f.epoch++;
      f.token = 'next-user';
      f.wallet.clearAccountView();
      f.seed();
      final notifications = f.notifications;
      result.complete({'withdrawalId': 'owner-7-only', 'status': 'PENDING'});
      await submitting;
      expect(f.wallet.withdrawalConfirmation, isNull);
      expect(f.wallet.pending, isNull);
      expect(f.wallet.error, isNull);
      expect(f.wallet.notice, isNull);
      expect(f.notifications, notifications);
      expect(f.wallet.pendingSnapshot.single.key, key);
      expect(f.wallet.pendingSnapshot.single.status, 'ACCEPTED');
      f.userId = 7;
      f.epoch++;
      f.token = 'return-user';
      expect(f.wallet.withdrawalConfirmation!.reference, 'owner-7-only');
    },
  );

  test(
    'late security challenge cannot enable verification or reveal destination for another owner',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      final challenge = Completer<Map<String, dynamic>>();
      f.api.withdrawReply = (_) async =>
          throw ApiException(428, 'verification required');
      f.api.challengeReply = () => challenge.future;
      final submitting = f.send();
      while (f.api.challenges == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      f.userId = 8;
      f.epoch++;
      f.token = 'next-user';
      f.wallet.clearAccountView();
      final notifications = f.notifications;
      challenge.complete({'destination': 'previous-private-email'});
      await submitting;
      expect(f.wallet.withdrawalTotpRequired, isFalse);
      expect(f.wallet.notice, isNull);
      expect(f.notifications, notifications);
      expect(f.wallet.pendingSnapshot.single.status, 'VERIFY');
    },
  );

  test(
    'old unknown commands coexist with a second account and are never erased by switching',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      f.api.withdrawReply = (_) async => throw StateError('offline');
      await f.send();
      final originalKey = f.wallet.pending!.key;
      f.userId = 8;
      f.epoch++;
      f.token = 'next';
      f.wallet.clearAccountView();
      f.seed();
      f.api.withdrawReply = (_) async => {
        'withdrawalId': 'next-receipt',
        'status': 'PENDING',
      };
      await f.send();
      expect(f.wallet.pendingSnapshot, hasLength(2));
      await f.wallet.resetWithdrawalIntent();
      expect(f.wallet.pending, isNull);
      expect(f.wallet.pendingSnapshot.single.key, originalKey);
      expect(
        jsonDecode(f.settings.values['pendingWithdrawals']!).single['userId'],
        7,
      );
    },
  );

  test(
    'legacy single-user receipts migrate conservatively without generating a new key',
    () async {
      final settings = _Settings()
        ..values = {
          'withdrawalKey': 'app-withdraw-7-legacy',
          'withdrawalUserId': '7',
          'withdrawalFingerprint': 'ETH|USDT|$_address|1.00',
        };
      final f = _Fixture(settings: settings)..seed();
      addTearDown(f.dispose);
      expect(await f.wallet.restore(), isTrue);
      expect(f.wallet.pending!.key, 'app-withdraw-7-legacy');
      expect(f.wallet.pending!.amount, '1.00');
      expect(f.wallet.withdrawalOutcomeUnknown, isTrue);
      await f.persist();
      expect(settings.values.containsKey('withdrawalKey'), isFalse);
      expect(
        jsonDecode(settings.values['pendingWithdrawals']!).single['key'],
        'app-withdraw-7-legacy',
      );
    },
  );

  test(
    'corrupt withdrawal recovery blocks destructive saves and network writes',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      f.settings.values['pendingWithdrawals'] = '[{"userId":7}]';
      await f.send();
      expect(f.api.requests, isEmpty);
      expect(f.wallet.pendingSnapshot, isEmpty);
      expect(f.wallet.error, contains('读取原提币凭证'));
      expect(f.settings.values['pendingWithdrawals'], '[{"userId":7}]');
    },
  );

  test(
    'ambiguous 409 and malformed success stay unknown and cannot be replayed',
    () async {
      for (final failure in [
        ApiException(409, 'receipt unknown'),
        <String, dynamic>{'status': 'PENDING'},
      ]) {
        final f = _Fixture()..seed();
        try {
          f.api.withdrawReply = (_) async {
            if (failure is Exception) throw failure;
            return failure as Map<String, dynamic>;
          };
          await f.send();
          await f.send();
          await f.wallet.resetWithdrawalIntent();
          expect(f.api.requests, hasLength(1));
          expect(f.wallet.withdrawalOutcomeUnknown, isTrue);
        } finally {
          f.dispose();
        }
      }
    },
  );

  test(
    'definitive rejection clears only after durable removal and allows a new command',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      f.api.withdrawReply = (_) async =>
          throw ApiException(422, 'invalid destination');
      await f.send();
      expect(f.wallet.pending, isNull);
      expect(jsonDecode(f.settings.values['pendingWithdrawals']!), isEmpty);
    },
  );

  test(
    'dispose prevents late withdrawal callbacks while preserving accepted receipt',
    () async {
      final f = _Fixture()..seed();
      addTearDown(f.dispose);
      final result = Completer<Map<String, dynamic>>();
      f.api.withdrawReply = (_) => result.future;
      final submitting = f.send();
      while (f.api.requests.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final notifications = f.notifications;
      f.wallet.dispose();
      result.complete({
        'withdrawalId': 'accepted-before-shutdown',
        'status': 'PENDING',
      });
      await submitting;
      expect(f.notifications, notifications);
      expect(f.wallet.pendingSnapshot.single.status, 'ACCEPTED');
    },
  );

  test(
    'portfolio and deposit responses check epoch/token and never overwrite a newer owner',
    () async {
      final f = _Fixture(offline: false);
      addTearDown(f.dispose);
      final oldPortfolio = Completer<WalletPortfolio>();
      f.api.portfolioReply = (userId) =>
          userId == 7 ? oldPortfolio.future : Future.value(_portfolio('8'));
      final original = f.wallet.refresh();
      f.userId = 8;
      f.epoch++;
      f.token = 'next';
      f.wallet.clearAccountView();
      await f.wallet.refresh();
      oldPortfolio.complete(_portfolio('777'));
      await original;
      expect(f.wallet.portfolio.assets.single.availableAmount, '8');
      final address = Completer<WalletDepositAddress>();
      f.api.depositReply = (_, _) => address.future;
      final loading = f.wallet.loadDepositAddress(chain: 'ETH', symbol: 'USDT');
      f.token = 'rotated';
      address.complete(
        WalletDepositAddress.fromJson({
          'chain': 'ETH',
          'symbol': 'USDT',
          'address': _address,
        }),
      );
      await loading;
      expect(f.wallet.depositAddress, isNull);
    },
  );

  test(
    'token rotation rejects old network rules but does not leave loading stuck',
    () async {
      final f = _Fixture(offline: false);
      addTearDown(f.dispose);
      final result = Completer<List<Map<String, dynamic>>>();
      f.api.chainsReply = () => result.future;
      final loading = f.wallet.refreshWithdrawalRules();
      expect(f.wallet.rulesLoading, isTrue);
      f.token = 'rotated';
      result.complete([]);
      await loading;
      expect(f.wallet.rulesLoading, isFalse);
      expect(f.wallet.rulesReady, isFalse);
    },
  );

  test(
    'network metadata keeps exact scientific decimal fees and rejects invalid supplied fees',
    () async {
      final f = _Fixture(offline: false);
      addTearDown(f.dispose);
      f.api.chainsReply = () async => [
        {
          'chain': 'ETH',
          'network': 'Ethereum',
          'family': 'evm',
          'withdrawalEnabled': true,
          'tokens': [
            {
              'symbol': 'USDT',
              'decimals': 6,
              'withdrawalFee': '1E-8',
              'minWithdraw': '1.25E+3',
            },
          ],
        },
      ];
      await f.wallet.refreshWithdrawalRules();
      expect(f.wallet.rules.single.feeAmount, '0.00000001');
      expect(f.wallet.rules.single.minimumAmount, '1250');
      expect(
        const WithdrawalAssetRule(
          chain: 'ETH',
          symbol: 'USDT',
          network: '',
          family: 'evm',
          withdrawalEnabled: true,
          fee: 'NaN',
        ).hasValidFee,
        isFalse,
      );
    },
  );
}
