import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  final email = Platform.environment['LINEAR_DELIVERY_EXPIRY_EMAIL'];
  final id = Platform.environment['LINEAR_DELIVERY_EXPIRY_INSTRUMENT'];
  testWidgets(
    'LINEAR_DELIVERY FUSED ended contract and actual cash ledger remain queryable',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          expect(email, startsWith('qa-expiry-trader-'));
          expect(email, endsWith('@surprising.test'));
          final run = email!.split('@').first.split('-').last;
          final http = HttpClient();
          const config = AppConfig(
            gatewayBaseUrl: 'http://127.0.0.1:9094',
            websocketUrl: '',
          );
          final api = ApiClient(config, httpClient: http);
          AppState? state;
          try {
            final session = AuthSession.fromJson(
              await api.post('/api/v1/auth/login', {
                'identifier': email,
                'password': 'SixLine-QA-$run!',
              }),
            );
            api.setSession(session);
            final contract = await api.instrumentLatest(
              id!,
              ProductMode.linearDelivery,
            );
            expect(contract.status, 'CLOSED');
            expect(contract.canPlaceOrder(reduceOnly: true), false);
            state =
                AppState(
                    config: config,
                    apiClient: api,
                    seedInstruments: [contract],
                  )
                  ..mode = ProductMode.linearDelivery
                  ..session = session;
            await state.refreshInstruments();
            expect(state.selectedInstrument.instrumentId, id);
            expect(state.selectedInstrument.status, 'CLOSED');
            List<Position>? positions;
            for (var attempt = 0; attempt < 50; attempt++) {
              try {
                positions = await api.positions(
                  session.user.userId,
                  productLine: 'LINEAR_DELIVERY',
                );
                break;
              } on ApiException catch (error) {
                if (error.statusCode != 503) rethrow;
                await Future<void>.delayed(const Duration(milliseconds: 200));
              }
            }
            expect(
              positions,
              isNotNull,
              reason: 'realtime snapshot must become ready',
            );
            expect(positions, isEmpty);
            final page = await api.accountRecords(
              category: 'delivery-ledger',
              userId: session.user.userId,
              product: ProductMode.linearDelivery,
            );
            final row = page.rows.singleWhere(
              (r) => asString(r['instrumentId']) == id,
            );
            expect(row['amountUnits'], '200000000');
            for (final brightness in Brightness.values) {
              tester.view.physicalSize = const Size(320, 900);
              tester.view.devicePixelRatio = 1;
              await tester.pumpWidget(
                MaterialApp(
                  key: ValueKey(brightness),
                  theme: ThemeData(brightness: brightness),
                  home: FundingRecordsPage(
                    state: state,
                    initialCategory: 'delivery-ledger',
                  ),
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 500));
              await tester.pump();
              await tester.scrollUntilVisible(
                find.text('USDT 2'),
                150,
                scrollable: find
                    .descendant(
                      of: find.byType(ListView),
                      matching: find.byType(Scrollable),
                    )
                    .first,
              );
              expect(find.text('USDT 2'), findsOneWidget);
              expect(find.text(contract.symbol), findsOneWidget);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            }
            debugPrint(
              'LINEAR_DELIVERY_EXPIRY_CLIENT_PASS status=CLOSED selectionRetained=true cash=2USDT positions=0 widths=320 themes=dark,light',
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
            state?.dispose();
            http.close(force: true);
          }
        }, _RealHttp()),
      );
    },
    skip: email == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _RealHttp extends HttpOverrides {}
