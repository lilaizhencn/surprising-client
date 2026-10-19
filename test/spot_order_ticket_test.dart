import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/spot_amend_order_sheet.dart';

Instrument spot({String status = 'TRADING'}) => Instrument.fromJson({
  'instrumentId': '1',
  'symbol': 'BTC-USDT',
  'instrumentType': 'SPOT',
  'contractType': 'SPOT',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'priceTickUnits': 1000000,
  'quantityStepUnits': 10000,
  'pricePrecision': 2,
  'quantityPrecision': 4,
  'status': status,
  'baseScaleUnits': 100000000,
  'quoteScaleUnits': 100000000,
  'minQuantitySteps': 1,
  'maxQuantitySteps': 10000000,
  'minNotionalUnits': 1,
  'maxNotionalUnits': '9223372036854775807',
  'notionalMultiplierUnits': 100,
  'changeId': 1,
});
const session = AuthSession(
  user: AuthUser(userId: 1, username: 'spot', email: '', status: 'ACTIVE'),
  accessToken: 'test',
  refreshToken: 'test',
);

Future<void> submitSpot(AppState state) => state.placeOrder(
  side: 'BUY',
  orderType: 'LIMIT',
  timeInForce: 'GTC',
  price: 0,
  quantitySteps: 2,
  marginMode: 'CROSS',
  positionSide: 'NET',
  reduceOnly: false,
  postOnly: false,
  bboPriceMode: 'OPPONENT_1',
);

OrderModel cancelTarget({int id = 91, String status = 'ACCEPTED'}) =>
    OrderModel.fromJson({
      'orderId': id,
      'symbol': 'BTC-USDT',
      'instrumentId': '1',
      'side': 'BUY',
      'orderType': 'LIMIT',
      'timeInForce': 'GTC',
      'status': status,
      'priceTicks': 100,
      'quantitySteps': 2,
      'remainingQuantitySteps': 2,
    });

Future<void> amendSpot(AppState state) =>
    state.amendSpotOrder(cancelTarget(), spot(), '1.10', '0.0003');
AmendOrderResult amendmentResult() => AmendOrderResult(
  originalOrder: cancelTarget(status: 'CANCELED'),
  replacementOrder: cancelTarget(id: 9007199254740993),
  cancelRequested: true,
  message: 'amended',
);

void main() {
  test(
    'amendment success cannot be inferred when the original order is still open',
    () async {
      final api = _SpotApi()
        ..amendResponse = (Completer<AmendOrderResult>()
          ..complete(
            AmendOrderResult(
              originalOrder: cancelTarget(),
              replacementOrder: cancelTarget(id: 92),
              cancelRequested: true,
              message: 'amended',
            ),
          ));
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      await amendSpot(state);
      expect(state.tradingCommandPending, isTrue);
      expect(state.lastNotice, contains('待确认'));
    },
  );

  test(
    'direct amendment API supplies the mandatory request identity',
    () async {
      final api = _AmendPayloadApi();
      await api.amendOrder(
        userId: 1,
        orderId: 91,
        newClientOrderId: 'replacement-1',
        priceTicks: 110,
        quantitySteps: 3,
        productLine: 'SPOT',
      );
      expect(api.sent!['clientRequestId'], 'replacement-1');
      expect(api.sent!['newClientOrderId'], 'replacement-1');
    },
  );

  test(
    'lost HTTP amendment reply is recovered by original request with one POST and read only queries',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final methods = <String>[];
      String? key;
      var queries = 0;
      server.listen((request) async {
        methods.add(request.method);
        final body = await utf8.decoder.bind(request).join();
        if (request.method == 'POST') {
          final payload = asMap(jsonDecode(body));
          key = asString(payload['clientRequestId']);
          expect(key, isNotEmpty);
          expect(payload['newClientOrderId'], key);
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
        } else {
          expect(request.uri.path, '/api/v1/gateway/trading/amendments');
          expect(request.uri.queryParameters['clientRequestId'], key);
          queries++;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'commandId': '11111111-1111-1111-1111-111111111111',
              'outcome': queries > 1 ? 'TERMINAL' : 'RESULT_UNKNOWN',
              'code': queries > 1 ? 'NONE' : 'RESULT_UNKNOWN',
            }),
          );
          await request.response.close();
        }
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      final api =
          ApiClient(
              AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
              httpClient: http,
            )
            ..setSession(session)
            ..instrumentCatalog = [spot()];
      final state = _SpotState(api)..session = session;
      addTearDown(() async {
        state.dispose();
        http.close(force: true);
        await server.close(force: true);
      });
      await amendSpot(state);
      expect(state.tradingCommandPending, isTrue);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(methods, ['POST', 'GET', 'GET']);
    },
  );

  test(
    'spot amendment persists its original request before POST and survives cold start without resending',
    () async {
      final settings = _MemorySettings(), api = _SpotApi();
      api.beforeAmend = () {
        final saved = asMap(
          asList(jsonDecode(settings.values['pendingTradingOrders']!)).single,
        );
        expect(saved['amendOrderId'], 91);
        expect(saved['amendRequestId'], api.lastAmend!['clientRequestId']);
      };
      final state = _SpotState(api, settings: settings)..session = session;
      await amendSpot(state);
      final key = state.pendingTradingCommand?.amendRequestId;
      expect(key, startsWith('app-amend-'));
      expect(
        api.lastAmend!['clientRequestId'],
        api.lastAmend!['newClientOrderId'],
      );
      expect(api.lastAmend!['priceTicks'], 110);
      expect(api.lastAmend!['quantitySteps'], 3);
      await amendSpot(state);
      await submitSpot(state);
      expect(api.amendments, 1);
      expect(api.calls, 0);
      state.dispose();
      final restored = _SpotState(api, settings: settings);
      addTearDown(restored.dispose);
      await restored.bootstrap();
      restored.session = session;
      expect(restored.pendingTradingCommand?.amendRequestId, key);
      await restored.checkPendingTradingCommand();
      expect(restored.tradingCommandPending, isTrue);
      api.terminal = true;
      await restored.checkPendingTradingCommand();
      expect(restored.tradingCommandPending, isFalse);
      expect(api.amendments, 1);
      expect(api.amendQueries, 2);
      expect(restored.lastNotice, contains('改单处理结果已确认'));
    },
  );
  test(
    'spot amendment does not send on storage or precision failure and keeps query errors locked',
    () async {
      final settings = _MemorySettings()..failWrites = true;
      final api = _SpotApi();
      final active = _SpotState(api, settings: settings)..session = session;
      addTearDown(active.dispose);
      await amendSpot(active);
      expect(api.amendments, 0);
      expect(active.lastError, contains('未发送改单'));
      settings.failWrites = false;
      await active.amendSpotOrder(cancelTarget(), spot(), '1.101', '0.0003');
      expect(api.amendments, 0);
      api.amendFailure = PendingTradingCommand('amend-1');
      await amendSpot(active);
      api.queryFailure = ApiException(503, 'unavailable');
      await active.checkPendingTradingCommand();
      expect(active.tradingCommandPending, isTrue);
      api.queryFailure = null;
      api.terminal = true;
      api.submissionCode = 'INSUFFICIENT_AVAILABLE_BALANCE';
      await active.checkPendingTradingCommand();
      expect(active.tradingCommandPending, isFalse);
      expect(active.lastError, contains('改单请求被拒绝'));
    },
  );
  test(
    'spot amendment retains both returned orders and preserves the 64 bit replacement ID',
    () async {
      final api = _SpotApi()
        ..amendResponse = (Completer<AmendOrderResult>()
          ..complete(amendmentResult()));
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      await amendSpot(state);
      expect(state.tradingCommandPending, isFalse);
      expect(state.lastNotice, contains('9007199254740993'));
      expect(
        state.openOrders.map((o) => o.orderId),
        contains(9007199254740993),
      );
    },
  );
  test(
    'late amendment response cannot mutate another user or notify a disposed state',
    () async {
      final api = _SpotApi()..amendResponse = Completer<AmendOrderResult>();
      final state = _SpotState(api)..session = session;
      final sent = amendSpot(state);
      while (api.amendments == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      state.session = const AuthSession(
        user: AuthUser(userId: 2, username: 'new', email: '', status: 'ACTIVE'),
        accessToken: 'new',
        refreshToken: 'new',
      );
      api.amendResponse!.complete(amendmentResult());
      await sent;
      expect(state.lastNotice, isNull);
      expect(state.openOrders, isEmpty);
      state.dispose();
      final lateApi = _SpotApi()..amendResponse = Completer<AmendOrderResult>();
      final disposed = _SpotState(lateApi)..session = session;
      final late = amendSpot(disposed);
      while (lateApi.amendments == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      disposed.dispose();
      lateApi.amendResponse!.completeError(const SocketException('lost reply'));
      await late;
    },
  );
  test(
    'real HTTP spot amendment sends the required request ID and decodes both order images',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, dynamic>? sent;
      server.listen((request) async {
        expect(request.uri.path, '/api/v1/gateway/trading/amend');
        expect(request.headers.value('X-Product-Line'), 'SPOT');
        sent = asMap(jsonDecode(await utf8.decoder.bind(request).join()));
        expect(sent!['clientRequestId'], sent!['newClientOrderId']);
        expect(sent!['timeInForce'], 'GTC');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'outcome': 'TERMINAL',
            'code': 'NONE',
            'result': {
              'cancelRequested': true,
              'originalOrder': {
                'orderId': 91,
                'instrumentId': '1',
                'status': 'CANCELED',
              },
              'replacementOrder': {
                'orderId': 9007199254740993,
                'instrumentId': '1',
                'status': 'ACCEPTED',
              },
            },
          }),
        );
        await request.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      final api =
          ApiClient(
              AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
              httpClient: http,
            )
            ..setSession(session)
            ..instrumentCatalog = [spot()];
      final state = _SpotState(api)..session = session;
      addTearDown(() async {
        state.dispose();
        http.close(force: true);
        await server.close(force: true);
      });
      await amendSpot(state);
      expect(sent, isNotNull);
      expect(state.tradingCommandPending, isFalse);
      expect(state.lastNotice, contains('9007199254740993'));
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'spot amendment row editor and recovery work at 320px ${brightness.name}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _SpotApi();
        final state = _SpotState(api)
          ..session = session
          ..openOrders = [cancelTarget()];
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: TradePage()),
            ),
          ),
        );
        final orders = find.text('当前委托 (1)');
        await tester.ensureVisible(orders);
        await tester.tap(orders);
        await tester.pumpAndSettle();
        final edit = find.widgetWithText(TextButton, '改单');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final price = find
            .descendant(
              of: find.byType(SpotAmendOrderSheet),
              matching: find.byType(TextField),
            )
            .first;
        await tester.enterText(price, '1.10');
        await tester.tap(find.text('确认改单'));
        await tester.pumpAndSettle();
        expect(api.amendments, 1);
        expect(state.tradingCommandPending, isTrue);
        final check = find.descendant(
          of: find.byType(PrivateTradingPanel),
          matching: find.text('查询改单结果'),
        );
        await tester.ensureVisible(check);
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isTrue);
        api.terminal = true;
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isFalse);
        expect(api.amendments, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'loopback HTTP cancellation loses the POST reply then recovers by read only with a 64 bit order ID',
    () async {
      const orderId = 9007199254740993;
      final requests = <String>[];
      var terminal = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        requests.add('${request.method} ${request.uri.path}');
        expect(request.headers.value('X-Product-Line'), 'SPOT');
        expect(request.headers.value('X-User-Id'), '1');
        final body = await utf8.decoder.bind(request).join();
        if (request.method == 'POST') {
          expect(asMap(jsonDecode(body))['orderId'], orderId);
          final socket = await request.response.detachSocket(
            writeHeaders: false,
          );
          socket.destroy();
        } else {
          expect(
            request.uri.path,
            '/api/v1/gateway/trading/cancellations/$orderId',
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'commandId': 'cancel-1',
              'prospectiveOrderIds': [orderId],
              'outcome': terminal ? 'TERMINAL' : 'RESULT_UNKNOWN',
              'code': terminal ? 'NONE' : 'RESULT_UNKNOWN',
            }),
          );
          await request.response.close();
        }
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      )..setSession(session);
      final state = _SpotState(api)..session = session;
      addTearDown(() async {
        state.dispose();
        http.close(force: true);
        await server.close(force: true);
      });
      await state.cancelOrder(cancelTarget(id: orderId));
      expect(state.pendingTradingCommand?.cancelOrderId, orderId);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      terminal = true;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(requests, [
        'POST /api/v1/gateway/trading/cancel',
        'GET /api/v1/gateway/trading/cancellations/$orderId',
        'GET /api/v1/gateway/trading/cancellations/$orderId',
      ]);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'spot cancellation stays locked until confirmed on a 320px ${brightness.name} screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _SpotApi();
        final state = _SpotState(api)..session = session;
        state.openOrders = [cancelTarget()];
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: TradePage()),
            ),
          ),
        );
        final ordersTab = find.text('当前委托 (1)');
        await tester.ensureVisible(ordersTab);
        await tester.tap(ordersTab);
        await tester.pumpAndSettle();
        final cancel = find.widgetWithText(TextButton, '撤单');
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(api.cancellations, 1);
        expect(state.tradingCommandPending, isTrue);
        // Pending cancellation removes the active action from every visible order row.
        expect(find.widgetWithText(TextButton, '撤单'), findsNothing);
        final check = find.descendant(
          of: find.byType(PrivateTradingPanel),
          matching: find.text('查询撤单结果'),
        );
        await tester.ensureVisible(check);
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isTrue);
        api.terminal = true;
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isFalse);
        expect(api.cancellations, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'spot cancellation survives lost response and cold start without resending',
    () async {
      final settings = _MemorySettings(), api = _SpotApi();
      api.beforeCancel = () {
        final saved = asMap(
          asList(jsonDecode(settings.values['pendingTradingOrders']!)).single,
        );
        expect(saved['cancelOrderId'], 91);
        expect(saved['productLine'], 'SPOT');
      };
      final state = _SpotState(api, settings: settings)..session = session;
      await state.cancelOrder(cancelTarget());
      expect(state.pendingTradingCommand?.cancelOrderId, 91);
      await state.cancelOrder(cancelTarget(id: 92));
      await submitSpot(state);
      expect(api.cancellations, 1);
      expect(api.calls, 0);
      state.dispose();
      final restored = _SpotState(api, settings: settings);
      addTearDown(restored.dispose);
      await restored.bootstrap();
      restored.session = session;
      expect(restored.pendingTradingCommand?.cancelOrderId, 91);
      await restored.checkPendingTradingCommand();
      expect(restored.tradingCommandPending, isTrue);
      api.terminal = true;
      await restored.checkPendingTradingCommand();
      expect(restored.tradingCommandPending, isFalse);
      expect(restored.lastNotice, contains('撤单处理结果已确认'));
      expect(api.cancellations, 1);
      expect(api.cancelQueries, 2);
      expect(jsonDecode(settings.values['pendingTradingOrders']!), isEmpty);
    },
  );
  test(
    'spot cancellation sends nothing on storage failure and clears definitive refusal',
    () async {
      final settings = _MemorySettings()..failWrites = true;
      final api = _SpotApi();
      final active = _SpotState(api, settings: settings)..session = session;
      addTearDown(active.dispose);
      await active.cancelOrder(cancelTarget());
      expect(api.cancellations, 0);
      expect(active.lastError, contains('未发送撤单'));
      expect(active.tradingCommandPending, isFalse);
      settings.failWrites = false;
      api.cancelFailure = ApiException(400, 'invalid order');
      await active.cancelOrder(cancelTarget());
      expect(active.tradingCommandPending, isFalse);
      expect(api.cancellations, 1);
    },
  );
  test(
    'spot cancellation keeps unavailable or mismatched queries pending and recovers a committed rejection',
    () async {
      final api = _SpotApi()..cancelFailure = PendingTradingCommand('cancel-1');
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      await state.cancelOrder(cancelTarget());
      api.queryFailure = ApiException(503, 'view unavailable');
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      api.queryFailure = null;
      api.recoveredCancelId = 92;
      api.terminal = true;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      expect(state.lastError, contains('不匹配'));
      api.recoveredCancelId = 91;
      api.submissionCode = 'ORDER_NOT_FOUND';
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(state.lastError, contains('撤单请求被拒绝'));
      expect(api.cancellations, 1);
    },
  );
  test(
    'malformed cancellation replies stay pending and late responses cannot mutate another user or disposed state',
    () async {
      final api = _SpotApi()..cancelResponse = Completer<OrderModel>();
      final state = _SpotState(api)..session = session;
      final sent = state.cancelOrder(cancelTarget());
      while (api.cancellations == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      state.session = const AuthSession(
        user: AuthUser(userId: 2, username: 'new', email: '', status: 'ACTIVE'),
        accessToken: 'new',
        refreshToken: 'new',
      );
      api.cancelResponse!.complete(cancelTarget(id: 92, status: 'CANCELED'));
      await sent;
      expect(state.lastNotice, isNull);
      expect(state.lastError, isNull);
      state.session = session;
      expect(state.pendingTradingCommand?.cancelOrderId, 91);
      state.dispose();
      final disposedApi = _SpotApi()..cancelResponse = Completer<OrderModel>();
      final disposed = _SpotState(disposedApi)..session = session;
      final late = disposed.cancelOrder(cancelTarget());
      while (disposedApi.cancellations == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      disposed.dispose();
      disposedApi.cancelResponse!.completeError(
        PendingTradingCommand('cancel-1'),
      );
      await late;
    },
  );

  test(
    'a committed rejected submission is recovered without an order entity',
    () async {
      final api = _SpotApi();
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      await submitSpot(state);
      api.queryFailure = ApiException(503, 'order view not initialized');
      api.terminal = true;
      api.submissionCode = 'ORDER_NOT_FOUND';
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(state.lastError, contains('委托未被接受'));
      expect(api.calls, 1);
      expect(api.submissionQueries, 1);
      expect(api.commandQueries, 0);
    },
  );
  test(
    'malformed spot responses and unavailable or mismatched projections keep the original intent',
    () async {
      final api = _SpotApi()
        ..response = (Completer<OrderModel>()
          ..complete(OrderModel.fromJson({})));
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      await submitSpot(state);
      expect(state.tradingCommandPending, isTrue);
      expect(state.pendingTradingCommand?.commandId, isNull);
      api.queryFailure = ApiException(503, 'view unavailable');
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      api.queryFailure = null;
      api.orderFound = true;
      api.recoveryUser = 2;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      expect(state.lastError, contains('资料不匹配'));
      api.recoveryUser = 1;
      api.recoveredStatus = 'CANCELED';
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(api.calls, 1);
      expect(api.commandQueries, 0);
    },
  );
  test(
    'a late pending spot response does not notify a disposed state',
    () async {
      final api = _SpotApi()..response = Completer<OrderModel>();
      final state = _SpotState(api)..session = session;
      final sent = submitSpot(state);
      for (var i = 0; api.calls == 0 && i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(api.calls, 1);
      state.dispose();
      api.response!.completeError(PendingTradingCommand('123'));
      await sent;
    },
  );
  test(
    'an old refresh cannot replay a spot POST or replace a newer account',
    () async {
      final refreshSeen = Completer<void>(), release = Completer<void>();
      var posts = 0, callbacks = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        if (request.uri.path.endsWith('/auth/refresh')) {
          refreshSeen.complete();
          await release.future;
          request.response.write(
            jsonEncode({
              'accessToken': 'refreshed',
              'refreshToken': 'rotated',
              'user': {
                'userId': 1,
                'username': 'old',
                'email': '',
                'status': 'ACTIVE',
              },
            }),
          );
        } else if (request.uri.path.endsWith('/trading')) {
          posts++;
          request.response.statusCode = 401;
          request.response.write('{}');
        } else {
          expect(request.headers.value('Authorization'), 'Bearer other');
          request.response.write('{}');
        }
        await request.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      )..setSession(session);
      api.onSessionRefreshed = (_) async {
        callbacks++;
      };
      final submitted = api.placeOrder(
        userId: 1,
        symbol: 'BTC-USDT',
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        priceTicks: 1000,
        quantitySteps: 1,
        marginMode: 'CROSS',
        positionSide: 'NET',
        reduceOnly: false,
        postOnly: false,
        productLine: 'SPOT',
        clientOrderId: 'refresh-test',
      );
      final rejected = expectLater(submitted, throwsA(isA<ApiException>()));
      await refreshSeen.future;
      api.setSession(
        const AuthSession(
          user: AuthUser(
            userId: 2,
            username: 'other',
            email: '',
            status: 'ACTIVE',
          ),
          accessToken: 'other',
          refreshToken: 'other-refresh',
        ),
      );
      release.complete();
      await rejected;
      await api.get('/probe', userId: 2);
      expect(posts, 1);
      expect(callbacks, 0);
    },
  );
  test(
    'spot recovery survives a cold start and verifies the original client ID through realtime',
    () async {
      final settings = _MemorySettings();
      final api = _SpotApi()..failure = const SocketException('lost response');
      api.beforePlace = () {
        final saved = asMap(
          asList(jsonDecode(settings.values['pendingTradingOrders']!)).single,
        );
        expect(saved['clientOrderId'], api.lastClientOrderId);
        expect(saved['instrumentId'], '1');
      };
      final state = _SpotState(api, settings: settings)..session = session;
      await submitSpot(state);
      final clientId = state.pendingTradingCommand?.clientOrderId;
      expect(clientId, startsWith('app-'));
      await submitSpot(state);
      expect(api.calls, 1);
      state.dispose();
      final restored = _SpotState(api, settings: settings);
      addTearDown(restored.dispose);
      await restored.bootstrap();
      restored.session = session;
      expect(restored.pendingTradingCommand?.clientOrderId, clientId);
      await restored.checkPendingTradingCommand();
      expect(restored.tradingCommandPending, isTrue);
      api.orderFound = true;
      await restored.checkPendingTradingCommand();
      expect(restored.tradingCommandPending, isFalse);
      expect(api.calls, 1);
      expect(api.commandQueries, 0);
      expect(jsonDecode(settings.values['pendingTradingOrders']!), isEmpty);
    },
  );
  test(
    'spot storage failure prevents sending, while definite validation rejection releases the intent',
    () async {
      final api = _SpotApi()..failure = ApiException(400, 'invalid quantity');
      final settings = _MemorySettings()..failWrites = true;
      final state = _SpotState(api, settings: settings)..session = session;
      addTearDown(state.dispose);
      await submitSpot(state);
      expect(api.calls, 0);
      expect(state.tradingCommandPending, isFalse);
      expect(state.lastError, contains('未发送订单'));
      settings.failWrites = false;
      await submitSpot(state);
      expect(api.calls, 1);
      expect(state.tradingCommandPending, isFalse);
      expect(jsonDecode(settings.values['pendingTradingOrders']!), isEmpty);
      api.failure = ApiException(503, 'unavailable');
      await submitSpot(state);
      expect(state.tradingCommandPending, isTrue);
    },
  );
  test(
    'late spot response preserves the old user intent without changing a new session',
    () async {
      final api = _SpotApi()..response = Completer<OrderModel>();
      final settings = _MemorySettings();
      final state = _SpotState(api, settings: settings)..session = session;
      addTearDown(state.dispose);
      final sent = submitSpot(state);
      for (var i = 0; api.calls == 0 && i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(api.calls, 1);
      await state.logout();
      state.session = const AuthSession(
        user: AuthUser(
          userId: 2,
          username: 'other',
          email: '',
          status: 'ACTIVE',
        ),
        accessToken: 'other',
        refreshToken: 'other',
      );
      state.lastNotice = 'new user';
      api.response!.completeError(const SocketException('lost response'));
      await sent;
      expect(state.lastNotice, 'new user');
      expect(state.tradingCommandPending, isFalse);
      api.response = null;
      api.failure = const SocketException('second user response lost');
      await submitSpot(state);
      final secondClientId = state.pendingTradingCommand?.clientOrderId;
      expect(secondClientId, isNotNull);
      state.session = session;
      expect(state.tradingCommandPending, isTrue);
      expect(state.pendingTradingCommand?.clientOrderId, isNot(secondClientId));
      expect(
        asList(jsonDecode(settings.values['pendingTradingOrders']!)),
        hasLength(2),
      );
    },
  );
  test(
    'a real HTTP response loss recovers by client ID with a single POST',
    () async {
      final methods = <String>[];
      Map<String, dynamic>? posted;
      final settings = _MemorySettings();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        methods.add('${request.method} ${request.uri.path}');
        expect(request.headers.value('X-Product-Line'), 'SPOT');
        if (request.method == 'POST') {
          posted = asMap(jsonDecode(await utf8.decoder.bind(request).join()));
          expect(
            asMap(
              asList(
                jsonDecode(settings.values['pendingTradingOrders']!),
              ).single,
            )['clientOrderId'],
            posted!['clientOrderId'],
          );
          (await request.response.detachSocket(writeHeaders: false)).destroy();
        } else {
          expect(
            request.uri.queryParameters['clientOrderId'],
            posted!['clientOrderId'],
          );
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              ...posted!,
              'productLine': 'SPOT',
              'commandId': '11111111-1111-1111-1111-111111111111',
              'outcome': 'TERMINAL',
              'code': 'NONE',
            }),
          );
          await request.response.close();
        }
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      );
      final state = _SpotState(api, settings: settings)..session = session;
      addTearDown(state.dispose);
      await submitSpot(state);
      expect(state.tradingCommandPending, isTrue);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(methods, [
        'POST /api/v1/gateway/trading',
        'GET /api/v1/gateway/trading/submission',
      ]);
    },
  );
  test(
    'unanswered spot submission stays pending after the transport fails',
    () async {
      final api = _SpotApi()..failure = const SocketException('lost response');
      final settings = _MemorySettings();
      final state = _SpotState(api, settings: settings)..session = session;
      addTearDown(state.dispose);
      await state.placeOrder(
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        price: 0,
        quantitySteps: 2,
        marginMode: 'CROSS',
        positionSide: 'NET',
        reduceOnly: false,
        postOnly: false,
        bboPriceMode: 'OPPONENT_1',
      );
      expect(state.tradingCommandPending, isTrue);
      expect(api.calls, 1);
    },
  );
  testWidgets(
    'spot book selection and order quantities use authoritative asset scales',
    (tester) async {
      final spec = Instrument.fromJson({
        'symbol': 'BTC-USDT',
        'contractType': 'SPOT',
        'baseAsset': 'BTC',
        'quoteAsset': 'USDT',
        'baseScaleUnits': 1000000,
        'quoteScaleUnits': '1000000000000000000',
        'priceTickUnits': 1,
        'quantityStepUnits': 10,
        'pricePrecision': 2,
      });
      String? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BookLine(
              level: const OrderBookLevel(
                priceTicks: 9007199254740993,
                quantitySteps: 12,
                orderCount: 1,
              ),
              maxQuantity: 12,
              instrument: spec,
              color: Colors.green,
              onTap: (price) => selected = price,
            ),
          ),
        ),
      );
      expect(find.text('0.009007199254740993'), findsOneWidget);
      expect(find.text('0.00012'), findsOneWidget);
      await tester.tap(find.byType(BookLine));
      expect(selected, '0.009007199254740993');
      expect(tradingQuantity(spec, 12), '0.00012 BTC');
      final orderSpec = Instrument.fromJson({
        'symbol': 'BTC-USDT',
        'contractType': 'SPOT',
        'baseAsset': 'BTC',
        'quoteAsset': 'USDT',
        'settleAsset': 'USDT',
        'baseScaleUnits': 1000000,
        'quoteScaleUnits': 1000,
        'priceTickUnits': 100,
        'quantityStepUnits': 10,
        'pricePrecision': 2,
      });
      expect(tradingAmount(1000, orderSpec), '1 USDT');
      expect(tradingAmount(1000, Instrument.empty(ProductMode.spot)), '--');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OrderRow(
              order: OrderModel.fromJson({
                'orderId': 1,
                'symbol': 'BTC-USDT',
                'status': 'FILLED',
                'priceTicks': 1000,
                'quantitySteps': 12,
                'executedQuantitySteps': 12,
                'remainingQuantitySteps': 0,
                'averagePriceTicks': '1000.5',
              }),
              instrument: orderSpec,
              onCancel: null,
            ),
          ),
        ),
      );
      expect(find.text('100.05'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test(
    'spot manual prices reach the API as exact ticks without a double round trip',
    () async {
      final api = _SpotApi();
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      await state.placeOrder(
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        price: 0.009007199254740993,
        priceText: '0.009007199254740993',
        quantitySteps: 2,
        marginMode: 'CROSS',
        positionSide: 'NET',
        reduceOnly: false,
        postOnly: false,
        targetInstrument: Instrument.fromJson({
          'instrumentId': '1',
          'symbol': 'BTC-USDT',
          'contractType': 'SPOT',
          'priceTickUnits': 1,
          'quoteScaleUnits': '1000000000000000000',
          'status': 'TRADING',
        }),
      );
      expect(api.last?['ticks'], 9007199254740993);
    },
  );
  test(
    'late spot terms cannot cross user identity or notify a disposed state',
    () async {
      final api = _TermsApi();
      final state =
          AppState(
              apiClient: api,
              seedInstruments: [spot()],
              config: const AppConfig(websocketUrl: ''),
            )
            ..mode = ProductMode.spot
            ..session = session;
      final request = state.refreshOrderTerms();
      state.session = const AuthSession(
        user: AuthUser(
          userId: 2,
          username: 'other',
          email: '',
          status: 'ACTIVE',
        ),
        accessToken: 'other',
        refreshToken: 'other',
      );
      api.result.complete((takerFeeRatePpm: 1000, marketMaxSlippagePpm: 10000));
      await request;
      expect(state.spotOrderTerms, isNull);
      state.dispose();
      final lateApi = _TermsApi();
      final disposed =
          AppState(
              apiClient: lateApi,
              seedInstruments: [spot()],
              config: const AppConfig(websocketUrl: ''),
            )
            ..mode = ProductMode.spot
            ..session = session;
      final late = disposed.refreshOrderTerms();
      disposed.dispose();
      lateApi.result.complete((
        takerFeeRatePpm: 1000,
        marketMaxSlippagePpm: 10000,
      ));
      await late;
    },
  );
  test(
    'spot terms decoder rejects mismatched fee identity instead of guessing a fee',
    () async {
      var wrongProduct = false;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path.contains('trading-fees')
                ? {
                    'userId': 1,
                    'productLine': wrongProduct ? 'LINEAR_PERPETUAL' : 'SPOT',
                    'instrumentId': '1',
                    'changeId': 1,
                    'takerFeeRatePpm': 1234,
                  }
                : {'productLine': 'SPOT', 'marketMaxSlippagePpm': 2345},
          ),
        );
        await request.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      );
      expect(await api.spotOrderTerms(1, spot()), (
        takerFeeRatePpm: 1234,
        marketMaxSlippagePpm: 2345,
      ));
      wrongProduct = true;
      await expectLater(api.spotOrderTerms(1, spot()), throwsFormatException);
    },
  );
  test(
    'spot BBO payload keeps product identity and decodes terminal order receipts',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body = asMap(jsonDecode(await utf8.decoder.bind(request).join()));
        requests.add({
          ...body,
          'product': request.headers.value('X-Product-Line'),
        });
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'commandId': 'abc',
            'outcome': 'TERMINAL',
            'code': 'NONE',
            'result': {
              'resultType': 'order',
              'orderId': 42,
              'instrumentId': '1',
              'status': 'ACCEPTED',
              'side': 'BUY',
            },
          }),
        );
        await request.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      )..instrumentCatalog = [spot()];
      for (final mode in bboPriceModes) {
        final order = await api.placeOrder(
          userId: 1,
          symbol: 'BTC-USDT',
          side: 'BUY',
          orderType: 'LIMIT',
          timeInForce: 'GTC',
          priceTicks: 9999,
          quantitySteps: 2,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
          bboPriceMode: mode,
          productLine: 'SPOT',
        );
        expect(order.orderId, 42);
        expect(order.symbol, 'BTC-USDT');
        expect(requests.last['priceTicks'], 0);
        expect(requests.last['bboPriceMode'], mode);
        expect(requests.last['instrumentId'], '1');
        expect(requests.last['product'], 'SPOT');
      }
      await expectLater(
        api.testOrder(
          userId: 1,
          symbol: 'BTC-USDT',
          side: 'BUY',
          orderType: 'MARKET',
          timeInForce: 'GTC',
          priceTicks: 0,
          quantitySteps: 1,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
          productLine: 'SPOT',
        ),
        throwsFormatException,
      );
      expect(requests, hasLength(4));
    },
  );

  test(
    'spot uses fixed account semantics and blocks pending commands until explicitly confirmed',
    () async {
      final api = _SpotApi();
      final settings = _MemorySettings();
      final state = _SpotState(api, settings: settings)..session = session;
      addTearDown(state.dispose);
      Future<void> place() => state.placeOrder(
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        price: 0,
        quantitySteps: 2,
        marginMode: 'ISOLATED',
        positionSide: 'LONG',
        reduceOnly: true,
        postOnly: false,
        bboPriceMode: 'OPPONENT_5',
      );
      await place();
      expect(api.calls, 1);
      expect(api.last, {
        'margin': 'CROSS',
        'position': 'NET',
        'reduce': false,
        'ticks': 0,
        'bbo': 'OPPONENT_5',
        'product': 'SPOT',
      });
      expect(state.tradingCommandPending, isTrue);
      final stored = asMap(
        asList(jsonDecode(settings.values['pendingTradingOrders']!)).single,
      );
      expect(stored['commandId'], '123');
      expect(stored['productLine'], 'SPOT');
      expect(stored['userId'], 1);
      expect(stored['clientOrderId'], api.lastClientOrderId);
      expect(state.lastError, isNull);
      expect(state.lastNotice, contains('待确认'));
      await place();
      expect(api.calls, 1);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      api.lookupNotAccepted = true;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      api.lookupNotAccepted = false;
      api.terminal = true;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isFalse);
      expect(jsonDecode(settings.values['pendingTradingOrders']!), isEmpty);
      expect(state.lastNotice, contains('已确认'));
      expect(api.submissionQueries, 3);
      expect(api.commandQueries, 0);
    },
  );

  test(
    'paused spot or conflicting execution policy never reaches order submission',
    () async {
      final api = _SpotApi();
      final state = _SpotState(api)..session = session;
      addTearDown(state.dispose);
      for (final tif in ['GTC', 'GTX']) {
        await state.placeOrder(
          side: 'BUY',
          orderType: 'MARKET',
          timeInForce: tif,
          price: 0,
          quantitySteps: 1,
          marginMode: 'CROSS',
          positionSide: 'NET',
          reduceOnly: false,
          postOnly: false,
        );
        expect(state.lastError, contains('市价单'));
      }
      state.instruments = [spot(status: 'PAUSED')];
      await state.placeOrder(
        side: 'BUY',
        orderType: 'LIMIT',
        timeInForce: 'GTC',
        price: 1,
        quantitySteps: 1,
        marginMode: 'CROSS',
        positionSide: 'NET',
        reduceOnly: false,
        postOnly: false,
      );
      expect(state.lastError, contains('暂停'));
      expect(api.calls, 0);
    },
  );

  for (final brightness in Brightness.values) {
    testWidgets(
      'spot BBO and market controls fit a 320px ${brightness.name} ticket',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _SpotApi()
          ..failure = const SocketException('response lost');
        final state = _SpotState(api)..session = session;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: TradePage()),
            ),
          ),
        );
        expect(find.text('只减仓'), findsNothing);
        await tester.ensureVisible(find.text('BBO 最优价'));
        await tester.tap(find.text('BBO 最优价'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('bbo-price-mode')), findsOneWidget);
        expect(find.text('对手价 1'), findsOneWidget);
        final percentage = find.byKey(const ValueKey('spot-percent-100'));
        await tester.ensureVisible(percentage);
        state.termsReady = false;
        state.notifyListeners();
        await tester.pump();
        expect(tester.widget<TextButton>(percentage).onPressed, isNull);
        expect(find.text('刷新下单资料'), findsOneWidget);
        state.termsReady = true;
        state.notifyListeners();
        await tester.pump();
        await tester.tap(percentage);
        await tester.pumpAndSettle();
        final sizedTicket = tester.widget<OrderTicket>(
          find.byType(OrderTicket),
        );
        expect(sizedTicket.quantityController.text, '0.0098');
        expect(tester.takeException(), isNull);
        final orderType = find.byWidgetPredicate(
          (w) => w is SmallDropdown && w.value == 'LIMIT',
        );
        for (final scroll in tester.stateList<ScrollableState>(
          find.ancestor(of: orderType, matching: find.byType(Scrollable)),
        )) {
          scroll.position.jumpTo(0);
        }
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: orderType,
            matching: find.byType(DropdownButton<String>),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('市价单').last);
        await tester.pumpAndSettle();
        final ticket = tester.widget<OrderTicket>(find.byType(OrderTicket));
        expect(ticket.timeInForce, 'IOC');
        expect(ticket.postOnly, isFalse);
        expect(ticket.bboEnabled, isFalse);
        expect(find.byKey(const ValueKey('bbo-price-mode')), findsNothing);
        ticket.quantityController.text = '0.001';
        final submitButton = find
            .ancestor(
              of: find
                  .descendant(
                    of: find.byType(OrderTicket),
                    matching: find.text('买入'),
                  )
                  .last,
              matching: find.byWidgetPredicate((w) => w is FilledButton),
            )
            .first;
        await tester.ensureVisible(submitButton);
        await tester.tap(submitButton);
        await tester.pumpAndSettle();
        expect(api.calls, 1);
        expect(state.tradingCommandPending, isTrue);
        expect(tester.widget<FilledButton>(submitButton).onPressed, isNull);
        final checkResult = find.text('查询委托结果');
        await tester.ensureVisible(checkResult);
        await tester.tap(checkResult);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isTrue);
        api.orderFound = true;
        await tester.tap(checkResult);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isFalse);
        expect(api.calls, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _RealHttp extends HttpOverrides {}

class _TermsApi extends ApiClient {
  _TermsApi() : super(const AppConfig());
  final result = Completer<({int takerFeeRatePpm, int marketMaxSlippagePpm})>();
  @override
  Future<({int takerFeeRatePpm, int marketMaxSlippagePpm})> spotOrderTerms(
    int userId,
    Instrument instrument,
  ) => result.future;
}

class _SpotState extends AppState {
  bool termsReady = true;
  _SpotState(ApiClient api, {ClientSettingsStore? settings})
    : super(
        apiClient: api,
        settingsStore: settings ?? _MemorySettings(),
        sessionStore: _EmptySessionStore(),
        seedInstruments: [spot()],
        config: const AppConfig(websocketUrl: ''),
      ) {
    mode = ProductMode.spot;
    balances = const [
      ProductBalance(
        accountType: 'SPOT',
        asset: 'USDT',
        availableUnits: 100000000,
        lockedUnits: 0,
        equityUnits: 100000000,
      ),
    ];
    orderBook = OrderBook(
      symbol: 'BTC-USDT',
      sequence: 1,
      bids: [10000, 9900, 9800, 9700, 9600]
          .map(
            (p) => OrderBookLevel(
              priceTicks: p,
              quantitySteps: 100,
              orderCount: 1,
            ),
          )
          .toList(),
      asks: [10100, 10200, 10300, 10400, 10500]
          .map(
            (p) => OrderBookLevel(
              priceTicks: p,
              quantitySteps: 100,
              orderCount: 1,
            ),
          )
          .toList(),
    );
  }
  @override
  ({int takerFeeRatePpm, int marketMaxSlippagePpm})? get spotOrderTerms =>
      termsReady ? (takerFeeRatePpm: 1000, marketMaxSlippagePpm: 10000) : null;
  @override
  Future<void> refreshPrivateData() async {}
  @override
  Future<void> refreshInstruments({bool silent = false}) async {}
  @override
  Future<void> refreshValuation({bool silent = false}) async {}
  @override
  Future<void> refreshPublicData({bool silent = false}) async {}
  @override
  Future<void> refreshAnnouncements() async {}
}

class _SpotApi extends ApiClient {
  _SpotApi() : super(const AppConfig());
  int calls = 0, commandQueries = 0, submissionQueries = 0;
  int cancellations = 0, cancelQueries = 0;
  int? recoveredCancelId;
  VoidCallback? beforeCancel;
  Object cancelFailure = const SocketException('lost cancellation response');
  Completer<OrderModel>? cancelResponse;
  @override
  Future<OrderModel> cancelOrder(
    int userId,
    int orderId, {
    String? productLine,
  }) async {
    expect(productLine, 'SPOT');
    cancellations++;
    beforeCancel?.call();
    if (cancelResponse != null) return cancelResponse!.future;
    throw cancelFailure;
  }

  int amendments = 0, amendQueries = 0;
  Map<String, dynamic>? lastAmend;
  VoidCallback? beforeAmend;
  Object amendFailure = const SocketException('lost amendment response');
  Completer<AmendOrderResult>? amendResponse;
  @override
  Future<AmendOrderResult> amendOrder({
    required int userId,
    required int orderId,
    int? priceTicks,
    int? quantitySteps,
    String? timeInForce,
    bool? postOnly,
    String? newClientOrderId,
    String? clientRequestId,
    String? productLine,
  }) async {
    expect(productLine, 'SPOT');
    amendments++;
    lastAmend = {
      'clientRequestId': clientRequestId,
      'newClientOrderId': newClientOrderId,
      'priceTicks': priceTicks,
      'quantitySteps': quantitySteps,
    };
    beforeAmend?.call();
    if (amendResponse != null) return amendResponse!.future;
    throw amendFailure;
  }

  String submissionCode = 'NONE';
  bool terminal = false;
  bool lookupNotAccepted = false, orderFound = false;
  Object? queryFailure;
  int? recoveryUser;
  String recoveredStatus = 'FILLED';
  String? lastClientOrderId;
  VoidCallback? beforePlace;
  Completer<OrderModel>? response;
  Object? failure;
  Map<String, dynamic>? last;
  @override
  Future<OrderModel> placeOrder({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? bboPriceMode,
    String? productLine,
    String? clientOrderId,
  }) async {
    calls++;
    lastClientOrderId = clientOrderId;
    beforePlace?.call();
    last = {
      'margin': marginMode,
      'position': positionSide,
      'reduce': reduceOnly,
      'ticks': priceTicks,
      'bbo': bboPriceMode,
      'product': productLine,
    };
    if (failure != null) throw failure!;
    if (response != null) return response!.future;
    throw PendingTradingCommand('123');
  }

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    if (path == '/api/v1/gateway/trading/amendments') {
      amendQueries++;
      expect(productLine, 'SPOT');
      expect(query?['clientRequestId'], lastAmend!['clientRequestId']);
      if (queryFailure != null) throw queryFailure!;
      return {
        'commandId': 'amend-1',
        'outcome': terminal ? 'TERMINAL' : 'RESULT_UNKNOWN',
        'code': terminal ? submissionCode : 'RESULT_UNKNOWN',
      };
    }
    if (path.startsWith('/api/v1/gateway/trading/cancellations/')) {
      cancelQueries++;
      expect(productLine, 'SPOT');
      expect(path, '/api/v1/gateway/trading/cancellations/91');
      expect(userId, 1);
      if (queryFailure != null) throw queryFailure!;
      return {
        'commandId': 'cancel-1',
        'prospectiveOrderIds': [recoveredCancelId ?? 91],
        'outcome': terminal ? 'TERMINAL' : 'RESULT_UNKNOWN',
        'code': terminal ? submissionCode : 'RESULT_UNKNOWN',
      };
    }
    if (path == '/api/v1/gateway/trading/submission') {
      submissionQueries++;
      expect(productLine, 'SPOT');
      expect(query?['clientOrderId'], lastClientOrderId);
      return {
        'userId': userId,
        'productLine': 'SPOT',
        'clientOrderId': lastClientOrderId,
        'instrumentId': terminal ? '1' : null,
        'commandId': '123',
        'outcome': lookupNotAccepted
            ? 'NOT_ACCEPTED'
            : terminal
            ? 'TERMINAL'
            : 'RESULT_UNKNOWN',
        'code': terminal ? submissionCode : 'RESULT_UNKNOWN',
      };
    }
    if (path == '/api/v1/gateway/trading/by-client-order-id') {
      if (queryFailure != null) throw queryFailure!;
      expect(productLine, 'SPOT');
      expect(query?['clientOrderId'], lastClientOrderId);
      if (!orderFound) throw ApiException(404, 'not found');
      return {
        'orderId': 42,
        'userId': recoveryUser ?? userId,
        'clientOrderId': query?['clientOrderId'],
        'instrumentId': '1',
        'status': recoveredStatus,
      };
    }
    expect(path, '/api/v1/gateway/trading/commands/123');
    expect(productLine, 'SPOT');
    commandQueries++;
    return {
      'commandId': '123',
      'outcome': lookupNotAccepted
          ? 'NOT_ACCEPTED'
          : terminal
          ? 'TERMINAL'
          : 'MATCHING_PENDING',
      'code': terminal ? 'NONE' : 'MATCHING_PENDING',
    };
  }
}

class _MemorySettings implements ClientSettingsStore {
  bool failWrites = false;
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> values) async {
    if (failWrites) throw const FileSystemException('storage unavailable');
    this.values = {...values};
  }
}

class _EmptySessionStore implements SessionStore {
  @override
  Future<AuthSession?> readSession() async => null;
  @override
  Future<void> saveSession(AuthSession session) async {}
  @override
  Future<void> clear() async {}
  @override
  Future<bool> biometricEnabled() async => false;
  @override
  Future<bool> canUseBiometrics() async => false;
  @override
  Future<bool> authenticateBiometric() async => false;
  @override
  Future<void> enableBiometric() async {}
}

class _AmendPayloadApi extends ApiClient {
  _AmendPayloadApi() : super(const AppConfig());
  Map<String, dynamic>? sent;
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = false,
  }) async {
    expect(path, '/api/v1/gateway/trading/amend');
    sent = body;
    return {
      'originalOrder': {'orderId': 91},
      'replacementOrder': {'orderId': 92},
      'cancelRequested': true,
    };
  }
}
