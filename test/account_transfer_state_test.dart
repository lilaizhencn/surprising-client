import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/pending_transfer.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/wallet/account_transfer_state.dart';

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  final history = <String>[];
  bool failWrites = false, failReads = false;
  Completer<void>? gate;
  Completer<void>? writeStarted;

  @override
  Future<Map<String, String>> read() async {
    if (failReads) throw StateError('storage unavailable');
    return {...values};
  }

  @override
  Future<void> write(Map<String, String> next) async {
    if (failWrites) throw StateError('storage unavailable');
    final started = writeStarted;
    if (started != null && !started.isCompleted) started.complete();
    await gate?.future;
    values = {...next};
    history.add(jsonEncode(next));
  }
}

class _Ledger {
  final calls = <Map<String, dynamic>>[];
  final applied = <String>{};
  int debits = 0;
  Future<Map<String, dynamic>> Function(Map<String, dynamic>) respond =
      (_) async => {'status': 'COMPLETED'};
}

class _Api extends ApiClient {
  _Api(this.settings, this.ledger) : super(const AppConfig());
  final _Settings settings;
  final _Ledger ledger;

  @override
  Future<Map<String, String>> assetScales() async => {'USDT': '1000000'};

  @override
  Future<Map<String, dynamic>> issueSecurityChallenge(String scene) async => {
    'destination': 'test-only',
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
    final stored = (jsonDecode(settings.values['pendingTransfers']!) as List)
        .where((row) => row['userId'] == userId)
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
    ledger.calls.add(request);
    if (ledger.applied.add(idempotencyKey)) ledger.debits++;
    return ledger.respond(request);
  }
}

class _Fixture {
  _Fixture({_Settings? settings, _Ledger? ledger})
    : settings = settings ?? _Settings(),
      ledger = ledger ?? _Ledger();
  final _Settings settings;
  final _Ledger ledger;
  int? userId = 7;
  int epoch = 0, notifications = 0, refreshes = 0;
  late final api = _Api(settings, ledger);
  late final state = AccountTransferState(
    api: api,
    settingsStore: settings,
    owner: () => (userId: userId, epoch: epoch),
    persist: persist,
    refreshAssets: () async {
      refreshes++;
    },
    onChanged: () {
      notifications++;
    },
  );
  Future<void> _tail = Future.value();

  /// Mirrors the app's shared settings queue, including confirmation before unlock.
  Future<bool> persist({PendingAccountTransfer? completed}) async {
    final previous = _tail, done = Completer<void>();
    _tail = done.future;
    await previous;
    try {
      if (completed != null && !state.matches(completed)) return false;
      if (!state.restored && !await state.restore()) return false;
      await settings.write({
        ...settings.values,
        'theme': 'dark',
        'pendingTransfers': jsonEncode(
          state.pendingSnapshot
              .where((intent) => !identical(intent, completed))
              .map((intent) => intent.toJson())
              .toList(),
        ),
      });
      return completed == null || state.completeSaved(completed);
    } catch (_) {
      return false;
    } finally {
      done.complete();
    }
  }

  Future<void> send({String amount = '1.000001'}) => state.submit(
    sourceAccountType: 'FUNDING',
    targetAccountType: 'USDT_PERPETUAL',
    asset: 'USDT',
    amountText: amount,
  );

  void dispose() {
    state.dispose();
    api.dispose();
  }
}

void main() {
  test(
    'lost response and process restart preserve one immutable debit identity',
    () async {
      final settings = _Settings(), ledger = _Ledger();
      ledger.respond = (_) async => throw const SocketException('reply lost');
      final original = _Fixture(settings: settings, ledger: ledger);
      await original.send();
      final key = original.state.pending!.key;
      expect(original.state.outcomeLocked, isTrue);
      original.dispose();
      final restarted = _Fixture(settings: settings, ledger: ledger);
      addTearDown(restarted.dispose);
      expect(await restarted.state.restore(), isTrue);
      expect(restarted.state.pending!.amountUnits, 1000001);
      await restarted.send(amount: '2');
      expect(ledger.calls, hasLength(1));
      ledger.respond = (_) async => {'status': 'COMPLETED'};
      await restarted.state.resume();
      expect(ledger.calls.map((request) => request['key']).toSet(), {key});
      expect(ledger.calls.map((request) => request['amount']).toSet(), {
        1000001,
      });
      expect(ledger.debits, 1);
      expect(restarted.state.pending, isNull);
      expect(jsonDecode(settings.values['pendingTransfers']!), isEmpty);
    },
  );

  test(
    'verification reuses the original command and never persists security codes',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.ledger.respond = (_) async =>
          throw ApiException(428, 'verification required');
      await f.send();
      expect(f.state.verificationRequired, isTrue);
      final key = f.state.pending!.key;
      await f.send(amount: '2');
      expect(f.ledger.calls, hasLength(1));
      expect(f.state.error, contains('原划转'));
      f.ledger.respond = (_) async => {'status': 'COMPLETED'};
      await f.state.resume(emailCode: '123456', totpCode: '654321');
      expect(f.ledger.calls.last['key'], key);
      expect(f.ledger.calls.last['emailCode'], '123456');
      expect(f.settings.history.join(), isNot(contains('123456')));
      expect(f.settings.history.join(), isNot(contains('654321')));
    },
  );

  test(
    'save failure sends no HTTP and explicit recovery retains the same key',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.settings.failWrites = true;
      await f.send();
      expect(f.ledger.calls, isEmpty);
      expect(f.state.error, contains('未发送'));
      final key = f.state.pending!.key;
      f.settings.failWrites = false;
      await f.state.resume();
      expect(f.ledger.calls.single['key'], key);
      expect(f.state.pending, isNull);
    },
  );

  test(
    'confirmed completion remains locked until durable removal finishes',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final gate = Completer<void>(), started = Completer<void>();
      f.ledger.respond = (_) async {
        f.settings.gate = gate;
        f.settings.writeStarted = started;
        return {'status': 'COMPLETED'};
      };
      final sending = f.send();
      await started.future;
      expect(f.state.outcomeLocked, isTrue);
      expect(f.state.submitting, isTrue);
      await f.send(amount: '2');
      expect(f.ledger.calls, hasLength(1));
      gate.complete();
      await sending;
      expect(f.state.pending, isNull);
      expect(f.state.notice, contains('已完成'));
      expect(f.refreshes, 1);
    },
  );

  test('failed durable completion removal keeps recovery locked', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    f.ledger.respond = (_) async {
      f.settings.failWrites = true;
      return {'status': 'COMPLETED'};
    };
    await f.send();
    expect(f.state.pending, isNotNull);
    expect(f.state.error, contains('恢复凭证'));
    expect(f.state.notice, isNull);
    f.settings.failWrites = false;
    f.ledger.respond = (_) async => {'status': 'COMPLETED'};
    await f.state.resume();
    expect(f.ledger.debits, 1);
    expect(f.state.pending, isNull);
  });

  test(
    'a late original-owner result cannot update another account feedback',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final result = Completer<Map<String, dynamic>>();
      f.ledger.respond = (request) async =>
          request['userId'] == 7 ? result.future : {'status': 'COMPLETED'};
      final sending = f.send();
      while (f.ledger.calls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      f.userId = 8;
      f.epoch++;
      await f.send(amount: '2');
      final notice = f.state.notice, notifications = f.notifications;
      result.complete({'status': 'PENDING'});
      await sending;
      expect(f.state.pending, isNull);
      expect(f.state.notice, notice);
      expect(f.notifications, notifications);
      f.userId = 7;
      f.epoch++;
      expect(f.state.pending!.amountUnits, 1000001);
      expect(f.state.outcomeLocked, isTrue);
      expect(f.state.notice, isNull);
    },
  );

  test('missing receipts cannot unlock an unknown monetary request', () async {
    final f = _Fixture();
    addTearDown(f.dispose);
    f.ledger.respond = (_) async => throw ApiException(404, 'NOT_FOUND');
    await f.send();
    final key = f.state.pending!.key;
    await f.state.resume();
    await f.state.resetFailedIntent();
    expect(f.state.pending!.key, key);
    expect(f.ledger.calls.map((request) => request['key']).toSet(), {key});
  });

  test(
    'only an explicitly failed terminal request may be reset durably',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.ledger.respond = (_) async => {'status': 'FAILED'};
      await f.send();
      expect(f.state.terminalFailure, isTrue);
      await f.state.resetFailedIntent();
      expect(f.state.pending, isNull);
      expect(jsonDecode(f.settings.values['pendingTransfers']!), isEmpty);
    },
  );

  test(
    'corrupt restore is atomic and a temporary storage failure can be retried',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      f.settings.failReads = true;
      expect(await f.state.restore(), isFalse);
      f.settings.failReads = false;
      f.settings.values['pendingTransfers'] = '[{"userId":7}]';
      await f.send();
      expect(f.ledger.calls, isEmpty);
      expect(f.state.pendingSnapshot, isEmpty);
      expect(f.state.error, contains('读取原划转凭证'));
      expect(f.settings.values['pendingTransfers'], '[{"userId":7}]');
      f.settings.values['pendingTransfers'] = '[]';
      expect(await f.state.restore(), isTrue);
      await f.send();
      expect(f.ledger.calls, hasLength(1));
    },
  );

  test(
    'disposal prevents late notification or refresh without erasing recovery identity',
    () async {
      final f = _Fixture();
      addTearDown(f.dispose);
      final result = Completer<Map<String, dynamic>>();
      f.ledger.respond = (_) => result.future;
      final sending = f.send();
      while (f.ledger.calls.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }
      final key = f.state.pending!.key, notifications = f.notifications;
      f.state.dispose();
      result.complete({'status': 'PENDING'});
      await sending;
      expect(f.notifications, notifications);
      expect(f.refreshes, 0);
      expect(f.state.pending!.key, key);
      expect(
        jsonDecode(f.settings.values['pendingTransfers']!).single['key'],
        key,
      );
    },
  );
}
