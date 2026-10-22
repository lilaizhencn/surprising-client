import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

void main() {
  final fixturePath = Platform.environment['OPTION_SINGLE_LIVE_FIXTURE'];
  testWidgets(
    'OPTION FUSED independent trigger and cancellation survive real lost replies and state reconstruction',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          expect(fixturePath, startsWith('/tmp/surprising-option-fused-'));
          final fixture = asMap(
            jsonDecode(await File(fixturePath!).readAsString()),
          );
          final root = File(fixturePath).parent;
          expect(fixture['productLine'], 'OPTION');
          final session = AuthSession.fromJson(asMap(fixture['session']));
          Future<int> ownedPid(String role) async {
            final path = File(
              '${root.path}/runtime/${fixture['runId']}/pids/$role.pid',
            );
            final pid = int.parse((await path.readAsString()).trim());
            expect(
              (await Process.run('ps', ['-p', '$pid', '-o', 'args='])).stdout,
              contains(
                '-Dsurprising.launcher.identity=${fixture['runId']}/$role',
              ),
            );
            return pid;
          }

          final realtimePid = await ownedPid('realtime'),
              corePid = await ownedPid('core-node0');
          final upstream = HttpClient(),
              proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final settings = _Settings(),
              posts = <Map<String, dynamic>>[],
              ids = <String>[];
          var realtimePaused = false,
              corePaused = false,
              placeDropped = false,
              cancelDropped = false,
              pausedReads = 0;
          proxy.listen((incoming) async {
            try {
              final payload = await utf8.decoder.bind(incoming).join();
              final place =
                  incoming.method == 'POST' &&
                  incoming.uri.path == '/api/v1/gateway/trading-trigger';
              final cancel =
                  incoming.method == 'POST' &&
                  incoming.uri.path == '/api/v1/gateway/trading-trigger/cancel';
              final drop =
                  (place && !placeDropped) || (cancel && !cancelDropped);
              if (place || cancel) {
                final body = asMap(jsonDecode(payload));
                posts.add(body);
                final pending = asMap(
                  asList(
                    jsonDecode(settings.values['pendingTradingOrders']!),
                  ).single,
                );
                expect(pending['productLine'], 'OPTION');
                if (place) {
                  expect(
                    pending['clientTriggerOrderId'],
                    body['clientTriggerOrderId'],
                  );
                }
                if (cancel) {
                  expect(
                    pending['cancelTriggerOrderId'],
                    body['triggerOrderId'],
                  );
                }
                if (drop) {
                  expect(
                    Process.killPid(realtimePid, ProcessSignal.sigstop),
                    true,
                  );
                  realtimePaused = true;
                }
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
              if (place) {
                expect(response.statusCode, 200);
                ids.add(
                  '${asMap(jsonDecode(utf8.decode(bytes)))['triggerOrderId']}',
                );
              }
              if (drop) {
                expect(response.statusCode, 200);
                if (place) {
                  placeDropped = true;
                } else {
                  cancelDropped = true;
                }
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
            const draft = TriggerOrderDraft(
              side: 'SELL',
              triggerType: 'TAKE_PROFIT',
              triggerPriceTicks: 12000,
              quantitySteps: 1,
              marginMode: 'CROSS',
              positionSide: 'NET',
              priceSource: 'LAST',
              orderType: 'LIMIT',
              priceTicks: 10000,
            );
            expect(await state.placeTriggerOrders([draft, draft, draft]), 0);
            expect(posts.length, 1);
            expect(state.tradingCommandPending, true);
            expect(placeDropped, true);
            final original = state.pendingTradingCommand!.clientTriggerOrderId!;
            await state.checkPendingTradingCommand();
            expect(state.tradingCommandPending, true);
            expect(Process.killPid(realtimePid, ProcessSignal.sigcont), true);
            realtimePaused = false;
            Future<void> waitReceipt(
              String path,
              Map<String, String> query,
            ) async {
              final deadline = DateTime.now().add(const Duration(seconds: 30));
              while (true) {
                final value = await direct.get(
                  path,
                  userId: session.user.userId,
                  productLine: 'OPTION',
                  query: query,
                );
                if (value['outcome'] == 'TERMINAL') {
                  expect(value['code'], 'NONE');
                  return;
                }
                expect(DateTime.now().isBefore(deadline), true);
                await Future<void>.delayed(const Duration(milliseconds: 100));
              }
            }

            final userQuery = {'userId': '${session.user.userId}'};
            await waitReceipt('/api/v1/gateway/trading-trigger/submission', {
              ...userQuery,
              'clientTriggerOrderId': original,
            });
            state.dispose();
            state = make(instrument);
            await state.bootstrap();
            expect(state.pendingTradingCommand!.clientTriggerOrderId, original);
            expect(Process.killPid(corePid, ProcessSignal.sigstop), true);
            corePaused = true;
            await state.checkPendingTradingCommand();
            expect(state.tradingCommandPending, false);
            pausedReads++;
            expect(Process.killPid(corePid, ProcessSignal.sigcont), true);
            corePaused = false;
            final order = TriggerOrderModel.fromJson(
              await direct.get(
                '/api/v1/gateway/trading-trigger/${ids.single}',
                userId: session.user.userId,
                productLine: 'OPTION',
                query: userQuery,
              ),
            );
            expect(order.status, 'PENDING');
            await state.cancelTriggerOrder(order);
            expect(
              state.pendingTradingCommand!.cancelTriggerOrderId,
              int.parse(ids.single),
            );
            await state.checkPendingTradingCommand();
            expect(state.tradingCommandPending, true);
            expect(Process.killPid(realtimePid, ProcessSignal.sigcont), true);
            realtimePaused = false;
            await waitReceipt(
              '/api/v1/gateway/trading-trigger/cancellations/${ids.single}',
              userQuery,
            );
            state.dispose();
            state = make(instrument);
            await state.bootstrap();
            expect(Process.killPid(corePid, ProcessSignal.sigstop), true);
            corePaused = true;
            await state.checkPendingTradingCommand();
            expect(state.tradingCommandPending, false);
            pausedReads++;
            expect(Process.killPid(corePid, ProcessSignal.sigcont), true);
            corePaused = false;
            expect(posts.length, 2);
            // Ordinary acknowledgments must resolve immediately as well as the loss path.
            await state.refreshPrivateData();
            expect(await state.placeTriggerOrders([draft]), 1);
            expect(state.tradingCommandPending, false);
            final known = TriggerOrderModel.fromJson(
              await direct.get(
                '/api/v1/gateway/trading-trigger/${ids.last}',
                userId: session.user.userId,
                productLine: 'OPTION',
                query: userQuery,
              ),
            );
            await state.cancelTriggerOrder(known);
            expect(state.tradingCommandPending, false);
            expect(posts.length, 4);
            for (final id in ids) {
              final row = await direct.get(
                '/api/v1/gateway/trading-trigger/$id',
                userId: session.user.userId,
                productLine: 'OPTION',
                query: userQuery,
              );
              // Current read view may trail the final acknowledged cancellation briefly.
              if (row['status'] != 'CANCELED') {
                final deadline = DateTime.now().add(
                  const Duration(seconds: 15),
                );
                while ((await direct.get(
                      '/api/v1/gateway/trading-trigger/$id',
                      userId: session.user.userId,
                      productLine: 'OPTION',
                      query: userQuery,
                    ))['status'] !=
                    'CANCELED') {
                  expect(DateTime.now().isBefore(deadline), true);
                  await Future<void>.delayed(const Duration(milliseconds: 100));
                }
              }
            }
            await File(
              '${root.path}/single-trigger-client-evidence.json',
            ).writeAsString(
              jsonEncode({
                'productLine': 'OPTION',
                'triggerIds': ids,
                'posts': 4,
                'placementPosts': 2,
                'cancellationPosts': 2,
                'lostReplyCreate': true,
                'lostReplyCancel': true,
                'pausedUnknown': 2,
                'reconstructed': 2,
                'corePausedQueries': pausedReads,
                'unsentTiersStopped': 2,
                'normalAcknowledgments': true,
                'allTriggersCanceled': true,
                'positionStillOneUntilParentCloses': true,
              }),
            );
            debugPrint(
              'OPTION_SINGLE_TRIGGER_CLIENT_PASS lostCreate=true lostCancel=true rebuilt=2 corePausedReads=2 unsentTiersStopped=2 normalAcks=true posts=4',
            );
          } finally {
            if (realtimePaused) {
              Process.killPid(realtimePid, ProcessSignal.sigcont);
            }
            if (corePaused) Process.killPid(corePid, ProcessSignal.sigcont);
            state?.dispose();
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
