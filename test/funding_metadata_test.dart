import 'support/core_snapshot_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'account_display_test.dart' show session;

WithdrawalAssetRule rule({String? fee, String? minimum}) => WithdrawalAssetRule(
  chain: 'ETH',
  symbol: 'USDT',
  network: 'Ethereum',
  family: 'evm',
  withdrawalEnabled: true,
  decimals: 8,
  fee: fee,
  configuredMinimum: minimum,
);

void main() {
  test(
    'withdrawal maximum truncates to chain precision and never rounds a balance up',
    () {
      final state = AppState(initialSession: session, offline: true)
        ..withdrawalRulesReady = true
        ..walletReady = true
        ..withdrawalRules = [rule(fee: '0')]
        ..walletPortfolio = WalletPortfolio.fromJson({
          'assets': [
            {
              'symbol': 'USDT',
              'availableBalance': '90071992.54740993',
              'lockedBalance': '0',
              'totalBalance': '90071992.54740993',
            },
          ],
        });
      addTearDown(state.dispose);
      expect(
        state.walletPortfolio.assets.single.availableAmount,
        '90071992.54740993',
      );
      String? validate(String amount) => state.validateWithdrawal(
        chain: 'ETH',
        symbol: 'USDT',
        toAddress: '0x1111111111111111111111111111111111111111',
        amount: amount,
      );
      expect(validate('90071992.54740994'), contains('超过可用余额'));
      expect(validate('90071992.54740993'), isNull);
      state.withdrawalRules = const [
        WithdrawalAssetRule(
          chain: 'ETH',
          symbol: 'USDT',
          network: 'Ethereum',
          family: 'evm',
          withdrawalEnabled: true,
          decimals: 6,
          fee: '0',
        ),
      ];
      expect(state.withdrawalMaximum('ETH', 'USDT'), '90071992.547409');
      state.walletPortfolio = WalletPortfolio.fromJson({
        'assets': [
          {
            'symbol': 'USDT',
            'availableBalance': '1E-18',
            'lockedBalance': '0',
            'totalBalance': '1E-18',
          },
        ],
      });
      state.withdrawalRules = const [
        WithdrawalAssetRule(
          chain: 'ETH',
          symbol: 'USDT',
          network: 'Ethereum',
          family: 'evm',
          withdrawalEnabled: true,
          decimals: 18,
          fee: '0',
        ),
      ];
      expect(validate('0.000000000000000001'), isNull);
      expect(state.withdrawalMaximum('ETH', 'USDT'), '0.000000000000000001');
    },
  );

  test('nonzero balance amounts require an authoritative asset scale', () {
    ProductBalance balance(int? scale) => ProductBalance(
      accountType: 'USDT_PERPETUAL',
      asset: 'USDT',
      availableUnits: 1234567,
      lockedUnits: 1,
      equityUnits: 1234568,
      scaleUnits: scale,
    );
    expect(balance(1000000).available, 1.234567);
    expect(balance(1000000000000000000).locked, 1e-18);
    for (final unavailable in [null, 0, -1, 123]) {
      expect(balance(unavailable).equity, isNull);
    }
  });

  test(
    'private snapshots gain correct valuation after registry precision loads',
    () async {
      final api = CatalogApi()..scale = '1000000';
      final state = AppState(initialSession: session, apiClient: api);
      addTearDown(state.dispose);
      state.handleRealtimeMessage({'op': 'authenticated', 'userId': 1});
      state.handleRealtimeMessage(
        completeCoreSnapshot({
          'op': 'snapshot',
          'userId': 1,
          'productLine': 'LINEAR_PERPETUAL',
          'data': {
            'status': 'READY',
            'snapshotVersion': '0000000000000000001:0000000000',
            'account': {
              'balances': [
                {'asset': 'USDT', 'availableUnits': 1234567, 'lockedUnits': 1},
              ],
              'positions': [],
            },
            'openOrders': [],
            'triggerOrders': [],
            'positionRisks': [],
          },
        }),
      );
      expect(state.productBalancesUsdt(product: ProductMode.linear), isNull);
      await state.refreshBalanceScales();
      expect(
        state.productBalances[ProductMode.linear]!.single.scaleUnits,
        1000000,
      );
      expect(state.productBalancesUsdt(product: ProductMode.linear), 1.234568);
      api.scale = '100001';
      await state.refreshBalanceScales();
      expect(state.productBalancesUsdt(product: ProductMode.linear), isNull);
    },
  );

  test('withdrawal preview tolerates empty and partially entered amounts', () {
    final configured = rule(fee: '0.1');
    for (final input in ['', ' ', '.', '1.', '-1', 'NaN', '1e2']) {
      expect(configured.receivedAmount(input), isNull, reason: input);
    }
    expect(configured.receivedAmount('1.25'), '1.15');
    expect(configured.receivedAmount('0.01'), '-0.09');
    expect(rule().receivedAmount('1'), isNull);
  });

  test('BigDecimal metadata preserves tiny fees and exact net amounts', () {
    final configured = rule(fee: '1E-8', minimum: '1.25E+3');
    expect(configured.feeAmount, '0.00000001');
    expect(configured.minimumAmount, '1250');
    expect(
      configured.receivedAmount('9007199254740993.00000002'),
      '9007199254740993.00000001',
    );
    expect(rule(fee: '0E-8').feeAmount, '0');
    expect(rule(fee: '1.2300').feeAmount, '1.23');
    expect(rule(fee: '10E-1').feeAmount, '1');
  });

  test('invalid fee and minimum metadata are unavailable', () {
    for (final value in ['', '-0.1', 'NaN', 'Infinity', '1E10000000']) {
      final configured = rule(fee: value, minimum: value);
      expect(configured.hasValidFee, isFalse, reason: value);
      expect(configured.receivedAmount('1'), isNull, reason: value);
      expect(configured.minimumAmount, isNull, reason: value);
    }
  });

  test(
    'wallet network supplies actual address family and bounded precision',
    () async {
      final api = CatalogApi();
      final networks = await api.walletChains(7);
      expect(networks.single['family'], 'evm');
      final token = asMap(asList(networks.single['tokens']).single);
      expect(token['decimals'], 6); // ledger 8, chain 6
      expect(token['withdrawalFee'], '1E-8');
      api.chainDecimals = 18;
      expect(
        asMap(
          asList((await api.walletChains(7)).single['tokens']).single,
        )['decimals'],
        8,
      );
      for (final invalid in [null, -1, 37, '6', 6.5]) {
        api.chainDecimals = invalid;
        expect(
          asMap(
            asList((await api.walletChains(7)).single['tokens']).single,
          )['decimals'],
          isNull,
        );
      }
      api.chainDecimals = 6;
      api.scale = '100001';
      expect(
        asMap(
          asList((await api.walletChains(7)).single['tokens']).single,
        )['decimals'],
        isNull,
      );
    },
  );
}

class CatalogApi extends ApiClient {
  CatalogApi() : super(const AppConfig());
  Object? chainDecimals = 6;
  String scale = '100000000';
  @override
  Future<Map<String, String>> assetScales() async => {'USDT': scale};
  @override
  Future<List<Map<String, dynamic>>> fundingAssets(String operation) async => [
    {
      'asset': 'USDT',
      'networks': [
        {
          'networkCode': 'ETH',
          'displayName': 'Ethereum',
          'family': 'evm',
          'chainDecimals': chainDecimals,
          'withdrawalFee': '1E-8',
          'minWithdrawal': '1',
        },
      ],
    },
  ];
}
