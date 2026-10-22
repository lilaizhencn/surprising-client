// 显式本机验收：真实 HTTP 鉴权、Core 记账与 realtime；固定验证码和合成 KYC 由独立 QA 环境提供。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart' show AppScope;
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/c2c_trading_page.dart';
import 'package:surprising_client/src/models.dart';

class _LiveBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

late Zone _networkZone;

class _ObservedApi extends ApiClient {
  _ObservedApi()
    : super(
        const AppConfig(
          gatewayBaseUrl: 'http://127.0.0.1:9094',
          websocketUrl: 'ws://127.0.0.1:9094/ws/v1',
        ),
        httpClient: _networkZone.run(() => HttpClient()),
      );
  bool loseOrderResponse = false;
  int orderPosts = 0;
  String? createdOrder;
  Map<String, dynamic>? cancelResponse, latestBond;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    final value = await _networkZone.run(
      () => super.get(
        path,
        query: query,
        headers: headers,
        userId: userId,
        productLine: productLine,
        unwrapResponseResult: unwrapResponseResult,
      ),
    );
    if (path.endsWith('/me/merchant-bond')) latestBond = value;
    return value;
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    final result = await _networkZone.run(
      () => super.post(
        path,
        body,
        headers: headers,
        userId: userId,
        productLine: productLine,
        unwrapResponseResult: unwrapResponseResult,
      ),
    );
    if (path.endsWith('/cancel')) cancelResponse = result;
    if (path == '/api/v1/c2c/orders') {
      orderPosts++;
      createdOrder = asString(result['resultId']);
      if (loseOrderResponse) {
        loseOrderResponse = false;
        throw ApiException(504, '模拟已提交响应丢失，请查询原请求');
      }
    }
    return result;
  }
}

void main() {
  _networkZone = Zone.current;
  final root = Platform.environment['C2C_LIVE_QA_ROOT'];
  if (root == null) {
    test(
      'local real C2C business scenarios require an owned runtime',
      () {},
      skip: 'Set C2C_LIVE_QA_ROOT for explicit local integration',
    );
    return;
  }
  _LiveBinding();
  if (!RegExp(
    r'^/(private/)?tmp/surprising-c2c-\d{8}_\d{6}/live$',
  ).hasMatch(root)) {
    throw StateError('Only the dedicated local QA runtime is allowed');
  }
  final owner = asMap(
    jsonDecode(File('$root/../owner.json').readAsStringSync()),
  );
  if (owner['purpose'] !=
      'C2C authenticated HTTP, settlement lifecycle, security and admin integration') {
    throw StateError('QA owner mismatch');
  }
  final fixture = asMap(
    jsonDecode(File('$root/private-fixture.json').readAsStringSync()),
  );
  final evidence = <String, dynamic>{
    'scope':
        'Flutter real HTTP/Core widgets at 320 and 390; synthetic KYC/OTP; injected lost response only',
    'steps': <String>[],
    'passed': false,
  };
  void save() => File(
    '$root/mobile-business-evidence.json',
  ).writeAsStringSync(jsonEncode(evidence));
  Future<void> until(
    WidgetTester tester,
    bool Function() ready,
    String label,
  ) async {
    for (var i = 0; i < 160; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 70)),
      );
      if (ready()) return;
    }
    throw StateError(
      'Timed out: $label; visible=${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(80).join(" | ")}',
    );
  }

  Future<void> tap(WidgetTester tester, String text) async {
    debugPrint('UI action: $text');
    final finder = find.text(text).first;
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).last,
      );
    }
    await tester.ensureVisible(finder);
    await until(tester, () {
      final buttons = find
          .ancestor(
            of: finder,
            matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
          )
          .evaluate();
      return buttons.isNotEmpty &&
          (buttons.first.widget as ButtonStyleButton).onPressed != null;
    }, 'enabled button $text');
    await tester.tap(finder);
    await tester.pump();
  }

  Future<AppState> mount(
    WidgetTester tester,
    String role,
    double width,
    _ObservedApi api,
  ) async {
    FlutterSecureStorage.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = AuthSession.fromJson(asMap(asMap(fixture['users'])[role]));
    api.setSession(session);
    final state = AppState(
      initialSession: session,
      apiClient: api,
      offline: true,
    );
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: const Scaffold(body: C2cTradingPage()),
        ),
      ),
    );
    await until(
      tester,
      () => find.text('自选交易').evaluate().isNotEmpty,
      'initial real catalog',
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    });
    return state;
  }

  testWidgets(
    '320px buyer recovers the original committed order without a second POST and cancels safely',
    (tester) async {
      final api = _ObservedApi()..loseOrderResponse = true;
      await mount(tester, 'buyer', 320, api);
      await until(
        tester,
        () => find.text('购买').evaluate().isNotEmpty,
        'real sell offers',
      );
      await tap(tester, '购买');
      final input = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.labelText == '交易数量',
      );
      await until(tester, () => input.evaluate().isNotEmpty, 'quantity form');
      await tester.ensureVisible(input);
      await tester.enterText(input, '0.5');
      await tap(tester, '获取报价');
      await until(
        tester,
        () => find.text('确认下单').evaluate().isNotEmpty,
        'exact quote',
      );
      await tap(tester, '确认下单');
      await tap(tester, '确认');
      await until(
        tester,
        () =>
            find.text('查询原请求').evaluate().isNotEmpty &&
            api.createdOrder != null,
        'lost response recovery',
      );
      await tap(tester, '查询原请求');
      await until(
        tester,
        () => find.text('取消未付款订单').evaluate().isNotEmpty,
        'original order',
      );
      expect(api.orderPosts, 1);
      expect(api.createdOrder, isNotEmpty);
      await tap(tester, '取消未付款订单');
      await tap(tester, '确认');
      await until(
        tester,
        () => find.text('已取消').evaluate().isNotEmpty,
        'canceled original order',
      );
      final result = api.cancelResponse;
      expect(result!['status'], 'CANCELED');
      expect(result['buyerFeeUnits'], '50000');
      expect(result['buyerReceivesUnits'], '49950000');
      expect(tester.takeException(), isNull);
      evidence['mobileOrderId'] = api.createdOrder;
      evidence['orderPostCount'] = api.orderPosts;
      (evidence['steps'] as List<String>).add(
        '320px native buyer recovers real committed 0.5 USDT order, exact fee/net, no second POST, cancels it',
      );
      save();
    },
  );
  testWidgets(
    '390px merchant deposits and receives exactly the original bond back after exit',
    (tester) async {
      final api = _ObservedApi();
      final session = AuthSession.fromJson(
        asMap(asMap(fixture['users'])['other']),
      );
      api.setSession(session);
      await tester.runAsync(() async {
        Future<Map<String, dynamic>> direct(
          String path, [
          Map<String, dynamic>? body,
        ]) async {
          final client = HttpClient();
          try {
            final request = await client.openUrl(
              body == null ? 'GET' : 'POST',
              Uri.parse('http://127.0.0.1:9094/api/v1/c2c$path'),
            );
            request.headers.set(
              'Authorization',
              'Bearer ${session.accessToken}',
            );
            if (body != null) {
              request.headers.contentType = ContentType.json;
              request.write(jsonEncode(body));
            }
            final response = await request.close();
            final value = asMap(
              jsonDecode(await utf8.decoder.bind(response).join()),
            );
            expect(response.statusCode, 200);
            return value;
          } finally {
            client.close(force: true);
          }
        }

        final me = await direct('/me');
        final merchant = asMap(me['merchant']);
        if (merchant.isEmpty ||
            ['WITHDRAWN', 'REJECTED'].contains(merchant['status'])) {
          await direct('/me/merchant-application', {
            'revision': merchant['revision'] ?? '0',
            'application':
                'Local native merchant application and original bond refund validation',
          });
        }
      });
      await mount(tester, 'other', 390, api);
      await tap(tester, '商家中心');
      await tap(tester, '获取安全验证码');
      final input = find
          .byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == '邮箱验证码',
          )
          .first;
      await tester.ensureVisible(input);
      await tester.enterText(input, '123456');
      await tap(tester, '确认质押');
      await until(
        tester,
        () => find.text('退出商家并退押').evaluate().isNotEmpty,
        'real merchant bond confirmation',
      );
      final locked = api.latestBond;
      expect(asMap(locked!['bond'])['amount'], '100');
      expect(asMap(locked['bond'])['status'], 'LOCKED');
      await tap(tester, '退出商家并退押');
      await tap(tester, '确认');
      await until(
        tester,
        () => find.textContaining('RETURNED').evaluate().isNotEmpty,
        'original bond returned',
      );
      final returned = api.latestBond;
      expect(asMap(returned!['bond'])['status'], 'RETURNED');
      expect(
        asMap(returned['bond'])['bondId'],
        asMap(locked['bond'])['bondId'],
      );
      expect(tester.takeException(), isNull);
      (evidence['steps'] as List<String>).add(
        '390px native merchant submits real 100 USDT bond, waits for Core confirmation, exits and receives the same bond back',
      );
      evidence['passed'] = (evidence['steps'] as List<String>).length == 2;
      save();
    },
  );
}
