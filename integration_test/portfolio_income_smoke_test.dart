import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/portfolio_income.dart';

/// Uses an actual gateway and an explicitly provisioned isolated QA account.
/// The JSON session comes from a mode-0600 --dart-define-from-file, never a log.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native portfolio consumes authenticated gateway estimates', (
    tester,
  ) async {
    const sessionJson = String.fromEnvironment('PORTFOLIO_QA_SESSION_JSON');
    if (sessionJson.isEmpty) {
      throw StateError('An isolated QA session is required');
    }
    final session = AuthSession.fromJson(
      jsonDecode(sessionJson) as Map<String, dynamic>,
    );
    const config = AppConfig(websocketUrl: '');
    final api = ApiClient(config)..setSession(session);
    final state = AppState(config: config, apiClient: api)..session = session;
    Future<void> capture(String name) async {
      final ack = File('${Directory.systemTemp.path}/native-capture-$name.ack');
      if (await ack.exists()) await ack.delete();
      debugPrint('NATIVE_CAPTURE_READY:$name:${ack.path}');
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (!await ack.exists()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Host capture timed out');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await ack.delete();
    }

    try {
      debugPrint('PORTFOLIO_QA_GATEWAY:${config.gatewayBaseUrl}');
      final wire = await api.get(
        '/api/v1/portfolio/income',
        userId: session.user.userId,
      );
      expect(
        PortfolioIncomeSummary.fromJson(wire).groups['overview']?.amount,
        '-2',
      );
      await state.refreshPortfolioIncome();
      final income = state.portfolioIncome();
      expect(income?.amount, '-2');
      expect(income?.currentEquity, '118');
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      for (final theme in [ClientTheme.dark, ClientTheme.light]) {
        state.clientTheme = theme;
        state.notifyListeners();
        await tester.pumpAndSettle();
        expect(find.text('交易所'), findsOneWidget);
        expect(find.text('118.00'), findsOneWidget);
        expect(find.textContaining('-2.00'), findsOneWidget);
        await capture('income-home-${theme.name}');
      }
      state.clientTheme = ClientTheme.dark;
      state.notifyListeners();
      await tester.tap(find.text('资产').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('今日收益 -2.00'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('asset-account-trading')));
      await tester.pumpAndSettle();
      expect(find.textContaining('今日收益 0.00'), findsOneWidget);
      await capture('income-assets-filter');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    }
  });
}
