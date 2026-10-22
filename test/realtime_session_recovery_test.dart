import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

import 'financial_boundary_test.dart' as boundary;

const _user = AuthUser(
  userId: 7,
  username: 'session-test',
  email: '',
  status: 'ACTIVE',
);
const _original = AuthSession(
  user: _user,
  accessToken: 'original-access',
  refreshToken: 'original-refresh',
);
const _rotated = AuthSession(
  user: _user,
  accessToken: 'rotated-access',
  refreshToken: 'rotated-refresh',
);

class _RefreshApi extends ApiClient {
  _RefreshApi() : super(const AppConfig());
  final refreshTokens = <String>[];
  Future<AuthSession> Function()? reply;

  @override
  Future<AuthSession> refresh(String refreshToken) {
    refreshTokens.add(refreshToken);
    return reply?.call() ?? Future.value(_rotated);
  }
}

class _Realtime extends RealtimeClient {
  _Realtime() : super(const AppConfig());
  final connections = <({int? userId, String? accessToken})>[];
  void Function()? disconnected;
  int? _lastCloseCode;
  final resubscriptions = <Map<String, String>>[];

  @override
  void resubscribe(Map<String, String> subscription) {
    resubscriptions.add({...subscription});
  }

  @override
  int? get closeCode => _lastCloseCode;

  @override
  Future<void> connect({
    int? userId,
    String? accessToken,
    required void Function(Map<String, dynamic>) onEvent,
    required void Function(Object) onError,
    void Function()? onDone,
  }) async {
    connections.add((userId: userId, accessToken: accessToken));
    disconnected = onDone;
    _lastCloseCode = null;
  }

  void revoke() {
    _lastCloseCode = 1008;
    disconnected?.call();
  }

  @override
  Future<void> close() async {
    disconnected = null;
  }
}

class _SessionStore implements SessionStore {
  final saved = <AuthSession>[];
  AuthSession? persisted;
  Completer<void>? saveGate;
  var clears = 0;

  @override
  Future<void> saveSession(AuthSession session) async {
    saved.add(session);
    await saveGate?.future;
    persisted = session;
  }

  @override
  Future<void> clear() async {
    clears++;
    persisted = null;
  }

  @override
  Future<AuthSession?> readSession() async => persisted;
  @override
  Future<bool> authenticateBiometric() async => false;
  @override
  Future<bool> biometricEnabled() async => false;
  @override
  Future<bool> canUseBiometrics() async => false;
  @override
  Future<void> enableBiometric() async {}
}

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => {...values};
  @override
  Future<void> write(Map<String, String> values) async {
    this.values = {...values};
  }
}

class _State extends AppState {
  _State(
    _RefreshApi api,
    _Realtime realtime,
    _SessionStore store, {
    super.initialSession,
  }) : super(
         apiClient: api,
         realtimeClient: realtime,
         sessionStore: store,
         settingsStore: _Settings(),
         seedInstruments: [fallbackInstruments().first],
         config: const AppConfig(websocketUrl: 'ws://127.0.0.1:1/test'),
       );

  @override
  Future<void> refreshInstruments({bool silent = false}) async {}
  @override
  Future<void> refreshPublicData({bool silent = false}) async {}
  @override
  Future<void> refreshPrivateData() async {}
  @override
  Future<void> refreshAnnouncements() async {}
  @override
  Future<void> refreshProductAvailability() async {}
}

class _Fixture {
  final api = _RefreshApi();
  final realtime = _Realtime();
  final store = _SessionStore();
  late final state = _State(initialSession: _original, api, realtime, store);
  bool _disposed = false;

  Future<void> start(WidgetTester tester) async {
    api.setSession(_original);
    await state.selectMode(ProductMode.linear);
    await flush(tester);
    expect(realtime.connections, [(userId: 7, accessToken: 'original-access')]);
  }

  Future<void> flush(
    WidgetTester tester, [
    Duration elapsed = Duration.zero,
  ]) async {
    await tester.pump(elapsed);
    if (!_disposed) {
      // These tests isolate session recovery from depth's independent watchdog.
      state.market.resetBook(OrderBook.empty(state.selectedSymbol));
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    state.dispose();
  }
}

void main() {
  testWidgets(
    'invalid delta versions immediately start bounded account recovery',
    (tester) async {
      final f = _Fixture();
      try {
        await f.start(tester);
        Map<String, dynamic> snapshot(int sequence) =>
            boundary.snapshot(sequence)
              ..['userId'] = 7
              ..['productLine'] = ProductMode.linear.productLine;
        f.state.handleRealtimeMessage(snapshot(1));
        final view = f.state.privateViews[ProductMode.linear]!;
        expect(view.ready, isTrue);
        for (final product in ProductMode.values.where(
          (product) => product != ProductMode.linear,
        )) {
          f.state.handleRealtimeMessage({
            'op': 'snapshot',
            'productLine': product.productLine,
            'userId': 7,
            'data': {'status': 'INITIALIZING'},
          });
        }
        f.state.handleRealtimeMessage({
          'op': 'event',
          'channel': 'accountState',
          'productLine': ProductMode.linear.productLine,
          'userId': 7,
          'data': {'version': 'broken'},
        });
        expect(view.ready, isFalse);
        expect(view.fence, boundary.version(1));
        expect(f.realtime.resubscriptions, hasLength(1));
        await f.flush(tester, const Duration(seconds: 3));
        expect(f.realtime.resubscriptions, hasLength(2));
        f.state.handleRealtimeMessage(snapshot(2));
        expect(view.ready, isTrue);
        await f.flush(tester, const Duration(seconds: 6));
        expect(f.realtime.resubscriptions, hasLength(2));
        f.state.handleRealtimeMessage({
          'op': 'snapshot',
          'productLine': ProductMode.spot.productLine,
          'userId': 7,
          'data': {'status': 'INITIALIZING'},
        });
        expect(f.state.privateViews[ProductMode.spot]!.status, 'INITIALIZING');
      } finally {
        f.dispose();
      }
    },
  );

  test(
    'malformed realtime identities cannot authenticate or create account views',
    () {
      final state = AppState(initialSession: _original, offline: true);
      addTearDown(state.dispose);
      for (final invalid in [
        null,
        'not-a-user',
        '7.5',
        7.5,
        double.infinity,
        true,
        '9223372036854775808',
      ]) {
        for (final operation in ['authenticated', 'snapshot', 'event']) {
          expect(
            () => state.handleRealtimeMessage({
              'op': operation,
              'channel': 'accountState',
              'userId': invalid,
              'productLine': ProductMode.linear.productLine,
              'data': <String, dynamic>{},
            }),
            returnsNormally,
          );
        }
      }
      expect(state.session, same(_original));
      expect(state.privateViews, isEmpty);
      expect(state.assetsReady, isFalse);
    },
  );

  testWidgets(
    '1008 refreshes the original token and reconnects with the rotated session',
    (tester) async {
      final f = _Fixture();
      try {
        await f.start(tester);
        f.realtime.revoke();
        await f.flush(tester);
        expect(f.api.refreshTokens, ['original-refresh']);
        expect(f.state.session, same(_rotated));
        expect(f.store.persisted, same(_rotated));
        expect(f.store.saved, [_rotated]);
        expect(f.realtime.connections, [
          (userId: 7, accessToken: 'original-access'),
          (userId: 7, accessToken: 'rotated-access'),
        ]);
      } finally {
        f.dispose();
      }
    },
  );

  for (final status in [401, 403]) {
    testWidgets(
      '1008 followed by refresh $status clears session and resumes public traffic',
      (tester) async {
        final f = _Fixture();
        f.api.reply = () =>
            Future.error(ApiException(status, 'session revoked'));
        try {
          await f.start(tester);
          f.realtime.revoke();
          await f.flush(tester);
          expect(f.api.refreshTokens, ['original-refresh']);
          expect(f.state.session, isNull);
          expect(f.store.persisted, isNull);
          expect(f.store.saved, isEmpty);
          expect(f.store.clears, 1);
          expect(f.realtime.connections.last, (
            userId: null,
            accessToken: null,
          ));
          await f.flush(tester, const Duration(minutes: 1));
          expect(f.api.refreshTokens, hasLength(1));
          expect(
            f.realtime.connections.skip(1).every((c) => c.accessToken == null),
            isTrue,
          );
        } finally {
          f.dispose();
        }
      },
    );
  }

  testWidgets(
    '503 retains session, resumes public without the old token, and stops after three retries',
    (tester) async {
      final f = _Fixture();
      f.api.reply = () => Future.error(ApiException(503, 'temporary outage'));
      try {
        await f.start(tester);
        f.realtime.revoke();
        await f.flush(tester);
        expect(f.api.refreshTokens, hasLength(1));
        expect(f.state.session, same(_original));
        expect(f.realtime.connections.last, (userId: null, accessToken: null));
        for (final seconds in [1, 2, 4]) {
          await f.flush(tester, Duration(seconds: seconds));
        }
        expect(f.api.refreshTokens, List.filled(4, 'original-refresh'));
        expect(f.state.session, same(_original));
        expect(f.store.clears, 0);
        expect(f.store.saved, isEmpty);
        expect(f.state.assetsReady, isFalse);
        expect(f.state.lastError, contains('私有操作暂不可用'));
        expect(
          f.realtime.connections
              .skip(1)
              .every((c) => c.userId == null && c.accessToken == null),
          isTrue,
        );
        await f.flush(tester, const Duration(minutes: 1));
        expect(f.api.refreshTokens, hasLength(4));
      } finally {
        f.dispose();
      }
    },
  );

  testWidgets(
    'a refresh response arriving after logout cannot restore credentials or reconnect privately',
    (tester) async {
      final f = _Fixture();
      final response = Completer<AuthSession>();
      f.api.reply = () => response.future;
      try {
        await f.start(tester);
        f.realtime.revoke();
        await f.flush(tester);
        expect(f.api.refreshTokens, hasLength(1));
        await f.state.logout();
        await f.flush(tester);
        final connectionCount = f.realtime.connections.length;
        response.complete(_rotated);
        await f.flush(tester);
        expect(f.state.session, isNull);
        expect(f.store.persisted, isNull);
        expect(f.store.saved, isEmpty);
        expect(f.realtime.connections, hasLength(connectionCount));
        expect(f.realtime.connections.last, (userId: null, accessToken: null));
        expect(tester.takeException(), isNull);
      } finally {
        f.dispose();
      }
    },
  );

  testWidgets(
    'a refresh response arriving after disposal cannot save or reconnect',
    (tester) async {
      final f = _Fixture();
      final response = Completer<AuthSession>();
      f.api.reply = () => response.future;
      try {
        await f.start(tester);
        f.realtime.revoke();
        await f.flush(tester);
        expect(f.api.refreshTokens, hasLength(1));
        f.dispose();
        response.complete(_rotated);
        await f.flush(tester);
        expect(f.state.session, same(_original));
        expect(f.store.saved, isEmpty);
        expect(f.realtime.connections, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        f.dispose();
      }
    },
  );

  testWidgets(
    'a session save completing after logout cannot overwrite cleared storage',
    (tester) async {
      final f = _Fixture();
      final save = Completer<void>();
      f.store.saveGate = save;
      try {
        await f.start(tester);
        f.realtime.revoke();
        await f.flush(tester);
        expect(f.store.saved, [_rotated]);
        final loggingOut = f.state.logout();
        await f.flush(tester);
        expect(f.state.session, isNull);
        save.complete();
        await loggingOut;
        await f.flush(tester);
        final connectionCount = f.realtime.connections.length;
        await f.flush(tester);
        expect(f.state.session, isNull);
        expect(f.store.persisted, isNull);
        expect(f.realtime.connections, hasLength(connectionCount));
        expect(tester.takeException(), isNull);
      } finally {
        if (!save.isCompleted) save.complete();
        f.dispose();
      }
    },
  );
}
