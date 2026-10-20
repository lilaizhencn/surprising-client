import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'account_display_test.dart' show session;
import 'transfer_page_test.dart' show MemorySettings;

void main() {
  for (final theme in [ClientTheme.dark, ClientTheme.light]) {
    for (final width in [320.0, 392.0]) {
      testWidgets('personal settings, chart and C2C at $width ${theme.name}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state =
            AppState(
                offline: true,
                apiClient: AvailabilityApi(),
                settingsStore: MemorySettings(),
              )
              ..session = session
              ..clientTheme = theme;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          SurprisingClientApp(state: state, bootstrap: false),
        );
        await tester.tap(find.byTooltip('个人设置'));
        await tester.pumpAndSettle();
        expect(find.byType(ProfilePage), findsOneWidget);
        expect(find.byType(WalletPage), findsNothing);
        expect(find.text('安全中心'), findsOneWidget);
        expect(find.text('身份认证'), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        final product = state.mode;
        await tester.tap(find.text('交易').last);
        await tester.pumpAndSettle();
        expect(state.mode, product);
        final instrument = state.selectedInstrument;
        await tester.tap(find.byTooltip('K线'));
        await tester.pumpAndSettle();
        expect(find.byType(MarketChartPage), findsOneWidget);
        expect(state.selectedInstrument.instrumentId, instrument.instrumentId);
        await tester.tap(find.widgetWithText(ChoiceChip, '5m').last);
        await tester.pumpAndSettle();
        expect(state.period, '5m');
        await tester.pageBack();
        await tester.pumpAndSettle();
        await tester.tap(find.text('C2C').last);
        await tester.pumpAndSettle();
        expect(find.byType(C2cPage), findsOneWidget);
        expect(find.byType(TradePage), findsNothing);
        expect(state.mode, product);
        await tester.tap(find.text('资产').last);
        await tester.pumpAndSettle();
        expect(find.text('钱包工具'), findsNothing);
        expect(find.text('资产估值'), findsNothing);
        expect(find.text('资产组合'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('asset-account-funding')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('asset-account-trading')),
          findsOneWidget,
        );
        final actions = [
          '充值',
          '提币',
          '划转',
        ].map((label) => tester.getCenter(find.text(label).last)).toList();
        expect(actions.map((p) => p.dy).toSet().length, 1);
        expect(
          actions[0].dx < actions[1].dx && actions[1].dx < actions[2].dx,
          isTrue,
        );
        await tester.tap(find.text('划转'));
        await tester.pumpAndSettle();
        expect(find.byType(TransferPage), findsOneWidget);
        expect(find.text('确认转出'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
  test(
    'only explicit disabled products count as zero; unknown config cannot become zero',
    () async {
      final api = AvailabilityApi();
      final state = AppState(apiClient: api)..session = session;
      addTearDown(state.dispose);
      await state.refreshProductAvailability();
      state.handleRealtimeMessage({
        'op': 'authenticated',
        'userId': session.user.userId,
      });
      expect(state.disabledProducts.length, 5);
      expect(state.productBalancesUsdt(product: ProductMode.spot), 0);
      expect(state.productBalancesUsdt(product: ProductMode.linear), isNull);
      expect(state.productBalancesUsdt(), isNull);
      api.fail = true;
      await state.refreshProductAvailability();
      expect(state.disabledProducts, isEmpty);
      expect(state.productBalancesUsdt(product: ProductMode.spot), isNull);
      expect(state.assetsReady, isFalse);
    },
  );
}

class AvailabilityApi extends ApiClient {
  AvailabilityApi() : super(const AppConfig());
  bool fail = false;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = true,
  }) async {
    if (path == '/api/v1/c2c/status') return {'runtimeEnabled': false};
    throw ApiException(503, 'offline navigation fixture');
  }

  @override
  Future<Set<ProductMode>> disabledProducts() async {
    if (fail) throw ApiException(503, 'configuration unavailable');
    return ProductMode.values.where((p) => p != ProductMode.linear).toSet();
  }
}
