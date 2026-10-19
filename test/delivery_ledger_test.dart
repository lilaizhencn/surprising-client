import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/account_records.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness delivery cash history keeps signed exact units',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _LedgerApi();
        final state =
            AppState(
                apiClient: api,
                config: const AppConfig(websocketUrl: ''),
              )
              ..mode = ProductMode.linearDelivery
              ..session = const AuthSession(
                user: AuthUser(
                  userId: 1,
                  username: 'delivery',
                  email: '',
                  status: 'ACTIVE',
                ),
                accessToken: 'test',
                refreshToken: 'test',
              );
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: FundingRecordsPage(
              state: state,
              initialCategory: 'delivery-ledger',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(api.product, ProductMode.linearDelivery);
        expect(api.category, 'delivery-ledger');
        await tester.scrollUntilVisible(
          find.text('USDT -2'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('USDT -2'), findsOneWidget);
        expect(find.text('变动后余额：90071992.54740993 USDT'), findsOneWidget);
        expect(find.text('合约 868'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _LedgerApi extends ApiClient {
  _LedgerApi() : super(const AppConfig());
  ProductMode? product;
  String? category;
  @override
  Future<Map<String, String>> assetScales() async => {'USDT': '100000000'};
  @override
  Future<AccountRecordPage> accountRecords({
    required String category,
    required int userId,
    required ProductMode product,
    String asset = '',
    String referenceType = '',
    String instrumentId = '',
    String status = '',
    DateTime? from,
    DateTime? to,
    String? cursor,
  }) async {
    this.product = product;
    this.category = category;
    return AccountRecordPage(
      [
        {
          'entryId': '9007199254740993',
          'asset': 'USDT',
          'instrumentId': '868',
          'referenceType': 'DELIVERY_SETTLEMENT',
          'amountUnits': '-200000000',
          'balanceAfterUnits': '9007199254740993',
          'createdAt': '2026-10-20T00:00:00Z',
          'referenceId': 'LINEAR_DELIVERY:868:1792425600000',
        },
      ],
      null,
      false,
    );
  }
}
