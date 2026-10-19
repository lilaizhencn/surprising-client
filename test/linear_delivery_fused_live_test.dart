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
  final fixturePath = Platform.environment['LINEAR_DELIVERY_LIVE_FIXTURE'];
  testWidgets(
    'LINEAR_DELIVERY FUSED settling closes and recovers a lost response without another order',
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
          final session = AuthSession.fromJson(asMap(fixture['session']));
          final instrumentId = asString(fixture['instrumentId']);
          final pidFile = File(
            Platform.environment['LINEAR_DELIVERY_REALTIME_PID_FILE']!,
          );
          expect(
            pidFile.path,
            startsWith('/tmp/surprising-linear-delivery-fused-'),
          );
          final pid = int.parse((await pidFile.readAsString()).trim());
          final identity = await Process.run('ps', [
            '-p',
            '$pid',
            '-o',
            'command=',
          ]);
          expect(
            identity.stdout,
            contains(
              '-Dsurprising.launcher.identity=${fixture['runId']}/realtime',
            ),
          );
          final upstream = HttpClient(),
              server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final settings = _Settings();
          final posts = <Map<String, dynamic>>[];
          var paused = false, lost = false;
          server.listen((incoming) async {
            try {
              final payload = await utf8.decoder.bind(incoming).join();
              if (incoming.method == 'POST' &&
                  incoming.uri.path == '/api/v1/gateway/trading') {
                final body = asMap(jsonDecode(payload));
                posts.add(body);
                expect(body['reduceOnly'], true);
                expect(body['quantitySteps'], 1);
                expect(body['instrumentId'], instrumentId);
                final pending = asMap(
                  asList(
                    jsonDecode(settings.values['pendingTradingOrders']!),
                  ).single,
                );
                expect(pending['clientOrderId'], body['clientOrderId']);
                expect(pending['productLine'], 'LINEAR_DELIVERY');
                if (!lost) {
                  expect(Process.killPid(pid, ProcessSignal.sigstop), true);
                  paused = true;
                }
              }
              final req = await upstream.openUrl(
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
                  req.headers.set(name, values);
                }
              });
              if (payload.isNotEmpty) req.write(payload);
              final response = await req.close();
              final bytes = await response.fold<List<int>>(
                [],
                (all, chunk) => all..addAll(chunk),
              );
              if (incoming.method == 'POST' &&
                  incoming.uri.path == '/api/v1/gateway/trading' &&
                  !lost) {
                expect(response.statusCode, 200);
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
          final clients = <HttpClient>[];
          AppState? state;
          AppState make(Instrument instrument) {
            final http = HttpClient();
            clients.add(http);
            final config = AppConfig(
              gatewayBaseUrl: 'http://127.0.0.1:${server.port}',
              websocketUrl: 'ws://127.0.0.1:9094/ws/v1',
            );
            final api = ApiClient(config, httpClient: http)
              ..setSession(session)
              ..instrumentCatalog = [instrument];
            return AppState(
                config: config,
                apiClient: api,
                settingsStore: settings,
                sessionStore: _Sessions(),
                seedInstruments: [instrument],
              )
              ..mode = ProductMode.linearDelivery
              ..session = session;
          }

          try {
            final direct = ApiClient(
              const AppConfig(gatewayBaseUrl: 'http://127.0.0.1:9094'),
              httpClient: upstream,
            )..setSession(session);
            final raw = await direct.get(
              '/api/v1/gateway/instrument/latest',
              query: {'instrumentId': instrumentId},
              productLine: 'LINEAR_DELIVERY',
            );
            final scales = await direct.assetScales();
            final instrument = Instrument.fromJson({
              ...raw,
              'quoteScaleUnits': scales[asString(raw['quoteAsset'])],
              'baseScaleUnits': scales[asString(raw['baseAsset'])],
              'settleScaleUnits': scales[asString(raw['settleAsset'])],
            });
            expect(instrument.status, 'SETTLING');
            state = make(instrument);
            await state.bootstrap();
            for (var i = 0; i < 100 && state.positions.isEmpty; i++) {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            final initial = state.positions.single;
            expect(initial.signedQuantitySteps, 1);
            expect(state.selectedInstrument.status, 'SETTLING');
            await state.placeOrder(
              side: 'BUY',
              orderType: 'MARKET',
              timeInForce: 'IOC',
              price: 0,
              quantitySteps: 1,
              marginMode: initial.marginMode,
              positionSide: 'NET',
              reduceOnly: false,
              postOnly: false,
            );
            expect(posts, isEmpty);
            expect(state.lastError, contains('仅允许减仓'));
            await state.closePosition(initial);
            expect(posts.length, 1);
            expect(state.tradingCommandPending, true);
            await state.checkPendingTradingCommand();
            expect(state.tradingCommandPending, true);
            expect(posts.length, 1);
            final clientId = state.pendingTradingCommand!.clientOrderId;
            expect(Process.killPid(pid, ProcessSignal.sigcont), true);
            paused = false;
            state.dispose();
            state = null;
            state = make(instrument);
            await state.bootstrap();
            expect(state.pendingTradingCommand?.clientOrderId, clientId);
            for (var i = 0; i < 100 && state.tradingCommandPending; i++) {
              await state.checkPendingTradingCommand();
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(state.tradingCommandPending, false, reason: state.lastError);
            expect(posts.length, 1);
            for (var i = 0; i < 100; i++) {
              if (state.positions.isEmpty &&
                  state.balances.isNotEmpty &&
                  state.balances.every((b) => b.lockedUnits == 0)) {
                break;
              }
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            expect(state.positions, isEmpty);
            expect(state.balances, isNotEmpty);
            expect(state.balances.every((b) => b.lockedUnits == 0), true);
            tester.view.physicalSize = const Size(320, 1000);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            await tester.pumpWidget(
              AppScope(
                notifier: state,
                child: MaterialApp(
                  theme: ThemeData.light(),
                  home: const Scaffold(body: TradePage()),
                ),
              ),
            );
            await tester.pump(const Duration(milliseconds: 400));
            expect(find.byType(ProductLifecyclePanel), findsOneWidget);
            expect(tester.takeException(), isNull);
            await File('$fixturePath.client-evidence.json').writeAsString(
              jsonEncode({
                'productLine': 'LINEAR_DELIVERY',
                'status': 'SETTLING',
                'openBlocked': true,
                'closeQuantity': 1,
                'posts': 1,
                'clientOrderId': clientId,
                'pausedUnknown': true,
                'restartRestored': true,
                'positions': 0,
                'locked': 0,
                'width': 320,
                'theme': 'light',
              }),
            );
            debugPrint(
              'LINEAR_DELIVERY_CLIENT_PASS status=SETTLING openBlocked=true closeQuantity=1 posts=1 pausedUnknown=true restartRestored=true positions=0 locked=0',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            if (paused) Process.killPid(pid, ProcessSignal.sigcont);
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
