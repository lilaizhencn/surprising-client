import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surprising_client/src/account/account_switch_sheet.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/auth/auth_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';
import 'package:surprising_client/src/telegram_login.dart';

import 'support/authentication.dart';

const parent = AuthSession(
  user: AuthUser(userId: 7, username: 'Owner', email: '', status: 'NORMAL'),
  accessToken: 'test-login-token',
);
AuthSession selected(
  int id, {
  String status = 'ACTIVE',
  String permissions = 'TRADING',
}) => AuthSession(
  user: parent.user,
  accessToken: '',
  operatingAccount: OperatingAccount(
    userId: id,
    parent: id == 7,
    name: id == 7 ? 'Owner' : 'Bot',
    status: status,
    permissions: permissions,
  ),
);

class SwitchApi extends ApiClient {
  SwitchApi() : super(const AppConfig());
  AuthSession response = selected(21);
  Object? failure;
  Completer<AuthSession>? gate;
  final requested = <int>[];
  @override
  Future<AuthSession> switchOperatingAccount(int userId) async {
    requested.add(userId);
    if (failure != null) throw failure!;
    return gate?.future ?? response;
  }

  @override
  Future<AuthSession> currentSession() async => response;
  @override
  Future<List<SubAccountModel>> loadSubAccounts(
    int parentUserId, {
    String? productLine,
  }) async => [
    SubAccountModel(
      id: 1,
      parentUserId: 7,
      subUserId: 21,
      subAccountName: 'Bot',
      permissions: 'READONLY',
      status: 'FROZEN',
      createdAt: '2026-01-01T00:00:00Z',
    ),
  ];
}

class Settings implements ClientSettingsStore {
  @override
  Future<Map<String, String>> read() async => {};
  @override
  Future<void> write(Map<String, String> values) async {}
}

class Socket extends RealtimeClient {
  Socket() : super(const AppConfig());
  final users = <int?>[];
  final events = <void Function(Map<String, dynamic>)>[];
  int closed = 0;
  @override
  Future<void> connect({
    int? userId,
    String? accessToken,
    required void Function(Map<String, dynamic>) onEvent,
    required void Function(Object) onError,
    void Function()? onDone,
  }) async {
    users.add(userId);
    events.add(onEvent);
    onEvent({'op': 'authenticated', 'userId': userId});
  }

  @override
  Future<void> close() async {
    closed++;
  }
}

class SwitchingApp extends AppState {
  SwitchingApp(SwitchApi api, Socket socket)
    : super(
        apiClient: api,
        realtimeClient: socket,
        initialSession: parent,
        sessionStore: MemorySessionStore(),
        settingsStore: Settings(),
        seedInstruments: [fallbackInstruments().first],
        config: const AppConfig(websocketUrl: 'ws://127.0.0.1:1/test'),
      );
  final refreshedUsers = <int?>[];
  @override
  Future<void> refreshPrivateData() async {
    // These assertions run before any new-account data is fetched.
    expect(balances, isEmpty);
    expect(positions, isEmpty);
    expect(openOrders, isEmpty);
    refreshedUsers.add(userId);
  }

  @override
  Future<void> refreshProductAvailability() async {}
  @override
  Future<void> refreshAnnouncements() async {}
}

void main() {
  test('inconsistent server identity never replaces the login session', () {
    final invalid = AuthSession(
      user: parent.user,
      accessToken: '',
      operatingAccount: const OperatingAccount(userId: 21, parent: true),
    );
    expect(() => parent.withServerSession(invalid), throwsFormatException);
  });

  test(
    'session serialization keeps parent login and operating account separately',
    () {
      final sub = parent.withServerSession(
        selected(21, status: 'FROZEN', permissions: 'READONLY'),
      );
      final restored = AuthSession.fromJson(sub.toJson());
      expect(restored.user.userId, 7);
      expect(restored.operatingUserId, 21);
      expect(restored.operatingAccount!.status, 'FROZEN');
      expect(restored.operatingAccount!.permissions, 'READONLY');
      expect(restored.accessToken, parent.accessToken);
      expect(AuthSession.fromJson(parent.toJson()).operatingUserId, 7);
    },
  );

  test(
    'switch and back clears private data and reconnects with operating user',
    () async {
      final api = SwitchApi(), socket = Socket();
      final state = SwitchingApp(api, socket);
      addTearDown(state.dispose);
      expect(await state.auth.switchOperatingAccount(21), true);
      expect(state.loginUserId, 7);
      expect(state.userId, 21);
      expect(socket.users, [21]);
      expect(state.refreshedUsers, [21]);
      final oldEvent = socket.events.single;
      api.response = selected(7);
      state.balances = const [
        ProductBalance(
          accountType: 'SPOT',
          asset: 'USDT',
          availableUnits: 100,
          lockedUnits: 0,
          equityUnits: 100,
        ),
      ];
      expect(await state.auth.switchOperatingAccount(7), true);
      expect(socket.users, [21, 7]);
      expect(socket.closed, greaterThanOrEqualTo(2));
      oldEvent({
        'op': 'snapshot',
        'userId': 21,
        'productLine': 'SPOT',
        'data': {
          'account': {
            'balances': [
              {'asset': 'USDT', 'availableUnits': 999},
            ],
            'positions': [],
          },
        },
      });
      expect(state.balances, isEmpty);
      expect(state.userId, 7);
    },
  );

  test(
    'restore uses server selection instead of stale locally saved selection',
    () async {
      final api = SwitchApi();
      final store = MemorySessionStore(initialSession: parent);
      final auth = AuthState(
        api: api,
        sessionStore: store,
        telegramLoginStore: TelegramLoginStore(),
      );
      addTearDown(auth.dispose);
      await auth.restore();
      expect(auth.current!.user.userId, 7);
      expect(auth.current!.operatingUserId, 21);
      expect(store.stored!.operatingUserId, 21);
      expect(store.stored!.accessToken, parent.accessToken);
    },
  );

  test(
    'denied switch does not change displayed account; ambiguous response fails closed',
    () async {
      final api = SwitchApi();
      final auth = AuthState(
        api: api,
        sessionStore: MemorySessionStore(),
        telegramLoginStore: TelegramLoginStore(),
        initialSession: parent,
      );
      addTearDown(auth.dispose);
      api.failure = ApiException(403, 'not owned', fromGateway: true);
      expect(await auth.switchOperatingAccount(21), false);
      expect(auth.current!.operatingUserId, 7);
      api.failure = const SocketException('response lost');
      expect(await auth.switchOperatingAccount(21), false);
      expect(auth.current, isNull);
    },
  );

  test(
    'switch ignores late response after logout and prevents double submission',
    () async {
      final api = SwitchApi()..gate = Completer<AuthSession>();
      final auth = AuthState(
        api: api,
        sessionStore: MemorySessionStore(),
        telegramLoginStore: TelegramLoginStore(),
        initialSession: parent,
      );
      addTearDown(auth.dispose);
      final switching = auth.switchOperatingAccount(21);
      expect(await auth.switchOperatingAccount(22), false);
      await auth.expire();
      api.gate!.complete(selected(21));
      expect(await switching, false);
      expect(auth.current, isNull);
      expect(api.requested, [21]);
    },
  );

  testWidgets(
    'profile second-level switcher lists frozen sub and current account; failure stays open',
    (tester) async {
      final api = SwitchApi()
        ..failure = ApiException(403, 'not owned', fromGateway: true);
      final state = SwitchingApp(api, Socket());
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AccountSwitchSheet(state: state)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('主账号'), findsOneWidget);
      expect(find.text('Bot'), findsOneWidget);
      expect(find.textContaining('已冻结'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('Bot'));
      await tester.pumpAndSettle();
      expect(state.userId, 7);
      expect(find.textContaining('切换未完成'), findsOneWidget);
      expect(find.text('Bot'), findsOneWidget);
    },
  );
  testWidgets(
    'compact profile sheet switches both ways and closes on success',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final api = SwitchApi()
        ..response = selected(21, status: 'FROZEN', permissions: 'READONLY');
      final state = SwitchingApp(api, Socket());
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.5)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAccountSwitchSheet(context, state),
                child: const Text('Open switcher'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open switcher'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bot'));
      await tester.pumpAndSettle();
      expect(state.userId, 21);
      expect(find.byType(AccountSwitchSheet), findsNothing);
      await tester.tap(find.text('Open switcher'));
      await tester.pumpAndSettle();
      final selectedTile = tester.widget<ListTile>(
        find.ancestor(of: find.text('Bot'), matching: find.byType(ListTile)),
      );
      expect((selectedTile.trailing as Icon).icon, Icons.check);
      api.response = selected(7);
      await tester.tap(find.text('主账号'));
      await tester.pumpAndSettle();
      expect(state.userId, 7);
      expect(api.requested, [21, 7]);
      expect(find.byType(AccountSwitchSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
