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

// Explicit local FUSED handoff only. This test never connects to the production config.
void main() {
  final fixturePath = Platform.environment['SPOT_FUSED_LIVE_FIXTURE'];
  testWidgets(
    'SPOT FUSED real HTTP/WS bulk cancellation survives projection pause and restart',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          final path = fixturePath!;
          expect(path, startsWith('/tmp/surprising-spot-fused-'));
          final fixture = asMap(jsonDecode(await File(path).readAsString()));
          final session = AuthSession.fromJson(asMap(fixture['session']));
          final id = session.user.userId,
              instrumentId = asString(fixture['instrumentId']);
          final pidFile = File(
            Platform.environment['SPOT_FUSED_REALTIME_PID_FILE']!,
          );
          expect(pidFile.path, startsWith('/tmp/surprising-spot-fused-'));
          final realtimePid = int.parse((await pidFile.readAsString()).trim());
          final identity = await Process.run('ps', [
            '-p',
            '$realtimePid',
            '-o',
            'command=',
          ]);
          expect(
            identity.stdout,
            contains(
              '-Dsurprising.launcher.identity=${fixture['runId']}/realtime',
            ),
          );
          final upstream = HttpOverrides.runWithHttpOverrides(
            () => HttpClient(),
            _RealHttp(),
          );
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final methods = <String>[], batches = <Map<String, dynamic>>[];
          final settings = _Settings();
          var paused = false, lost = false;
          int? endedId;
          Future<Map<String, dynamic>> direct(
            String method,
            String endpoint, {
            Object? body,
          }) async {
            final req = await upstream.openUrl(
              method,
              Uri.parse('http://127.0.0.1:9094$endpoint'),
            );
            req.headers.set('Authorization', 'Bearer ${session.accessToken}');
            req.headers.set('X-Product-Line', 'SPOT');
            req.headers.contentType = ContentType.json;
            if (body != null) req.write(jsonEncode(body));
            final response = await req.close();
            final raw = await utf8.decoder.bind(response).join();
            expect(
              response.statusCode,
              inInclusiveRange(200, 202),
              reason: raw,
            );
            return asMap(jsonDecode(raw));
          }

          server.listen((incoming) async {
            try {
              final payload = await utf8.decoder.bind(incoming).join();
              if (incoming.uri.path.endsWith('/batch-cancel')) {
                final body = asMap(jsonDecode(payload));
                batches.add(body);
                methods.add(incoming.method);
                final stored = asList(
                  jsonDecode(settings.values['pendingTradingOrders']!),
                );
                expect(
                  asMap(asMap(stored.single)['cancelPlan'])['issued'],
                  isTrue,
                );
                if (!lost) {
                  endedId = asInt(
                    asMap(asList(body['orders']).first)['orderId'],
                  );
                  final canceled = await direct(
                    'POST',
                    '/api/v1/gateway/trading/cancel',
                    body: {'userId': id, 'orderId': endedId},
                  );
                  expect(canceled['outcome'], 'TERMINAL');
                  expect(canceled['code'], 'NONE');
                  expect(
                    Process.killPid(realtimePid, ProcessSignal.sigstop),
                    isTrue,
                  );
                  paused = true;
                }
              } else if (incoming.uri.path.endsWith('/cancellation-batches')) {
                methods.add(incoming.method);
              }
              final request = await upstream.openUrl(
                incoming.method,
                Uri.parse('http://127.0.0.1:9094${incoming.uri}'),
              );
              incoming.headers.forEach((name, values) {
                if (![
                  'host',
                  'content-length',
                  'connection',
                  'transfer-encoding',
                ].contains(name.toLowerCase())) {
                  request.headers.set(name, values);
                }
              });
              if (payload.isNotEmpty) request.write(payload);
              final response = await request.close();
              final bytes = await response.fold<List<int>>(
                [],
                (all, chunk) => all..addAll(chunk),
              );
              if (incoming.uri.path.endsWith('/batch-cancel') && !lost) {
                expect(response.statusCode, inInclusiveRange(200, 202));
                lost = true;
                (await incoming.response.detachSocket(
                  writeHeaders: false,
                )).destroy();
                return;
              }
              incoming.response.statusCode = response.statusCode;
              incoming.response.headers.contentType = ContentType.json;
              incoming.response.add(bytes);
              await incoming.response.close();
            } catch (error, stack) {
              incoming.response.statusCode = 500;
              incoming.response.write('$error');
              await incoming.response.close();
              Zone.current.handleUncaughtError(error, stack);
            }
          });
          AppState? state;
          final clients = <HttpClient>[];
          AppState createState(Instrument instrument) {
            final http = HttpOverrides.runWithHttpOverrides(
              () => HttpClient(),
              _RealHttp(),
            );
            clients.add(http);
            final config = AppConfig(
              gatewayBaseUrl: 'http://127.0.0.1:${server.port}',
              websocketUrl: 'ws://127.0.0.1:9094/ws/v1',
            );
            final api = ApiClient(config, httpClient: http)
              ..setSession(session)
              ..instrumentCatalog = [instrument];
            return AppState(
              initialSession: session,
              config: config,
              apiClient: api,
              settingsStore: settings,
              sessionStore: _Sessions(),
              seedInstruments: [instrument],
            )..mode = ProductMode.spot;
          }

          try {
            final raw = await direct(
              'GET',
              '/api/v1/gateway/instrument/latest?instrumentId=$instrumentId',
            );
            final scales = await direct(
              'GET',
              '/api/v1/gateway/instrument/asset-scales',
            );
            final instrument = Instrument.fromJson({
              ...raw,
              'baseScaleUnits': scales[asString(raw['baseAsset'])],
              'quoteScaleUnits': scales[asString(raw['quoteAsset'])],
            });
            state = createState(instrument);
            await state.bootstrap();
            final target = state;
            final orderIds = <int>[];
            for (var i = 0; i < 52; i++) {
              final receipt = await direct(
                'POST',
                '/api/v1/gateway/trading',
                body: {
                  'userId': id,
                  'clientOrderId':
                      'fused-client-${DateTime.now().microsecondsSinceEpoch}-$i',
                  'instrumentId': instrumentId,
                  'side': 'BUY',
                  'orderType': 'LIMIT',
                  'timeInForce': 'GTC',
                  'priceTicks': 100000,
                  'quantitySteps': 1,
                  'marginMode': 'CROSS',
                  'positionSide': 'NET',
                  'reduceOnly': false,
                  'postOnly': false,
                },
              );
              expect(receipt['outcome'], 'TERMINAL');
              expect(receipt['code'], 'NONE');
              orderIds.add(
                asInt(asList(receipt['prospectiveOrderIds']).single),
              );
            }
            for (var attempt = 0; attempt < 100; attempt++) {
              final plan = await target.api.cancellationPlan(
                id,
                instrumentId: instrumentId,
              );
              if (plan.length == 52) break;
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(
              (await target.api.cancellationPlan(
                id,
                instrumentId: instrumentId,
              )).toSet(),
              orderIds.toSet(),
            );
            await target.cancelOpenSpotOrders(onlyCurrentPair: true);
            expect(target.tradingCommandPending, isTrue);
            expect(batches.length, 1);
            await target.checkPendingTradingCommand();
            expect(target.tradingCommandPending, isTrue);
            expect(batches.length, 1);
            final key =
                target.pendingTradingCommand!.cancelPlan!.batches.first.key;
            expect(Process.killPid(realtimePid, ProcessSignal.sigcont), isTrue);
            paused = false;
            target.dispose();
            state = null;
            state = createState(instrument);
            await state.bootstrap();
            expect(
              state.pendingTradingCommand!.cancelPlan!.batches.first.key,
              key,
            );
            for (
              var attempt = 0;
              attempt < 100 && state.tradingCommandPending;
              attempt++
            ) {
              await state.checkPendingTradingCommand();
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(
              state.tradingCommandPending,
              isFalse,
              reason: state.lastError,
            );
            expect(batches.length, 2);
            expect(batches.map((b) => b['batchKey']).toSet().length, 2);
            expect(
              batches
                  .expand((b) => asList(b['orders']))
                  .map((r) => asInt(asMap(r)['orderId']))
                  .toSet(),
              orderIds.toSet(),
            );
            expect(state.lastCancellationResult?.requested, 52);
            expect(state.lastCancellationResult?.completed, 51);
            expect(state.lastCancellationResult?.failed, 1);
            expect(
              state.lastCancellationResult?.failures.single.orderId,
              endedId,
            );
            for (var attempt = 0; attempt < 100; attempt++) {
              if (state.balances.isNotEmpty &&
                  state.balances.every((b) => b.lockedUnits == 0) &&
                  state.openOrders.isEmpty &&
                  state.orderBook.bids.isNotEmpty) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(state.balances, isNotEmpty);
            expect(state.balances.every((b) => b.lockedUnits == 0), isTrue);
            expect(state.openOrders, isEmpty);
            expect(state.orderBook.bids, isNotEmpty);
            expect(state.orderBook.asks, isNotEmpty);
            final current = state;
            tester.view.physicalSize = const Size(320, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              AppScope(
                notifier: current,
                child: MaterialApp(
                  theme: ThemeData.dark(),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: PrivateTradingPanel(state: current),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('当前委托 (0)'));
            await tester.pump();
            expect(find.text('已处理 52 笔，成功 51 笔，失败 1 笔'), findsOneWidget);
            await tester.ensureVisible(find.text('查看失败订单'));
            await tester.tap(find.text('查看失败订单'));
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.text('订单 #$endedId'), findsOneWidget);
            expect(tester.takeException(), isNull);
            debugPrint(
              'SPOT_FUSED_CLIENT_PASS requested=52 completed=51 failed=1 batches=2 pausedUnknown=true restored=true realtimeBook=true locked=0 methods=$methods',
            );
            final evidence = File('$path.client-evidence.json');
            await evidence.writeAsString(
              jsonEncode({
                'requested': 52,
                'completed': 51,
                'failed': 1,
                'batchKeys': batches.map((b) => b['batchKey']).toList(),
                'orderIds': orderIds,
                'endedId': endedId,
                'methods': methods,
                'unknownDuringRealProjectionPause': true,
                'restartRestoredOriginalKey': true,
                'realBookBothSides': true,
                'privateLockedZero': true,
                'widgetWidth': 320,
                'widgetTheme': 'dark',
              }),
            );
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            if (paused) Process.killPid(realtimePid, ProcessSignal.sigcont);
            state?.dispose();
            for (final client in clients) {
              client.close(force: true);
            }
            upstream.close(force: true);
            await server.close(force: true);
          }
        }, _RealHttp()),
      );
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _RealHttp extends HttpOverrides {}

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> values) async {
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
