import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/exchange_widgets.dart';
import 'package:surprising_client/src/models.dart';

import 'transfer_page_test.dart' show MemorySettings;

void main() {
  testWidgets('market updates retain MaterialApp while page data updates', (
    tester,
  ) async {
    final state = MarketNotificationState();
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    final instrument = state.selectedInstrument;
    final initialPrice = state.latestPriceFor(instrument)!;

    for (var index = 0; index < 100; index++) {
      state.latestPrices['${state.mode.productLine}:${instrument.symbol}'] =
          initialPrice + index;
      state.publishMarketUpdate();
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)), same(app));
    expect(state.latestPriceFor(instrument), initialPrice + 99);
    expect(
      find.text(
        groupedMoney(initialPrice + 99, digits: instrument.pricePrecision),
      ),
      findsWidgets,
    );
    expect(find.byType(PublicMarketRow), findsWidgets);
    expect(tester.takeException(), isNull);

    state.selectTheme(ClientTheme.light);
    await tester.pumpAndSettle();
    final themedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(themedApp, isNot(same(app)));
    expect(themedApp.theme!.brightness, Brightness.light);

    state.selectTheme(ClientTheme.light);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)),
      same(themedApp),
    );

    state.selectLanguage(ClientLanguage.en);
    await tester.pumpAndSettle();
    final translatedApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(translatedApp.locale, const Locale('en', 'US'));
    expect(tester.takeException(), isNull);
  });
}

class MarketNotificationState extends AppState {
  MarketNotificationState()
    : super(offline: true, settingsStore: MemorySettings());

  void publishMarketUpdate() => notifyListeners();
}
