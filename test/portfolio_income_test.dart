import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/exchange_widgets.dart';
import 'package:surprising_client/src/asset_overview.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/portfolio_income.dart';
import 'account_display_test.dart' show session, portfolio;
import 'support/portfolio_income_fixture.dart';
import 'support/authentication.dart';

void main() {
  test(
    'server decimals remain exact and freshness uses elapsed time rather than phone clock',
    () {
      final data = incomeFixture();
      (data['groups'] as Map)['funding']['amountUsdt'] = '9007199254740.993123';
      final summary = PortfolioIncomeSummary.fromJson(data);
      expect(
        summary.fresh('funding', Duration.zero)!.amount,
        '9007199254740.993123',
      );
      expect(summary.fresh('funding', const Duration(seconds: 89)), isNotNull);
      expect(summary.fresh('funding', const Duration(seconds: 90)), isNull);
      expect(summary.nextExpiry(Duration.zero), const Duration(seconds: 90));
      expect(summary.fresh('funding', const Duration(seconds: -1)), isNull);
    },
  );
  test(
    'business-day rollover clears yesterday even if the cut is still under two minutes old',
    () {
      final data = incomeFixture();
      data['generatedAt'] = '2026-10-20T15:59:50Z';
      for (final row in (data['groups'] as Map).values) {
        row['asOf'] = '2026-10-20T15:59:00Z';
      }
      final summary = PortfolioIncomeSummary.fromJson(data);
      expect(summary.fresh('overview', const Duration(seconds: 9)), isNotNull);
      expect(summary.fresh('overview', const Duration(seconds: 10)), isNull);
      expect(summary.nextExpiry(Duration.zero), const Duration(seconds: 10));
    },
  );
  test(
    'wrong day, malformed monetary strings and contradictory availability fail closed',
    () {
      for (final mutate in <void Function(Map<String, dynamic>)>[
        (j) => j['timeZone'] = 'UTC',
        (j) => j['periodStart'] = '2026-10-20T00:00:00Z',
        (j) => j['groups']['overview']['amountUsdt'] = 3,
        (j) => j['groups']['overview']['amountUsdt'] = 'NaN',
        (j) => j['groups']['overview']['available'] = false,
        (j) => j['groups']['overview']['asOf'] = '2026-10-20T04:01:00Z',
        (j) => j['groups']['overview']['asOf'] = '2026-10-20T04:00:01Z',
        (j) => j['groups'].remove('OPTION'),
      ]) {
        final data = incomeFixture();
        mutate(data);
        expect(
          () => PortfolioIncomeSummary.fromJson(data),
          throwsFormatException,
        );
      }
    },
  );
  test(
    'capital-free profit may have a null percentage; unknown baseline may retain current equity',
    () {
      final data = incomeFixture();
      data['groups']['funding']['percent'] = null;
      data['groups']['trading'] = {
        'available': false,
        'status': 'HISTORY_UNAVAILABLE',
        'amountUsdt': null,
        'percent': null,
        'currentEquityUsdt': '5',
        'openingEquityUsdt': null,
        'asOf': '2026-10-20T04:00:00Z',
      };
      final summary = PortfolioIncomeSummary.fromJson(data);
      expect(summary.fresh('funding', Duration.zero)!.percent, isNull);
      expect(summary.fresh('trading', Duration.zero)!.equityValue, 5);
      expect(summary.fresh('trading', Duration.zero)!.amountValue, isNull);
    },
  );
  test(
    'late response after account switch or disposal cannot publish financial data',
    () async {
      final api = IncomeApi()..pending = Completer();
      final state = IncomeTestState(initialSession: session, api: api);
      final request = state.refreshPortfolioIncome();
      await state.logout();
      await signInAs(
        state,
        const AuthSession(
          user: AuthUser(
            userId: 9,
            username: 'other',
            email: '',
            status: 'NORMAL',
          ),
          accessToken: 'other',
          refreshToken: 'other',
        ),
      );
      api.pending!.complete(incomeFixture());
      await request;
      expect(state.portfolioIncome(), isNull);
      state.dispose();
      final api2 = IncomeApi()..pending = Completer();
      final disposed = IncomeTestState(initialSession: session, api: api2);
      final pending = disposed.refreshPortfolioIncome();
      disposed.dispose();
      api2.pending!.complete(incomeFixture());
      await pending;
      expect(api2.owners, [session.user.userId]);
    },
  );
  test(
    'failed refresh clears an old estimate and never touches spendable balances',
    () async {
      final api = IncomeApi();
      final state = IncomeTestState(initialSession: session, api: api);
      addTearDown(state.dispose);
      await state.refreshPortfolioIncome();
      expect(state.portfolioIncome()!.amount, '3');
      expect(state.balances, isEmpty);
      expect(state.productBalances, isEmpty);
      await state.logout();
      await signInAs(
        state,
        const AuthSession(
          user: AuthUser(
            userId: 9,
            username: 'other',
            email: '',
            status: 'NORMAL',
          ),
          accessToken: 'other',
          refreshToken: 'other',
        ),
      );
      expect(state.portfolioIncome(), isNull);
      await state.logout();
      await signInAs(state, session);
      api.fail = true;
      await state.refreshPortfolioIncome();
      expect(state.portfolioIncome(), isNull);
    },
  );
  testWidgets(
    'a known summary cannot certify an empty or complete asset detail list',
    (tester) async {
      final state = IncomeTestState(initialSession: session, api: IncomeApi());
      await state.refreshPortfolioIncome();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (_, _) => SingleChildScrollView(
                child: AssetOverview(
                  state: state,
                  onDeposit: () {},
                  onWithdraw: () {},
                  onTools: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('资产明细同步中'), findsOneWidget);
      expect(find.text('暂无资产'), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('asset-total'))).data,
        '17.00',
      );
      state.walletReady = true;
      state.walletPortfolio = portfolio(12);
      state.notifyListeners();
      await tester.tap(find.byKey(const ValueKey('asset-account-funding')));
      await tester.pumpAndSettle();
      expect(find.text('资产明细同步中'), findsNothing);
      expect(find.text('资金账户同步中'), findsNothing);
      expect(find.text('暂无资产'), findsNothing);
      expect(find.byKey(const ValueKey('asset-coin-USDT')), findsOneWidget);
      state.walletReady = false;
      state.notifyListeners();
      await tester.pump();
      expect(find.text('资金账户同步中'), findsOneWidget);
      expect(find.text('暂无资产'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets('scoped income, currency and privacy at 320px $brightness', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final state = IncomeTestState(initialSession: session, api: IncomeApi());
      await state.refreshPortfolioIncome();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: ListenableBuilder(
              listenable: state,
              builder: (_, _) => SingleChildScrollView(
                child: AssetOverview(
                  state: state,
                  onDeposit: () {},
                  onWithdraw: () {},
                  onTools: () {},
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.textContaining('今日收益 +3.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('asset-account-funding')));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日收益 +1.00'), findsOneWidget);
      state.valuationRates[ValuationCurrency.cny] = 7;
      state.valuationCurrency = ValuationCurrency.cny;
      state.notifyListeners();
      await tester.pump();
      expect(find.textContaining('今日收益 +7.00'), findsOneWidget);
      await tester.tap(find.byTooltip('隐藏资产'));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日收益 ••••••'), findsOneWidget);
      expect(find.textContaining('2.50%'), findsNothing);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AccountValueHeader(state: state)),
        ),
      );
      expect(find.textContaining('+21.00'), findsOneWidget);
      await tester.tap(find.byTooltip('隐藏资产'));
      await tester.pumpAndSettle();
      final privateText = tester.widget<Text>(
        find.textContaining('••••••').last,
      );
      final muted = Theme.of(
        tester.element(find.byType(AccountValueHeader)),
      ).colorScheme.onSurfaceVariant;
      expect(
        privateText.style?.color,
        muted,
        reason: 'Hidden income must not reveal gain/loss through its color',
      );
      if (privateText.textSpan case final TextSpan span) {
        expect(
          span.children!.whereType<TextSpan>().map((s) => s.style?.color),
          everyElement(muted),
        );
      }

      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
  }
}
