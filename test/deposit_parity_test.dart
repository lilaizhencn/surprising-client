import 'support/authentication.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/deposit_page.dart';
import 'package:surprising_client/src/models.dart';
import 'account_display_test.dart' show session;

void main() {
  for (final brightness in Brightness.values) {
    testWidgets(
      'deposit uses server networks, ignores late addresses and clears identity on $brightness',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = DepositApi();
        final state = AppState(
          initialSession: session,
          sessionStore: MemorySessionStore(),
          offline: true,
          apiClient: api,
        );
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MobileDepositPage(state: state),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('选择资产'), findsOneWidget);
        expect(find.text('USDT'), findsWidgets);
        expect(find.text('SOL'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('deposit-asset-USDT')));
        await tester.pumpAndSettle();
        expect(find.text('选择网络'), findsOneWidget);
        await tester.tap(find.text('Ethereum').last);
        await tester.pump(const Duration(milliseconds: 400));
        expect(api.networks, ['ETH']);
        await tester.tap(find.byTooltip('返回'));
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.text('Tron').last);
        await tester.pump(const Duration(milliseconds: 400));
        api.addresses[1].complete(
          WalletDepositAddress.fromJson({
            'symbol': 'USDT',
            'chain': 'TRON',
            'address': 'NEW-ADDRESS',
            'memo': '123',
          }),
        );
        await tester.pumpAndSettle();
        api.addresses[0].complete(
          WalletDepositAddress.fromJson({
            'symbol': 'USDT',
            'chain': 'ETH',
            'address': 'OLD-ADDRESS',
          }),
        );
        await tester.pumpAndSettle();
        expect(find.byType(QrImageView), findsOneWidget);
        expect(find.text('NEW-ADDRESS'), findsOneWidget);
        expect(find.text('OLD-ADDRESS'), findsNothing);
        expect(find.text('Memo / Tag：123'), findsOneWidget);
        await state.logout();
        await tester.pumpAndSettle();
        expect(find.text('NEW-ADDRESS'), findsNothing);
        expect(find.byType(QrImageView), findsNothing);
        expect(find.text('请先登录'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class DepositApi extends ApiClient {
  DepositApi() : super(const AppConfig());
  final addresses = <Completer<WalletDepositAddress>>[], networks = <String>[];
  @override
  Future<List<Map<String, dynamic>>> fundingAssets(String operation) async => [
    {
      'asset': 'USDT',
      'networks': [
        {
          'networkCode': 'ETH',
          'displayName': 'Ethereum',
          'minDeposit': '1',
          'confirmations': 12,
        },
        {
          'networkCode': 'TRON',
          'displayName': 'Tron',
          'minDeposit': '2',
          'confirmations': 20,
        },
      ],
    },
  ];
  @override
  Future<WalletDepositAddress> walletDepositAddress(
    int userId, {
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) {
    networks.add(chain);
    final pending = Completer<WalletDepositAddress>();
    addresses.add(pending);
    return pending.future;
  }
}
