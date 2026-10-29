import 'support/authentication.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/account_records.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/device_access_panel.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/kyc_application_page.dart';
import 'package:surprising_client/src/models.dart';
import 'transfer_page_test.dart' show MemorySettings;
import 'account_display_test.dart' show AccountApi, session;

void main() {
  test(
    'late deposit address cannot replace a newer network selection',
    () async {
      final api = AddressApi();
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      final old = state.loadDepositAddress(chain: 'BTC', symbol: 'BTC');
      final next = state.loadDepositAddress(chain: 'ETH', symbol: 'ETH');
      api.pending[1].complete(
        WalletDepositAddress.fromJson({
          'chain': 'ETH',
          'symbol': 'ETH',
          'address': 'NEW',
        }),
      );
      await next;
      api.pending[0].complete(
        WalletDepositAddress.fromJson({
          'chain': 'BTC',
          'symbol': 'BTC',
          'address': 'OLD',
        }),
      );
      await old;
      expect(state.walletDepositAddress?.address, 'NEW');
    },
  );
  test(
    'disposed address request cannot restore data or notify the closed state',
    () async {
      final api = AddressApi();
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      final request = state.loadDepositAddress(chain: 'BTC', symbol: 'BTC');
      state.dispose();
      api.pending.single.complete(
        WalletDepositAddress.fromJson({
          'chain': 'BTC',
          'symbol': 'BTC',
          'address': 'OLD',
        }),
      );
      await request;
      expect(state.walletDepositAddress, isNull);
    },
  );
  test(
    'transfer rejects excessive precision before any debit command',
    () async {
      final api = TransferPrecisionApi();
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
        settingsStore: MemorySettings(),
      );
      addTearDown(state.dispose);
      await state.transfer(
        sourceAccountType: 'FUNDING',
        targetAccountType: 'SPOT',
        asset: 'USDT',
        amount: 0.000000001,
        amountText: '0.000000001',
      );
      expect(api.commands, isEmpty);
      expect(state.lastError, contains('精度'));
      expect(state.transferOutcomeLocked, false);
      await state.transfer(
        sourceAccountType: 'FUNDING',
        targetAccountType: 'SPOT',
        asset: 'USDT',
        amount: 90071992.54740993,
        amountText: '90071992.54740993',
      );
      expect(api.commands, [9007199254740993]);
    },
  );
  test(
    'money conversion never rounds, overflows or guesses missing precision',
    () {
      expect(
        exactAmountUnits('90071992.54740993', '100000000'),
        9007199254740993,
      );
      expect(exactAmountUnits('0.00000001', '100000000'), 1);
      expect(exactAmountUnits('1.200000000', '100000000'), 120000000);
      expect(exactAmountUnits('1.234567', '1000000'), 1234567);
      for (final amount in [
        '0',
        '-1',
        '1e8',
        'NaN',
        '0.000000001',
        '92233720368.54775808',
      ]) {
        expect(
          () => exactAmountUnits(amount, '100000000'),
          throwsFormatException,
        );
      }
      expect(() => exactAmountUnits('1', ''), throwsFormatException);
      expect(
        formatAccountUnits('9007199254740993', '100000000'),
        '90071992.54740993',
      );
      expect(formatAccountUnits(-1, '1000000'), '-0.000001');
      expect(formatAccountUnits(123, null), '—');
    },
  );
  test(
    'record cursor requires an actual continuation and reads list responses',
    () {
      expect(
        AccountRecordPage.fromJson([
          {'id': 1},
        ], 'deposits').rows.single['id'],
        1,
      );
      expect(
        AccountRecordPage.fromJson({
          'items': [],
          'hasMore': true,
        }, 'orders').hasMore,
        false,
      );
      expect(
        AccountRecordPage.fromJson({
          'orders': [],
          'hasMore': true,
          'nextCursor': 'next',
        }, 'orders').nextCursor,
        'next',
      );
    },
  );
  test('KYC materials reflect document, applicant and verification grade', () {
    expect(kycRequiredSlots('ID_CARD', 'INDIVIDUAL', 'BASIC'), [
      'ID_CARD_FRONT',
      'ID_CARD_BACK',
      'ID_CARD_SELFIE',
    ]);
    expect(kycRequiredSlots('PASSPORT', 'BUSINESS', 'ENHANCED'), [
      'PASSPORT',
      'ADDRESS_PROOF',
      'BUSINESS_LICENSE',
      'FACE_IMAGE',
    ]);
    expect(kycRequiredSlots('DRIVING_LICENSE', 'INDIVIDUAL', 'STANDARD'), [
      'DRIVING_LICENSE_FRONT',
      'DRIVING_LICENSE_BACK',
      'ADDRESS_PROOF',
    ]);
    expect(
      threeMonthsBefore(DateTime.utc(2026, 5, 31)),
      DateTime.utc(2026, 2, 28),
    );
    expect(
      threeMonthsBefore(DateTime.utc(2024, 5, 31)),
      DateTime.utc(2024, 2, 29),
    );
  });
  test(
    'internal errors never expose transport or server implementation details',
    () {
      expect(
        ApiException(
          400,
          '{"code":"INVALID_COMMAND","message":"Aeron order command rejected"}',
        ).toString(),
        '操作未完成，请刷新状态后重试',
      );
      expect(
        ApiException(503, '<html>SQL exception</html>').toString(),
        '服务暂时不可用，请稍后重试',
      );
      expect(ApiException(400, '{"message":"可用余额不足"}').toString(), '可用余额不足');
      expect(ApiException(428, '').toString(), contains('安全验证'));
      expect(
        clientErrorMessage(
          const SocketException('host secret.invalid refused'),
        ),
        '网络连接失败，请检查网络后重试',
      );
      final state = AppState(offline: true);
      addTearDown(state.dispose);
      state.handleRealtimeMessage({
        'op': 'error',
        'error': 'Aeron internal transport failed',
      });
      expect(state.lastError, isNot(contains('Aeron')));
    },
  );
  testWidgets(
    'late history response cannot overwrite a new category or survive logout',
    (tester) async {
      final api = RecordApi();
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(home: FundingRecordsPage(state: state)),
      );
      await tester.pump();
      expect(api.pending, hasLength(1));
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('充值记录').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(api.pending, hasLength(2));
      api.pending[1].complete(
        const AccountRecordPage(
          [
            {'asset': 'USDT', 'amount': '2', 'referenceId': 'NEW'},
          ],
          null,
          false,
        ),
      );
      await tester.pumpAndSettle();
      api.pending[0].complete(
        const AccountRecordPage(
          [
            {'asset': 'USDT', 'amount': '1', 'referenceId': 'OLD'},
          ],
          null,
          false,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('参考号：NEW'), findsOneWidget);
      expect(find.text('参考号：OLD'), findsNothing);
      await state.logout();
      await tester.pump();
      expect(find.text('参考号：NEW'), findsNothing);
      expect(find.text('请先登录查看记录'), findsOneWidget);
    },
  );
  testWidgets('KYC form survives credentials refreshing during country load', (
    tester,
  ) async {
    final api = KycApi();
    final state = AppState(
      initialSession: session,
      sessionStore: MemorySessionStore(),
      offline: true,
      apiClient: api,
      settingsStore: MemorySettings(),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(home: KycApplicationPage(state: state)),
    );
    await tester.pump();
    await state.auth.persistRefreshedSession(
      AuthSession(
        user: session.user,
        accessToken: 'renewed',
        refreshToken: 'renewed',
      ),
    );
    api.countries.complete([
      {
        'code': 'CN',
        'names': {'zh': '中国'},
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.textContaining('登录状态已变更'), findsNothing);
    expect(find.text('证件类型'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('KYC status survives credentials refreshing during its read', (
    tester,
  ) async {
    final api = RefreshingKycApi();
    final state = AppState(
      initialSession: session,
      sessionStore: MemorySessionStore(),
      offline: true,
      apiClient: api,
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: const MaterialApp(
          home: Scaffold(body: SecuritySheet(kycOnly: true)),
        ),
      ),
    );
    await tester.pump();
    await state.auth.persistRefreshedSession(
      AuthSession(
        user: session.user,
        accessToken: 'renewed',
        refreshToken: 'renewed',
      ),
    );
    api.pending.complete({
      'status': 'REJECTED',
      'rejectionReason': '请重新拍摄完整证件',
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('请重新拍摄完整证件'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('KYC country load is fenced when the account changes', (
    tester,
  ) async {
    final api = KycApi();
    final state = AppState(
      initialSession: session,
      sessionStore: MemorySessionStore(),
      offline: true,
      apiClient: api,
      settingsStore: MemorySettings(),
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(home: KycApplicationPage(state: state)),
    );
    await tester.pump();
    await state.logout();
    await tester.pump();
    api.countries.complete([
      {
        'code': 'CN',
        'names': {'zh': '中国'},
      },
    ]);
    await tester.pumpAndSettle();
    expect(find.text('中国'), findsNothing);
    expect(find.textContaining('登录状态已变更'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'device data is cleared on logout and old reads cannot restore it',
    (tester) async {
      final api = DeviceApi();
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: DeviceAccessPanel(state: state)),
        ),
      );
      await tester.tap(find.text('设备与登录 IP'));
      await tester.pump(const Duration(milliseconds: 400));
      await state.logout();
      await tester.pump();
      api.pending.complete([
        {'deviceId': 'old', 'userAgent': 'PRIVATE OLD DEVICE'},
      ]);
      await tester.pump();
      expect(find.text('PRIVATE OLD DEVICE'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  for (final brightness in Brightness.values) {
    testWidgets(
      'API secret is one-time and clears on identity change on a small $brightness screen',
      (tester) async {
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = SecurityApi()..failKyc = false;
        final state = AppState(
          initialSession: session,
          sessionStore: MemorySessionStore(),
          offline: true,
          apiClient: api,
        );
        addTearDown(state.dispose);
        await tester.pumpWidget(
          AppScope(
            notifier: state,
            child: MaterialApp(
              theme: ThemeData(brightness: brightness),
              home: const Scaffold(body: SecuritySheet()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final create = find.text('创建 API Key');
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(api.permissions, ['READ']);
        expect(find.byKey(const ValueKey('api-secret')), findsOneWidget);
        final saved = find.text('我已保存');
        await tester.ensureVisible(saved);
        await tester.tap(saved);
        await tester.pump();
        expect(find.byKey(const ValueKey('api-secret')), findsNothing);
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('api-secret')), findsOneWidget);
        await state.logout();
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('api-secret')), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets(
    'cancelling session revocation does not report a successful logout',
    (tester) async {
      final api = SecurityApi()..failKyc = false;
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: const MaterialApp(home: Scaffold(body: SecuritySheet())),
        ),
      );
      await tester.pumpAndSettle();
      final revoke = find.text('下线其他设备');
      await tester.ensureVisible(revoke);
      await tester.tap(revoke);
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(api.revokedOthers, false);
      expect(find.text('其他设备已下线'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'KYC-only page can continue provider verification without MFA endpoint',
    (tester) async {
      final api = ProviderApi()..failKyc = false;
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: const MaterialApp(
            home: Scaffold(body: SecuritySheet(kycOnly: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final button = find.text('继续认证');
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(api.refreshed, true);
      expect(tester.takeException(), isNull);
    },
  );
}

class RefreshingKycApi extends ProviderApi {
  final pending = Completer<Map<String, dynamic>>();
  @override
  Future<Map<String, dynamic>> kycStatus() => pending.future;
}

class RecordApi extends ApiClient {
  RecordApi() : super(const AppConfig());
  final pending = <Completer<AccountRecordPage>>[];
  @override
  Future<Map<String, String>> assetScales() async => {'USDT': '100000000'};
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
  }) {
    final request = Completer<AccountRecordPage>();
    pending.add(request);
    return request.future;
  }
}

class KycApi extends ApiClient {
  KycApi() : super(const AppConfig());
  final countries = Completer<List<Map<String, dynamic>>>();
  @override
  Future<List<Map<String, dynamic>>> kycCountries() => countries.future;
  @override
  Future<Map<String, dynamic>> kycProvider() async => {
    'provider': 'SELF',
    'verificationOptions': [
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'BASIC'},
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'STANDARD'},
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'ENHANCED'},
      {'applicantType': 'BUSINESS', 'kycLevel': 'BASIC'},
    ],
  };
}

class DeviceApi extends ApiClient {
  DeviceApi() : super(const AppConfig());
  final pending = Completer<List<Map<String, dynamic>>>();
  @override
  Future<List<Map<String, dynamic>>> devices() => pending.future;
  @override
  Future<List<Map<String, dynamic>>> loginIps() async => [];
  @override
  Future<Map<String, dynamic>> mfaStatus() async => {'enabled': false};
}

class ProviderApi extends AccountApi {
  bool refreshed = false;
  @override
  Future<Map<String, dynamic>> kycStatus() async => {
    'status': 'PENDING',
    'provider': 'SUMSUB',
  };
  @override
  Future<Map<String, dynamic>> kycProvider() async => {
    'provider': 'SUMSUB',
    'simulationEnabled': false,
  };
  @override
  Future<Map<String, dynamic>> refreshKycSession() async {
    refreshed = true;
    return {'provider': 'SUMSUB', 'token': 'test'};
  }
}

class SecurityApi extends AccountApi {
  List<String>? permissions;
  bool revokedOthers = false;
  @override
  Future<Map<String, dynamic>> mfaRecoveryStatus() async => {};
  @override
  Future<Map<String, dynamic>> kycProvider() async => {
    'provider': 'SELF',
    'verificationOptions': [
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'BASIC'},
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'STANDARD'},
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'ENHANCED'},
      {'applicantType': 'BUSINESS', 'kycLevel': 'BASIC'},
    ],
  };
  @override
  Future<List<Map<String, dynamic>>> devices() async => [];
  @override
  Future<List<Map<String, dynamic>>> loginIps() async => [];
  @override
  Future<Map<String, dynamic>> createApiKey({
    required String label,
    required List<String> permissions,
    List<String> ipAllowlist = const [],
    String? emailCode,
    String? totpCode,
  }) async {
    this.permissions = permissions;
    return {
      'apiKey': {'apiKey': 'public-key', 'label': label},
      'secret': 'ONE TIME TEST SECRET',
    };
  }

  @override
  Future<void> revokeOtherSessions(String refreshToken) async {
    revokedOthers = true;
  }
}

class TransferPrecisionApi extends ApiClient {
  TransferPrecisionApi() : super(const AppConfig());
  final commands = <int>[];
  @override
  Future<Map<String, String>> assetScales() async => {'USDT': '100000000'};
  @override
  Future<Map<String, dynamic>> transfer({
    required int userId,
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required int amountUnits,
    String? idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) async {
    commands.add(amountUnits);
    return {'status': 'FAILED'};
  }
}

class AddressApi extends ApiClient {
  AddressApi() : super(const AppConfig());
  final pending = <Completer<WalletDepositAddress>>[];
  @override
  Future<WalletDepositAddress> walletDepositAddress(
    int userId, {
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) {
    final result = Completer<WalletDepositAddress>();
    pending.add(result);
    return result.future;
  }
}
