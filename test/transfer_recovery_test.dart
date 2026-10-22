import 'support/authentication.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

AuthSession account(int id) => AuthSession(
  user: AuthUser(
    userId: id,
    username: 'synthetic-$id',
    email: '',
    status: 'NORMAL',
  ),
  accessToken: 'synthetic-access',
  refreshToken: 'synthetic-refresh',
);

AppState stateFor(RecoveryApi api, DurableSettings store, [int user = 7]) =>
    _TransferState(api, store, initialSession: account(user));

Future<void> send(AppState state, {String amount = '1.000001'}) =>
    state.transfer(
      sourceAccountType: 'FUNDING',
      targetAccountType: 'USDT_PERPETUAL',
      asset: 'USDT',
      amount: 0,
      amountText: amount,
    );

void main() {
  test(
    'lost response and restart recover only original command without a second debit',
    () async {
      final store = DurableSettings();
      final api = RecoveryApi(store);
      api.respond = (_) async => throw const SocketException('response lost');
      final original = stateFor(api, store);
      await send(original);
      final key = original.pendingTransfer!.key;
      expect(original.transferOutcomeLocked, isTrue);
      expect(api.debits, 1);
      original.dispose();
      final restarted = stateFor(api, store);
      addTearDown(restarted.dispose);
      expect(await restarted.restorePendingTransfers(), isTrue);
      expect(restarted.pendingTransfer!.amountUnits, 1000001);
      await send(restarted, amount: '2');
      expect(api.calls, hasLength(1));
      api.respond = (_) async => {'status': 'COMPLETED'};
      await restarted.resumePendingTransfer();
      expect(api.calls.map((e) => e['key']).toSet(), {key});
      expect(api.calls.map((e) => e['amount']).toSet(), {1000001});
      expect(api.debits, 1);
      expect(restarted.pendingTransfer, isNull);
      expect(jsonDecode(store.values['pendingTransfers']!), isEmpty);
    },
  );

  test(
    'security verification cannot change the original intent or persist codes',
    () async {
      final store = DurableSettings();
      final api = RecoveryApi(store)
        ..respond = (_) async =>
            throw ApiException(428, 'verification required');
      final state = stateFor(api, store);
      addTearDown(state.dispose);
      await send(state);
      expect(state.transferVerificationRequired, isTrue);
      await send(state, amount: '2');
      expect(api.calls, hasLength(1));
      expect(state.lastError, contains('原划转'));
      final key = state.pendingTransfer!.key;
      api.respond = (_) async => {'status': 'COMPLETED'};
      await state.resumePendingTransfer(
        emailCode: '123456',
        totpCode: '654321',
      );
      expect(api.calls.last['key'], key);
      expect(api.calls.last['emailCode'], '123456');
      expect(store.history.join(), isNot(contains('123456')));
      expect(store.history.join(), isNot(contains('654321')));
    },
  );

  test(
    'failed durable save sends nothing and recovery keeps the same key',
    () async {
      final store = DurableSettings()..failWrites = true;
      final api = RecoveryApi(store);
      final state = stateFor(api, store);
      addTearDown(state.dispose);
      await send(state);
      expect(api.calls, isEmpty);
      final key = state.pendingTransfer!.key;
      expect(state.lastError, contains('未发送'));
      store.failWrites = false;
      await state.resumePendingTransfer();
      expect(api.calls.single['key'], key);
      expect(state.pendingTransfer, isNull);
    },
  );

  test(
    'completion is not unlocked until its durable receipt is removed',
    () async {
      final store = DurableSettings();
      final api = RecoveryApi(store)
        ..respond = (_) async {
          store.failWrites = true;
          return {'status': 'COMPLETED'};
        };
      final state = stateFor(api, store);
      addTearDown(state.dispose);
      await send(state);
      expect(state.pendingTransfer, isNotNull);
      expect(state.transferOutcomeLocked, isTrue);
      expect(state.lastNotice, isNull);
      store.failWrites = false;
      api.respond = (_) async => {'status': 'COMPLETED'};
      await state.resumePendingTransfer();
      expect(api.debits, 1);
      expect(state.pendingTransfer, isNull);
    },
  );

  test('a late result belongs only to its original user', () async {
    final store = DurableSettings(),
        pending = Completer<Map<String, dynamic>>();
    final api = RecoveryApi(store)
      ..respond = (request) async =>
          request['userId'] == 7 ? pending.future : {'status': 'COMPLETED'};
    final state = stateFor(api, store);
    addTearDown(state.dispose);
    final original = send(state);
    while (api.calls.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await state.logout();
    await signInAs(state, account(8));
    expect(state.transferOutcomeLocked, isFalse);
    await send(state, amount: '2');
    expect(state.pendingTransfer, isNull);
    final notice = state.lastNotice;
    pending.complete({'status': 'PENDING'});
    await original;
    expect(state.pendingTransfer, isNull);
    expect(state.lastNotice, notice);
    await state.logout();
    await signInAs(state, account(7));
    expect(state.transferOutcomeLocked, isTrue);
    expect(state.pendingTransfer!.amountUnits, 1000001);
    final restarted = stateFor(api, store);
    addTearDown(restarted.dispose);
    await restarted.restorePendingTransfers();
    expect(restarted.pendingTransfer!.userId, 7);
  });

  test('missing receipts never erase an uncertain command', () async {
    final store = DurableSettings();
    final api = RecoveryApi(store)
      ..respond = (_) async => throw ApiException(404, 'NOT_FOUND');
    final state = stateFor(api, store);
    addTearDown(state.dispose);
    await send(state);
    final key = state.pendingTransfer!.key;
    await state.resumePendingTransfer();
    await state.resetTransferIntent();
    expect(state.pendingTransfer!.key, key);
    expect(api.calls.map((e) => e['key']).toSet(), {key});
  });

  test(
    'corrupt stored receipts block both transfers and destructive settings saves',
    () async {
      final store = DurableSettings()
        ..values['pendingTransfers'] = '[{"userId":7}]';
      final api = RecoveryApi(store);
      final state = stateFor(api, store);
      addTearDown(state.dispose);
      await send(state);
      expect(api.calls, isEmpty);
      expect(state.lastError, contains('读取原划转凭证'));
      expect(store.values['pendingTransfers'], '[{"userId":7}]');
    },
  );
}

class DurableSettings implements ClientSettingsStore {
  Map<String, String> values = {};
  final history = <String>[];
  bool failWrites = false;
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> next) async {
    if (failWrites) throw StateError('storage unavailable');
    values = {...next};
    history.add(jsonEncode(next));
  }
}

class RecoveryApi extends TestApiClient {
  RecoveryApi(this.store) : super(const AppConfig());
  final DurableSettings store;
  final calls = <Map<String, dynamic>>[];
  final applied = <String>{};
  int debits = 0;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) respond =
      (_) async => {'status': 'COMPLETED'};
  @override
  Future<Map<String, String>> assetScales() async => {'USDT': '1000000'};
  @override
  Future<Map<String, dynamic>> issueSecurityChallenge(String scene) async => {
    'destination': 'synthetic',
  };
  @override
  Future<Map<String, dynamic>> transfer({
    required int userId,
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required int amountUnits,
    required String idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) async {
    final stored = (jsonDecode(store.values['pendingTransfers']!) as List)
        .where((e) => e['userId'] == userId)
        .single;
    expect(stored['key'], idempotencyKey);
    expect(stored['amountUnits'], '$amountUnits');
    expect(stored['source'], sourceAccountType);
    expect(stored['target'], targetAccountType);
    final request = {
      'userId': userId,
      'key': idempotencyKey,
      'amount': amountUnits,
      'source': sourceAccountType,
      'target': targetAccountType,
      'asset': asset,
      'emailCode': emailCode,
      'totpCode': totpCode,
    };
    calls.add(request);
    if (applied.add(idempotencyKey)) debits++;
    return respond(request);
  }
}

class _TransferState extends AppState {
  _TransferState(
    RecoveryApi api,
    DurableSettings store, {
    required super.initialSession,
  }) : super(
         apiClient: api,
         settingsStore: store,
         sessionStore: MemorySessionStore(),
         config: const AppConfig(websocketUrl: ''),
         seedInstruments: fallbackInstruments(),
       );
  @override
  Future<void> refreshPrivateData() async {}
}
