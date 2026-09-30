import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

Instrument market({String id = '42', String symbol = 'BTC-USDT-PERP'}) =>
    Instrument.fromJson({
      'instrumentId': id,
      'symbol': symbol,
      'contractType': 'LINEAR_PERPETUAL',
      'baseAsset': 'BTC',
      'quoteAsset': 'USDT',
      'priceTickUnits': 1000000,
      'quantityStepUnits': 100000,
      'lastPrice': '60000',
      'change24h': '-1.25',
    });

void main() {
  test(
    'wire requests use instrument ID and decode IDs back to display symbols',
    () async {
      final requests = <Map<String, dynamic>>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        final body = await utf8.decoder.bind(request).join();
        requests.add({
          'path': request.uri.path,
          'query': request.uri.queryParameters,
          'body': body.isEmpty ? null : jsonDecode(body),
          'product': request.headers.value('X-Product-Line'),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'instrumentId': '42',
            'bids': [],
            'asks': [],
            'trades': [],
          }),
        );
        await request.response.close();
      });
      final httpClient = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        RealHttpOverrides(),
      );
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: httpClient,
      )..instrumentCatalog = [market()];
      addTearDown(() async {
        httpClient.close(force: true);
        await server.close(force: true);
      });
      final book = await api.orderBook(
        'BTC-USDT-PERP',
        productLine: 'LINEAR_PERPETUAL',
      );
      await api.recentTrades('BTC-USDT-PERP', productLine: 'LINEAR_PERPETUAL');
      await api.placeOrder(
        userId: 1,
        symbol: 'BTC-USDT-PERP',
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        priceTicks: 6000000,
        quantitySteps: 1,
        marginMode: 'CROSS',
        positionSide: 'NET',
        reduceOnly: false,
        postOnly: false,
        productLine: 'LINEAR_PERPETUAL',
      );
      expect(book.symbol, 'BTC-USDT-PERP');
      expect(requests[0]['query'], {'instrumentId': '42', 'depth': '20'});
      expect(requests[1]['query'], {'instrumentId': '42', 'limit': '50'});
      expect(requests[2]['body']['instrumentId'], '42');
      expect(requests[2]['body'].containsKey('symbol'), isFalse);
      expect(requests.every((r) => r['product'] == 'LINEAR_PERPETUAL'), isTrue);
    },
  );

  test(
    'login challenge never becomes an empty authenticated session',
    () async {
      final state = AppState(apiClient: ChallengeApi());
      addTearDown(state.dispose);
      expect(await state.login('user@example.com', 'password'), isNull);
      expect(state.session, isNull);
      expect(state.pendingLoginChallenge?.methods, hasLength(2));
      expect(state.pendingLoginChallenge?.token, 'challenge');
      expect(state.lastError, isNull);
    },
  );

  test(
    'live trades using IDs deduplicate and isolate products, empty depth replaces book',
    () async {
      final state = AppState(offline: true)..instruments = [market()];
      addTearDown(state.dispose);
      await state.selectMode(ProductMode.linear);
      Map<String, dynamic> event(
        int sequence, {
        String product = 'LINEAR_PERPETUAL',
      }) => {
        'op': 'event',
        'channel': 'trades',
        'productLine': product,
        'instrumentId': '42',
        'data': {
          'version': '${sequence.toString().padLeft(19, '0')}:0000000000',
          'value': {
            'tradeId': '$sequence',
            'sequence': sequence,
            'priceTicks': 6000000,
            'quantitySteps': 3,
            'side': 'BUY',
          },
        },
      };
      state.handleRealtimeMessage(event(2));
      state.handleRealtimeMessage(event(2));
      state.handleRealtimeMessage(event(1));
      state.handleRealtimeMessage(event(3, product: 'INVERSE_PERPETUAL'));
      expect(state.recentTrades, hasLength(1));
      expect(state.latestPriceFor(market()), 60000);
      state.handleRealtimeMessage({
        'op': 'event',
        'channel': 'depth',
        'productLine': 'LINEAR_PERPETUAL',
        'instrumentId': '42',
        'data': {'levels': []},
      });
      expect(state.orderBook.bids, isEmpty);
      await state.selectMode(ProductMode.option);
      expect(state.recentTrades, isEmpty);
      expect(state.selectedSymbol, isEmpty);
    },
  );

  test(
    'trade history merges REST overlap without losing newer events and is bounded',
    () {
      final rows = mergeRecentTrades(
        [
          for (var n = 1; n < 80; n++) {'tradeId': '$n', 'sequence': n},
        ],
        [
          {'tradeId': '79', 'sequence': 79, 'side': 'SELL'},
        ],
      );
      expect(rows, hasLength(50));
      expect(rows.first['side'], 'SELL');
      expect(rows.last['sequence'], 30);
    },
  );

  test('price increments are exact, reject rounding and integer overflow', () {
    expect(decimalIncrement('123.45', 1000000), 12345);
    expect(decimalIncrement('123.451', 1000000), isNull);
    expect(decimalIncrement('-1', 1), isNull);
    expect(decimalIncrement('NaN', 1), isNull);
    expect(decimalIncrement('999999999999999999999999999', 1), isNull);
    expect(decimalIncrement('0.1', 10000), 1000);
    expect(decimalIncrement('10', 10000), 100000);
  });

  test('private position identity separates cross and isolated margin', () {
    expect(
      positionKey({'instrumentId': '42', 'marginMode': 'CROSS'}),
      isNot(positionKey({'instrumentId': '42', 'marginMode': 'ISOLATED'})),
    );
  });

  testWidgets(
    'password recovery stays open through reset and returns to login',
    (tester) async {
      final state = RecoveryState();
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: const MaterialApp(home: Scaffold(body: AuthSheet())),
        ),
      );
      await tester.tap(find.text('忘记密码？'));
      await tester.pump();
      await tester.enterText(
        find.byType(TextField).first,
        'person@example.com',
      );
      await tester.tap(find.text('发送验证码'));
      await tester.pumpAndSettle();
      expect(find.text('设置新密码'), findsOneWidget);
      await tester.enterText(find.byType(TextField).at(1), 'new-password');
      await tester.enterText(find.byType(TextField).at(2), '123456');
      await tester.tap(find.text('更新密码'));
      await tester.pumpAndSettle();
      expect(find.text('登录账户'), findsOneWidget);
      expect(state.resetIdentifier, 'person@example.com');
    },
  );

  for (final theme in ClientTheme.values) {
    testWidgets(
      'compact ${theme.name} markets search, navigation and keyboard fit',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state = AppState(offline: true)..clientTheme = theme;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          SurprisingClientApp(state: state, bootstrap: false),
        );
        await tester.tap(find.text('行情').last);
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('market-search')),
          'not-a-symbol',
        );
        await tester.pump();
        expect(find.text('暂无匹配的交易对'), findsOneWidget);
        await tester.enterText(
          find.byKey(const ValueKey('market-search')),
          'BTC',
        );
        await tester.pump();
        expect(find.byType(PublicMarketRow), findsWidgets);
        await tester.tap(find.text('合约').last);
        await tester.pumpAndSettle();
        expect(state.mode, ProductMode.linear);
      },
    );
  }
}

class ChallengeApi extends ApiClient {
  ChallengeApi() : super(const AppConfig());
  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    throw LoginChallenge.fromJson({
      'challengeToken': 'challenge',
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 5))
          .toIso8601String(),
      'methods': [
        {'type': 'EMAIL', 'destination': 'p***@example.com'},
        {'type': 'TOTP'},
      ],
    });
  }
}

class RecoveryState extends AppState {
  RecoveryState() : super(offline: true);
  String? resetIdentifier;
  @override
  Future<bool> requestPasswordReset(String identifier) async => true;
  @override
  Future<bool> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    resetIdentifier = identifier;
    return true;
  }
}

class RealHttpOverrides extends HttpOverrides {}
