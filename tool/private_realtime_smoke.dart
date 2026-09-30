// Read-only authenticated check. Credentials are read from hidden terminal input.
import 'dart:io';

import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

Future<void> main() async {
  final previousEcho = stdin.echoMode;
  stdin.echoMode = false;
  stdout.writeln('Enter account and password on separate lines (hidden):');
  final identifier = stdin.readLineSync() ?? '';
  final password = stdin.readLineSync() ?? '';
  stdin.echoMode = previousEcho;
  final http = HttpClient();
  final api = ApiClient(const AppConfig(), httpClient: http);
  final ws = RealtimeClient(const AppConfig());
  final views = <ProductMode, PrivateView>{};
  final snapshots = <ProductMode, int>{};
  final pushes = <String, int>{};
  final acknowledgments = <String>{};
  var authenticated = false;
  var errorCount = 0;
  try {
    final session = await api.login(username: identifier, password: password);
    api.setSession(session);
    final catalog = await api.instruments();
    final activeProducts = catalog.map((i) => i.mode).toSet();
    stdout.writeln('LOGIN succeeded; status=${session.user.status}');
    Future<void> connect() async {
      views.clear();
      snapshots.clear();
      pushes.clear();
      acknowledgments.clear();
      authenticated = false;
      await ws.connect(
        userId: session.user.userId,
        accessToken: session.accessToken,
        onEvent: (message) {
          final op = message['op'];
          if (op == 'authenticated') {
            authenticated = asInt(message['userId']) == session.user.userId;
          }
          if (op == 'error') {
            errorCount++;
            return;
          }
          if (op == 'subscribed') {
            acknowledgments.add(
              '${message['productLine']}:${message['channel']}',
            );
          }
          final product = ProductMode.values
              .where((p) => p.productLine == message['productLine'])
              .firstOrNull;
          if (product == null ||
              asInt(message['userId']) != session.user.userId) {
            return;
          }
          final normalized = asMap(
            api.normalizeInstruments(message, product.productLine),
          );
          if (op == 'snapshot') {
            snapshots[product] = (snapshots[product] ?? 0) + 1;
          }
          if (op == 'event') {
            final key = '${product.productLine}:${message['channel']}';
            pushes[key] = (pushes[key] ?? 0) + 1;
          }
          views.putIfAbsent(product, PrivateView.new).apply(normalized);
        },
        onError: (_) {
          errorCount++;
        },
      );
      ws.replaceSubscriptions([
        for (final p in ProductMode.values)
          for (final channel in [
            'accountState',
            'orders',
            'triggerOrders',
            'positions',
            'positionRisk',
            'executionReports',
          ])
            {'productLine': p.productLine, 'channel': channel},
      ]);
    }

    Future<void> check(String phase) async {
      await Future<void>.delayed(const Duration(seconds: 16));
      stdout.writeln(
        '$phase authenticated=$authenticated acknowledged=${acknowledgments.length}/36 errors=$errorCount',
      );
      for (final product in ProductMode.values) {
        final view = views[product];
        stdout.writeln(
          '${product.productLine} status=${view?.status} fresh=${view?.ready} snapshots=${snapshots[product] ?? 0} positions=${view?.rows('position').length} orders=${view?.rows('order').length} triggers=${view?.rows('trigger').length} risks=${view?.rows('risk').length}',
        );
      }
      stdout.writeln('Push counts: $pushes');
      if (!authenticated ||
          errorCount != 0 ||
          acknowledgments.length != 36 ||
          ProductMode.values.any((p) => (snapshots[p] ?? 0) < 2) ||
          activeProducts.any((p) => !(views[p]?.ready ?? false))) {
        throw StateError(
          'Private authentication/subscriptions/periodic snapshots incomplete',
        );
      }
    }

    await connect();
    await check('INITIAL');
    // Each REST read is explicitly scoped to the corresponding product.
    for (final product in ProductMode.values) {
      try {
        final positions = await api.positions(
          session.user.userId,
          productLine: product.productLine,
        );
        final orders = await api.openOrders(
          session.user.userId,
          productLine: product.productLine,
        );
        final triggers = await api.openTriggerOrders(
          session.user.userId,
          productLine: product.productLine,
        );
        stdout.writeln(
          'REST ${product.productLine} positions=${positions.length} orders=${orders.orders.length} more=${orders.hasMore} triggers=${triggers.length}',
        );
      } on ApiException catch (e) {
        stdout.writeln('REST ${product.productLine} HTTP ${e.statusCode}');
      }
    }
    await ws.close();
    await connect();
    await check('RECONNECT');
    final unavailable = ProductMode.values.where(
      (p) => !(views[p]?.ready ?? false),
    );
    stdout.writeln(
      'Not READY (not accepted as empty): ${unavailable.map((p) => p.productLine).join(',')}',
    );
    stdout.writeln(
      'PASS for active products: private authentication, all product subscriptions, periodic snapshots and reconnect. No orders, cancellations or account changes were submitted.',
    );
  } on LoginChallenge catch (challenge) {
    stdout.writeln(
      'LOGIN_CHALLENGE ${challenge.methods.map((m) => m['type']).join(',')}',
    );
    exitCode = 2;
  } on ApiException catch (error) {
    stdout.writeln('API_FAILED HTTP ${error.statusCode}');
    exitCode = 1;
  } catch (_) {
    stdout.writeln(
      'FAILED: check summary above; sensitive server payloads suppressed.',
    );
    exitCode = 1;
  } finally {
    await ws.close();
    http.close(force: true);
  }
}
