// Isolated HTTP fixtures exercise the real native UI, API client and persistence.
// Financial database / chain fault tests run separately in the backend repositories.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_scope.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/wallet/withdrawal_page.dart';
import 'package:surprising_client/src/wallet/wallet_components.dart';
import '../test/transfer_page_test.dart' show MemorySettings;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'quotation, lost reply, restart and original-request recovery',
    (tester) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <Map<String, dynamic>>[];
      final accepted = <String, Map<String, dynamic>>{};
      var lostReply = true, paid = 0, failQuery = false;
      server.listen((request) async {
        final text = await utf8.decoder.bind(request).join();
        final body = text.isEmpty
            ? <String, dynamic>{}
            : jsonDecode(text) as Map<String, dynamic>;
        final key = request.headers.value('Idempotency-Key') ?? '';
        requests.add({
          'path': request.uri.path,
          'query': request.uri.queryParameters,
          'key': key,
          'body': body,
          'method': request.method,
        });
        Object response;
        if (request.uri.path.endsWith('/quote')) {
          response = {
            'asset': 'USDT',
            'chain': 'ETH',
            'amount': body['amount'],
            'fee': '0.25',
            'receivedAmount': '24.75',
            'networkRevision': 17,
          };
        } else if (request.uri.path.endsWith('/submission')) {
          final row = accepted[request.uri.queryParameters['reference']];
          request.response.statusCode = failQuery
              ? 503
              : row == null
              ? 404
              : 200;
          response = failQuery || row == null
              ? {'message': 'Synthetic status service unavailable'}
              : row;
        } else if (request.method == 'GET' &&
            request.uri.path.endsWith('/deposits')) {
          response = <Object>[];
        } else if (request.method == 'GET' &&
            request.uri.path.endsWith('/withdrawals')) {
          response = [
            {
              'id': 'native-original-42',
              'gatewayWithdrawalId': 'native-original-42',
              'chain': 'ETH',
              'asset': 'USDT',
              'amount': '25',
              'platformFee': '0.25',
              'receivedAmount': '24.75',
              'networkFee': '0.000021',
              'networkFeeAsset': 'ETH',
              'status': 'COMPLETED',
              'toAddress': '0x${'a' * 40}',
              'txHash': '0x${'b' * 64}',
              'createdAt': '2026-10-30T00:00:00Z',
            },
          ];
        } else if (request.uri.path.endsWith('/withdrawals') &&
            request.method == 'POST') {
          if (body['networkRevision'] != 17 ||
              body['amount'] != '25' ||
              key.isEmpty) {
            request.response.statusCode = 400;
            response = {'message': 'Quotation version or amount missing'};
          } else {
            final receipt = accepted.putIfAbsent(key, () {
              paid++;
              return {
                'withdrawalId': 'native-original-42',
                'status': 'SUBMITTED',
                'amount': '25',
                'platformFee': '0.25',
                'receivedAmount': '24.75',
                'networkRevision': 17,
              };
            });
            request.response.statusCode = lostReply ? 503 : 200;
            response = lostReply
                ? {'message': 'Synthetic proxy lost the accepted reply'}
                : receipt;
            lostReply = false;
          }
        } else {
          request.response.statusCode = 404;
          response = {'message': 'Unexpected isolated fixture request'};
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      final settings = MemorySettings();
      AppState createState() => AppState(
        offline: true,
        settingsStore: settings,
        apiClient: ApiClient(
          AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        ),
        initialSession: const AuthSession(
          user: AuthUser(
            userId: 42,
            username: 'synthetic-wallet',
            email: 'wallet@example.test',
            status: 'ACTIVE',
          ),
          accessToken: 'test-only',
          refreshToken: 'test-only',
        ),
      );
      Widget screen(AppState state, {bool dark = false, bool large = false}) =>
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(
                brightness: dark ? Brightness.dark : Brightness.light,
              ),
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: TextScaler.linear(large ? 1.4 : 1)),
                child: child!,
              ),
              home: const WithdrawalPage(
                initialSymbol: 'USDT',
                initialChain: 'ETH',
              ),
            ),
          );
      Future<void> settleUntil(bool Function() condition) async {
        final deadline = DateTime.now().add(const Duration(seconds: 20));
        while (!condition()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Native wallet condition timed out');
          }
          await tester.pump(const Duration(milliseconds: 100));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
        }
        await tester.pumpAndSettle();
      }

      Future<void> capture(String name) async {
        await tester.pumpAndSettle();
        final ack = File(
          '${Directory.systemTemp.path}/wallet-closure-$name.ack',
        );
        if (await ack.exists()) await ack.delete();
        debugPrint('NATIVE_CAPTURE_READY:$name:${ack.path}');
        await tester.runAsync(() async {
          final deadline = DateTime.now().add(const Duration(seconds: 45));
          while (!await ack.exists()) {
            if (DateTime.now().isAfter(deadline)) {
              throw StateError('Host screenshot missing: $name');
            }
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          await ack.delete();
        });
      }

      var state = createState();
      state.walletReady = true;
      state.withdrawalRulesReady = true;
      state.walletPortfolio = const WalletPortfolio(
        generatedAt: 'synthetic',
        assetCount: 1,
        assets: [
          WalletAssetSummary(
            symbol: 'USDT',
            availableBalance: 50,
            availableBalanceText: '50',
            lockedBalance: 0,
            totalBalance: 50,
            chains: [],
          ),
        ],
      );
      state.withdrawalRules = const [
        WithdrawalAssetRule(
          chain: 'ETH',
          symbol: 'USDT',
          network: 'Ethereum',
          family: 'EVM',
          withdrawalEnabled: true,
          decimals: 6,
          configuredMinimum: '1',
          fee: '0.25',
        ),
      ];
      await tester.pumpWidget(screen(state));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '0x${'a' * 40}');
      await tester.enterText(find.byType(TextField).at(1), '25');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final review = find.text('核对并确认提币');
      await tester.ensureVisible(review);
      await tester.tap(review);
      await settleUntil(() => find.text('确认提币信息').evaluate().isNotEmpty);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('24.75 USDT'),
        ),
        findsOneWidget,
      );
      expect(paid, 0);
      await capture('native-wallet-quote');
      await tester.tap(find.text('确认提交'));
      await settleUntil(() => state.withdrawalOutcomeUnknown);
      expect(paid, 1);
      expect(accepted.length, 1);
      final original = state.wallet.pending!.key;
      await capture('native-wallet-unknown');
      await tester.pumpWidget(const SizedBox.shrink());
      state.dispose();
      state = createState();
      addTearDown(state.dispose);
      expect(await state.wallet.restore(), isTrue);
      // A restart with no current balance/rules must still expose the saved request.
      expect(state.walletReady, isFalse);
      expect(state.wallet.pending!.key, original);
      await tester.pumpWidget(screen(state, dark: true, large: true));
      await tester.pumpAndSettle();
      expect(find.text('原请求与金额快照'), findsOneWidget);
      failQuery = true;
      var query = find.text('查询原请求状态');
      await tester.ensureVisible(query);
      await tester.tap(query);
      await settleUntil(
        () => !state.withdrawalSubmitting && state.wallet.error != null,
      );
      expect(state.wallet.pending!.key, original);
      expect(state.withdrawalOutcomeUnknown, isTrue);
      await capture('native-wallet-restarted-dark-large');
      failQuery = false;
      final retry = find.text('重试原请求');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await settleUntil(() => state.wallet.pending?.status == 'ACCEPTED');
      expect(paid, 1);
      expect(
        requests
            .where(
              (r) =>
                  r['method'] == 'POST' &&
                  r['path'] == '/api/v1/wallet/withdrawals',
            )
            .map((r) => r['key'])
            .toSet(),
        {original},
      );
      accepted[original]!['status'] = 'COMPLETED';
      query = find.text('查询原请求状态');
      await tester.ensureVisible(query);
      await tester.tap(query);
      await settleUntil(
        () => state.withdrawalConfirmation?.status == 'COMPLETED',
      );
      final rssBefore = ProcessInfo.currentRss;
      for (var i = 0; i < 20; i++) {
        binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
        binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpWidget(screen(state, dark: i.isEven, large: i.isOdd));
        await tester.pumpAndSettle();
        query = find.text('查询原请求状态');
        await tester.ensureVisible(query);
        await tester.tap(query);
        await settleUntil(() => !state.withdrawalSubmitting);
        expect(state.wallet.pending!.key, original);
        expect(paid, 1);
        expect(tester.takeException(), isNull);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 500)),
        );
      }
      await capture('native-wallet-completed');
      final rows = await tester.runAsync(() => state.api.walletOrders(42));
      expect(rows, hasLength(1));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
            body: SafeArea(
              child: ListView(
                children: [WalletOrderRecordRow(record: rows!.single)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('净到账：24.75 USDT'), findsOneWidget);
      expect(find.text('实际链上手续费：0.000021 ETH'), findsOneWidget);
      await capture('native-wallet-history');

      binding.reportData = {
        'paidOnce': paid,
        'distinctIntents': accepted.length,
        'quoteVersion': 17,
        'platformFee': '0.25',
        'net': '24.75',
        'lifecycleCycles': 20,
        'rssBefore': rssBefore,
        'rssAfter': ProcessInfo.currentRss,
        'httpRequests': requests.length,
      };
      await tester.pumpWidget(const SizedBox.shrink());
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
