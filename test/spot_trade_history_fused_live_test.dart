import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/account_records.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  final path = Platform.environment['SPOT_FILLS_LIVE_FIXTURE'];
  testWidgets(
    'SPOT real committed private fills and 320px record pages remain readable',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          expect(path, startsWith('/tmp/surprising-spot-fused-fills-'));
          final fixture = asMap(jsonDecode(File(path!).readAsStringSync()));
          expect(fixture['productLine'], 'SPOT');
          final expected = asList(
            asMap(fixture['userFills'])['tradeIds'],
          ).map(asString).toSet();
          final session = AuthSession.fromJson(asMap(fixture['session']));
          final http = HttpClient();
          const config = AppConfig(
            gatewayBaseUrl: 'http://127.0.0.1:9094',
            websocketUrl: '',
          );
          final api = ApiClient(config, httpClient: http)..setSession(session);
          AppState? state;
          try {
            final instrument = await api.instrumentLatest(
              asString(fixture['instrumentId']),
              ProductMode.spot,
            );
            final corePid = int.parse(
              Platform.environment['SPOT_FILLS_CORE_PID']!,
            );
            final command = Process.runSync('ps', [
              '-p',
              '$corePid',
              '-o',
              'command=',
            ]).stdout.toString();
            expect(
              command,
              contains(
                '-Dsurprising.launcher.identity=${fixture['runId']}/core-node0',
              ),
            );
            late final AccountRecordPage page;
            Process.killPid(corePid, ProcessSignal.sigstop);
            try {
              page = await api.accountRecords(
                category: 'trade',
                userId: session.user.userId,
                product: ProductMode.spot,
                instrumentId: instrument.instrumentId,
              );
            } finally {
              Process.killPid(corePid, ProcessSignal.sigcont);
            }
            expect(
              page.rows.map((row) => asString(row['tradeId'])).toSet(),
              expected,
            );
            expect(
              page.rows.every((row) => row['liquidityRole'] == 'TAKER'),
              isTrue,
            );
            expect(
              page.rows.every(
                (row) =>
                    row['takerUserId'] == null && row['makerUserId'] == null,
              ),
              isTrue,
            );
            state = AppState(
              initialSession: session,
              config: config,
              apiClient: api,
              seedInstruments: [instrument],
            )..mode = ProductMode.spot;
            for (final brightness in Brightness.values) {
              tester.view.physicalSize = const Size(320, 900);
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                MaterialApp(
                  key: ValueKey(brightness),
                  theme: ThemeData(brightness: brightness),
                  home: Scaffold(
                    body: SingleChildScrollView(
                      child: PrivateTradingPanel(state: state),
                    ),
                  ),
                ),
              );
              await tester.tap(
                find.byKey(const ValueKey('spot-history-trade')),
              );
              await tester.pump();
              for (
                var attempt = 0;
                attempt < 60 && find.text('买入 · Taker').evaluate().isEmpty;
                attempt++
              ) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(find.byType(FundingRecordsPage), findsOneWidget);
              await tester.scrollUntilVisible(
                find.text('买入 · Taker').first,
                200,
                scrollable: find
                    .descendant(
                      of: find.byType(ListView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
              expect(find.text('买入 · Taker'), findsWidgets);
              expect(
                find.text('订单号：${page.rows.first['orderId']}'),
                findsOneWidget,
              );
              expect(tester.takeException(), isNull);
            }
            File(
              '${File(path).parent.path}/own-fills-client-evidence.json',
            ).writeAsStringSync(
              '${jsonEncode({
                'productLine': 'SPOT',
                'fills': page.rows.length,
                'tradeIds': expected.toList(),
                'themes': ['dark', 'light'],
                'width': 320,
                'writes': 0,
                'realApiAndWidgets': true,
              })}\n',
            );
            await tester.pumpWidget(const SizedBox.shrink());
          } finally {
            state?.dispose();
            http.close(force: true);
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          }
        }, _RealHttp()),
      );
    },
    skip: path == null,
  );
}

class _RealHttp extends HttpOverrides {}
