import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  final sessionPath = Platform.environment['OPTION_REFERENCE_FEE_SESSION'];
  testWidgets(
    'OPTION public fee revision enables exact premium in the real ticket',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          expect(sessionPath, startsWith('/tmp/surprising-option-fused-'));
          final session = AuthSession.fromJson(
            asMap(jsonDecode(await File(sessionPath!).readAsString())),
          );
          final http = HttpClient();
          final api = ApiClient(
            const AppConfig(
              gatewayBaseUrl: 'http://127.0.0.1:9094',
              websocketUrl: '',
            ),
            httpClient: http,
          )..setSession(session);
          AppState? state;
          try {
            final instrument = await api.instrumentLatest(
              '868',
              ProductMode.option,
            );
            expect(instrument.optionType, 'PUT');
            expect(instrument.status, 'TRADING');
            state = AppState(
              initialSession: session,
              apiClient: api,
              seedInstruments: [instrument],
            )..mode = ProductMode.option;
            await state.refreshOrderTerms();
            expect(
              state.optionOrderTerms,
              isNotNull,
              reason: 'public fee revision must survive gateway sanitization',
            );
            expect(state.optionOrderTerms!.takerFeeRatePpm, 500);
            tester.view.physicalSize = const Size(320, 1200);
            tester.view.devicePixelRatio = 1;
            for (final brightness in Brightness.values) {
              await tester.pumpWidget(
                AppScope(
                  notifier: state,
                  child: MaterialApp(
                    key: ValueKey(brightness),
                    theme: ThemeData(brightness: brightness),
                    home: const Scaffold(body: TradePage()),
                  ),
                ),
              );
              await tester.pump();
              final price = find
                  .descendant(
                    of: find.byWidgetPredicate(
                      (w) => w is TradeNumericField && w.label.startsWith('价格'),
                    ),
                    matching: find.byType(TextField),
                  )
                  .first;
              final quantity = find
                  .descendant(
                    of: find.byWidgetPredicate(
                      (w) => w is TradeNumericField && w.label == '数量',
                    ),
                    matching: find.byType(TextField),
                  )
                  .first;
              await tester.ensureVisible(price);
              await tester.enterText(price, '500');
              await tester.ensureVisible(quantity);
              await tester.enterText(quantity, '2');
              await tester.pump();
              expect(find.text('买入权利金及手续费 1.0005 USDT'), findsOneWidget);
              expect(tester.takeException(), isNull);
              await tester.pumpWidget(const SizedBox.shrink());
            }
            debugPrint(
              'OPTION_FEE_CLIENT_PASS publicRevision=true premiumAndFee=1.0005_USDT width=320 themes=dark,light writes=0',
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
    skip: sessionPath == null,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

class _RealHttp extends HttpOverrides {}
