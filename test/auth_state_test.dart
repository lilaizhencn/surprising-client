import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/auth/auth_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/telegram_login.dart';

AuthSession credentials(String token, {int userId = 7}) => AuthSession(
  user: AuthUser(
    userId: userId,
    username: 'owner',
    email: '',
    status: 'ACTIVE',
  ),
  accessToken: token,
  refreshToken: 'refresh-$token',
);

void main() {
  late AuthenticationApi api;
  late DelayedSessionStore store;
  late AuthState auth;
  late List<AuthSessionChange> ready;

  AuthState createAuth({AuthSession? initialSession}) => AuthState(
    api: api,
    sessionStore: store,
    telegramLoginStore: TelegramLoginStore(),
    initialSession: initialSession,
    onSessionReady: (_, _, change, _) async => ready.add(change),
  );

  void startWithSession(AuthSession session) {
    auth.dispose();
    auth = createAuth(initialSession: session);
  }

  setUp(() {
    api = AuthenticationApi();
    store = DelayedSessionStore();
    ready = [];
    auth = createAuth();
  });
  tearDown(() {
    auth.dispose();
    api.dispose();
  });

  test('late password-login response cannot revive a logout', () async {
    final login = auth.login('owner@example.test', 'password');
    await api.loginStarted.future;
    final logout = auth.logout();
    expect(auth.current, isNull);
    await logout;
    api.loginReply.complete(credentials('late'));
    expect(await login, isNull);
    expect(auth.current, isNull);
    expect(store.stored, isNull);
    expect(store.writes, ['clear']);
    expect(ready, [AuthSessionChange.signedOut]);
    expect(auth.loading, isFalse);
  });

  test(
    'logout clears after an already running refresh save completes',
    () async {
      startWithSession(credentials('old'));
      store.saveGate = Completer<void>();
      final refresh = auth.persistRefreshedSession(credentials('fresh'));
      await store.saveStarted.future;
      final logout = auth.logout();
      expect(auth.current, isNull);
      expect(store.clearCalls, 0);
      store.saveGate!.complete();
      await Future.wait([refresh, logout]);
      expect(store.writes, ['save:fresh', 'clear']);
      expect(store.stored, isNull);
      expect(auth.current, isNull);
      expect(ready, [AuthSessionChange.signedOut]);
    },
  );

  test('a new login persists after an older logout clear', () async {
    startWithSession(credentials('old'));
    store.clearGate = Completer<void>();
    final logout = auth.logout();
    await store.clearStarted.future;
    final login = auth.login('next@example.test', 'password');
    api.loginReply.complete(credentials('next', userId: 9));
    store.clearGate!.complete();
    await logout;
    expect((await login)?.user.userId, 9);
    expect(store.writes, ['clear', 'save:next']);
    expect(store.stored?.accessToken, 'next');
    expect(auth.current?.accessToken, 'next');
    expect(ready, [AuthSessionChange.signedIn]);
  });

  test('failed secure save does not poison the following logout', () async {
    startWithSession(credentials('old'));
    store.saveFailure = StateError('secure storage unavailable');
    await expectLater(
      auth.persistRefreshedSession(credentials('fresh')),
      throwsStateError,
    );
    expect(auth.current, isNull);
    expect(api.appliedSession, isNull);
    expect(auth.lastError, contains('无法安全保存'));
    await auth.logout();
    expect(store.stored, isNull);
    expect(store.clearCalls, 2);
    expect(auth.current, isNull);
  });

  test(
    'failed login persistence clears credentials and a later login succeeds',
    () async {
      store.saveFailure = StateError('secure storage unavailable');
      api.loginReply.complete(credentials('first'));
      expect(await auth.login('owner@example.test', 'password'), isNull);
      expect(auth.current, isNull);
      expect(api.appliedSession, isNull);
      expect(store.stored, isNull);
      expect(auth.loading, isFalse);
      expect(auth.lastError, contains('无法安全保存'));
      expect(store.writes, ['save:first', 'clear']);

      store.saveFailure = null;
      api.loginReply = Completer<AuthSession>()
        ..complete(credentials('second'));
      expect(
        (await auth.login('owner@example.test', 'password'))?.accessToken,
        'second',
      );
      expect(store.stored?.accessToken, 'second');
      expect(api.appliedSession?.accessToken, 'second');
      expect(auth.lastError, isNull);
    },
  );

  test('late restore read cannot refresh credentials after logout', () async {
    store.readGate = Completer<AuthSession?>();
    final restored = auth.restore();
    await store.readStarted.future;
    await auth.logout();
    store.readGate!.complete(credentials('saved'));
    await restored;
    expect(api.refreshCalls, 0);
    expect(auth.current, isNull);
    expect(store.stored, isNull);
    expect(auth.pendingBiometricSession, isNull);
  });

  test(
    'late native biometric success cannot unlock a logged-out account',
    () async {
      auth
        ..pendingBiometricSession = credentials('saved')
        ..biometricLoginEnabled = true
        ..biometricSessionLocked = true;
      store.authenticationGate = Completer<bool>();
      final unlock = auth.unlockBiometricSession();
      await store.authenticationStarted.future;
      await auth.logout();
      store.authenticationGate!.complete(true);
      expect(await unlock, isFalse);
      expect(api.refreshCalls, 0);
      expect(auth.current, isNull);
      expect(auth.requiresBiometricUnlock, isFalse);
    },
  );

  test(
    'failed credential clearing keeps a previously locked screen protected',
    () async {
      startWithSession(credentials('saved'));
      auth
        ..biometricLoginEnabled = true
        ..biometricSessionLocked = true;
      store.clearFailure = StateError('secure storage unavailable');
      await expectLater(auth.logout(), throwsStateError);
      expect(auth.current, isNull);
      expect(api.appliedSession, isNull);
      expect(auth.requiresBiometricUnlock, isTrue);
      expect(auth.lastError, contains('无法清除'));
    },
  );

  test('disabling biometrics saves the latest refreshed token', () async {
    startWithSession(credentials('old'));
    auth.biometricLoginEnabled = true;
    store.clearGate = Completer<void>();
    final disabled = auth.disableBiometricLogin();
    await store.clearStarted.future;
    final refresh = auth.persistRefreshedSession(credentials('fresh'));
    store.clearGate!.complete();
    expect(await disabled, isTrue);
    await refresh;
    expect(auth.biometricLoginEnabled, isFalse);
    expect(store.stored?.accessToken, 'fresh');
    expect(store.writes, isNot(contains('save:old')));
  });

  test(
    'logout queues its clear behind an active biometric preference write',
    () async {
      startWithSession(credentials('old'));
      store.enableGate = Completer<void>();
      final enabled = auth.enableBiometricLogin();
      await store.enableStarted.future;
      final logout = auth.logout();
      expect(auth.current, isNull);
      store.enableGate!.complete();
      expect(await enabled, isFalse);
      await logout;
      expect(auth.biometricLoginEnabled, isFalse);
      expect(store.enabled, isFalse);
      expect(store.writes, ['enable', 'clear']);
    },
  );

  test(
    'temporary refresh failure keeps the cold biometric session recoverable',
    () async {
      store
        ..stored = credentials('saved')
        ..enabled = true;
      api.refreshFailure = ApiException(503, 'offline');
      await auth.restore();
      expect(auth.current, isNull);
      expect(auth.requiresBiometricUnlock, isTrue);
      expect(await auth.unlockBiometricSession(), isFalse);
      expect(auth.biometricUnlockError, contains('网络暂不可用'));
      expect(store.clearCalls, 0);
      expect(store.stored?.accessToken, 'saved');
      api.refreshFailure = null;
      expect(await auth.unlockBiometricSession(), isTrue);
      expect(auth.current?.accessToken, 'refreshed');
      expect(auth.requiresBiometricUnlock, isFalse);
    },
  );

  test('secure preference read failure cannot bypass the local lock', () async {
    store
      ..stored = credentials('saved')
      ..preferenceReadFailure = StateError('keychain unavailable');
    await auth.restore();
    expect(api.refreshCalls, 0);
    expect(auth.current, isNull);
    expect(auth.lastError, contains('无法读取安全登录资料'));
    expect(store.stored?.accessToken, 'saved');
  });

  test('foreign-user refresh is ignored without writing credentials', () async {
    startWithSession(credentials('active'));
    final foreign = credentials('foreign', userId: 8);
    api.setSession(foreign);
    await expectLater(
      auth.persistRefreshedSession(foreign),
      throwsFormatException,
    );
    expect(auth.current?.accessToken, 'active');
    expect(api.appliedSession?.accessToken, 'active');
    expect(store.writes, isEmpty);
    expect(ready, isEmpty);
  });

  test(
    'constructor session restores credentials without queries or writes',
    () {
      startWithSession(credentials('seed'));
      expect(auth.current?.accessToken, 'seed');
      expect(api.appliedSession, same(auth.current));
      expect(ready, isEmpty);
      expect(store.writes, isEmpty);
      expect(api.refreshCalls, 0);
    },
  );

  for (final userId in [0, -1]) {
    test('constructor rejects invalid user $userId', () {
      expect(
        () => createAuth(initialSession: credentials('seed', userId: userId)),
        throwsStateError,
      );
      expect(api.appliedSession, isNull);
      expect(store.writes, isEmpty);
    });
  }

  for (final missingAccessToken in [true, false]) {
    test(
      'constructor rejects missing ${missingAccessToken ? 'access' : 'refresh'} token',
      () {
        final valid = credentials('seed');
        expect(
          () => createAuth(
            initialSession: AuthSession(
              user: valid.user,
              accessToken: missingAccessToken ? ' ' : valid.accessToken,
              refreshToken: missingAccessToken ? valid.refreshToken : '',
            ),
          ),
          throwsStateError,
        );
        expect(api.appliedSession, isNull);
        expect(store.writes, isEmpty);
      },
    );
  }

  test('invalid refresh tokens cannot replace the API credentials', () async {
    final active = credentials('active');
    startWithSession(active);
    final malformed = AuthSession(
      user: active.user,
      accessToken: '',
      refreshToken: 'incomplete',
    );
    api.setSession(malformed);
    await expectLater(api.onSessionRefreshed!(malformed), throwsStateError);
    expect(auth.current, same(active));
    expect(api.appliedSession, same(active));
    expect(store.writes, isEmpty);
  });
}

class AuthenticationApi extends ApiClient {
  AuthenticationApi() : super(const AppConfig());

  Completer<AuthSession> loginReply = Completer<AuthSession>();
  final loginStarted = Completer<void>();
  int refreshCalls = 0;
  ApiException? refreshFailure;
  AuthSession? appliedSession;

  @override
  void setSession(AuthSession? session) {
    appliedSession = session;
    super.setSession(session);
  }

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) {
    if (!loginStarted.isCompleted) loginStarted.complete();
    return loginReply.future;
  }

  @override
  Future<AuthSession> refresh(String refreshToken) async {
    refreshCalls++;
    final error = refreshFailure;
    if (error != null) throw error;
    return credentials('refreshed');
  }
}

class DelayedSessionStore implements SessionStore {
  AuthSession? stored;
  bool enabled = false;
  final writes = <String>[];
  int clearCalls = 0;
  Completer<AuthSession?>? readGate;
  Completer<void>? saveGate, clearGate, enableGate;
  Completer<bool>? authenticationGate;
  Object? saveFailure, clearFailure, preferenceReadFailure;
  final readStarted = Completer<void>();
  final saveStarted = Completer<void>();
  final clearStarted = Completer<void>();
  final enableStarted = Completer<void>();
  final authenticationStarted = Completer<void>();

  @override
  Future<AuthSession?> readSession() async {
    if (!readStarted.isCompleted) readStarted.complete();
    return readGate == null ? stored : readGate!.future;
  }

  @override
  Future<void> saveSession(AuthSession session) async {
    writes.add('save:${session.accessToken}');
    if (!saveStarted.isCompleted) saveStarted.complete();
    await saveGate?.future;
    final error = saveFailure;
    if (error != null) throw error;
    stored = session;
  }

  @override
  Future<void> clear() async {
    clearCalls++;
    writes.add('clear');
    if (!clearStarted.isCompleted) clearStarted.complete();
    await clearGate?.future;
    final error = clearFailure;
    if (error != null) throw error;
    stored = null;
    enabled = false;
  }

  @override
  Future<bool> biometricEnabled() async {
    final error = preferenceReadFailure;
    if (error != null) throw error;
    return enabled;
  }

  @override
  Future<bool> canUseBiometrics() async => true;

  @override
  Future<bool> authenticateBiometric() async {
    if (!authenticationStarted.isCompleted) authenticationStarted.complete();
    return authenticationGate == null ? true : authenticationGate!.future;
  }

  @override
  Future<void> enableBiometric() async {
    writes.add('enable');
    if (!enableStarted.isCompleted) enableStarted.complete();
    await enableGate?.future;
    enabled = true;
  }
}
