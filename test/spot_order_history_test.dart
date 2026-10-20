import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/account_records.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/models.dart';

const session = AuthSession(
  user: AuthUser(userId: 1, username: 'spot', email: '', status: 'ACTIVE'),
  accessToken: 'qa',
  refreshToken: 'qa',
);
Map<String, dynamic> order([String id = '9007199254740993']) => {
  'orderId': id,
  'userId': 1,
  'instrumentId': '868',
  'clientOrderId': 'original',
  'side': 'BUY',
  'orderType': 'LIMIT',
  'timeInForce': 'GTC',
  'status': 'CANCELED',
  'priceTicks': '12345',
  'quantitySteps': '25',
  'executedQuantitySteps': '10',
  'remainingQuantitySteps': '15',
  'cumulativeFeeUnits': '-1',
  'averagePriceTicks': '12344.5',
  'createdAt': '2026-10-20T00:00:00Z',
  'updatedAt': '2026-10-20T00:01:00Z',
};
Instrument instrument({String id = '868', String status = 'TRADING'}) =>
    Instrument.fromJson({
      'instrumentId': id,
      'symbol': 'BTC-USDT',
      'instrumentType': 'SPOT',
      'contractType': 'SPOT',
      'baseAsset': 'BTC',
      'quoteAsset': 'USDT',
      'settleAsset': 'USDT',
      'priceTickUnits': 5,
      'quantityStepUnits': 20,
      'baseScaleUnits': 1000000,
      'quoteScaleUnits': 1000,
      'status': status,
    });
Map<String, dynamic> page() => {
  'count': 1,
  'orders': [order()],
  'nextCursor': null,
  'hasMore': false,
  'sort': 'updatedAt.desc',
  'limit': 100,
};
void main() {
  test('fractional average ticks preserve all transmitted int64 digits', () {
    expect(
      formatExecutionPrice('9007199254740993.5', 5, '1000'),
      '45035996273704.9675',
    );
    expect(formatExecutionPrice('1e6', 5, '1000'), '—');
    expect(formatExecutionPrice('1.5', 5, '3'), '—');
  });
  testWidgets(
    'history loads ended instrument metadata by permanent identity when absent from the trading catalog',
    (tester) async {
      final api = _HistoryApi();
      final state =
          AppState(
              apiClient: api,
              seedInstruments: [instrument(id: '869')],
              config: const AppConfig(websocketUrl: ''),
            )
            ..mode = ProductMode.spot
            ..session = session;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FundingRecordsPage(state: state, initialCategory: 'order'),
        ),
      );
      await tester.pumpAndSettle();
      expect(api.metadataRequests, [('868', ProductMode.spot)]);
      await tester.scrollUntilVisible(
        find.text('成交均价：61.7225 USDT'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(find.text('成交均价：61.7225 USDT'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalid in ['user', 'instrument', 'cursor', 'count', 'quantity']) {
    test('order history rejects malformed $invalid page', () async {
      final body = page();
      if (invalid == 'user') {
        body['orders'] = [
          {...order(), 'userId': 2},
        ];
      }
      if (invalid == 'instrument') {
        body['orders'] = [
          {...order(), 'instrumentId': '869'},
        ];
      }
      if (invalid == 'cursor') body['hasMore'] = true;
      if (invalid == 'count') body['count'] = 2;
      if (invalid == 'quantity') {
        body['orders'] = [
          {...order(), 'executedQuantitySteps': '26'},
        ];
      }
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((r) async {
        r.response.headers.contentType = ContentType.json;
        r.response.write(jsonEncode(body));
        await r.response.close();
      });
      final http = HttpOverrides.runWithHttpOverrides(
        () => HttpClient(),
        _RealHttp(),
      );
      addTearDown(() async {
        http.close(force: true);
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: http,
      )..setSession(session);
      await expectLater(
        api.accountRecords(
          category: 'order',
          userId: 1,
          product: ProductMode.spot,
          instrumentId: '868',
        ),
        throwsFormatException,
      );
    });
  }
  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness order history shows executed, remaining, average and historical fees',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final state =
            AppState(
                apiClient: _HistoryApi(),
                seedInstruments: [instrument()],
                config: const AppConfig(websocketUrl: ''),
              )
              ..mode = ProductMode.spot
              ..session = session;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: FundingRecordsPage(state: state, initialCategory: 'order'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('成交均价：61.7225 USDT'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('已成交：0.0002 BTC'), findsOneWidget);
        expect(find.text('剩余：0.0003 BTC'), findsOneWidget);
        expect(find.text('累计手续费：-0.001 USDT'), findsOneWidget);
        expect(find.text('订单号：9007199254740993'), findsOneWidget);
        expect(find.text('买入 · 限价 · 已撤销'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'invalid date range and product change cannot retain another product history',
    (tester) async {
      final api = _HistoryApi();
      final state =
          AppState(
              apiClient: api,
              seedInstruments: [instrument()],
              config: const AppConfig(websocketUrl: ''),
            )
            ..mode = ProductMode.spot
            ..session = session;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FundingRecordsPage(state: state, initialCategory: 'order'),
        ),
      );
      await tester.pumpAndSettle();
      final scroll = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      Future<void> pickPreviousMonth(String label, String day) async {
        final button = find.widgetWithText(TextButton, label);
        await tester.scrollUntilVisible(button, 150, scrollable: scroll);
        await tester.tap(button);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Previous month'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(day).last);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }

      await pickPreviousMonth('结束日期', '2');
      await pickPreviousMonth('开始日期', '3');
      final product = find.byType(DropdownButtonFormField<ProductMode>);
      await tester.scrollUntilVisible(product, -150, scrollable: scroll);
      await tester.tap(product);
      await tester.pumpAndSettle();
      await tester.tap(find.text(ProductMode.linearDelivery.label).last);
      await tester.pumpAndSettle();
      await tester.drag(find.byType(ListView), const Offset(0, -1500));
      await tester.pumpAndSettle();
      expect(find.text('开始日期不能晚于结束日期'), findsOneWidget);
      expect(api.calls, hasLength(1));
      expect(find.text('订单号：9007199254740993'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'editing an instrument draft cannot combine a new filter with the previous page cursor',
    (tester) async {
      final api = _HistoryApi();
      final state =
          AppState(
              apiClient: api,
              seedInstruments: [instrument()],
              config: const AppConfig(websocketUrl: ''),
            )
            ..mode = ProductMode.spot
            ..session = session;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: FundingRecordsPage(
            state: state,
            initialCategory: 'order',
            initialInstrumentId: '868',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final filter = find.widgetWithText(TextField, '合约 ID（可留空）');
      await tester.enterText(filter, '869');
      await tester.pump();
      final more = find.widgetWithText(OutlinedButton, '加载更多');
      await tester.scrollUntilVisible(
        more,
        300,
        scrollable: find
            .descendant(
              of: find.byType(ListView),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(more);
      await tester.pumpAndSettle();
      expect(api.calls.last, ('868', 'next-page'));
      expect(find.text('订单号：9007199254740993'), findsOneWidget);
    },
  );
}

class _RealHttp extends HttpOverrides {}

class _HistoryApi extends ApiClient {
  _HistoryApi() : super(const AppConfig());
  final calls = <(String, String?)>[];
  final metadataRequests = <(String, ProductMode)>[];
  @override
  Future<Instrument> instrumentLatest(String id, ProductMode product) async {
    metadataRequests.add((id, product));
    return instrument(id: id, status: 'CLOSED');
  }

  @override
  Future<Map<String, String>> assetScales() async => {
    'BTC': '1000000',
    'USDT': '1000',
  };
  @override
  Future<AccountRecordPage> accountRecords({
    required String category,
    required int userId,
    required ProductMode product,
    String asset = '',
    String referenceType = '',
    String instrumentId = '',
    String status = '',
    DateTime? from,
    DateTime? to,
    String? cursor,
  }) async {
    calls.add((instrumentId, cursor));
    return AccountRecordPage(
      [order(cursor == null ? '9007199254740993' : '9007199254740994')],
      cursor == null ? 'next-page' : null,
      cursor == null,
    );
  }
}
