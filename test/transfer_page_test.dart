import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';
import 'package:surprising_client/src/session_store.dart';
import 'account_display_test.dart' show session;

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 392.0]) {
      for (final textScale in [1.0, 1.5]) {
        testWidgets(
          'six-decimal maximum and keypad submit exact units at $width $brightness scale $textScale',
          (tester) async {
            tester.view.physicalSize = Size(width, 900);
            tester.view.devicePixelRatio = 1;
            tester.platformDispatcher.textScaleFactorTestValue = textScale;
            addTearDown(
              tester.platformDispatcher.clearTextScaleFactorTestValue,
            );
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final api = TransferApi();
            final state = AppState(
              initialSession: session,
              offline: true,
              apiClient: api,
              settingsStore: MemorySettings(),
            );
            addTearDown(state.dispose);
            state.valuedProducts.add(ProductMode.spot);
            state.privateViews[ProductMode.spot] = PrivateView()
              ..status = 'READY'
              ..receivedAt = DateTime.now();
            state.productBalances[ProductMode.spot] = [
              const ProductBalance(
                scaleUnits: 1000000,
                accountType: 'SPOT',
                asset: 'USDT',
                availableUnits: 12345678,
                lockedUnits: 0,
                equityUnits: 12345678,
              ),
            ];
            await tester.pumpWidget(
              AppScope(
                notifier: state,
                child: MaterialApp(
                  theme: ThemeData(brightness: brightness),
                  home: const TransferPage(),
                ),
              ),
            );
            await tester.pumpAndSettle();
            expect(find.text('12.345678 USDT'), findsOneWidget);
            final from = tester.getRect(
              find.byKey(const ValueKey('transfer-account-从')),
            );
            final to = tester.getRect(
              find.byKey(const ValueKey('transfer-account-到')),
            );
            final swap = tester.getRect(
              find.byKey(const ValueKey('transfer-swap')),
            );
            expect(from.top, to.top);
            expect(from.height, to.height);
            expect(swap.width, greaterThanOrEqualTo(44));
            expect(swap.height, greaterThanOrEqualTo(44));
            expect(swap.center.dy, from.center.dy);

            await tester.tap(find.text('最大'));
            await tester.pumpAndSettle();
            final input = tester.widget<TextField>(
              find.byKey(const ValueKey('transfer-amount')),
            );
            expect(input.controller!.text, '12.345678');
            expect(input.readOnly, isTrue);
            await tester.tap(find.byIcon(Icons.backspace_outlined));
            await tester.tap(find.widgetWithText(TextButton, '9'));
            await tester.pumpAndSettle();
            expect(input.controller!.text, '12.345679');
            expect(
              tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, '确认转出'),
                  )
                  .onPressed,
              isNull,
            );
            await tester.tap(find.byIcon(Icons.backspace_outlined));
            await tester.tap(find.widgetWithText(TextButton, '8'));
            await tester.pumpAndSettle();
            await tester.tap(find.widgetWithText(FilledButton, '确认转出'));
            await tester.pumpAndSettle();
            expect(api.units, 12345678);
            expect(api.source, 'FUNDING');
            expect(api.target, 'USDT_PERPETUAL');
            expect(state.lastNotice, contains('已完成'));
            api.status = 'PENDING';
            await state.transfer(
              sourceAccountType: 'FUNDING',
              targetAccountType: 'USDT_PERPETUAL',
              asset: 'USDT',
              amount: 1,
            );
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<IconButton>(
                    find.byKey(const ValueKey('transfer-swap')),
                  )
                  .onPressed,
              isNull,
            );
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

class TransferApi extends ApiClient {
  TransferApi() : super(const AppConfig());
  String status = 'COMPLETED';
  int? units;
  String? source, target;
  @override
  Future<Map<String, String>> assetScales() async => {'USDT': '1000000'};
  @override
  Future<Map<String, dynamic>> transfer({
    required int userId,
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required int amountUnits,
    required String idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) async {
    units = amountUnits;
    source = sourceAccountType;
    target = targetAccountType;
    return {'status': status, 'transferId': 'synthetic'};
  }
}

class MemorySettings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> next) async {
    values = {...next};
  }
}
