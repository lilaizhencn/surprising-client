import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

const _session = AuthSession(
  user: AuthUser(userId: 1, username: 'spot', email: '', status: 'ACTIVE'),
  accessToken: 'test',
  refreshToken: 'test',
);
Instrument _instrument() => Instrument.fromJson({
  'instrumentId': '1',
  'symbol': 'BTC-USDT',
  'instrumentType': 'SPOT',
  'contractType': 'SPOT',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'status': 'TRADING',
  'priceTickUnits': 1000000,
  'quantityStepUnits': 10000,
  'pricePrecision': 2,
  'quantityPrecision': 4,
  'baseScaleUnits': 100000000,
  'quoteScaleUnits': 100000000,
  'changeId': 1,
});
final _ids = List.generate(120, (i) => 9007199254740993 + i);
Map<String, dynamic> _receipt(List<int> ids, {int failed = 0}) => {
  'commandId': 'command-1',
  'outcome': 'TERMINAL',
  'code': 'NONE',
  'prospectiveOrderIds': ids,
  'result': {
    'requested': ids.length,
    'completed': ids.length - failed,
    'failed': failed,
    'results': List.generate(
      ids.length,
      (i) => {
        'index': i,
        'success': i >= failed,
        'message': i >= failed ? 'NONE' : 'ORDER_NOT_FOUND',
        'order': null,
      },
    ),
  },
};
OrderBatchResult _result(List<int> ids, {int failed = 0}) =>
    OrderBatchResult.fromJson(asMap(_receipt(ids, failed: failed)['result']));
void main() {
  test(
    'a completed cancellation plan stays locked until its removal is persisted',
    () async {
      final settings = _Settings()..failRemoval = true;
      final api = _Api()..targets = [_ids.first];
      final state = _State(api, settings: settings)..session = _session;
      await state.cancelOpenSpotOrders(onlyCurrentPair: false);
      expect(api.posts, hasLength(1));
      expect(state.pendingTradingCommand?.cancelPlan?.index, 1);
      expect(state.lastCancellationResult, isNull);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      expect(api.posts, hasLength(1));
      state.dispose();

      settings.failRemoval = false;
      final restored = _State(api, settings: settings);
      addTearDown(restored.dispose);
      await restored.bootstrap();
      restored.session = _session;
      expect(restored.tradingCommandPending, isTrue);
      await restored.checkPendingTradingCommand();
      expect(restored.tradingCommandPending, isFalse);
      expect(restored.lastCancellationResult?.completed, 1);
      expect(api.posts, hasLength(1));
      expect(api.queries, 0);
      expect(jsonDecode(settings.values['pendingTradingOrders']!), isEmpty);
    },
  );

  test(
    'direct batch API generates or preserves the mandatory batch key',
    () async {
      final api = _PayloadApi();
      await api.cancelOrderBatch(1, [9007199254740993], productLine: 'SPOT');
      expect(api.body?['batchKey'], isNotEmpty);
      expect(
        asMap(asList(api.body?['orders']).single)['orderId'],
        9007199254740993,
      );
      await api.cancelOrderBatch(
        1,
        [91],
        batchKey: 'original-key',
        productLine: 'SPOT',
      );
      expect(api.body?['batchKey'], 'original-key');
    },
  );
  test(
    'fixes all targets beyond displayed pages and persists before native batches with partial results',
    () async {
      final api = _Api()
        ..targets = List.generate(1205, (i) => i + 1)
        ..failed = 1;
      final state = _State(api)..session = _session;
      addTearDown(state.dispose);
      api.beforePost = () {
        expect(state.pendingTradingCommand?.cancelPlan?.issued, isTrue);
        expect(state.pendingTradingCommand?.cancelPlan?.requested, 1205);
      };
      await state.cancelOpenSpotOrders(onlyCurrentPair: true);
      expect(api.scope, '1');
      expect(api.posts.length, 25);
      expect(api.posts.first.length, 50);
      expect(api.posts.last.length, 5);
      expect(api.keys.toSet().length, 25);
      expect(state.lastCancellationResult?.requested, 1205);
      expect(state.lastCancellationResult?.completed, 1180);
      expect(state.lastCancellationResult?.failed, 25);
      expect(state.tradingCommandPending, isFalse);
    },
  );
  test(
    'lost reply survives restart, only queries issued batch and continues original fixed targets',
    () async {
      final settings = _Settings(), api = _Api()..loseFirst = true;
      var state = _State(api, settings: settings)..session = _session;
      await state.cancelOpenSpotOrders(onlyCurrentPair: false);
      final key = state.pendingTradingCommand!.cancelPlan!.batches.first.key;
      expect(api.scope, isNull);
      expect(api.posts.length, 1);
      state.dispose();
      state = _State(api, settings: settings);
      addTearDown(state.dispose);
      await state.bootstrap();
      state.session = _session;
      expect(state.pendingTradingCommand!.cancelPlan!.batches.first.key, key);
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      expect(api.posts.length, 1);
      api.terminal = true;
      api.targets = [999];
      await state.checkPendingTradingCommand();
      expect(api.planReads, 1);
      expect(api.posts.length, 3);
      expect(api.posts.expand((ids) => ids), _ids);
      expect(api.keys.first, key);
      expect(api.queries, 2);
      expect(state.lastCancellationResult?.completed, 120);
      expect(state.tradingCommandPending, isFalse);
      expect(jsonDecode(settings.values['pendingTradingOrders']!), isEmpty);
    },
  );
  for (final failure in [
    'lookup400',
    'lookup503',
    'wrongIds',
    'badCount',
    'badCode',
    'missingResult',
    'missingSuccess',
  ]) {
    test('retains issued batch on $failure without another POST', () async {
      final api = _Api()
        ..targets = [_ids.first]
        ..loseFirst = true;
      final state = _State(api)..session = _session;
      addTearDown(state.dispose);
      await state.cancelOpenSpotOrders(onlyCurrentPair: false);
      api.terminal = true;
      api.queryFailure = failure;
      await state.checkPendingTradingCommand();
      expect(state.tradingCommandPending, isTrue);
      expect(api.posts.length, 1);
      expect(state.lastCancellationResult, isNull);
    });
  }
  for (final checkpoint in [1, 2, 3]) {
    test(
      'no repeated batch when storage fails at checkpoint $checkpoint',
      () async {
        final settings = _Settings()..failAt = checkpoint;
        final api = _Api()..targets = [_ids.first];
        final state = _State(api, settings: settings)..session = _session;
        addTearDown(state.dispose);
        await state.cancelOpenSpotOrders(onlyCurrentPair: false);
        expect(api.posts.length, checkpoint == 3 ? 1 : 0);
        settings.failAt = -1;
        api.terminal = true;
        await state.checkPendingTradingCommand();
        expect(api.posts.length, checkpoint == 1 ? 0 : 1);
        expect(state.tradingCommandPending, isFalse);
      },
    );
  }
  test(
    'account changes stop later batches and keep the old plan for its owner',
    () async {
      final api = _Api();
      final state = _State(api)..session = _session;
      addTearDown(state.dispose);
      api.beforePost = () async {
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
      };
      await state.cancelOpenSpotOrders(onlyCurrentPair: false);
      expect(api.posts.length, 1);
      expect(state.pendingTradingCommand, isNull);
      expect(state.lastCancellationResult, isNull);
      state.session = _session;
      expect(state.tradingCommandPending, isTrue);
      api.beforePost = null;
      api.terminal = true;
      await state.checkPendingTradingCommand();
      expect(api.posts.length, 3);
      expect(state.tradingCommandPending, isFalse);
    },
  );
  test(
    'simultaneous recovery clicks do not duplicate the next batch',
    () async {
      final api = _Api()..loseFirst = true;
      final state = _State(api)..session = _session;
      addTearDown(state.dispose);
      await state.cancelOpenSpotOrders(onlyCurrentPair: false);
      api.terminal = true;
      await Future.wait([
        state.checkPendingTradingCommand(),
        state.checkPendingTradingCommand(),
      ]);
      expect(api.posts.length, 3);
      expect(api.queries, 1);
      expect(state.tradingCommandPending, isFalse);
    },
  );
  test('empty target set produces no POST', () async {
    final api = _Api()..targets = [];
    final state = _State(api)..session = _session;
    addTearDown(state.dispose);
    await state.cancelOpenSpotOrders(onlyCurrentPair: false);
    expect(api.posts, isEmpty);
    expect(state.lastNotice, contains('没有可撤销'));
  });
  test(
    'real HTTP lost batch response uses original key and resumes only unsent chunks',
    () async {
      final methods = <String>[], posted = <List<int>>[], keys = <String>[];
      var queries = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        methods.add(request.method);
        expect(request.headers.value('X-Product-Line'), 'SPOT');
        expect(request.headers.value('X-User-Id'), '1');
        Map<String, dynamic> response;
        if (request.uri.path.endsWith('cancellation-plan')) {
          response = {
            'userId': 1,
            'productLine': 'SPOT',
            'instrumentId': null,
            'orderIds': _ids,
          };
        } else if (request.method == 'POST') {
          final body = asMap(
            jsonDecode(await utf8.decoder.bind(request).join()),
          );
          keys.add(asString(body['batchKey']));
          expect(keys.last, isNotEmpty);
          posted.add(
            asList(
              body['orders'],
            ).map((r) => asInt(asMap(r)['orderId'])).toList(),
          );
          if (posted.length == 1) {
            (await request.response.detachSocket(
              writeHeaders: false,
            )).destroy();
            return;
          }
          response = _receipt(posted.last);
        } else {
          expect(request.uri.queryParameters['batchKey'], keys.first);
          queries++;
          response = queries == 1
              ? {
                  'commandId': 'command-1',
                  'outcome': 'RESULT_UNKNOWN',
                  'code': 'RESULT_UNKNOWN',
                }
              : _receipt(posted.first, failed: 1);
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      )..setSession(_session);
      final state = _State(api)..session = _session;
      addTearDown(() async {
        state.dispose();
        http.close(force: true);
        await server.close(force: true);
      });
      await state.cancelOpenSpotOrders(onlyCurrentPair: false);
      await state.checkPendingTradingCommand();
      expect(posted.length, 1);
      await state.checkPendingTradingCommand();
      expect(methods, ['GET', 'POST', 'GET', 'GET', 'POST', 'POST']);
      expect(posted.expand((ids) => ids), _ids);
      expect(keys.toSet().length, 3);
      expect(state.lastCancellationResult?.failed, 1);
      expect(state.lastCancellationResult?.completed, 119);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness confirms scope, shows partial failures and keeps recovery accessible',
      (tester) async {
        tester.view.physicalSize = const Size(320, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _Api()
          ..targets = [_ids.first]
          ..failed = 1;
        final state = _State(api)..session = _session;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: Scaffold(
                body: SingleChildScrollView(
                  child: AnimatedBuilder(
                    animation: state,
                    builder: (context, _) => PrivateTradingPanel(state: state),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('当前委托 (0)'));
        await tester.pumpAndSettle();
        final cancel = find.text('撤销当前交易对委托');
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(find.text('撤销 BTC-USDT 当前委托？'), findsOneWidget);
        expect(api.posts, isEmpty);
        await tester.tap(find.text('确认撤单'));
        await tester.pumpAndSettle();
        expect(find.text('已处理 1 笔，成功 0 笔，失败 1 笔'), findsOneWidget);
        await tester.ensureVisible(find.text('查看失败订单'));
        await tester.tap(find.text('查看失败订单'));
        await tester.pumpAndSettle();
        expect(find.text('订单 #${_ids.first}'), findsOneWidget);
        expect(find.text('订单不存在或已结束'), findsOneWidget);
        Navigator.of(tester.element(find.text('订单不存在或已结束'))).pop();
        await tester.pumpAndSettle();
        api.loseFirst = true;
        api.posts.clear();
        api.keys.clear();
        api.failed = 0;
        await tester.ensureVisible(cancel);
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        await tester.tap(find.text('确认撤单'));
        await tester.pumpAndSettle();
        final recover = find.text('确认并继续撤单');
        await tester.ensureVisible(recover);
        await tester.tap(recover);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isTrue);
        expect(api.posts.length, 1);
        api.terminal = true;
        await tester.tap(recover);
        await tester.pumpAndSettle();
        expect(state.tradingCommandPending, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _Api extends ApiClient {
  _Api() : super(const AppConfig());
  List<int> targets = [..._ids];
  final posts = <List<int>>[], keys = <String>[];
  int planReads = 0, queries = 0, failed = 0;
  String? scope, queryFailure;
  bool loseFirst = false, terminal = false;
  FutureOr<void> Function()? beforePost;
  @override
  Future<List<int>> cancellationPlan(int userId, {String? instrumentId}) async {
    planReads++;
    scope = instrumentId;
    return [...targets];
  }

  @override
  Future<OrderBatchResult> cancelOrderBatch(
    int userId,
    List<int> orderIds, {
    String? productLine,
    String? batchKey,
  }) async {
    expect(productLine, 'SPOT');
    expect(batchKey, isNotEmpty);
    await beforePost?.call();
    posts.add([...orderIds]);
    keys.add(batchKey!);
    if (loseFirst && posts.length == 1) {
      throw const SocketException('lost reply');
    }
    return _result(orderIds, failed: failed);
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
    expect(path, '/api/v1/gateway/trading/cancellation-batches');
    expect(productLine, 'SPOT');
    expect(userId, 1);
    expect(query?['batchKey'], keys.first);
    queries++;
    if (queryFailure == 'lookup400') throw ApiException(400, 'invalid lookup');
    if (queryFailure == 'lookup503') throw ApiException(503, 'offline');
    if (!terminal) {
      return {'commandId': 'command-1', 'outcome': 'RESULT_UNKNOWN'};
    }
    final receipt = _receipt(posts.first);
    if (queryFailure == 'wrongIds') receipt['prospectiveOrderIds'] = [999];
    if (queryFailure == 'missingResult') receipt['result'] = {};
    if (queryFailure == 'missingSuccess') {
      asMap(
        asList(asMap(receipt['result'])['results']).first,
      ).remove('success');
    }
    if (queryFailure == 'badCount') asMap(receipt['result'])['completed'] = 999;
    if (queryFailure == 'badCode') {
      asMap(asList(asMap(receipt['result'])['results']).first)['message'] =
          'ORDER_NOT_FOUND';
    }
    return receipt;
  }
}

class _State extends AppState {
  _State(ApiClient api, {ClientSettingsStore? settings})
    : super(
        apiClient: api,
        settingsStore: settings ?? _Settings(),
        sessionStore: _Sessions(),
        seedInstruments: [_instrument()],
        config: const AppConfig(websocketUrl: ''),
      ) {
    mode = ProductMode.spot;
  }
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

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  int writes = 0, failAt = -1;
  bool failRemoval = false;
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> values) async {
    if (++writes == failAt) throw const FileSystemException('full');
    if (failRemoval &&
        asList(jsonDecode(values['pendingTradingOrders']!)).isEmpty) {
      throw const FileSystemException('cannot remove confirmed plan');
    }
    this.values = {...values};
  }
}

class _Sessions implements SessionStore {
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

class _RealHttp extends HttpOverrides {}

class _PayloadApi extends ApiClient {
  _PayloadApi() : super(const AppConfig());
  Map<String, dynamic>? body;
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = true,
  }) async {
    this.body = body;
    return asMap(
      _receipt(
        asList(body['orders']).map((r) => asInt(asMap(r)['orderId'])).toList(),
      )['result'],
    );
  }
}
