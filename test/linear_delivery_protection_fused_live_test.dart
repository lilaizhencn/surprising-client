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

void main() {
  final fixturePath = Platform.environment['LINEAR_PROTECTION_LIVE_FIXTURE'];
  testWidgets(
    'LINEAR_DELIVERY FUSED protection and settling preserve original results',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          expect(
            fixturePath,
            startsWith('/tmp/surprising-linear-delivery-fused-'),
          );
          final fixture = asMap(
            jsonDecode(await File(fixturePath!).readAsString()),
          );
          expect(fixture['productLine'], 'LINEAR_DELIVERY');
          final root = File(fixturePath).parent;
          final session = AuthSession.fromJson(asMap(fixture['session']));
          final pidFile = File(
            '${root.path}/runtime/${fixture['runId']}/pids/realtime.pid',
          );
          expect(pidFile.path, startsWith(root.path));
          final pid = int.parse((await pidFile.readAsString()).trim());
          expect(
            (await Process.run('ps', ['-p', '$pid', '-o', 'command='])).stdout,
            contains(
              '-Dsurprising.launcher.identity=${fixture['runId']}/realtime',
            ),
          );
          final upstream = HttpClient(),
              proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final settings = _Settings();
          final posts = <Map<String, dynamic>>[];
          final ids = <int>[];
          var paused = false, dropped = false, corePaused = false;
          final ordinaryPosts = <Map<String, dynamic>>[];
          final phase = asString(fixture['deliveryProtectionPhase']);
          expect(phase, anyOf('TRADING', 'SETTLING'));
          final corePid = int.parse(
            (await File(
              '${root.path}/runtime/${fixture['runId']}/pids/core-node0.pid',
            ).readAsString()).trim(),
          );
          expect(
            (await Process.run('ps', ['-p', '$corePid', '-o', 'args='])).stdout,
            contains(
              '-Dsurprising.launcher.identity=${fixture['runId']}/core-node0',
            ),
          );
          proxy.listen((incoming) async {
            try {
              final payload = await utf8.decoder.bind(incoming).join();
              final batch =
                  incoming.method == 'POST' &&
                  incoming.uri.path == '/api/v1/gateway/trading-trigger/batch';
              if (incoming.method == 'POST' &&
                  incoming.uri.path == '/api/v1/gateway/trading') {
                ordinaryPosts.add(asMap(jsonDecode(payload)));
              }
              if (batch) {
                final body = asMap(jsonDecode(payload));
                posts.add(body);
                expect(body['atomic'], true);
                expect(asList(body['orders']).length, 2);
                final saved = asMap(
                  asList(
                    jsonDecode(settings.values['pendingTradingOrders']!),
                  ).single,
                );
                expect(
                  saved['ocoTakeProfitClientId'],
                  asMap(asList(body['orders']).first)['clientTriggerOrderId'],
                );
                final backup = File(
                  '${root.path}/delivery-protection-client-pending.json',
                );
                await backup.writeAsString(jsonEncode(settings.values));
                await Process.run('chmod', ['600', backup.path]);
                expect(Process.killPid(pid, ProcessSignal.sigstop), true);
                paused = true;
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
              if (batch && !dropped) {
                expect(response.statusCode, 200);
                final result = asMap(jsonDecode(utf8.decode(bytes)));
                for (final item in asList(result['results'])) {
                  ids.add(asInt(asMap(asMap(item)['order'])['triggerOrderId']));
                }
                expect(ids.length, 2);
                dropped = true;
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
          final clients = <HttpClient>[];
          _State? state;
          _State make(Instrument instrument) {
            final http = HttpClient();
            clients.add(http);
            final api = ApiClient(
              AppConfig(
                gatewayBaseUrl: 'http://127.0.0.1:${proxy.port}',
                websocketUrl: '',
              ),
              httpClient: http,
            )..setSession(session);
            return _State(api, settings, instrument)..session = session;
          }

          try {
            final direct = ApiClient(
              const AppConfig(gatewayBaseUrl: 'http://127.0.0.1:9094'),
              httpClient: upstream,
            )..setSession(session);
            final instrument = await direct.instrumentLatest(
              asString(fixture['instrumentId']),
              ProductMode.linearDelivery,
            );
            state = make(instrument);
            await state.refreshPrivateData();
            if (phase == 'SETTLING') {
              expect(instrument.status, 'SETTLING');
              settings.values = Map<String, String>.from(
                asMap(
                  jsonDecode(
                    await File(
                      '${root.path}/delivery-protection-client-pending.json',
                    ).readAsString(),
                  ),
                ),
              );
              await state.bootstrap();
              state.session = session;
              expect(state.tradingCommandPending, true);
              expect(Process.killPid(corePid, ProcessSignal.sigstop), true);
              corePaused = true;
              await state.checkPendingTradingCommand();
              expect(state.tradingCommandPending, false);
              expect(state.lastError, isNull);
              expect(Process.killPid(corePid, ProcessSignal.sigcont), true);
              corePaused = false;
              await state.refreshPrivateData();
              expect(state.positions.single.signedQuantitySteps, 1);
              const draft = TriggerOrderDraft(
                side: 'SELL',
                triggerType: 'TAKE_PROFIT',
                triggerPriceTicks: 600000,
                quantitySteps: 1,
                marginMode: 'CROSS',
                positionSide: 'NET',
              );
              expect(await state.placeTriggerOrders([draft]), 0);
              expect(
                await state.placeOco([
                  draft,
                  const TriggerOrderDraft(
                    side: 'SELL',
                    triggerType: 'STOP_LOSS',
                    triggerPriceTicks: 400000,
                    quantitySteps: 1,
                    marginMode: 'CROSS',
                    positionSide: 'NET',
                  ),
                ]),
                0,
              );
              expect(posts, isEmpty);
              expect(instrument.canPlaceOrder(reduceOnly: true), true);
              expect(instrument.canPlaceTrigger(), false);
              tester.view.physicalSize = const Size(320, 1500);
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                AppScope(
                  notifier: state,
                  child: MaterialApp(
                    theme: ThemeData.dark(),
                    home: Scaffold(
                      body: SingleChildScrollView(
                        child: TriggerOrderPanel(
                          state: state,
                          marginMode: 'CROSS',
                        ),
                      ),
                    ),
                  ),
                ),
              );
              await tester.tap(find.text('独立条件单'));
              await tester.pumpAndSettle();
              await tester.tap(find.text('TP/SL 双腿 OCO').last);
              await tester.pumpAndSettle();
              final inputs = find.byWidgetPredicate(
                (w) => w is AppTextField && w.label.startsWith('触发价'),
              );
              await tester.enterText(
                find.descendant(
                  of: inputs.first,
                  matching: find.byType(TextField),
                ),
                '60000',
              );
              await tester.enterText(
                find.descendant(
                  of: inputs.last,
                  matching: find.byType(TextField),
                ),
                '40000',
              );
              await tester.pump();
              expect(
                tester
                    .widget<FilledButton>(
                      find.widgetWithText(FilledButton, '一起提交 TP/SL'),
                    )
                    .onPressed,
                isNull,
              );
              await state.closePosition(state.positions.single);
              final deadline = DateTime.now().add(const Duration(seconds: 25));
              while (true) {
                if (state.tradingCommandPending) {
                  await state.checkPendingTradingCommand();
                }
                await state.refreshPrivateData();
                if (!state.tradingCommandPending &&
                    state.positions.every((p) => p.signedQuantitySteps == 0)) {
                  break;
                }
                expect(DateTime.now().isBefore(deadline), true);
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
              expect(posts, isEmpty);
              expect(ordinaryPosts.length, 1);
              expect(ordinaryPosts.single['reduceOnly'], true);
              await File(
                '${root.path}/delivery-protection-client-settling-evidence.json',
              ).writeAsString(
                jsonEncode({
                  'productLine': 'LINEAR_DELIVERY',
                  'phase': 'SETTLING',
                  'triggerPosts': 0,
                  'directClosePosts': 1,
                  'priorOcoRestored': true,
                  'corePausedQueries': 1,
                  'finalPosition': 0,
                  'width': 320,
                }),
              );
              expect(tester.takeException(), isNull);
              debugPrint(
                'LINEAR_DELIVERY_PROTECTION_CLIENT_SETTLING_PASS triggerPosts=0 originalOcoRestored=true corePausedRead=true directClosePosts=1 finalPosition=0',
              );
              return;
            }
            expect(state.positions.single.signedQuantitySteps, 2);
            tester.view.physicalSize = const Size(320, 1500);
            tester.view.devicePixelRatio = 1;
            await tester.pumpWidget(
              AppScope(
                notifier: state,
                child: MaterialApp(
                  theme: ThemeData.dark(),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: TriggerOrderPanel(
                        state: state,
                        marginMode: 'CROSS',
                      ),
                    ),
                  ),
                ),
              ),
            );
            await tester.tap(find.text('独立条件单'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('TP/SL 双腿 OCO').last);
            await tester.pumpAndSettle();
            final prices = find.byWidgetPredicate(
              (w) => w is AppTextField && w.label.startsWith('触发价'),
            );
            await tester.enterText(
              find.descendant(
                of: prices.first,
                matching: find.byType(TextField),
              ),
              '49000',
            );
            await tester.enterText(
              find.descendant(
                of: prices.last,
                matching: find.byType(TextField),
              ),
              '40000',
            );
            await tester.pump();
            await tester.tap(find.text('一起提交 TP/SL'));
            await tester.pump();
            for (
              var i = 0;
              i < 200 && (posts.isEmpty || state.submittingTriggers);
              i++
            ) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
              await tester.pump();
            }
            expect(posts.length, 1);
            expect(dropped, true);
            expect(state.tradingCommandPending, true);
            await state.checkPendingTradingCommand();
            expect(state.tradingCommandPending, true);
            expect(state.lastError, isNull);
            await tester.pumpWidget(const SizedBox.shrink());
            state.dispose();
            state = null;
            expect(Process.killPid(pid, ProcessSignal.sigcont), true);
            paused = false;
            state = make(instrument);
            await state.bootstrap();
            state.session = session;
            expect(state.tradingCommandPending, true);
            for (var i = 0; i < 200 && state.tradingCommandPending; i++) {
              await state.checkPendingTradingCommand();
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(state.tradingCommandPending, false);
            for (var i = 0; i < 100; i++) {
              await state.refreshPrivateData();
              if (state.positions.any((p) => p.signedQuantitySteps == 1)) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(state.positions.single.signedQuantitySteps == 1, true);
            expect(posts.length, 1);
            await File(
              '${root.path}/delivery-protection-client-evidence.json',
            ).writeAsString(
              jsonEncode({
                'productLine': 'LINEAR_DELIVERY',
                'triggerIds': ids.map((id) => '$id').toList(),
                'posts': 1,
                'atomic': true,
                'pausedUnknown': true,
                'restartRestored': true,
                'finalPosition': 1,
                'width': 320,
              }),
            );
            expect(tester.takeException(), isNull);
            debugPrint(
              'LINEAR_DELIVERY_PROTECTION_CLIENT_PASS atomic=true posts=1 marketCloseOne=true pausedUnknown=true restartRestored=true remainingPosition=1 width320',
            );
          } finally {
            if (paused) Process.killPid(pid, ProcessSignal.sigcont);
            if (corePaused) Process.killPid(corePid, ProcessSignal.sigcont);
            await tester.pumpWidget(const SizedBox.shrink());
            state?.dispose();
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            for (final client in clients) {
              client.close(force: true);
            }
            upstream.close(force: true);
            await proxy.close(force: true);
          }
        }, _RealHttp()),
      );
    },
    skip: fixturePath == null,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

class _State extends AppState {
  _State(ApiClient api, _Settings settings, Instrument instrument)
    : super(
        apiClient: api,
        settingsStore: settings,
        sessionStore: _Sessions(),
        config: const AppConfig(websocketUrl: ''),
        seedInstruments: [instrument],
      ) {
    mode = ProductMode.linearDelivery;
  }
  @override
  Future<void> refreshPrivateData() async {
    if (userId != null) {
      positions = await api.positions(userId!, productLine: 'LINEAR_DELIVERY');
      notifyListeners();
    }
  }

  @override
  Future<void> refreshInstruments({bool silent = false}) async {}
  @override
  Future<void> refreshPublicData({bool silent = false}) async {}
  @override
  Future<void> refreshValuation({bool silent = false}) async {}
  @override
  Future<void> refreshAnnouncements() async {}
}

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

class _RealHttp extends HttpOverrides {}
