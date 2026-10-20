import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  final path = Platform.environment['SPOT_HISTORY_LIVE_FIXTURE'];
  testWidgets(
    'SPOT real history entry, status and continuation retain original own orders',
    (tester) async {
      await tester.runAsync(
        () => HttpOverrides.runWithHttpOverrides(() async {
          expect(path, startsWith('/tmp/surprising-spot-fused-history-'));
          final fixture = asMap(jsonDecode(File(path!).readAsStringSync()));
          expect(fixture['productLine'], 'SPOT');
          final expected = asList(
            asMap(fixture['orderHistory'])['orderIds'],
          ).map(asString).toSet();
          final filled = asList(
            asMap(fixture['orderHistory'])['filledOrderIds'],
          ).map(asString).toSet();
          final session = AuthSession.fromJson(asMap(fixture['session']));
          final upstream = HttpClient(), client = HttpClient();
          final queries = <Map<String, String>>[], writes = <String>[];
          // Forward every byte from the real gateway; only reduce history's page size.
          final proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          final subscription = proxy.listen((request) async {
            try {
              if (request.method != 'GET') {
                writes.add(request.method);
                request.response.statusCode = 405;
                await request.response.close();
                return;
              }
              final query = {...request.uri.queryParameters};
              if (request.uri.path.endsWith('/trading/history')) {
                query['limit'] = '1';
                queries.add({...query});
              }
              final uri = Uri(
                scheme: 'http',
                host: '127.0.0.1',
                port: 9094,
                path: request.uri.path,
                queryParameters: query,
              );
              final forwarded = await upstream.getUrl(uri);
              for (final name in [
                'authorization',
                'x-user-id',
                'x-product-line',
              ]) {
                final value = request.headers.value(name);
                if (value != null) forwarded.headers.set(name, value);
              }
              final response = await forwarded.close();
              request.response.statusCode = response.statusCode;
              request.response.headers.contentType = ContentType.json;
              await request.response.addStream(response);
              await request.response.close();
            } catch (error) {
              request.response.statusCode = 502;
              await request.response.close();
            }
          });
          AppState? state;
          try {
            final config = AppConfig(
              gatewayBaseUrl: 'http://127.0.0.1:${proxy.port}',
              websocketUrl: '',
            );
            final api = ApiClient(config, httpClient: client)
              ..setSession(session);
            final instrument = await api.instrumentLatest(
              asString(fixture['instrumentId']),
              ProductMode.spot,
            );
            final rows = <Map<String, dynamic>>[];
            String? cursor;
            do {
              final page = await api.accountRecords(
                category: 'order',
                userId: session.user.userId,
                product: ProductMode.spot,
                instrumentId: instrument.instrumentId,
                cursor: cursor,
              );
              rows.addAll(page.rows);
              cursor = page.hasMore ? page.nextCursor : null;
              expect(rows.length, lessThan(100));
            } while (cursor != null);
            expect(rows.map((r) => asString(r['orderId'])).toSet(), expected);
            state =
                AppState(
                    config: config,
                    apiClient: api,
                    seedInstruments: [instrument],
                  )
                  ..mode = ProductMode.spot
                  ..session = session;
            Future<void> waitFor(Finder finder) async {
              for (var n = 0; n < 80 && finder.evaluate().isEmpty; n++) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await tester.pump(const Duration(milliseconds: 100));
              }
              expect(finder, findsWidgets);
            }

            Future<void> waitForRead() async {
              for (var n = 0; n < 80; n++) {
                await Future<void>.delayed(const Duration(milliseconds: 100));
                await tester.pump(const Duration(milliseconds: 100));
                if (find.byType(LinearProgressIndicator).evaluate().isEmpty) {
                  return;
                }
              }
              fail('bounded real history request did not finish');
            }

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
                find.byKey(const ValueKey('spot-history-order')),
              );
              await tester.pump();
              await waitFor(find.byType(FundingRecordsPage));
              await waitForRead();
              await waitFor(find.byType(Card));
              final scroll = find
                  .descendant(
                    of: find.byType(ListView),
                    matching: find.byType(Scrollable),
                  )
                  .first;
              final status = find.byKey(const ValueKey('history-status-'));
              await tester.scrollUntilVisible(status, 150, scrollable: scroll);
              await tester.tap(status);
              await tester.pumpAndSettle();
              await tester.tap(find.text('全部成交').last);
              await tester.pumpAndSettle();
              final apply = find.widgetWithText(FilledButton, '筛选 / 刷新');
              await tester.scrollUntilVisible(apply, 150, scrollable: scroll);
              await tester.tap(apply);
              await tester.pump();
              await waitForRead();
              await waitFor(find.text('订单号：${filled.first}'));
              for (var count = 1; count < filled.length; count++) {
                final more = find.widgetWithText(OutlinedButton, '加载更多');
                await tester.scrollUntilVisible(more, 200, scrollable: scroll);
                await tester.tap(more);
                await tester.pump();
                await waitForRead();
              }
              for (final id in filled.toList().reversed) {
                await tester.scrollUntilVisible(
                  find.text('订单号：$id'),
                  -200,
                  scrollable: scroll,
                  maxScrolls: 60,
                );
                expect(find.text('订单号：$id'), findsOneWidget);
              }
              expect(writes, isEmpty);
              expect(tester.takeException(), isNull);
            }
            File(
              '${File(path).parent.path}/order-history-client-evidence.json',
            ).writeAsStringSync(
              '${jsonEncode({
                'productLine': 'SPOT',
                'orders': rows.length,
                'filled': filled.length,
                'themes': ['dark', 'light'],
                'width': 320,
                'writes': writes,
                'historyGets': queries.length,
                'realApiAndWidgets': true,
              })}\n',
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            state?.dispose();
            await subscription.cancel();
            await proxy.close(force: true);
            client.close(force: true);
            upstream.close(force: true);
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
