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
  final fixturePath = Platform.environment['OPTION_PROTECTION_LIVE_FIXTURE'];
  testWidgets(
    'OPTION FUSED atomic protection triggers a real close and recovers only its original receipt',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          expect(fixturePath, startsWith('/tmp/surprising-option-fused-'));
          final fixture = asMap(
            jsonDecode(await File(fixturePath!).readAsString()),
          );
          expect(fixture['productLine'], 'OPTION');
          final root = File(fixturePath).parent;
          final session = AuthSession.fromJson(asMap(fixture['session']));
          final pidFile = File(
            Platform.environment['OPTION_PROTECTION_REALTIME_PID_FILE']!,
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
          var paused = false, dropped = false;
          proxy.listen((incoming) async {
            try {
              final payload = await utf8.decoder.bind(incoming).join();
              final batch =
                  incoming.method == 'POST' &&
                  incoming.uri.path == '/api/v1/gateway/trading-trigger/batch';
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
            return _State(api, settings, instrument, initialSession: session);
          }

          try {
            final direct = ApiClient(
              const AppConfig(gatewayBaseUrl: 'http://127.0.0.1:9094'),
              httpClient: upstream,
            )..setSession(session);
            final instrument = await direct.instrumentLatest(
              asString(fixture['instrumentId']),
              ProductMode.option,
            );
            state = make(instrument);
            await state.refreshPrivateData();
            expect(state.positions.single.signedQuantitySteps, 1);
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
              '900',
            );
            await tester.enterText(
              find.descendant(
                of: prices.last,
                matching: find.byType(TextField),
              ),
              '800',
            );
            await tester.tap(find.text('触发后市价执行').first);
            await tester.pumpAndSettle();
            await tester.tap(find.text('触发后限价执行').last);
            await tester.pumpAndSettle();
            final limit = find.byWidgetPredicate(
              (w) => w is AppTextField && w.label.startsWith('委托限价'),
            );
            await tester.enterText(
              find.descendant(of: limit, matching: find.byType(TextField)),
              '900',
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
            await tester.pumpWidget(const SizedBox.shrink());
            state.dispose();
            state = null;
            expect(Process.killPid(pid, ProcessSignal.sigcont), true);
            paused = false;
            state = make(instrument);
            await state.bootstrap();
            expect(state.tradingCommandPending, true);
            for (var i = 0; i < 200 && state.tradingCommandPending; i++) {
              await state.checkPendingTradingCommand();
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(state.tradingCommandPending, false);
            for (var i = 0; i < 100; i++) {
              await state.refreshPrivateData();
              if (state.positions.every((p) => p.signedQuantitySteps == 0)) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(
              state.positions.every((p) => p.signedQuantitySteps == 0),
              true,
            );
            expect(posts.length, 1);
            await File(
              '${root.path}/protection-client-evidence.json',
            ).writeAsString(
              jsonEncode({
                'productLine': 'OPTION',
                'triggerIds': ids.map((id) => '$id').toList(),
                'posts': 1,
                'atomic': true,
                'pausedUnknown': true,
                'restartRestored': true,
                'finalPosition': 0,
                'width': 320,
              }),
            );
            expect(tester.takeException(), isNull);
            debugPrint(
              'OPTION_PROTECTION_CLIENT_PASS atomic=true posts=1 limitClose=true pausedUnknown=true restartRestored=true finalPosition=0 width320',
            );
          } finally {
            if (paused) Process.killPid(pid, ProcessSignal.sigcont);
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
  _State(
    ApiClient api,
    _Settings settings,
    Instrument instrument, {
    super.initialSession,
  }) : super(
         apiClient: api,
         settingsStore: settings,
         sessionStore: _Sessions(),
         config: const AppConfig(websocketUrl: ''),
         seedInstruments: [instrument],
       ) {
    mode = ProductMode.option;
  }
  @override
  Future<void> refreshPrivateData() async {
    if (userId != null) {
      positions = await api.positions(userId!, productLine: 'OPTION');
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
