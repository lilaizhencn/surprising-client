import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

class TestApiClient extends ApiClient {
  TestApiClient([super.config = const AppConfig()]);

  AuthSession? loginResponse;

  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final response = loginResponse;
    if (response == null) {
      throw StateError('Configure the login response in this fixture');
    }
    return response;
  }

  @override
  Future<Set<ProductMode>> disabledProducts() async => {};

  @override
  Future<Map<String, dynamic>> announcements({
    required String locale,
    required String productLine,
    required String platform,
    required String placement,
    int offset = 0,
    int limit = 50,
  }) async => {
    'announcements': <Map<String, dynamic>>[],
    'hasMore': false,
    'unreadCount': 0,
  };
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore({AuthSession? initialSession}) : stored = initialSession;

  AuthSession? stored;
  bool enabled = false;

  @override
  Future<AuthSession?> readSession() async => stored;
  @override
  Future<void> saveSession(AuthSession session) async => stored = session;
  @override
  Future<void> clear() async {
    stored = null;
    enabled = false;
  }

  @override
  Future<bool> biometricEnabled() async => enabled;
  @override
  Future<bool> canUseBiometrics() async => false;
  @override
  Future<bool> authenticateBiometric() async => false;
  @override
  Future<void> enableBiometric() async => enabled = true;
}

Future<void> signInAs(AppState state, AuthSession session) async {
  final api = state.api;
  if (state.offline || api is! TestApiClient) {
    throw StateError(
      'A real authentication transition needs a controlled API and an online fixture',
    );
  }
  api.loginResponse = session;
  final authenticated = await state.login(
    session.user.username,
    'fixture-password',
  );
  if (!identical(authenticated, session) ||
      !identical(state.session, session)) {
    throw StateError(
      'The fixture login did not establish the requested account: ${state.lastError}',
    );
  }
}
