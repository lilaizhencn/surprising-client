// Native-device regression coverage. All network values below are explicit,
// isolated fixtures; this test never connects to a production account.
import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';
import 'package:surprising_client/src/session_store.dart';

const _riskOnly = bool.fromEnvironment('REMEDIATION_RISK_ONLY');
const _liveOnly = bool.fromEnvironment('REMEDIATION_LIVE_ONLY');
const _inputOnly = bool.fromEnvironment('REMEDIATION_INPUT_ONLY');

String _version(int n) => '${n.toString().padLeft(19, '0')}:0000000000';

Map<String, dynamic> _instrument(ProductMode p) => {
  'instrumentId': '${100 + p.index}',
  'symbol': p.isOption
      ? 'BTC-USDT-271231-100000-C'
      : 'BTC-${p == ProductMode.inverse || p == ProductMode.inverseDelivery ? 'USD' : 'USDT'}-${p.name}',
  'instrumentType': p.isSpot
      ? 'SPOT'
      : p.isOption
      ? 'OPTION'
      : p.isDelivery
      ? 'DELIVERY'
      : 'PERPETUAL',
  'contractType': p.contractType,
  'productLine': p.productLine,
  'baseAsset': 'BTC',
  'quoteAsset': p == ProductMode.inverse || p == ProductMode.inverseDelivery
      ? 'USD'
      : 'USDT',
  'settleAsset': p == ProductMode.inverse || p == ProductMode.inverseDelivery
      ? 'BTC'
      : 'USDT',
  'priceTickUnits': 10000,
  'quantityStepUnits': 10000,
  'pricePrecision': 2,
  'quantityPrecision': 4,
  'maxLeveragePpm': 10000000,
  'status': 'TRADING',
  'baseScaleUnits': 100000000,
  'quoteScaleUnits': 1000000,
  'settleScaleUnits':
      p == ProductMode.inverse || p == ProductMode.inverseDelivery
      ? 100000000
      : 1000000,
  'minQuantitySteps': 1,
  'maxQuantitySteps': 10000000,
  'minNotionalUnits': 1,
  'maxNotionalUnits': '9223372036854775807',
  'notionalMultiplierUnits': 100,
  'changeId': 1,
  if (p.isExpiring) 'expiryTime': '2027-12-31T08:00:00Z',
  if (p.isExpiring) 'deliveryTime': '2027-12-31T08:00:00Z',
  if (p.isOption) 'strikePriceUnits': 100000000000,
  if (p.isOption) 'optionType': 'CALL',
  if (p.isOption) 'optionExerciseStyle': 'EUROPEAN',
  if (p.isOption) 'settlementMethod': 'CASH',
};

Map<String, dynamic> _snapshot(ProductMode p, int n, {int userId = 7}) => {
  'op': 'snapshot',
  'userId': userId,
  'productLine': p.productLine,
  'data': {
    'status': 'READY',
    'snapshotVersion': _version(n),
    'account': {
      'userId': userId,
      'productLine': p.productLine,
      'positionMode': 'ONE_WAY',
      'balances': [
        {'asset': 'USDT', 'availableUnits': 1000000000, 'lockedUnits': 0},
      ],
      'reservations': [],
      'positions': [],
      'leverages': [],
    },
    'openOrders': [],
    'triggerOrders': [],
    'positionRisks': [],
  },
};

Future<void> _frames(WidgetTester tester, [int count = 8]) async {
  for (var i = 0; i < count; i++) {
    final frameWait =
        _inputOnly || const bool.fromEnvironment('REMEDIATION_LIVE')
        ? Timer(const Duration(seconds: 10), () {
            final scheduler = SchedulerBinding.instance;
            debugPrint(
              'REMEDIATION_FRAME_WAIT:lifecycle=${scheduler.lifecycleState?.name}:enabled=${scheduler.framesEnabled}:scheduled=${scheduler.hasScheduledFrame}:phase=${scheduler.schedulerPhase.name}',
            );
          })
        : null;
    try {
      await tester.pump(const Duration(milliseconds: 150));
    } finally {
      frameWait?.cancel();
    }
  }
}

Future<void> _capture(WidgetTester tester, String name) async {
  await _frames(tester, 2);
  // Standard flutter test remains runnable without a host capture process.
  if (!const bool.fromEnvironment('REMEDIATION_HOST_CAPTURE')) return;
  // HTTP acknowledgement also works for Android profile builds where run-as
  // cannot write an acknowledgement into the app's private cache directory.
  final acknowledgment = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final captured = Completer<void>();
  acknowledgment.listen((request) async {
    request.response.statusCode = HttpStatus.noContent;
    await request.response.close();
    if (!captured.isCompleted) captured.complete();
  });
  debugPrint('REMEDIATION_CAPTURE:$name:HTTP:${acknowledgment.port}');
  try {
    await captured.future.timeout(const Duration(seconds: 55));
  } finally {
    await acknowledgment.close(force: true);
  }
  await tester.pump();
}

Future<void> _nav(WidgetTester tester, String label) async {
  final nav = find.descendant(
    of: find.byType(ExchangeBottomNav),
    matching: find.text(label),
  );
  await tester.tap(nav);
  await _frames(tester);
  const indices = {'首页': 0, '行情': 1, '交易': 2, 'C2C': 3, '资产': 4};
  expect(
    tester
        .widget<ExchangeBottomNav>(find.byType(ExchangeBottomNav))
        .selectedIndex,
    indices[label],
    reason: 'native navigation must select the tapped destination',
  );
}

Future<void> _reveal(
  WidgetTester tester,
  Finder target, {
  double delta = 250,
}) async {
  if (target.hitTestable().evaluate().isEmpty) {
    final vertical = find
        .descendant(
          of: find.byType(TradePage),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        )
        .first;
    // Use the broad order-book/header region, rather than the ticket's nested
    // scroll view or a narrow edge that would hide a real reachability issue.
    final bounds = tester.getRect(vertical);
    final position = tester.state<ScrollableState>(vertical).position;
    for (var n = 0; n < 16 && target.hitTestable().evaluate().isEmpty; n++) {
      final before = position.pixels;
      await tester.dragFrom(
        Offset(bounds.left + bounds.width * .78, bounds.center.dy),
        Offset(0, -delta),
      );
      await _frames(tester, 2);
      if (n == 0) {
        expect(position.pixels, isNot(before));
        debugPrint(
          'REMEDIATION_OUTER_SWIPE:xRatio=.78:before=$before:after=${position.pixels}',
        );
      }
    }
    if (target.hitTestable().evaluate().isEmpty) {
      await _capture(tester, 'missing-reveal-diagnostic');
      expect(target.hitTestable(), findsWidgets);
    }
  }
  await tester.ensureVisible(target);
  await _frames(tester, 2);
}

Future<void> _enterText(WidgetTester tester, Finder field, String value) async {
  debugPrint(
    'REMEDIATION_INPUT_STAGE:ensure-visible:${SchedulerBinding.instance.lifecycleState?.name}',
  );
  await tester.ensureVisible(field);
  await _frames(tester, 2);
  expect(field.hitTestable(), findsOneWidget, reason: 'native input reachable');
  debugPrint('REMEDIATION_INPUT_STAGE:tap');
  await tester.tap(field.hitTestable());
  await _frames(tester, 4);
  final editable = tester.widget<EditableText>(
    find.descendant(of: field, matching: find.byType(EditableText)),
  );
  for (
    var attempt = 0;
    attempt < 20 && !editable.focusNode.hasFocus;
    attempt++
  ) {
    await _frames(tester, 1);
  }
  expect(editable.focusNode.hasFocus, isTrue, reason: 'native input focus');
  final controller = editable.controller;
  controller.selection = TextSelection(
    baseOffset: 0,
    extentOffset: controller.text.length,
  );
  await _frames(tester, 2);
  debugPrint('REMEDIATION_INPUT_STAGE:focused-selected');
  if (const bool.fromEnvironment('REMEDIATION_HOST_CAPTURE')) {
    // Profile builds reject TestTextInput's debug-only client -1. Send actual
    // native keyboard input; the payload stays on this temporary loopback port.
    final bridge = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completed = Completer<void>();
    bridge.listen((request) async {
      if (request.uri.path == '/payload') {
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({'text': value}));
      } else if (request.uri.path == '/state') {
        final actual = controller.text;
        var difference = 0;
        while (difference < actual.length &&
            difference < value.length &&
            actual.codeUnitAt(difference) == value.codeUnitAt(difference)) {
          difference++;
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'matchesExpected': actual == value,
            'actualLength': actual.length,
            'expectedLength': value.length,
            'firstDifference': actual == value ? null : difference,
            'isExpectedPrefix': value.startsWith(actual),
            'isExpectedSuffix': value.endsWith(actual),
            'focused': editable.focusNode.hasFocus,
            'selectionStart': controller.selection.start,
            'selectionEnd': controller.selection.end,
            'keyboardType': editable.keyboardType.toString(),
            'obscured': editable.obscureText,
            'lifecycle': SchedulerBinding.instance.lifecycleState?.name,
            'framesEnabled': SchedulerBinding.instance.framesEnabled,
          }),
        );
      }
      await request.response.close();
      if (request.uri.path == '/ack' && !completed.isCompleted) {
        completed.complete();
      }
    });
    debugPrint('REMEDIATION_INPUT:HTTP:${bridge.port}');
    try {
      await completed.future.timeout(const Duration(seconds: 30));
      debugPrint('REMEDIATION_INPUT_STAGE:native-ack');
    } finally {
      await bridge.close(force: true);
    }
  } else {
    await tester.enterText(field, value);
  }
  await _frames(tester, 3);
  if (controller.text != value &&
      !const bool.fromEnvironment('REMEDIATION_LIVE')) {
    await _capture(tester, 'native-input-mismatch');
  }
  expect(
    controller.text == value,
    isTrue,
    reason: 'native text input must persist',
  );
}

Future<void> _requireKeyboard(WidgetTester tester) async {
  await _frames(tester, 5);
  if (tester.view.viewInsets.bottom == 0 &&
      Platform.isIOS &&
      const bool.fromEnvironment('REMEDIATION_HOST_CAPTURE')) {
    final bridge = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final completed = Completer<void>();
    bridge.listen((request) async {
      await request.response.close();
      if (!completed.isCompleted) completed.complete();
    });
    debugPrint('REMEDIATION_KEYBOARD:HTTP:${bridge.port}');
    try {
      await completed.future.timeout(const Duration(seconds: 30));
    } finally {
      await bridge.close(force: true);
    }
  }
  for (var n = 0; n < 30 && tester.view.viewInsets.bottom == 0; n++) {
    await _frames(tester, 1);
  }
  expect(tester.view.viewInsets.bottom, greaterThan(0));
  debugPrint(
    'REMEDIATION_REAL_KEYBOARD:inset=${tester.view.viewInsets.bottom}',
  );
}

Future<Map<String, dynamic>> _memory() async {
  final info = await developer.Service.getInfo();
  final uri = info.serverWebSocketUri;
  final isolate = developer.Service.getIsolateId(Isolate.current);
  if (uri == null || isolate == null) {
    throw StateError('VM memory service unavailable');
  }
  final socket = await WebSocket.connect('$uri');
  socket.add(
    jsonEncode({
      'jsonrpc': '2.0',
      'id': 'memory',
      'method': 'getMemoryUsage',
      'params': {'isolateId': isolate},
    }),
  );
  try {
    final raw = await socket.first.timeout(const Duration(seconds: 10));
    final message = jsonDecode(raw as String) as Map<String, dynamic>;
    if (message['error'] != null) throw StateError('VM memory request failed');
    return {...asMap(message['result']), 'rss': ProcessInfo.currentRss};
  } finally {
    await socket.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'native bounded realtime navigation soak',
    (tester) async {
      final fixture = await _Fixture.start();
      final api = ApiClient(fixture.config);
      final state = AppState(
        config: fixture.config,
        apiClient: api,
        sessionStore: _SessionMemory(),
        settingsStore: _SettingsMemory(),
        seedInstruments: ProductMode.values
            .map((p) => Instrument.fromJson(_instrument(p)))
            .toList(),
      );
      addTearDown(() async {
        state.dispose();
        await fixture.close();
      });
      final frameMicros = <int>[];
      void timings(List<FrameTiming> frames) {
        for (final frame in frames) {
          if (frameMicros.length < 60000) {
            frameMicros.add(frame.totalSpan.inMicroseconds);
          }
        }
      }

      SchedulerBinding.instance.addTimingsCallback(timings);
      addTearDown(
        () => SchedulerBinding.instance.removeTimingsCallback(timings),
      );
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await state.refreshInstruments();
      await state.selectMode(ProductMode.linear);
      await _nav(tester, '交易');
      final updates = Timer.periodic(const Duration(milliseconds: 20), (_) {
        fixture.sendTicker(state.mode);
        fixture.sendDepth(state.mode);
      });
      addTearDown(updates.cancel);
      await _frames(tester, 30);
      debugPrint('REMEDIATION_SOAK_START:${jsonEncode(await _memory())}');
      final started = Stopwatch()..start();
      final beforeMessages = fixture.messagesSent;
      const seconds = int.fromEnvironment(
        'REMEDIATION_SOAK_SECONDS',
        defaultValue: 300,
      );
      for (var elapsed = 0; elapsed < seconds; elapsed += 10) {
        await _nav(tester, (elapsed ~/ 10).isEven ? '行情' : '交易');
        for (var n = 0; n < 9; n++) {
          await tester.pump(const Duration(seconds: 1));
        }
        expect(fixture.sockets.length, 1);
        expect(state.orderBook.bids.length, lessThanOrEqualTo(50));
        expect(state.orderBook.asks.length, lessThanOrEqualTo(50));
        expect(state.latestPrices.length, lessThanOrEqualTo(6));
        expect(tester.takeException(), isNull);
        if (elapsed % 30 == 0) {
          debugPrint(
            'REMEDIATION_SOAK_SAMPLE:${elapsed + 10}:${jsonEncode(await _memory())}',
          );
        }
      }
      frameMicros.sort();
      debugPrint(
        'REMEDIATION_SOAK_END:${jsonEncode(await _memory())}:frames=${frameMicros.length}:p99us=${frameMicros.isEmpty ? 0 : frameMicros[(frameMicros.length * 0.99).floor()]}:sockets=${fixture.sockets.length}:depthSubscriptions=${fixture.depthSubscriptions}:messages=${fixture.messagesSent - beforeMessages}:elapsedMs=${started.elapsedMilliseconds}',
      );
      await _capture(tester, 'soak-finished');
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        _inputOnly ||
        _liveOnly ||
        _riskOnly ||
        !const bool.fromEnvironment('REMEDIATION_SOAK'),
    timeout: const Timeout(Duration(minutes: 8)),
  );

  testWidgets(
    'native boundary validation and complete HTTP response deadline',
    (tester) async {
      final fixture = await _Fixture.start();
      final transport = HttpClient();
      final api = ApiClient(fixture.config, httpClient: transport);
      addTearDown(() async {
        transport.close(force: true);
        await fixture.close();
      });
      final view = PrivateView();
      expect(view.apply(_snapshot(ProductMode.spot, 1)), isTrue);
      final fence = view.fence;
      expect(
        view.apply({
          'op': 'snapshot',
          'data': {
            'status': 'READY',
            'snapshotVersion': _version(2),
            'account': {},
          },
        }),
        isFalse,
      );
      expect(view.ready, isFalse);
      expect(view.fence, fence);
      expect(view.rows('balance').single['availableUnits'], 1000000000);
      for (final invalid in <Object?>[
        'invalid',
        '1.5',
        'NaN',
        'Infinity',
        '9223372036854775808',
        null,
      ]) {
        expect(
          () => ProductBalance.fromJson({
            'accountType': 'SPOT',
            'asset': 'USDT',
            'availableUnits': invalid,
            'lockedUnits': 0,
            'equityUnits': 0,
          }),
          throwsFormatException,
        );
      }
      expect(
        const ProductBalance(
          accountType: 'SPOT',
          asset: 'USDT',
          availableUnits: 0,
          lockedUnits: 0,
          equityUnits: 0,
        ).available,
        isNull,
      );
      final invalidBalance = _snapshot(ProductMode.spot, 2);
      asMap(asMap(invalidBalance['data'])['account'])['balances'] = [
        {'asset': 'USDT', 'availableUnits': 'invalid', 'lockedUnits': 0},
      ];
      expect(view.apply(invalidBalance), isFalse);
      expect(view.fence, fence);
      expect(view.apply(_snapshot(ProductMode.spot, 3)), isTrue);
      expect(view.ready, isTrue);
      expect(
        () => Instrument.fromJson({
          'symbol': 'UNKNOWN',
          'contractType': 'UNRECOGNIZED',
        }),
        throwsFormatException,
      );
      final noStatus = Map<String, dynamic>.from(_instrument(ProductMode.spot))
        ..remove('status');
      expect(
        Instrument.fromJson(noStatus).canPlaceOrder(reduceOnly: false),
        isFalse,
      );
      final watch = Stopwatch()..start();
      Object? failure;
      try {
        await api
            .get('/remediation/half-body')
            .timeout(const Duration(seconds: 26));
      } catch (error) {
        failure = error;
      }
      expect(failure, isNotNull);
      expect(watch.elapsed, lessThan(const Duration(seconds: 25)));
      debugPrint(
        'REMEDIATION_HTTP_DEADLINE:${watch.elapsedMilliseconds}:${failure.runtimeType}',
      );
      final shortApi = ApiClient(
        fixture.config,
        requestTimeout: const Duration(milliseconds: 300),
        maxResponseBytes: 1024,
      );
      addTearDown(shortApi.dispose);
      await expectLater(
        shortApi.get('/remediation/slow-headers'),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(
        shortApi.get('/remediation/oversized'),
        throwsA(isA<ApiResponseTooLarge>()),
      );
      final cancelApi = ApiClient(fixture.config);
      addTearDown(cancelApi.dispose);
      final pending = cancelApi.get('/remediation/half-body');
      Timer(const Duration(milliseconds: 100), cancelApi.cancelPendingRequests);
      await expectLater(pending, throwsA(isA<ApiRequestCancelled>()));
      // A raw upgraded TCP peer deliberately ignores protocol ping frames.
      // The client must close a half-open connection without onError/onDone
      // being supplied by that peer.
      final silent = RealtimeClient(
        AppConfig(
          websocketUrl: 'ws://127.0.0.1:${fixture.server.port}/silent-ws',
        ),
      );
      final silentDone = Completer<void>();
      addTearDown(silent.close);
      final silentWatch = Stopwatch()..start();
      await silent.connect(
        onEvent: (_) {},
        onError: (_) {},
        onDone: () {
          if (!silentDone.isCompleted) silentDone.complete();
        },
      );
      await silentDone.future.timeout(const Duration(seconds: 46));
      expect(silentWatch.elapsed, lessThan(const Duration(seconds: 45)));
      debugPrint(
        'REMEDIATION_SILENT_WEBSOCKET:${silentWatch.elapsedMilliseconds}',
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: Text('Native HTTP deadline and strict snapshot passed'),
            ),
          ),
        ),
      );
      await _capture(tester, 'boundary-passed');
    },
    skip:
        _inputOnly ||
        _liveOnly ||
        _riskOnly ||
        const bool.fromEnvironment('REMEDIATION_SOAK_ONLY'),
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native private snapshot failure remains visible and recovers',
    (tester) async {
      final fixture = await _Fixture.start();
      final state = AppState(
        config: fixture.config,
        apiClient: ApiClient(fixture.config),
        initialSession: const AuthSession(
          user: AuthUser(
            userId: 7,
            username: 'native-fixture',
            email: 'native-fixture@example.invalid',
            status: 'ACTIVE',
          ),
          accessToken: 'isolated-native-fixture',
          refreshToken: 'isolated-native-refresh',
        ),
        sessionStore: _SessionMemory(),
        settingsStore: _SettingsMemory(),
        seedInstruments: ProductMode.values
            .map((p) => Instrument.fromJson(_instrument(p)))
            .toList(),
      );
      addTearDown(() async {
        state.dispose();
        await fixture.close();
      });
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await state.refreshInstruments();
      await state.selectMode(ProductMode.linear);
      for (var n = 0; n < 50 && !state.assetsReady; n++) {
        await _frames(tester, 1);
      }
      expect(state.assetsReady, isTrue);
      await _nav(tester, '资产');
      final view = state.privateViews[ProductMode.linear]!;
      final fence = view.fence;
      final corrupted = _snapshot(ProductMode.linear, ++fixture.sequence);
      final account = asMap(asMap(corrupted['data'])['account']);
      account['balances'] = [
        {'asset': 'USDT', 'availableUnits': 'NaN', 'lockedUnits': 0},
      ];
      fixture.dropPrivate = true;
      fixture.emit(corrupted);
      await _frames(tester, 3);
      expect(view.ready, isFalse);
      expect(view.fence, fence);
      expect(state.assetsReady, isFalse);
      expect(view.rows('balance').single['availableUnits'], 1000000000);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'private-corrupt-data');
      fixture.dropPrivate = false;
      fixture.emit(_snapshot(ProductMode.linear, ++fixture.sequence));
      for (var n = 0; n < 50 && !state.assetsReady; n++) {
        await _frames(tester, 1);
      }
      expect(state.assetsReady, isTrue);
      expect(state.privateViews[ProductMode.linear]!.ready, isTrue);
      expect(state.productBalances[ProductMode.linear]!.single.available, 1000);
      final recoveredFence = state.privateViews[ProductMode.linear]!.fence;
      final beforeSubscriptions = fixture.privateSubscriptions;
      fixture.dropPrivate = true;
      fixture.emit({
        'op': 'event',
        'channel': 'accountState',
        'userId': 7,
        'productLine': ProductMode.linear.productLine,
        'data': {
          'version': 'invalid-version',
          'value': {'balances': []},
        },
      });
      await _frames(tester, 3);
      expect(state.privateViews[ProductMode.linear]!.ready, isFalse);
      expect(state.privateViews[ProductMode.linear]!.fence, recoveredFence);
      expect(state.assetsReady, isFalse);
      fixture.dropPrivate = false;
      for (var n = 0; n < 70 && !state.assetsReady; n++) {
        await _frames(tester, 1);
      }
      expect(state.assetsReady, isTrue);
      expect(
        fixture.privateSubscriptions - beforeSubscriptions,
        inInclusiveRange(1, 3),
      );
      await _capture(tester, 'private-recovered-data');
      expect(tester.takeException(), isNull);
      debugPrint(
        'REMEDIATION_PRIVATE_UI_RECOVERY:ready=true:amount=1000USDT:invalidVersionRecoverySubscriptions=${fixture.privateSubscriptions - beforeSubscriptions}',
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        _inputOnly ||
        _liveOnly ||
        _riskOnly ||
        const bool.fromEnvironment('REMEDIATION_SOAK_ONLY'),
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets(
    'native six-product navigation, recovery, order UI and layout',
    (tester) async {
      final fixture = await _Fixture.start();
      final transport = HttpClient();
      final api = ApiClient(fixture.config, httpClient: transport)
        ..deviceIdLoader = () async => '35ce0f55-d46c-43e4-bef8-49c60d0a8d71';
      final state = AppState(
        config: fixture.config,
        apiClient: api,
        sessionStore: _SessionMemory(),
        settingsStore: _SettingsMemory(),
        seedInstruments: ProductMode.values
            .map((p) => Instrument.fromJson(_instrument(p)))
            .toList(),
      );
      addTearDown(() async {
        state.dispose();
        transport.close(force: true);
        await fixture.close();
      });
      await tester.pumpWidget(SurprisingClientApp(state: state));
      for (
        var n = 0;
        n < 100 && (fixture.sockets.isEmpty || state.orderBook.bids.isEmpty);
        n++
      ) {
        await _frames(tester, 1);
      }
      expect(fixture.sockets, hasLength(1));
      expect(state.orderBook.bids, isNotEmpty);
      debugPrint('REMEDIATION_BOOTSTRAP:catalog=6:socket=1:depth=ready');
      await _frames(tester);
      expect(state.instruments, hasLength(6));
      await _capture(tester, 'home-dark');
      await _nav(tester, '资产');
      await _capture(tester, 'assets-logged-out');
      expect(tester.takeException(), isNull);
      await _nav(tester, '行情');
      await _capture(tester, 'markets-dark');
      await _nav(tester, '交易');
      for (final p in ProductMode.values) {
        final tab = find.byKey(ValueKey('product-tab-${p.name}'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        await _frames(tester, 14);
        expect(state.mode, p);
        expect(state.selectedInstrument.mode, p);
        expect(state.orderBook.symbol, state.selectedSymbol);
        expect(state.orderBook.bids, isNotEmpty);
        expect(tester.widget<ChoiceChip>(tab).selected, isTrue);
        expect(tester.takeException(), isNull);
        await _capture(tester, 'trade-${p.name}');
      }
      await state.selectMode(ProductMode.linear);
      await _frames(tester, 5);
      fixture.sendTicker(ProductMode.linear);
      await _frames(tester, 3);
      expect(
        state.latestPriceFor(state.selectedInstrument),
        closeTo(1.01, 0.0000001),
      );
      fixture.sendRaw('{"incomplete":');
      fixture.emit({
        'op': 'event',
        'channel': 'depth',
        'productLine': 'UNRECOGNIZED',
        'data': null,
      });
      await _frames(tester, 4);
      expect(tester.takeException(), isNull);
      final connectionCount = fixture.connections;
      // A binary frame violates the text-only wire contract and must result in
      // one bounded reconnect, then a fresh baseline on the selected product.
      for (final socket in fixture.sockets.toList()) {
        socket.add([1, 2, 3]);
      }
      await _frames(tester, 30);
      expect(fixture.connections, greaterThan(connectionCount));
      expect(fixture.sockets.length, 1);
      expect(state.orderBook.bids, isNotEmpty);
      expect(tester.takeException(), isNull);
      debugPrint(
        'REMEDIATION_BAD_FRAME_RECOVERY:connections=${fixture.connections}:sockets=${fixture.sockets.length}',
      );
      final before = fixture.depthSubscriptions;
      fixture.dropDepth = true;
      fixture.sendGap(state.mode);
      await _frames(tester, 55);
      expect(fixture.depthSubscriptions, greaterThan(before + 1));
      fixture.dropDepth = false;
      fixture.sendDepth(state.mode);
      await _frames(tester, 5);
      expect(state.orderBook.bids, isNotEmpty);
      expect(state.orderBook.bids.length, lessThanOrEqualTo(50));
      debugPrint(
        'REMEDIATION_DEPTH_RECOVERY:${fixture.depthSubscriptions - before}',
      );
      // Real lifecycle transition is driven by the host while this app stays mounted.
      debugPrint('REMEDIATION_BACKGROUND:now');
      await Future<void>.delayed(const Duration(seconds: 8));
      await _frames(tester, 5);
      expect(tester.takeException(), isNull);
      await _capture(tester, 'foreground-restored');
      // Every navigation and tap below is delivered to the actual native app.
      for (var n = 0; n < 12; n++) {
        await _nav(tester, n.isEven ? '行情' : '交易');
        expect(tester.takeException(), isNull);
      }
      expect(fixture.sockets.length, lessThanOrEqualTo(1));
      debugPrint(
        'REMEDIATION_STABILITY:sockets=${fixture.sockets.length}:rss=${ProcessInfo.currentRss}',
      );
      state.selectTheme(ClientTheme.light);
      await _frames(tester, 4);
      await _capture(tester, 'trade-light');
      // OS-level font scale is supplied by the host on Android; iOS rendering also
      // covers an explicit large accessibility scale through the app's MediaQuery.
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await _frames(tester, 4);
      await _nav(tester, '交易');
      await _capture(tester, 'trade-large-font');
      expect(tester.takeException(), isNull);
      // Unauthenticated submit must open the real login sheet, not emit an order.
      await state.selectMode(ProductMode.linear);
      await _frames(tester, 6);
      final ticket = find.byType(OrderTicket);
      await tester.ensureVisible(ticket);
      final fields = find.descendant(
        of: ticket,
        matching: find.byType(TextField),
      );
      expect(fields, findsAtLeastNWidgets(2));
      await _enterText(tester, fields.first, '1.00');
      await _enterText(tester, fields.at(1), '2');
      await _requireKeyboard(tester);
      await _capture(tester, 'trade-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(tester, 3);
      final login = find.descendant(of: ticket, matching: find.text('登录'));
      await tester.ensureVisible(login);
      await tester.tap(login);
      await _frames(tester, 5);
      expect(fixture.orders, isEmpty);
      expect(find.byType(BottomSheet), findsWidgets);
      await _capture(tester, 'order-login-required');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        _inputOnly ||
        _liveOnly ||
        _riskOnly ||
        const bool.fromEnvironment('REMEDIATION_SOAK_ONLY'),
    timeout: const Timeout(Duration(minutes: 6)),
  );

  testWidgets(
    'native authoritative risk recovery and keyboard input',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = (await _Fixture.start())..sendPrivateHeartbeats = true;
      final api = ApiClient(fixture.config)
        ..deviceIdLoader = () async => '35ce0f55-d46c-43e4-bef8-49c60d0a8d71';
      final state = AppState(
        config: fixture.config,
        apiClient: api,
        initialSession: const AuthSession(
          user: AuthUser(
            userId: 7,
            username: 'native-fixture',
            email: 'native-fixture@example.invalid',
            status: 'ACTIVE',
          ),
          accessToken: 'isolated-native-fixture-7',
          refreshToken: 'isolated-native-refresh-7',
        ),
        sessionStore: _SessionMemory(),
        settingsStore: _SettingsMemory(),
        seedInstruments: ProductMode.values
            .map((p) => Instrument.fromJson(_instrument(p)))
            .toList(),
      );
      addTearDown(() async {
        fixture.releaseRisk();
        state.dispose();
        await fixture.close();
      });
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await state.refreshInstruments();
      await state.selectMode(ProductMode.linear);
      await _nav(tester, '交易');
      Future<void> waitRisk(int amount) async {
        for (
          var n = 0;
          n < 100 && state.accountRisk?.equityUnits != amount;
          n++
        ) {
          await _frames(tester, 1);
        }
        expect(state.accountRisk?.equityUnits, amount);
        await _frames(tester, 3);
      }

      await waitRisk(7000000);
      final pageScroll = find
          .descendant(
            of: find.byType(TradePage),
            matching: find.byWidgetPredicate(
              (widget) =>
                  widget is Scrollable &&
                  widget.axisDirection == AxisDirection.down,
            ),
          )
          .first;
      final pagePosition = tester.state<ScrollableState>(pageScroll).position;
      final beforeHeaderSwipe = pagePosition.pixels;
      await tester.drag(find.byType(TradeSymbolHeader), const Offset(0, -180));
      await _frames(tester, 3);
      expect(pagePosition.pixels, greaterThan(beforeHeaderSwipe));
      debugPrint(
        'REMEDIATION_HEADER_SWIPE:before=$beforeHeaderSwipe:after=${pagePosition.pixels}',
      );
      await _reveal(tester, find.text('权益'));
      expect(find.text('7 USDT'), findsOneWidget);
      await _capture(tester, 'risk-usdt-normal');
      fixture.invalidRiskAmount = true;
      await state.refreshRiskDetails();
      await _frames(tester, 2);
      expect(state.accountRisk, isNull);
      expect(state.accountRiskError, isNotNull);
      fixture.invalidRiskAmount = false;
      fixture.riskReportedAge = const Duration(seconds: 20);
      await state.refreshRiskDetails();
      expect(state.accountRisk, isNull);
      expect(state.accountRiskError, isNotNull);
      await _capture(tester, 'risk-rejected-old-snapshot');
      fixture.riskReportedAge = Duration.zero;
      fixture.riskResponseStatus = 503;
      await state.refreshRiskDetails();
      expect(state.accountRisk, isNull);
      expect(find.text('刷新风险'), findsOneWidget);
      fixture.riskResponseStatus = 200;
      await tester.ensureVisible(find.text('刷新风险'));
      await tester.tap(find.text('刷新风险'));
      await waitRisk(7000000);
      await _capture(tester, 'risk-manual-recovered');

      // Native lifetime expiry while periodic authoritative baselines stay fresh.
      fixture.holdRiskForUser = 7;
      fixture.riskGate = Completer<void>();
      final beforeHeld = fixture.heldRiskRequests;
      final expiring = state.refreshRiskDetails();
      for (var n = 0; n < 30 && fixture.heldRiskRequests == beforeHeld; n++) {
        await _frames(tester, 1);
      }
      expect(fixture.heldRiskRequests, greaterThan(beforeHeld));
      await Future<void>.delayed(const Duration(seconds: 16));
      await _frames(tester, 2);
      expect(state.privateViews[state.mode]!.ready, isTrue);
      expect(state.accountRisk, isNull);
      expect(find.text('7 USDT'), findsNothing);
      fixture.releaseRisk();
      await expiring;
      await state.refreshRiskDetails();
      await waitRisk(7000000);

      // A request belonging to account 7 is still pending when account 8 logs in.
      fixture.holdRiskForUser = 7;
      fixture.riskGate = Completer<void>();
      final beforeSwitch = fixture.heldRiskRequests;
      final previousRequest = state.refreshRiskDetails();
      for (var n = 0; n < 30 && fixture.heldRiskRequests == beforeSwitch; n++) {
        await _frames(tester, 1);
      }
      expect(fixture.heldRiskRequests, greaterThan(beforeSwitch));
      await state.logout();
      expect(state.accountRisk, isNull);
      await state.login('native-fixture-8', 'isolated-password-8');
      expect(state.userId, 8);
      await waitRisk(8000000);
      fixture.releaseRisk();
      await previousRequest;
      await _frames(tester, 4);
      expect(state.accountRisk?.equityUnits, 8000000);
      await _capture(tester, 'risk-account-switched');

      final inverseTab = find.byKey(const ValueKey('product-tab-inverse'));
      await tester.ensureVisible(inverseTab);
      await tester.tap(inverseTab);
      await waitRisk(800000000);
      expect(state.accountRisk?.settleAsset, 'BTC');
      await _reveal(tester, find.text('权益'));
      expect(find.text('8 BTC'), findsOneWidget);
      await _capture(tester, 'risk-btc-normal');

      final optionTab = find.byKey(const ValueKey('product-tab-option'));
      await tester.ensureVisible(optionTab);
      await tester.tap(optionTab);
      await _frames(tester, 6);
      await _reveal(tester, find.text('看涨 CALL'), delta: -250);
      expect(find.text('看涨 CALL'), findsOneWidget);
      await _capture(tester, 'option-call-type');

      await state.selectMode(ProductMode.linear);
      await _frames(tester, 5);
      final ticket = find.byType(OrderTicket);
      await _reveal(tester, ticket, delta: -250);
      final fields = find.descendant(
        of: ticket,
        matching: find.byType(TextField),
      );
      await _enterText(tester, fields.first, '1.00');
      await _enterText(tester, fields.at(1), '2');
      await _requireKeyboard(tester);
      await _capture(tester, 'native-keyboard-entered');
      FocusManager.instance.primaryFocus?.unfocus();
      await _frames(tester, 4);
      for (var n = 0; n < 20 && tester.view.viewInsets.bottom > 0; n++) {
        await _frames(tester, 1);
      }
      expect(tester.view.viewInsets.bottom, 0);
      await tester.ensureVisible(ticket);
      await tester.drag(ticket, const Offset(0, 350));
      await _frames(tester, 3);
      await _capture(tester, 'native-numeric-labels-dark');
      state.selectTheme(ClientTheme.light);
      await _frames(tester, 3);
      await _capture(tester, 'native-numeric-labels-light');
      state.selectTheme(ClientTheme.dark);
      await _frames(tester, 3);
      await tester.drag(ticket, const Offset(0, -350));
      await _frames(tester, 4);
      final postOnly = find.descendant(
        of: ticket,
        matching: find.text('Post Only'),
      );
      expect(postOnly.hitTestable(), findsOneWidget);
      final checks = find.descendant(
        of: ticket,
        matching: find.byType(Checkbox),
      );
      await tester.tap(checks.last);
      await _frames(tester, 2);
      expect(tester.widget<OrderTicket>(ticket).postOnly, isTrue);
      await tester.tap(checks.last);
      await _frames(tester, 2);
      final submit = find.descendant(
        of: ticket,
        matching: find.widgetWithText(FilledButton, '买入 / 开多'),
      );
      expect(submit.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(submit).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(ExchangeBottomNav)).dy),
      );
      await _capture(tester, 'native-ticket-options-scrolled');
      expect(tester.takeException(), isNull);
      debugPrint(
        'REMEDIATION_RISK_NATIVE:normal:invalid-money:old-time:retry:monotonic-expiry:account-switch:btc-scale:option-type:keyboard:post-only',
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        _inputOnly ||
        _liveOnly ||
        const bool.fromEnvironment('REMEDIATION_SOAK_ONLY'),
    timeout: const Timeout(Duration(minutes: 4)),
  );

  testWidgets(
    'native affected numeric input labels keyboard steps and risk card',
    (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final fixture = (await _Fixture.start())..sendPrivateHeartbeats = true;
      final api = ApiClient(fixture.config)
        ..deviceIdLoader = () async => '35ce0f55-d46c-43e4-bef8-49c60d0a8d71';
      final state = AppState(
        config: fixture.config,
        apiClient: api,
        initialSession: const AuthSession(
          user: AuthUser(
            userId: 7,
            username: 'native-fixture',
            email: 'native-fixture@example.invalid',
            status: 'ACTIVE',
          ),
          accessToken: 'isolated-native-fixture-7',
          refreshToken: 'isolated-native-refresh-7',
        ),
        sessionStore: _SessionMemory(),
        settingsStore: _SettingsMemory(),
        seedInstruments: [Instrument.fromJson(_instrument(ProductMode.linear))],
      );
      addTearDown(() async {
        state.dispose();
        await fixture.close();
      });
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await state.refreshInstruments();
      await state.selectMode(ProductMode.linear);
      await _nav(tester, '交易');
      for (
        var n = 0;
        n < 100 && state.accountRisk?.equityUnits != 7000000;
        n++
      ) {
        await _frames(tester, 1);
      }
      expect(state.privateViews[ProductMode.linear]?.ready, isTrue);
      expect(state.accountRisk?.equityUnits, 7000000);
      await _reveal(tester, find.text('权益'));
      expect(find.text('7 USDT').hitTestable(), findsOneWidget);
      await _capture(tester, 'affected-risk-card');
      final ticket = find.byType(OrderTicket);
      await _reveal(tester, ticket, delta: -300);
      final fields = find.descendant(
        of: ticket,
        matching: find.byType(TextField),
      );
      expect(fields, findsNWidgets(2));
      await _enterText(tester, fields.first, '1.00');
      await _enterText(tester, fields.at(1), '2');
      await _requireKeyboard(tester);
      await _capture(tester, 'affected-native-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      for (var n = 0; n < 30 && tester.view.viewInsets.bottom > 0; n++) {
        await _frames(tester, 1);
      }
      expect(tester.view.viewInsets.bottom, 0);
      await _frames(tester, 3);
      // Restore the visible ticket after the keyboard changed both viewports.
      // Use the same broad inner swipe a user would use to reach the inputs.
      await tester.drag(ticket, const Offset(0, 350));
      await _frames(tester, 3);
      final numeric = find.descendant(
        of: ticket,
        matching: find.byType(TradeNumericField),
      );
      Future<void> step(int fieldIndex, String tooltip, String expected) async {
        final button = find.descendant(
          of: numeric.at(fieldIndex),
          matching: find.byTooltip(tooltip),
        );
        await tester.ensureVisible(button);
        await _frames(tester, 2);
        for (
          var n = 0;
          n < 10 && button.hitTestable().evaluate().isEmpty;
          n++
        ) {
          await tester.ensureVisible(button);
          await _frames(tester, 1);
        }
        expect(button.hitTestable(), findsOneWidget, reason: 'step reachable');
        await tester.tap(button.hitTestable());
        await _frames(tester, 2);
        expect(
          tester.widget<TextField>(fields.at(fieldIndex)).controller!.text,
          expected,
        );
      }

      await step(0, '增加', '1.01');
      await step(0, '减少', '1');
      await step(1, '增加', '3');
      await step(1, '减少', '2');
      await tester.ensureVisible(ticket);
      await tester.drag(ticket, const Offset(0, 350));
      await _frames(tester, 3);
      await _capture(tester, 'affected-labels-dark-font13');
      state.selectTheme(ClientTheme.light);
      await _frames(tester, 3);
      await _capture(tester, 'affected-labels-light-font13');
      state.selectTheme(ClientTheme.dark);
      await _frames(tester, 3);
      await tester.drag(ticket, const Offset(0, -350));
      await _frames(tester, 3);
      final postOnly = find.descendant(
        of: ticket,
        matching: find.text('Post Only'),
      );
      expect(postOnly.hitTestable(), findsOneWidget);
      final checks = find.descendant(
        of: ticket,
        matching: find.byType(Checkbox),
      );
      await tester.tap(checks.last);
      await _frames(tester, 2);
      expect(tester.widget<OrderTicket>(ticket).postOnly, isTrue);
      await tester.tap(checks.last);
      await _frames(tester, 2);
      expect(tester.widget<OrderTicket>(ticket).postOnly, isFalse);
      final submit = find.descendant(
        of: ticket,
        matching: find.widgetWithText(FilledButton, '买入 / 开多'),
      );
      expect(submit.hitTestable(), findsOneWidget);
      expect(
        tester.getBottomRight(submit).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(ExchangeBottomNav)).dy),
      );
      expect(fixture.orders, isEmpty);
      await _capture(tester, 'affected-post-only-safe-area');
      expect(tester.takeException(), isNull);
      debugPrint(
        'REMEDIATION_AFFECTED_INPUT:focus:selection:native-keyboard:controller:price-steps:quantity-steps:labels-dark-light-font13:risk-card:post-only:safe-area',
      );
      await tester.pumpWidget(const SizedBox());
    },
    skip: !_inputOnly,
    timeout: const Timeout(Duration(minutes: 3)),
  );

  testWidgets(
    'live native login order and cancel against local backend',
    (tester) async {
      const gateway = String.fromEnvironment('REMEDIATION_GATEWAY');
      const websocket = String.fromEnvironment('REMEDIATION_WEBSOCKET');
      const identifier = String.fromEnvironment('REMEDIATION_IDENTIFIER');
      const password = String.fromEnvironment('REMEDIATION_PASSWORD');
      final expectedOwner = requireInt64(
        const String.fromEnvironment('REMEDIATION_USER_ID'),
        'native expected userId',
      );
      expect(expectedOwner, greaterThan(0));
      const liveConfig = AppConfig(
        gatewayBaseUrl: gateway,
        websocketUrl: websocket,
      );
      final liveApi = ApiClient(liveConfig)
        ..deviceIdLoader = () async =>
            const String.fromEnvironment('REMEDIATION_DEVICE_ID');
      final state = AppState(
        config: liveConfig,
        apiClient: liveApi,
        sessionStore: _SessionMemory(),
        settingsStore: _SettingsMemory(),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await state.refreshInstruments();
      expect(state.instruments, isNotEmpty);
      await state.selectMode(ProductMode.linear);
      await _nav(tester, '交易');
      final ticket = find.byType(OrderTicket);
      final login = find.descendant(of: ticket, matching: find.text('登录'));
      await tester.ensureVisible(login);
      await tester.tap(login);
      await _frames(tester, 4);
      final authFields = find.descendant(
        of: find.byType(AuthSheet),
        matching: find.byType(TextField),
      );
      await _enterText(tester, authFields.first, identifier);
      await _enterText(tester, authFields.at(1), password);
      FocusManager.instance.primaryFocus?.unfocus();
      final authSubmit = find.descendant(
        of: find.byType(AuthSheet),
        matching: find.widgetWithText(FilledButton, '登录'),
      );
      await tester.ensureVisible(authSubmit);
      await tester.tap(authSubmit);
      for (var n = 0; n < 70 && !state.isLoggedIn; n++) {
        await _frames(tester, 1);
      }
      expect(state.isLoggedIn, isTrue, reason: state.lastError);
      expect(state.userId, expectedOwner, reason: 'native authenticated owner');
      for (
        var n = 0;
        n < 70 && !(state.privateViews[state.mode]?.ready ?? false);
        n++
      ) {
        await _frames(tester, 1);
      }
      expect(
        state.privateViews[state.mode]?.ready,
        isTrue,
        reason: 'real private snapshot must complete',
      );
      await _capture(tester, 'live-authenticated');
      for (final mode in [ProductMode.linear, ProductMode.spot]) {
        final tab = find.byKey(ValueKey('product-tab-${mode.name}'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        for (
          var n = 0;
          n < 100 &&
              (!(state.privateViews[mode]?.ready ?? false) ||
                  state.orderBook.bids.isEmpty ||
                  state.mode != mode);
          n++
        ) {
          await _frames(tester, 1);
        }
        expect(state.mode, mode);
        expect(state.selectedInstrument.mode, mode);
        expect(state.privateViews[mode]?.ready, isTrue);
        expect(state.orderBook.symbol, state.selectedSymbol);
        expect(state.userId, expectedOwner);
        expect(
          state.openOrders,
          isEmpty,
          reason: 'isolated native owner must start without open orders',
        );
        final instrument = state.selectedInstrument;
        final instrumentId = requireInt64(
          instrument.instrumentId,
          'instrumentId',
        );
        expect(instrumentId, greaterThan(0));
        final expectedInstrumentId = requireInt64(
          mode.isSpot
              ? const String.fromEnvironment('REMEDIATION_SPOT_INSTRUMENT_ID')
              : const String.fromEnvironment(
                  'REMEDIATION_LINEAR_INSTRUMENT_ID',
                ),
          'native expected instrumentId',
        );
        expect(
          instrumentId,
          expectedInstrumentId,
          reason: 'handoff instrument',
        );
        expect(state.orderBook.bids, isNotEmpty);
        final ticks = state.orderBook.bids.first.priceTicks - 20;
        expect(ticks, greaterThan(0));
        final price = scaledAmount(
          BigInt.from(ticks) * BigInt.from(instrument.priceTickUnits),
          instrument.quoteScaleUnits,
        );
        final quantity = instrument.isSpot
            ? scaledAmount(
                BigInt.from(instrument.minQuantitySteps ?? 1) *
                    BigInt.from(instrument.quantityStepUnits),
                instrument.baseScaleUnits,
              )
            : '${instrument.minQuantitySteps ?? 1}';
        final fields = find.descendant(
          of: ticket,
          matching: find.byType(TextField),
        );
        await _enterText(tester, fields.first, price);
        await _enterText(tester, fields.at(1), quantity);
        FocusManager.instance.primaryFocus?.unfocus();
        await _frames(tester, 3);
        final buy = find.descendant(
          of: ticket,
          matching: find.widgetWithText(
            FilledButton,
            instrument.isSpot ? '买入' : '买入 / 开多',
          ),
        );
        await tester.ensureVisible(buy);
        await tester.tap(buy);
        for (var n = 0; n < 100 && state.openOrders.isEmpty; n++) {
          await _frames(tester, 1);
        }
        expect(
          state.openOrders,
          isNotEmpty,
          reason: state.lastError ?? state.lastNotice,
        );
        final created = state.openOrders.first;
        var canceledByUi = false;
        addTearDown(() async {
          if (!canceledByUi) {
            try {
              await state.api.cancelOrder(
                state.userId!,
                created.orderId,
                productLine: instrument.mode.productLine,
              );
              debugPrint('REMEDIATION_LIVE_CLEANUP:${created.orderId}');
            } catch (_) {
              debugPrint(
                'REMEDIATION_LIVE_CLEANUP_REQUIRED:${created.orderId}',
              );
            }
          }
        });
        expect(created.orderId, greaterThan(0));
        expect(
          BigInt.from(created.orderId),
          lessThanOrEqualTo(BigInt.parse('9223372036854775807')),
        );
        expect(created.symbol, instrument.symbol);
        expect(created.orderType, 'LIMIT');
        expect(created.executedQuantitySteps, 0);
        final rawOrder = state.privateViews[mode]!
            .rows('order')
            .singleWhere(
              (row) => parseInt64(row['orderId']) == created.orderId,
            );
        expect(requireInt64(rawOrder['orderId'], 'orderId'), created.orderId);
        if (rawOrder.containsKey('userId')) {
          expect(requireInt64(rawOrder['userId'], 'userId'), expectedOwner);
        }
        if (rawOrder.containsKey('instrumentId')) {
          expect(
            requireInt64(rawOrder['instrumentId'], 'instrumentId'),
            instrumentId,
          );
        }
        expect(created.priceTicks, ticks);
        expect(created.quantitySteps, instrument.minQuantitySteps ?? 1);
        debugPrint(
          'REMEDIATION_LIVE_ORDER:${mode.productLine}:${created.orderId}:${instrument.instrumentId}:$ticks:$quantity',
        );
        final ordersTab = find.widgetWithText(
          ChoiceChip,
          '当前委托 (${state.openOrders.length})',
        );
        await tester.ensureVisible(ordersTab);
        await tester.tap(ordersTab);
        await _frames(tester, 3);
        final row = find.byWidgetPredicate(
          (widget) =>
              widget is OrderRow && widget.order.orderId == created.orderId,
        );
        final cancel = find.descendant(of: row, matching: find.text('撤单'));
        await tester.ensureVisible(cancel);
        await _capture(tester, 'live-${mode.name}-order-open');
        await tester.tap(cancel);
        await _frames(tester, 3);
        final confirmation = find.text('确认撤单');
        if (confirmation.evaluate().isNotEmpty) {
          await tester.tap(confirmation);
        }
        for (
          var n = 0;
          n < 100 &&
              state.openOrders.any((item) => item.orderId == created.orderId);
          n++
        ) {
          await _frames(tester, 1);
        }
        expect(
          state.openOrders.any((item) => item.orderId == created.orderId),
          isFalse,
          reason: state.lastError,
        );
        bool terminalEvent() =>
            (state.privateViews[state.mode]?.orderUpdates ?? []).any(
              (row) =>
                  parseInt64(row['orderId']) == created.orderId &&
                  row['status'] == 'CANCELED',
            );
        for (var n = 0; n < 70 && !terminalEvent(); n++) {
          await _frames(tester, 1);
        }
        expect(
          terminalEvent(),
          isTrue,
          reason: 'committed cancellation must reach the private realtime view',
        );
        final terminal = state.privateViews[mode]!.orderUpdates.firstWhere(
          (row) =>
              parseInt64(row['orderId']) == created.orderId &&
              row['status'] == 'CANCELED',
        );
        expect(requireInt64(terminal['orderId'], 'orderId'), created.orderId);
        if (terminal.containsKey('userId')) {
          expect(requireInt64(terminal['userId'], 'userId'), expectedOwner);
        }
        if (terminal.containsKey('instrumentId')) {
          expect(
            requireInt64(terminal['instrumentId'], 'instrumentId'),
            instrumentId,
          );
        }
        expect(state.userId, expectedOwner);
        canceledByUi = true;
        debugPrint(
          'REMEDIATION_LIVE_TERMINAL:${mode.productLine}:${created.orderId}:CANCELED:owner=$expectedOwner',
        );
        await _capture(tester, 'live-${mode.name}-order-canceled');
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    skip:
        _riskOnly ||
        !const bool.fromEnvironment('REMEDIATION_LIVE') ||
        const bool.fromEnvironment('REMEDIATION_SOAK_ONLY'),
    timeout: const Timeout(Duration(minutes: 5)),
  );
}

class _SettingsMemory implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> next) async {
    values = {...next};
  }
}

class _SessionMemory implements SessionStore {
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

class _Fixture {
  _Fixture(this.server);
  final HttpServer server;
  final sockets = <WebSocket>{};
  final socketOwners = <WebSocket, int>{};
  final orders = <Map<String, dynamic>>[];
  final hanging = <HttpResponse>[];
  final silentSockets = <Socket>[];
  int depthSubscriptions = 0,
      privateSubscriptions = 0,
      sequence = 10,
      connections = 0,
      messagesSent = 0;
  bool dropDepth = false, dropPrivate = false;
  bool sendPrivateHeartbeats = false, invalidRiskAmount = false;
  Duration riskReportedAge = Duration.zero;
  int riskResponseStatus = 200, heldRiskRequests = 0;
  int? holdRiskForUser;
  Completer<void>? riskGate;
  late final Timer pulse;
  AppConfig get config => AppConfig(
    gatewayBaseUrl: 'http://127.0.0.1:${server.port}',
    websocketUrl: 'ws://127.0.0.1:${server.port}/ws',
  );
  static Future<_Fixture> start() async {
    final value = _Fixture(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
    );
    value.server.listen(value.handle);
    value.pulse = Timer.periodic(const Duration(seconds: 3), (_) {
      for (final socket in value.sockets) {
        if (socket.readyState == WebSocket.open) {
          socket.add(jsonEncode({'op': 'pong'}));
          final owner = value.socketOwners[socket];
          if (value.sendPrivateHeartbeats &&
              !value.dropPrivate &&
              owner != null) {
            for (final product in ProductMode.values) {
              socket.add(
                jsonEncode(
                  value.privateSnapshot(product, ++value.sequence, owner),
                ),
              );
            }
          }
        }
      }
    });
    return value;
  }

  ProductMode _mode(String? line) => ProductMode.values.firstWhere(
    (p) => p.productLine == line,
    orElse: () => ProductMode.linear,
  );
  void emit(Map<String, dynamic> event) {
    for (final socket in sockets.toList()) {
      if (socket.readyState == WebSocket.open) {
        socket.add(jsonEncode(event));
        messagesSent++;
      }
    }
  }

  void sendRaw(String value) {
    for (final socket in sockets.toList()) {
      if (socket.readyState == WebSocket.open) socket.add(value);
    }
  }

  void releaseRisk() {
    holdRiskForUser = null;
    if (riskGate != null && !riskGate!.isCompleted) riskGate!.complete();
    riskGate = null;
  }

  Map<String, dynamic> privateSnapshot(ProductMode product, int n, int owner) {
    final snapshot = _snapshot(product, n, userId: owner);
    if (sendPrivateHeartbeats) {
      final asset = _instrument(product)['settleAsset'] as String;
      final scale = asset == 'BTC' ? 100000000 : 1000000;
      asMap(asMap(snapshot['data'])['account'])['balances'] = [
        {'asset': asset, 'availableUnits': owner * scale, 'lockedUnits': 0},
      ];
    }
    return snapshot;
  }

  void sendTicker(ProductMode p) => emit({
    'op': 'event',
    'channel': 'bookTicker',
    'productLine': p.productLine,
    'instrumentId': '${100 + p.index}',
    'data': {
      'version': _version(++sequence),
      'value': {
        'bid': {'priceTicks': 100},
        'ask': {'priceTicks': 102},
      },
    },
  });
  void sendDepth(ProductMode p) => emit({
    'op': 'event',
    'channel': 'depth',
    'productLine': p.productLine,
    'instrumentId': '${100 + p.index}',
    'data': {'version': _version(++sequence), 'value': book(p)},
  });
  void sendGap(ProductMode p) => emit({
    'op': 'event',
    'channel': 'depth',
    'productLine': p.productLine,
    'instrumentId': '${100 + p.index}',
    'data': {
      'version': _version(++sequence),
      'value': {
        'updateType': 'DELTA',
        'sequence': sequence + 10,
        'previousSequence': sequence + 9,
        'depth': 50,
        'bids': [
          {'priceTicks': 99, 'quantitySteps': 1},
        ],
        'asks': [],
      },
    },
  });
  Map<String, dynamic> book(ProductMode p) => {
    'symbol': _instrument(p)['symbol'],
    'instrumentId': '${100 + p.index}',
    'sequence': sequence,
    'previousSequence': null,
    'updateType': 'SNAPSHOT',
    'depth': 50,
    'bids': [
      {'priceTicks': 100, 'quantitySteps': 1000, 'orderCount': 1},
    ],
    'asks': [
      {'priceTicks': 102, 'quantitySteps': 1000, 'orderCount': 1},
    ],
  };
  Future<void> handle(HttpRequest request) async {
    if (request.uri.path == '/silent-ws') {
      final key = request.headers.value('sec-websocket-key')!;
      request.response.statusCode = HttpStatus.switchingProtocols;
      request.response.headers.set('connection', 'Upgrade');
      request.response.headers.set('upgrade', 'websocket');
      request.response.headers.set(
        'sec-websocket-accept',
        base64Encode(
          sha1
              .convert(
                utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11'),
              )
              .bytes,
        ),
      );
      final socket = await request.response.detachSocket(writeHeaders: true);
      silentSockets.add(socket);
      socket.listen((_) {}, onError: (Object _) {});
      return;
    }
    if (WebSocketTransformer.isUpgradeRequest(request)) {
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      connections++;
      socket.listen(
        (raw) {
          final command = jsonDecode(raw as String) as Map<String, dynamic>;
          if (command['op'] == 'authenticate') {
            final owner = asString(command['token']).endsWith('-8') ? 8 : 7;
            socketOwners[socket] = owner;
            socket.add(jsonEncode({'op': 'authenticated', 'userId': owner}));
          }
          if (command['op'] == 'ping') socket.add(jsonEncode({'op': 'pong'}));
          if (command['op'] == 'subscribe') {
            final p = _mode(command['productLine'] as String?);
            if (command['channel'] == 'depth') {
              depthSubscriptions++;
              if (!dropDepth) sendDepth(p);
            }
            if (command['channel'] == 'bookTicker') sendTicker(p);
            if (command['channel'] == 'accountState') {
              privateSubscriptions++;
              if (!dropPrivate) {
                emit(privateSnapshot(p, ++sequence, socketOwners[socket] ?? 7));
              }
            }
          }
        },
        onDone: () {
          sockets.remove(socket);
          socketOwners.remove(socket);
        },
        onError: (Object _) {
          sockets.remove(socket);
          socketOwners.remove(socket);
        },
      );
      return;
    }
    final path = request.uri.path, query = request.uri.queryParameters;
    if (path == '/api/v1/auth/login') {
      final body = asMap(jsonDecode(await utf8.decoder.bind(request).join()));
      final owner = asString(body['identifier']).endsWith('-8') ? 8 : 7;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'user': {
            'userId': owner,
            'username': 'native-fixture-$owner',
            'email': 'native-$owner@example.invalid',
            'status': 'ACTIVE',
          },
          'accessToken': 'isolated-native-fixture-$owner',
          'refreshToken': 'isolated-native-refresh-$owner',
        }),
      );
      await request.response.close();
      return;
    }
    if (path == '/api/v1/gateway/risk/account/latest') {
      final owner = int.parse(query['userId']!);
      final asset = query['settleAsset']!;
      final scale = asset == 'BTC' ? 100000000 : 1000000;
      final status = riskResponseStatus;
      final body = {
        'snapshotId': ++sequence,
        'userId': owner,
        'accountType': query['accountType'],
        'settleAsset': asset,
        'walletBalanceUnits': owner * scale,
        'unrealizedPnlUnits': 0,
        'equityUnits': invalidRiskAmount ? 'NaN' : owner * scale,
        'maintenanceMarginUnits': 0,
        'marginRatioPpm': 0,
        'status': 'NORMAL',
        'eventTime': DateTime.now()
            .toUtc()
            .subtract(riskReportedAge)
            .toIso8601String(),
      };
      if (holdRiskForUser == owner && riskGate != null) {
        heldRiskRequests++;
        await riskGate!.future;
      }
      try {
        request.response.statusCode = status;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(body));
        await request.response.close();
      } on SocketException {
        // Account switching deliberately cancels the old in-flight request.
      } on HttpException {
        // Its late server response must not mutate the newly logged-in account.
      } on StateError {
        // The response may already be closed after deliberate cancellation.
      }
      return;
    }
    if (path == '/remediation/slow-headers') {
      hanging.add(request.response);
      return;
    }
    if (path == '/remediation/oversized') {
      request.response.write('x' * 2048);
      await request.response.close();
      return;
    }
    if (path == '/remediation/half-body') {
      request.response.headers.contentType = ContentType.json;
      request.response.write('{"ok":');
      await request.response.flush();
      hanging.add(request.response);
      return;
    }
    final p = _mode(
      request.headers.value('X-Product-Line') ?? query['productLine'],
    );
    Object result = switch (path) {
      '/api/v1/gateway/instrument/asset-scales' => {
        'BTC': '100000000',
        'USD': '1000000',
        'USDT': '1000000',
      },
      '/api/v1/gateway/instrument/list' => {
        'instruments': ProductMode.values
            .where(
              (item) =>
                  query['productLine'] == null ||
                  item.productLine == query['productLine'],
            )
            .map(_instrument)
            .toList(),
        'hasMore': false,
      },
      '/api/v1/gateway/trading-market/orderbook' => book(p),
      '/api/v1/gateway/candlestick/candles' => {'candles': []},
      '/api/v1/gateway/candlestick/trades/recent' => {'trades': []},
      '/api/v1/runtime' => {'disabledProductLines': []},
      '/api/v1/gateway/account/balances' => {
        'balances': [
          {'asset': 'USDT', 'availableUnits': 1000000000, 'lockedUnits': 0},
        ],
      },
      '/api/v1/gateway/trading-fees/effective' => {
        'userId': 7,
        'instrumentId': query['instrumentId'],
        'productLine': p.productLine,
        'changeId': 1,
        'takerFeeRatePpm': 1000,
      },
      '/api/v1/gateway/trading/price-protection' => {
        'productLine': p.productLine,
        'marketMaxSlippagePpm': 10000,
      },
      _ => <String, dynamic>{},
    };
    if (request.method == 'POST' && path == '/api/v1/gateway/trading') {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      orders.add(body);
      result = {...body, 'orderId': '9007199254740993', 'status': 'ACCEPTED'};
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(result));
    await request.response.close();
  }

  Future<void> close() async {
    pulse.cancel();
    for (final socket in silentSockets) {
      socket.destroy();
    }
    for (final socket in sockets.toList()) {
      await socket.close();
    }
    for (final response in hanging) {
      unawaited(response.close().catchError((Object _) {}));
    }
    await server.close(force: true);
  }
}
