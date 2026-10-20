import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

void main() {
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState next) async {
    tester.binding.handleAppLifecycleStateChanged(next);
    await tester.pump();
  }

  Future<void> background(WidgetTester tester) async {
    await lifecycle(tester, AppLifecycleState.inactive);
    await lifecycle(tester, AppLifecycleState.hidden);
    await lifecycle(tester, AppLifecycleState.paused);
  }

  Future<void> settleAsync(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'a restored biometric session opens the system prompt automatically',
    (tester) async {
      final store = MemoryBiometricStore();
      final state = AppState(offline: true, sessionStore: store)
        ..pendingBiometricSession = savedSession
        ..biometricLoginEnabled = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await tester.pump();
      expect(store.authenticationCalls, 1);
      expect(find.text('验证身份以解锁'), findsOneWidget);
      expect(find.byType(ClientShell), findsNothing);
      store.authentication.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('验证身份以解锁'), findsOneWidget);
    },
  );
  testWidgets('cold launch restores tokens only after successful biometrics', (
    tester,
  ) async {
    final store = MemoryBiometricStore();
    final api = BiometricApi();
    final state = BootstrapState(store, api);
    await tester.pumpWidget(BootstrapHarness(state));
    await settleAsync(tester);
    expect(store.authenticationCalls, 1);
    expect(api.refreshCalls, 0);
    expect(state.session, isNull);
    expect(find.byType(ClientShell), findsNothing);
    store.authentication.complete(true);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 1);
    expect(state.session?.user.userId, savedSession.user.userId);
    expect(state.requiresBiometricUnlock, isFalse);
    expect(find.byType(ClientShell), findsOneWidget);
    expect(store.enabled, isTrue);
  });

  testWidgets('cancel stays locked without a prompt loop; retry can unlock', (
    tester,
  ) async {
    final store = MemoryBiometricStore();
    final state = AppState(offline: true, sessionStore: store)
      ..session = savedSession
      ..biometricLoginEnabled = true
      ..biometricSessionLocked = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );
    store.authentication.complete(false);
    await tester.pumpAndSettle();
    expect(find.text('验证已取消或未通过，请重试'), findsOneWidget);
    expect(store.authenticationCalls, 1);
    expect(find.byType(ClientShell), findsNothing);
    store.authentication = Completer<bool>();
    await tester.tap(find.text('验证解锁'));
    await tester.pump();
    expect(store.authenticationCalls, 2);
    await state.unlockBiometricSession();
    expect(store.authenticationCalls, 2);
    store.authentication.complete(true);
    await tester.pumpAndSettle();
    expect(state.requiresBiometricUnlock, isFalse);
    expect(find.byType(ClientShell), findsOneWidget);
  });

  testWidgets(
    'return from background locks nested routes and sheets then resumes them',
    (tester) async {
      final store = MemoryBiometricStore();
      final state = AppState(offline: true, sessionStore: store)
        ..session = savedSession
        ..biometricLoginEnabled = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      final context = tester.element(find.byType(ClientShell));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                const Scaffold(body: Text('private-account-details')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final detail = tester.element(find.text('private-account-details'));
      unawaited(
        showModalBottomSheet<void>(
          context: detail,
          builder: (_) =>
              const SizedBox(height: 100, child: Text('private-payment-sheet')),
        ),
      );
      await tester.pumpAndSettle();
      await background(tester);
      expect(state.requiresBiometricUnlock, isTrue);
      expect(store.authenticationCalls, 0);
      expect(find.text('private-account-details'), findsNothing);
      expect(find.text('private-payment-sheet'), findsNothing);
      await lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(store.authenticationCalls, 1);
      // The native prompt's inactive/resumed transitions must not open another prompt.
      await lifecycle(tester, AppLifecycleState.inactive);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(store.authenticationCalls, 1);
      store.authentication.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('private-account-details'), findsOneWidget);
      expect(find.text('private-payment-sheet'), findsOneWidget);
      expect(state.session?.refreshToken, savedSession.refreshToken);
    },
  );

  testWidgets(
    'inactive system UI is obscured without a new unlock requirement',
    (tester) async {
      final state =
          AppState(offline: true, sessionStore: MemoryBiometricStore())
            ..session = savedSession
            ..biometricLoginEnabled = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await lifecycle(tester, AppLifecycleState.inactive);
      expect(find.byType(ClientShell), findsNothing);
      expect(state.requiresBiometricUnlock, isFalse);
      await lifecycle(tester, AppLifecycleState.resumed);
      expect(find.byType(ClientShell), findsOneWidget);
      expect(state.biometricUnlocking, isFalse);
    },
  );

  testWidgets('a result delivered in background cannot unlock on resume', (
    tester,
  ) async {
    final store = MemoryBiometricStore();
    final state = AppState(offline: true, sessionStore: store)
      ..session = savedSession
      ..biometricLoginEnabled = true
      ..biometricSessionLocked = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );
    await background(tester);
    store.authentication.complete(true);
    await settleAsync(tester);
    expect(state.requiresBiometricUnlock, isTrue);
    store.authentication = Completer<bool>();
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(store.authenticationCalls, 2);
    store.authentication.complete(true);
    await tester.pumpAndSettle();
    expect(state.requiresBiometricUnlock, isFalse);
  });

  testWidgets('late authentication cannot revive a logged out account', (
    tester,
  ) async {
    final store = MemoryBiometricStore();
    final state = BootstrapState(store, BiometricApi())
      ..session = savedSession
      ..biometricLoginEnabled = true
      ..biometricSessionLocked = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );
    expect(store.authenticationCalls, 1);
    await state.logout();
    store.authentication.complete(true);
    await tester.pumpAndSettle();
    expect(state.session, isNull);
    expect(state.requiresBiometricUnlock, isFalse);
    expect(store.stored, isNull);
  });

  testWidgets('network failure keeps a cold session locked and recoverable', (
    tester,
  ) async {
    final store = MemoryBiometricStore();
    final api = BiometricApi()
      ..refreshError = ApiException(503, 'test unavailable');
    final state = BootstrapState(store, api);
    await tester.pumpWidget(BootstrapHarness(state));
    await settleAsync(tester);
    store.authentication.complete(true);
    await tester.pumpAndSettle();
    expect(state.session, isNull);
    expect(state.requiresBiometricUnlock, isTrue);
    expect(store.stored?.refreshToken, savedSession.refreshToken);
    expect(find.textContaining('网络暂不可用'), findsOneWidget);
    store.authentication = Completer<bool>();
    api.refreshError = null;
    await tester.tap(find.text('验证解锁'));
    store.authentication.complete(true);
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 2);
    expect(state.requiresBiometricUnlock, isFalse);
  });

  testWidgets('native error stays locked and offers account login', (
    tester,
  ) async {
    final store = MemoryBiometricStore();
    final state = BootstrapState(store, BiometricApi());
    await tester.pumpWidget(BootstrapHarness(state));
    await settleAsync(tester);
    store.authentication.completeError(StateError('test native lockout'));
    await tester.pumpAndSettle();
    expect(state.requiresBiometricUnlock, isTrue);
    expect(find.text('生物识别暂不可用，请重试或使用账号登录'), findsOneWidget);
    await tester.tap(find.text('使用账号密码登录'));
    await tester.pumpAndSettle();
    expect(state.requiresBiometricUnlock, isFalse);
    expect(find.byType(AuthSheet), findsOneWidget);
    expect(store.stored, isNull);
  });

  testWidgets('disabled biometrics do not prompt on launch or resume', (
    tester,
  ) async {
    final store = MemoryBiometricStore()..enabled = false;
    final api = BiometricApi();
    final state = BootstrapState(store, api);
    await tester.pumpWidget(BootstrapHarness(state));
    await tester.pumpAndSettle();
    expect(api.refreshCalls, 1);
    await background(tester);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(store.authenticationCalls, 0);
    expect(state.requiresBiometricUnlock, isFalse);
  });

  testWidgets(
    'capability failure cannot bypass a stored biometric preference',
    (tester) async {
      final store = MemoryBiometricStore()..capabilityError = true;
      final state = BootstrapState(store, BiometricApi());
      await tester.pumpWidget(BootstrapHarness(state));
      await settleAsync(tester);
      expect(state.biometricLoginAvailable, isFalse);
      expect(state.requiresBiometricUnlock, isTrue);
      expect(store.authenticationCalls, 1);
      store.authentication.complete(false);
      await tester.pumpAndSettle();
      expect(state.session, isNull);
    },
  );

  testWidgets('cold launch in background waits for a foreground frame', (
    tester,
  ) async {
    final store = MemoryBiometricStore()..readGate = Completer<AuthSession?>();
    final state = BootstrapState(store, BiometricApi());
    await tester.pumpWidget(BootstrapHarness(state));
    await background(tester);
    store.readGate!.complete(savedSession);
    await settleAsync(tester);
    expect(store.authenticationCalls, 0);
    expect(state.requiresBiometricUnlock, isTrue);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump();
    expect(store.authenticationCalls, 1);
    store.authentication.complete(false);
    await tester.pumpAndSettle();
    expect(state.requiresBiometricUnlock, isTrue);
  });

  testWidgets('server session expiry cannot reveal a locally locked route', (
    tester,
  ) async {
    final store = MemoryBiometricStore();
    final api = BiometricApi();
    final state = BootstrapState(store, api)
      ..session = savedSession
      ..biometricLoginEnabled = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );
    await background(tester);
    await api.onSessionExpired!();
    await tester.pump();
    expect(state.requiresBiometricUnlock, isTrue);
    expect(state.session, isNull);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(ClientShell), findsNothing);
    expect(find.text('登录状态已失效，请使用账号登录'), findsOneWidget);
    expect(store.authenticationCalls, 0);
    expect(find.text('使用账号密码登录').hitTestable(), findsOneWidget);
  });

  testWidgets(
    'a second foreground entry automatically retries a canceled prompt',
    (tester) async {
      final store = MemoryBiometricStore();
      final state = AppState(offline: true, sessionStore: store)
        ..session = savedSession
        ..biometricLoginEnabled = true
        ..biometricSessionLocked = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      store.authentication.complete(false);
      await tester.pumpAndSettle();
      store.authentication = Completer<bool>();
      await background(tester);
      await lifecycle(tester, AppLifecycleState.resumed);
      await tester.pump();
      expect(store.authenticationCalls, 2);
      store.authentication.complete(false);
      await tester.pumpAndSettle();
      expect(store.authenticationCalls, 2);
      expect(find.byType(ClientShell), findsNothing);
    },
  );

  testWidgets('a failed switch to password cannot reveal the account', (
    tester,
  ) async {
    final store = MemoryBiometricStore()..clearError = true;
    final state = BootstrapState(store, BiometricApi())
      ..session = savedSession
      ..biometricLoginEnabled = true
      ..biometricSessionLocked = true;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      SurprisingClientApp(state: state, bootstrap: false),
    );
    store.authentication.complete(false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用账号密码登录'));
    await tester.pumpAndSettle();
    expect(find.byType(ClientShell), findsNothing);
    expect(find.text('无法切换登录方式，请重试'), findsOneWidget);
    expect(state.requiresBiometricUnlock, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'native success during dialog dismissal waits for visible resume',
    (tester) async {
      final store = MemoryBiometricStore();
      final state = AppState(offline: true, sessionStore: store)
        ..session = savedSession
        ..biometricLoginEnabled = true
        ..biometricSessionLocked = true;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      await lifecycle(tester, AppLifecycleState.inactive);
      store.authentication.complete(true);
      await tester.pumpAndSettle();
      expect(find.byType(ClientShell), findsNothing);
      await lifecycle(tester, AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.byType(ClientShell), findsOneWidget);
      expect(store.authenticationCalls, 1);
    },
  );

  for (final theme in [ClientTheme.dark, ClientTheme.light]) {
    testWidgets('lock and cancellation at 320px, large text, ${theme.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final store = MemoryBiometricStore();
      final state = AppState(offline: true, sessionStore: store)
        ..session = savedSession
        ..biometricLoginEnabled = true
        ..biometricSessionLocked = true
        ..clientTheme = theme;
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(state: state, bootstrap: false),
      );
      store.authentication.complete(false);
      await tester.pumpAndSettle();
      expect(find.text('验证解锁').hitTestable(), findsOneWidget);
      expect(find.text('使用账号密码登录').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

const savedSession = AuthSession(
  user: AuthUser(
    userId: 7,
    username: 'biometric-test',
    email: 'biometric@example.test',
    status: 'NORMAL',
  ),
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
);

class MemoryBiometricStore implements SessionStore {
  AuthSession? stored = savedSession;
  Completer<AuthSession?>? readGate;
  bool enabled = true;
  int authenticationCalls = 0;
  bool capabilityError = false;
  bool clearError = false;
  Completer<bool> authentication = Completer<bool>();

  @override
  Future<AuthSession?> readSession() async =>
      readGate == null ? stored : await readGate!.future;
  @override
  Future<void> saveSession(AuthSession session) async => stored = session;
  @override
  Future<void> clear() async {
    if (clearError) throw StateError('test secure storage unavailable');
    stored = null;
    enabled = false;
  }

  @override
  Future<bool> biometricEnabled() async => enabled;
  @override
  Future<bool> canUseBiometrics() async {
    if (capabilityError) throw StateError('test capability unavailable');
    return true;
  }

  @override
  Future<bool> authenticateBiometric() {
    authenticationCalls++;
    return authentication.future;
  }

  @override
  Future<void> enableBiometric() async => enabled = true;
}

// Exercise the real secure-session restore/activation logic without market I/O.
class BootstrapState extends AppState {
  BootstrapState(MemoryBiometricStore store, BiometricApi api)
    : super(
        config: const AppConfig(websocketUrl: ''),
        apiClient: api,
        sessionStore: store,
        settingsStore: MemorySettings(),
        seedInstruments: fallbackInstruments(),
      );
  @override
  Future<void> refreshInstruments({bool silent = false}) async {}
  @override
  Future<void> refreshValuation({bool silent = false}) async {}
  @override
  Future<void> refreshPublicData({bool silent = false}) async {}
  @override
  Future<void> refreshAnnouncements() async {}
  @override
  Future<void> refreshPrivateData() async {}
  @override
  Future<void> refreshProductAvailability() async {}
}

class BiometricApi extends ApiClient {
  BiometricApi() : super(const AppConfig());
  int refreshCalls = 0;
  ApiException? refreshError;
  @override
  Future<AuthSession> refresh(String refreshToken) async {
    refreshCalls++;
    if (refreshError != null) throw refreshError!;
    return savedSession;
  }
}

class MemorySettings implements ClientSettingsStore {
  @override
  Future<Map<String, String>> read() async => {};
  @override
  Future<void> write(Map<String, String> values) async {}
}

class BootstrapHarness extends StatefulWidget {
  const BootstrapHarness(this.state, {super.key});
  final BootstrapState state;
  @override
  State<BootstrapHarness> createState() => _BootstrapHarnessState();
}

class _BootstrapHarnessState extends State<BootstrapHarness> {
  @override
  void dispose() {
    widget.state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SurprisingClientApp(state: widget.state);
}
