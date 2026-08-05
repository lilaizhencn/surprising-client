import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

void main() {
  test(
    'wallet withdrawal uses the production contract and security headers',
    () async {
      final http = _RecordingHttpClient(
        '{"withdrawalId":"withdrawal-1","status":"PENDING"}',
      );
      final api = ApiClient(
        const AppConfig(gatewayBaseUrl: 'https://gateway.example.com'),
        httpClient: http,
      )..setAccessToken('access-token');

      final result = await api.walletWithdraw(
        7,
        chain: 'ETH',
        symbol: 'USDT',
        toAddress: '0x1111111111111111111111111111111111111111',
        amount: '1.25',
        idempotencyKey: 'app-withdraw-7-stable-key',
        emailCode: '123456',
        totpCode: '654321',
      );

      expect(http.uri.path, '/api/v1/wallet/withdrawals');
      expect(
        http.request.headers.value('authorization'),
        'Bearer access-token',
      );
      expect(
        http.request.headers.value('idempotency-key'),
        'app-withdraw-7-stable-key',
      );
      expect(http.request.headers.value('x-security-email-code'), '123456');
      expect(http.request.headers.value('x-security-totp-code'), '654321');
      final capturedBody = asMap(jsonDecode(http.request.body.toString()));
      expect(capturedBody['assetSymbol'], 'USDT');
      expect(capturedBody['externalReference'], contains('app-withdraw-7'));
      expect(result['status'], 'PENDING');
    },
  );

  test('reuses one withdrawal key through a 428 security challenge', () async {
    final api = _WithdrawalApiClient(
      responses: [
        ApiException(428, 'security verification is required'),
        <String, dynamic>{
          'withdrawalId': 'withdrawal-2',
          'status': 'PENDING',
          'fee': '0.01',
          'netAmount': '0.99',
        },
      ],
    );
    final state = _withdrawalState(api: api);

    await state.withdrawWallet(
      chain: 'ETH',
      symbol: 'USDT',
      toAddress: '0x1111111111111111111111111111111111111111',
      amount: '1',
    );

    expect(state.withdrawalVerificationRequired, isTrue);
    expect(state.withdrawalTotpRequired, isTrue);
    expect(api.challengeScenes, ['WITHDRAWAL']);

    await state.withdrawWallet(
      chain: 'ETH',
      symbol: 'USDT',
      toAddress: '0x1111111111111111111111111111111111111111',
      amount: '1',
      emailCode: '123456',
      totpCode: '654321',
    );

    expect(api.idempotencyKeys, hasLength(2));
    expect(api.idempotencyKeys.toSet(), hasLength(1));
    expect(api.emailCodes.last, '123456');
    expect(api.totpCodes.last, '654321');
    expect(state.withdrawalOutcomeLocked, isTrue);
    expect(state.withdrawalOutcomeUnknown, isFalse);
    expect(state.withdrawalConfirmation?.fee, '0.01');
    expect(state.withdrawalConfirmation?.receivedAmount, '0.99');
  });

  test('locks an unknown withdrawal result and suppresses retries', () async {
    final settings = _MemorySettingsStore();
    final api = _WithdrawalApiClient(responses: [StateError('offline')]);
    final state = _withdrawalState(api: api, settings: settings);

    await state.withdrawWallet(
      chain: 'ETH',
      symbol: 'USDT',
      toAddress: '0x1111111111111111111111111111111111111111',
      amount: '1',
    );
    await state.withdrawWallet(
      chain: 'ETH',
      symbol: 'USDT',
      toAddress: '0x1111111111111111111111111111111111111111',
      amount: '1',
    );

    expect(api.idempotencyKeys, hasLength(1));
    expect(state.withdrawalOutcomeLocked, isTrue);
    expect(state.withdrawalOutcomeUnknown, isTrue);
    expect(state.lastError, contains('结果未知'));
    expect(settings.values['withdrawalLocked'], 'true');
    expect(settings.values['withdrawalUnknown'], 'true');
    expect(settings.values['withdrawalKey'], api.idempotencyKeys.single);
  });

  test('validates withdrawal address amount precision minimum and balance', () {
    final state =
        _withdrawalState(api: _WithdrawalApiClient(responses: const []))
          ..withdrawalRules = const [
            WithdrawalAssetRule(
              chain: 'ETH',
              symbol: 'USDT',
              network: 'Ethereum',
              family: 'EVM',
              withdrawalEnabled: true,
              decimals: 6,
              configuredMinimum: '0.1',
              fee: '0.01',
            ),
          ];

    String? validate(String address, String amount) => state.validateWithdrawal(
      chain: 'ETH',
      symbol: 'USDT',
      toAddress: address,
      amount: amount,
    );

    expect(validate('not-an-evm-address', '1'), contains('EVM'));
    expect(
      validate('0x1111111111111111111111111111111111111111', '0.0000001'),
      contains('6 位小数'),
    );
    expect(
      validate('0x1111111111111111111111111111111111111111', '0.01'),
      contains('最低提币数量'),
    );
    expect(
      validate('0x1111111111111111111111111111111111111111', '12.6'),
      contains('可用余额'),
    );
    expect(
      validate('0x1111111111111111111111111111111111111111', '1.25'),
      isNull,
    );
  });

  test('disabling biometric login preserves the encrypted session', () async {
    final store = _MemorySessionStore()
      ..session = _session
      ..biometric = true;
    final state =
        AppState(
            offline: true,
            sessionStore: store,
            settingsStore: _MemorySettingsStore(),
          )
          ..session = _session
          ..biometricLoginEnabled = true
          ..biometricLoginAvailable = true;

    expect(await state.disableBiometricLogin(), isTrue);
    expect(store.biometric, isFalse);
    expect(store.session?.refreshToken, _session.refreshToken);
    expect(state.biometricLoginEnabled, isFalse);
    expect(state.lastNotice, contains('已关闭'));
  });

  testWidgets('top withdrawal action opens the real withdrawal form', (
    tester,
  ) async {
    final state = _withdrawalState(
      api: _WithdrawalApiClient(responses: const []),
    );
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );

    await tester.tap(find.text('资产').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('提币').first);
    await tester.pumpAndSettle();

    expect(find.byType(WithdrawalPage), findsOneWidget);
    expect(find.text('资产与网络'), findsOneWidget);
    expect(find.text('提币地址'), findsOneWidget);
    expect(find.text('核对并确认提币'), findsOneWidget);
  });

  testWidgets('profile confirms and disables biometric login', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _MemorySessionStore()
      ..session = _session
      ..biometric = true;
    final state =
        AppState(
            offline: true,
            sessionStore: store,
            settingsStore: _MemorySettingsStore(),
          )
          ..session = _session
          ..biometricLoginEnabled = true
          ..biometricLoginAvailable = true;
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: const MaterialApp(home: Scaffold(body: ProfilePage())),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '关闭'));
    await tester.pumpAndSettle();
    expect(find.text('关闭生物识别登录？'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '确认关闭'));
    await tester.pumpAndSettle();

    expect(state.biometricLoginEnabled, isFalse);
    expect(find.text('启用生物识别登录'), findsOneWidget);
  });
}

const _session = AuthSession(
  user: AuthUser(
    userId: 7,
    username: 'withdrawal-user',
    email: 'withdrawal@example.com',
    status: 'ACTIVE',
  ),
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
);

AppState _withdrawalState({
  required _WithdrawalApiClient api,
  _MemorySettingsStore? settings,
}) {
  return AppState(
      offline: true,
      apiClient: api,
      settingsStore: settings ?? _MemorySettingsStore(),
    )
    ..session = _session
    ..walletPortfolio = WalletPortfolio.fromJson({
      'generatedAt': '2026-08-06T00:00:00Z',
      'assetCount': 1,
      'assets': [
        {
          'symbol': 'USDT',
          'availableBalance': '12.5',
          'lockedBalance': '0',
          'totalBalance': '12.5',
          'chains': [
            {
              'chain': 'ETH',
              'symbol': 'USDT',
              'network': 'Ethereum',
              'family': 'EVM',
              'standard': 'ERC20',
              'nativeAsset': false,
              'nativeSymbol': 'ETH',
              'availableBalance': '12.5',
              'lockedBalance': '0',
              'totalBalance': '12.5',
              'addresses': const [],
            },
          ],
        },
      ],
    })
    ..withdrawalRules = const [
      WithdrawalAssetRule(
        chain: 'ETH',
        symbol: 'USDT',
        network: 'Ethereum',
        family: 'EVM',
        withdrawalEnabled: true,
        decimals: 6,
        configuredMinimum: '0.1',
      ),
    ]
    ..withdrawalRulesReady = true;
}

class _RecordingHttpClient implements HttpClient {
  _RecordingHttpClient(this.responseBody);

  final String responseBody;
  late Uri uri;
  late _RecordingHttpClientRequest request;

  @override
  Duration? connectionTimeout;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async {
    uri = url;
    request = _RecordingHttpClientRequest(responseBody);
    return request;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingHttpClientRequest implements HttpClientRequest {
  _RecordingHttpClientRequest(this.responseBody);

  final String responseBody;
  final StringBuffer body = StringBuffer();

  @override
  final HttpHeaders headers = _RecordingHttpHeaders();

  @override
  void write(Object? object) => body.write(object);

  @override
  Future<HttpClientResponse> close() async {
    return _RecordingHttpClientResponse(responseBody);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingHttpHeaders implements HttpHeaders {
  final Map<String, String> values = {};

  @override
  ContentType? get contentType {
    final value = values[HttpHeaders.contentTypeHeader];
    return value == null ? null : ContentType.parse(value);
  }

  @override
  set contentType(ContentType? value) {
    if (value == null) {
      values.remove(HttpHeaders.contentTypeHeader);
    } else {
      values[HttpHeaders.contentTypeHeader] = value.toString();
    }
  }

  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {
    values[name.toLowerCase()] = '$value';
  }

  @override
  String? value(String name) => values[name.toLowerCase()];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _RecordingHttpClientResponse(String body) : bytes = utf8.encode(body);

  final List<int> bytes;

  @override
  int get statusCode => HttpStatus.ok;

  @override
  String get reasonPhrase => 'OK';

  @override
  int get contentLength => bytes.length;

  @override
  bool get persistentConnection => false;

  @override
  bool get isRedirect => false;

  @override
  final HttpHeaders headers = _RecordingHttpHeaders();

  @override
  List<RedirectInfo> get redirects => const [];

  @override
  List<Cookie> get cookies => const [];

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(bytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _WithdrawalApiClient extends ApiClient {
  _WithdrawalApiClient({required this.responses}) : super(const AppConfig());

  final List<Object> responses;
  final List<String> idempotencyKeys = [];
  final List<String?> emailCodes = [];
  final List<String?> totpCodes = [];
  final List<String> challengeScenes = [];
  int calls = 0;

  @override
  Future<Map<String, dynamic>> walletWithdraw(
    int userId, {
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
    required String idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) async {
    idempotencyKeys.add(idempotencyKey);
    emailCodes.add(emailCode);
    totpCodes.add(totpCode);
    final response = responses[calls++];
    if (response is Map<String, dynamic>) return response;
    throw response;
  }

  @override
  Future<Map<String, dynamic>> issueSecurityChallenge(String sceneCode) async {
    challengeScenes.add(sceneCode);
    return {'destination': 'w***@example.com'};
  }

  @override
  Future<Map<String, dynamic>> mfaStatus() async => {'enabled': true};
}

class _MemorySettingsStore implements ClientSettingsStore {
  Map<String, String> values = {};

  @override
  Future<Map<String, String>> read() async => Map.of(values);

  @override
  Future<void> write(Map<String, String> next) async {
    values = Map.of(next);
  }
}

class _MemorySessionStore implements SessionStore {
  AuthSession? session;
  bool biometric = false;

  @override
  Future<AuthSession?> readSession() async => session;

  @override
  Future<void> saveSession(AuthSession value) async => session = value;

  @override
  Future<void> clear() async {
    session = null;
    biometric = false;
  }

  @override
  Future<bool> biometricEnabled() async => biometric;

  @override
  Future<bool> canUseBiometrics() async => biometric;

  @override
  Future<bool> authenticateBiometric() async => biometric;

  @override
  Future<void> enableBiometric() async => biometric = true;
}
