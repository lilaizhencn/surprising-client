import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/telegram_login.dart';

import 'telegram_login_test.dart' as fixtures;

const device = '3105164f-5122-46be-8cb7-9c4e09825980';
ApiClient deviceApi({
  String url = 'https://api.surprising.test',
  String id = device,
}) =>
    ApiClient(AppConfig(gatewayBaseUrl: url))..deviceIdLoader = () async => id;
Uri returnLink(String id) => Uri.parse('surprising://auth/telegram?flowId=$id');

class RestoredAppState extends AppState {
  RestoredAppState(ApiClient api, TelegramLoginStore store)
    : super(apiClient: api, telegramLoginStore: store);
  @override
  Future<void> restoreAuthentication() async {}
}

class RestoringAppState extends AppState {
  RestoringAppState(this.restored, ApiClient api) : super(apiClient: api);
  final Future<void> restored;
  @override
  Future<void> restoreAuthentication() => restored;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));

  test(
    'saves the verifier before leaving the app and clears it after completion',
    () async {
      final api = fixtures.TelegramApi(fixtures.flow(), [fixtures.session()])
        ..deviceIdLoader = () async => device;
      final store = TelegramLoginStore();
      await signInWithTelegram(
        api: api,
        store: store,
        openBrowser: (_) async {
          final saved = await TelegramLoginStore().read(api);
          expect(saved!.verifier, 'v' * 43);
          expect(saved.matches(returnLink('s' * 43)), isTrue);
          return true;
        },
        cancelled: () => false,
      );
      expect(await store.read(api), isNull);
    },
  );

  test(
    'a recreated app redeems the saved flow without starting or opening another authorization',
    () async {
      final api = fixtures.TelegramApi(fixtures.flow(), [fixtures.session()])
        ..deviceIdLoader = () async => device;
      final original = TelegramLoginFlow.fromJson(fixtures.flow());
      await TelegramLoginStore().save(api, original);
      final restarted = TelegramLoginStore();
      final recovered = await restarted.read(api);
      final result = await signInWithTelegram(
        api: api,
        store: restarted,
        resume: recovered,
        openBrowser: (_) async => fail('Must not open another browser'),
        cancelled: () => false,
      );
      expect(result.user.userId, 7);
      expect(api.requests.single.$1, '/api/v1/auth/telegram/complete');
      expect(api.requests.single.$2['verifier'], original.verifier);
      expect(await restarted.read(api), isNull);
    },
  );

  for (final changed in ['api', 'device', 'expiry']) {
    test('pending authorization cannot move to a different $changed', () async {
      final api = deviceApi();
      final json = fixtures.flow();
      if (changed == 'expiry') {
        json['expiresAt'] = DateTime.now()
            .subtract(const Duration(seconds: 1))
            .toIso8601String();
      }
      final store = TelegramLoginStore();
      await store.save(api, TelegramLoginFlow.fromJson(json));
      final other = deviceApi(
        url: changed == 'api'
            ? 'https://another.test'
            : api.config.gatewayBaseUrl,
        id: changed == 'device'
            ? '4105164f-5122-46be-8cb7-9c4e09825980'
            : device,
      );
      expect(await store.read(other), isNull);
      expect(await store.read(api), isNull);
    });
  }

  test(
    'unsolicited, duplicate-parameter and credential-bearing links cannot identify a saved flow',
    () {
      final flow = TelegramLoginFlow.fromJson(fixtures.flow());
      expect(flow.matches(returnLink('s' * 43)), isTrue);
      for (final link in [
        returnLink('x' * 43).toString(),
        '${returnLink('s' * 43)}&flowId=${'s' * 43}',
        '${returnLink('s' * 43)}&accessToken=forged',
        '${returnLink('s' * 43)}#fragment',
        'surprising://attacker/telegram?flowId=${'s' * 43}',
        'https://auth/telegram?flowId=${'s' * 43}',
        'surprising://user@auth/telegram?flowId=${'s' * 43}',
      ]) {
        expect(flow.matches(Uri.parse(link)), isFalse, reason: link);
      }
    },
  );

  test('cancelling an older flow cannot erase a newer saved flow', () async {
    final store = TelegramLoginStore();
    final api = deviceApi();
    final next = TelegramLoginFlow.fromJson(
      fixtures.flow()..['flowId'] = 'n' * 43,
    );
    await store.save(api, next);
    await store.clear('s' * 43);
    expect((await store.read(api))!.flowId, next.flowId);
  });

  for (final cancel in [true, false]) {
    test(
      'browser ${cancel ? 'cancellation' : 'failure'} removes the pending verifier',
      () async {
        final api = fixtures.TelegramApi(fixtures.flow(), [])
          ..deviceIdLoader = () async => device;
        final store = TelegramLoginStore();
        var cancelled = false;
        await expectLater(
          signInWithTelegram(
            api: api,
            store: store,
            openBrowser: (_) async {
              cancelled = cancel;
              return cancel;
            },
            cancelled: () => cancelled,
          ),
          throwsA(cancel ? isA<TelegramLoginCancelled>() : isA<StateError>()),
        );
        expect(await store.read(api), isNull);
      },
    );
  }

  test(
    'cold return still requires configured MFA and duplicate return cannot redeem twice',
    () async {
      final api = fixtures.TelegramApi(fixtures.flow(), [
        {
          'requiresVerification': true,
          'challengeToken': 'challenge',
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'methods': [
            {'type': 'TOTP'},
          ],
        },
      ])..deviceIdLoader = () async => device;
      final store = TelegramLoginStore();
      await store.save(api, TelegramLoginFlow.fromJson(fixtures.flow()));
      final state = RestoredAppState(api, store);
      addTearDown(state.dispose);
      expect(await state.resumeTelegramLogin(returnLink('x' * 43)), isFalse);
      expect(api.requests, isEmpty);
      expect(await state.resumeTelegramLogin(returnLink('s' * 43)), isTrue);
      expect(state.session, isNull);
      expect(state.pendingLoginChallenge!.methods.single['type'], 'TOTP');
      expect(await state.resumeTelegramLogin(returnLink('s' * 43)), isFalse);
      expect(api.requests, hasLength(1));
      expect(await store.read(api), isNull);
    },
  );

  test(
    'logged-in or biometrically locked sessions never switch accounts from an incoming link',
    () async {
      final api = fixtures.TelegramApi(fixtures.flow(), [])
        ..deviceIdLoader = () async => device;
      final store = TelegramLoginStore();
      await store.save(api, TelegramLoginFlow.fromJson(fixtures.flow()));
      final state = RestoredAppState(api, store);
      addTearDown(state.dispose);
      state.session = AuthSession.fromJson(fixtures.session());
      expect(await state.resumeTelegramLogin(returnLink('s' * 43)), isFalse);
      state.pendingBiometricSession = state.session;
      state.session = null;
      expect(await state.resumeTelegramLogin(returnLink('s' * 43)), isFalse);
      expect(api.requests, isEmpty);
    },
  );

  test(
    'persisting another login or logging out invalidates any pending Telegram flow',
    () async {
      final api = deviceApi();
      final store = TelegramLoginStore();
      final sessions = SecureSessionStore();
      await store.save(api, TelegramLoginFlow.fromJson(fixtures.flow()));
      await sessions.saveSession(AuthSession.fromJson(fixtures.session()));
      expect(await store.read(api), isNull);
      await store.save(api, TelegramLoginFlow.fromJson(fixtures.flow()));
      await sessions.clear();
      expect(await store.read(api), isNull);
    },
  );

  test(
    'corrupted secure state is removed without trusting its contents',
    () async {
      const storage = FlutterSecureStorage();
      await storage.write(
        key: telegramLoginStorageKey,
        value: jsonEncode({'flowId': '<script>'}),
      );
      expect(await TelegramLoginStore().read(deviceApi()), isNull);
      expect(await storage.read(key: telegramLoginStorageKey), isNull);
    },
  );
  test(
    'disposing the app while restoring authentication cannot resume a late link',
    () async {
      final barrier = Completer<void>();
      final api = fixtures.TelegramApi(fixtures.flow(), []);
      final state = RestoringAppState(barrier.future, api);
      final resumed = state.resumeTelegramLogin(returnLink('s' * 43));
      state.dispose();
      barrier.complete();
      expect(await resumed, isFalse);
      expect(api.requests, isEmpty);
    },
  );
}
