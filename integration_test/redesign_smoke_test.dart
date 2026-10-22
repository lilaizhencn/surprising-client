import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/price_chart.dart';
import 'package:surprising_client/src/realtime_state.dart';
import 'package:surprising_client/src/sensitive_screen.dart';
import 'package:surprising_client/src/user_scanner_page.dart';
import 'package:webview_flutter/webview_flutter.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const nativeCapture = bool.fromEnvironment('NATIVE_CAPTURE_HANDSHAKE');
  Future<void> captureScene(String name) async {
    if (!nativeCapture) {
      await binding.takeScreenshot(name);
      return;
    }
    final ack = File('${Directory.systemTemp.path}/native-capture-$name.ack');
    if (await ack.exists()) await ack.delete();
    // The host captures the OS window while this exact scene is still mounted.
    debugPrint('NATIVE_CAPTURE_READY:$name:${ack.path}');
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (!await ack.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Host did not capture $name');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await ack.delete();
  }

  testWidgets(
    'native home, market and bundled TradingView render with synthetic data',
    (tester) async {
      final state =
          AppState(
              initialSession: const AuthSession(
                user: AuthUser(
                  userId: 7,
                  username: '',
                  displayName: 'Telegram 测试用户',
                  email: '',
                  status: 'NORMAL',
                ),
                accessToken: 'synthetic-only',
                refreshToken: 'synthetic-only',
              ),
              offline: true,
              apiClient: NativeQaApi(),
            )
            ..walletReady = true
            ..assetsReady = true
            ..walletPortfolio = const WalletPortfolio(
              generatedAt: 'synthetic',
              assetCount: 1,
              assets: [
                WalletAssetSummary(
                  symbol: 'USDT',
                  availableBalance: 1000,
                  lockedBalance: 0,
                  totalBalance: 1000,
                  chains: [],
                ),
              ],
            )
            ..valuationCurrency = ValuationCurrency.cny;
      state.valuationRates[ValuationCurrency.cny] = 7.2;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.pumpAndSettle();
      if (Platform.isAndroid && !nativeCapture) {
        await binding.convertFlutterSurfaceToImage();
      }
      await tester.pumpAndSettle();
      expect(find.text('交易所'), findsOneWidget);
      await captureScene('home-dark');
      state.clientTheme = ClientTheme.light;
      state.notifyListeners();
      await tester.pumpAndSettle();
      await captureScene('home-light');
      state.clientTheme = ClientTheme.dark;
      state.notifyListeners();
      await tester.tap(find.text('行情').last);
      await tester.pumpAndSettle();
      await captureScene('markets-dark');
      await tester.tap(find.byType(PublicMarketRow).first);
      await tester.pumpAndSettle(const Duration(milliseconds: 200));
      expect(find.byType(NativePriceChart), findsOneWidget);
      expect(find.byType(WebViewWidget), findsOneWidget);
      final view = tester
          .widget<WebViewWidget>(find.byType(WebViewWidget))
          .platform
          .params
          .controller;
      expect(
        (await view.runJavaScriptReturningResult(
          'LightweightCharts.version()',
        )).toString(),
        contains('5.2.1'),
      );
      expect(
        (await view.runJavaScriptReturningResult(
          'document.getElementById("legend").textContent',
        )).toString(),
        contains('开'),
      );
      // WebView's compositor paints independently of Flutter's scheduler.
      await Future<void>.delayed(const Duration(milliseconds: 750));
      await tester.pump();
      await captureScene('tradingview-dark');
      await tester.tap(find.widgetWithText(ChoiceChip, '5m'));
      await tester.pumpAndSettle();
      expect(state.period, '5m');
      await tester.pageBack();
      await tester.pumpAndSettle();

      // Exercise actual financial pages with explicit synthetic catalog/balances.
      for (final product in ProductMode.values) {
        state.privateViews[product] = PrivateView()
          ..status = 'READY'
          ..receivedAt = DateTime.now();
        state.valuedProducts.add(product);
        state.productBalances[product] = product.isSpot
            ? [
                const ProductBalance(
                  scaleUnits: 100000000,
                  accountType: 'SPOT',
                  asset: 'USDT',
                  availableUnits: 100000000000,
                  lockedUnits: 0,
                  equityUnits: 100000000000,
                ),
              ]
            : [];
      }
      state.assetsReady = true;
      state.withdrawalRulesReady = true;
      state.withdrawalRules = const [
        WithdrawalAssetRule(
          chain: 'ETH',
          symbol: 'USDT',
          network: 'Ethereum',
          family: 'EVM',
          withdrawalEnabled: true,
          decimals: 6,
          configuredMinimum: '1',
          fee: '0.1',
        ),
      ];
      await tester.tap(find.text('资产').last);
      await tester.pumpAndSettle();
      await captureScene('assets-dark');
      state.clientTheme = ClientTheme.light;
      state.notifyListeners();
      await tester.pumpAndSettle();
      await captureScene('assets-light');
      state.clientTheme = ClientTheme.dark;
      state.notifyListeners();
      await tester.pumpAndSettle();
      await tester.tap(find.text('充值'));
      await tester.pumpAndSettle();
      await captureScene('deposit-entry');
      await tester.tap(find.widgetWithText(ListTile, '充币'));
      await tester.pumpAndSettle();
      await captureScene('deposit-assets');
      await tester.tap(find.byKey(const ValueKey('deposit-asset-USDT')));
      await tester.pumpAndSettle();
      await captureScene('deposit-networks');
      await tester.tap(find.byKey(const ValueKey('deposit-network-ETH')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('deposit-address')), findsOneWidget);
      await captureScene('deposit-address');
      await tester.tap(find.byTooltip('更多'));
      await tester.pumpAndSettle();
      await captureScene('deposit-menu');
      Navigator.of(tester.element(find.text('帮助中心'))).pop();
      await tester.pumpAndSettle();
      for (var step = 0; step < 3; step++) {
        await tester.tap(find.byTooltip('返回'));
        await tester.pumpAndSettle();
      }
      state.privateViews[ProductMode.spot]!.receivedAt = DateTime.now();
      await tester.tap(find.text('划转'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最大'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TextField>(find.byKey(const ValueKey('transfer-amount')))
            .controller!
            .text,
        '1000',
      );
      await captureScene('transfer-dark');
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.tap(find.text('提币'));
      await tester.pumpAndSettle();
      await captureScene('withdrawal-assets');
      await tester.tap(find.byKey(const ValueKey('withdraw-asset-USDT')));
      await tester.pumpAndSettle();
      await captureScene('withdrawal-networks');
      await tester.tap(find.byKey(const ValueKey('withdraw-network-ETH')));
      await tester.pumpAndSettle();
      expect(find.text('提币地址'), findsOneWidget);
      await captureScene('withdrawal-form');
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: SensitiveScreen(
            child: Scaffold(
              body: Center(child: Text('synthetic-private-balances-7')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('synthetic-private-balances-7'), findsOneWidget);
      await captureScene('withdrawal-protected');
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('public-capture-restored'))),
        ),
      );
      await tester.pumpAndSettle();
      await captureScene('capture-restored');

      // Exercise the actual native QR decoder without using a real account or camera feed.
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..drawColor(Colors.white, BlendMode.src)
        ..translate(40, 40);
      QrPainter(
        data: userQrCode(7),
        version: QrVersions.auto,
      ).paint(canvas, const Size.square(400));
      final qrImage = await recorder.endRecording().toImage(480, 480);
      final image = await qrImage.toByteData(format: ui.ImageByteFormat.png);
      qrImage.dispose();
      final file = File(
        '${Directory.systemTemp.path}/surprising-synthetic-user-qr.png',
      );
      await file.writeAsBytes(image!.buffer.asUint8List());
      final scanner = MobileScannerController(
        autoStart: false,
        formats: [BarcodeFormat.qrCode],
      );
      try {
        final decoded = await scanner.analyzeImage(
          file.path,
          formats: [BarcodeFormat.qrCode],
        );
        expect(
          decoded?.barcodes.any((code) => code.rawValue == userQrCode(7)),
          isTrue,
        );
        (binding.reportData ??= {})['nativeQrDecode'] = 'passed';
      } on UnsupportedError catch (error) {
        // The plugin explicitly disables image analysis on Apple's simulator.
        // Keep this hardware limitation visible in evidence, and fail on devices.
        if (!Platform.isIOS || !error.toString().contains('iOS Simulator')) {
          rethrow;
        }
        (binding.reportData ??= {})['nativeQrDecode'] =
            'unsupported_ios_simulator';
        debugPrint('QR_DECODE_UNSUPPORTED_IOS_SIMULATOR');
      } finally {
        await scanner.dispose();
        await file.delete();
      }
      expect(tester.takeException(), isNull);
    },
  );
}

class NativeQaApi extends ApiClient {
  NativeQaApi() : super(const AppConfig());
  @override
  Future<Map<String, String>> assetScales() async => {'USDT': '100000000'};
  @override
  Future<List<Map<String, dynamic>>> fundingAssets(String operation) async => [
    {
      'asset': 'USDT',
      'displayName': 'Tether',
      'networks': [
        {
          'networkCode': 'ETH',
          'displayName': 'Ethereum (ERC20)',
          'minDeposit': '1',
          'minWithdrawal': '1',
          'withdrawalFee': '0.1',
          'confirmations': 12,
          'chainDecimals': 6,
          'nativeAsset': false,
          'contractAddress': '0x0000000000000000000000000000000000000001',
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
  }) async => WalletDepositAddress.fromJson({
    'symbol': symbol,
    'chain': chain,
    'network': 'Ethereum',
    'address': '0x1111111111111111111111111111111111111111',
    'memo': '',
  });
}
