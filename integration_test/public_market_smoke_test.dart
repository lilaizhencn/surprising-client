// Explicit, read-only live acceptance test. Run on a connected simulator/device.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'live markets and six product tabs on a device',
    (tester) async {
      final state = AppState();
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await state.refreshInstruments();
      expect(state.instruments, isNotEmpty);
      expect(state.lastError, isNull);
      await tester.pump();
      await tester.tap(find.text('合约').last);
      await tester.pumpAndSettle();

      for (final mode in ProductMode.values) {
        final tab = find.byKey(ValueKey('product-tab-${mode.name}'));
        await tester.ensureVisible(tab);
        await tester.tap(tab);
        // Real I/O, timers and subscription handshakes run between frames.
        for (var i = 0; i < 12; i++) {
          await tester.pump(const Duration(milliseconds: 500));
        }
        expect(state.mode, mode);
        expect(tester.widget<ChoiceChip>(tab).selected, isTrue);
        if (state.instruments.any((i) => i.mode == mode)) {
          expect(state.selectedInstrument.mode, mode);
          expect(state.orderBook.symbol, state.selectedSymbol);
          expect(state.orderBook.bids, isNotEmpty);
          expect(find.byType(OrderTicket), findsOneWidget);
        } else {
          expect(state.selectedSymbol, isEmpty);
          expect(state.orderBook.bids, isEmpty);
          expect(find.byType(OrderTicket), findsNothing);
        }
        expect(tester.takeException(), isNull);
      }

      for (final instrument
          in state.instruments
              .where((i) => i.mode == ProductMode.linear)
              .toList()) {
        await state.selectInstrument(instrument);
        await tester.pump(const Duration(seconds: 2));
        expect(state.orderBook.symbol, instrument.symbol);
        expect(state.orderBook.bids, isNotEmpty);
        expect(state.recentTrades, isNotEmpty);
        expect(state.lastError, isNull);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
