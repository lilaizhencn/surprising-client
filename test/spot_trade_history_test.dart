import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/account_records.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/models.dart';

final _fill = <String, dynamic>{
  'tradeId': 'SPOT:100:1:9007199254740993:0',
  'productLine': 'SPOT',
  'instrumentId': '868',
  'orderId': '9007199254740993',
  'side': 'SELL',
  'positionSide': 'NET',
  'liquidityRole': 'MAKER',
  'priceTicks': '12345',
  'quantitySteps': '25',
  'feeRatePpm': '-100',
  'eventTime': '2026-10-20T00:00:00Z',
};
Map<String, dynamic> _page() => {
  'userId': 1,
  'productLine': 'SPOT',
  'count': 1,
  'trades': [_fill],
  'hasMore': false,
  'nextCursor': null,
  'sort': 'eventTime.desc',
  'limit': 100,
};
Instrument _instrument() => Instrument.fromJson({
  'instrumentId': '868',
  'symbol': 'BTC-USDT',
  'instrumentType': 'SPOT',
  'contractType': 'SPOT',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'priceTickUnits': 5,
  'quantityStepUnits': 20,
  'baseScaleUnits': 1000000,
  'quoteScaleUnits': 1000,
  'status': 'TRADING',
});
const _session = AuthSession(
  user: AuthUser(userId: 1, username: 'spot', email: '', status: 'ACTIVE'),
  accessToken: 'qa',
  refreshToken: 'qa',
);

void main() {
  test(
    'private fills use the authenticated realtime route, date bounds and original cursor',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <HttpRequest>[];
      server.listen((request) async {
        seen.add(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_page()));
        await request.response.close();
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
      )..setSession(_session);
      final from = DateTime.utc(2026, 10, 19), to = DateTime.utc(2026, 10, 20);
      final result = await api.accountRecords(
        category: 'trade',
        userId: 1,
        product: ProductMode.spot,
        instrumentId: '868',
        from: from,
        to: to,
        cursor: 'original+cursor',
      );
      expect(seen.single.method, 'GET');
      expect(seen.single.uri.path, '/api/v1/gateway/trading/trades');
      expect(seen.single.headers.value('X-Product-Line'), 'SPOT');
      expect(seen.single.headers.value('Authorization'), 'Bearer qa');
      expect(
        seen.single.uri.queryParameters,
        containsPair('startTime', '${from.millisecondsSinceEpoch}'),
      );
      expect(
        seen.single.uri.queryParameters,
        containsPair('endTime', '${to.millisecondsSinceEpoch}'),
      );
      expect(
        seen.single.uri.queryParameters,
        containsPair('cursor', 'original+cursor'),
      );
      expect(result.rows.single['orderId'], '9007199254740993');
      expect(result.rows.single['feeRatePpm'], '-100');
    },
  );

  for (final mismatch in ['user', 'product', 'cursor', 'side']) {
    test(
      'private fills reject a $mismatch mismatch rather than showing a successful empty page',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final body = _page();
        if (mismatch == 'user') body['userId'] = 2;
        if (mismatch == 'product') body['productLine'] = 'OPTION';
        if (mismatch == 'cursor') body['hasMore'] = true;
        if (mismatch == 'side') {
          body['trades'] = [
            {..._fill, 'side': 'UNKNOWN'},
          ];
        }
        server.listen((request) async {
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode(body));
          await request.response.close();
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
        )..setSession(_session);
        await expectLater(
          api.accountRecords(
            category: 'trade',
            userId: 1,
            product: ProductMode.spot,
          ),
          throwsFormatException,
        );
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets(
      '320px $brightness private fills show actual asset scales and own execution identity',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _RecordsApi();
        final state =
            AppState(
                apiClient: api,
                seedInstruments: [_instrument()],
                config: const AppConfig(websocketUrl: ''),
              )
              ..mode = ProductMode.spot
              ..session = _session;
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: FundingRecordsPage(state: state, initialCategory: 'trade'),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('成交价：61.725 USDT'),
          200,
          scrollable: find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        expect(find.text('成交价：61.725 USDT'), findsOneWidget);
        expect(find.text('成交数量：0.0005 BTC'), findsOneWidget);
        expect(find.text('卖出 · Maker'), findsOneWidget);
        expect(find.text('成交费率：-0.01%'), findsOneWidget);
        expect(find.text('订单号：9007199254740993'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _RealHttp extends HttpOverrides {}

class _RecordsApi extends ApiClient {
  _RecordsApi() : super(const AppConfig());
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
  }) async => AccountRecordPage(
    [
      {..._fill},
    ],
    null,
    false,
  );
}
