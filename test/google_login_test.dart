import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/auth/auth_state.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/google_login.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/telegram_login.dart';
import 'support/authentication.dart';

const session = AuthSession(
  user: AuthUser(
    userId: 7,
    username: '',
    email: '',
    displayName: 'Google 用户 🚀',
    status: 'NORMAL',
  ),
  accessToken: 'access',
  refreshToken: 'refresh',
);
GoogleLoginConfig configuration() => GoogleLoginConfig.fromJson({
  'enabled': true,
  'webClientId': 'web.apps.googleusercontent.com',
  'iosClientId': 'ios.apps.googleusercontent.com',
  'androidEnabled': true,
  'iosEnabled': true,
});

class LocalGoogleHttp extends HttpOverrides {}

class GoogleApi extends TestApiClient {
  Map<String, dynamic> result = session.toJson();
  final requests = <(String, Map<String, dynamic>)>[];
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = false,
  }) async {
    requests.add((path, body));
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'native Google requests omit an old bearer while private API requests keep it',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final seen = <String, String?>{};
      server.listen((request) async {
        seen[request.uri.path] = request.headers.value(
          HttpHeaders.authorizationHeader,
        );
        await utf8.decoder.bind(request).join();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: LocalGoogleHttp().createHttpClient(null),
      );
      try {
        api.setSession(session);
        await api.get('/api/v1/auth/google/config');
        await api.get('/api/v1/fixture-private');
        expect(seen['/api/v1/auth/google/config'], isNull);
        expect(seen['/api/v1/fixture-private'], 'Bearer access');
      } finally {
        api.dispose();
        await server.close(force: true);
      }
    },
  );
  test(
    'Android and iOS send the native ID token to the same session boundary',
    () async {
      for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
        debugDefaultTargetPlatformOverride = platform;
        final api = GoogleApi();
        final result = await signInWithGoogle(
          api: api,
          config: configuration(),
          cancelled: () => false,
          authenticate: (_) async => 'signed-native-token',
          inviteCode: 'INVITE',
        );
        expect(result.user.name, 'Google 用户 🚀');
        expect(api.requests.single.$1, '/api/v1/auth/google/login');
        expect(api.requests.single.$2, {
          'credential': 'signed-native-token',
          'platform': platform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
          'inviteCode': 'INVITE',
        });
        api.dispose();
      }
    },
  );
  test(
    'closing the sheet during native selection cannot send or activate a late token',
    () async {
      final api = GoogleApi();
      var cancelled = false;
      final selected = Completer<String>();
      final result = signInWithGoogle(
        api: api,
        config: configuration(),
        cancelled: () => cancelled,
        authenticate: (_) => selected.future,
      );
      final checked = expectLater(result, throwsA(isA<GoogleLoginCancelled>()));
      cancelled = true;
      selected.complete('late-token');
      await checked;
      expect(api.requests, isEmpty);
      api.dispose();
    },
  );
  test('MFA response remains a challenge without saved credentials', () async {
    final api = GoogleApi()
      ..result = {
        'requiresVerification': true,
        'challengeToken': 'challenge',
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'methods': [
          {'type': 'TOTP'},
        ],
      };
    final storage = MemorySessionStore();
    final auth = AuthState(
      api: api,
      sessionStore: storage,
      telegramLoginStore: TelegramLoginStore(),
    );
    await auth.loginGoogle(
      () => signInWithGoogle(
        api: api,
        config: configuration(),
        cancelled: () => false,
        authenticate: (_) async => 'token',
      ),
    );
    expect(auth.current, isNull);
    expect(auth.pendingLoginChallenge, isNotNull);
    expect(storage.stored, isNull);
    auth.dispose();
    api.dispose();
  });
  test(
    'Google success persists the session and cancellation has no error',
    () async {
      final api = GoogleApi();
      final storage = MemorySessionStore();
      final auth = AuthState(
        api: api,
        sessionStore: storage,
        telegramLoginStore: TelegramLoginStore(),
      );
      expect(
        await auth.loginGoogle(() async => throw const GoogleLoginCancelled()),
        isNull,
      );
      expect(auth.lastError, isNull);
      expect(await auth.loginGoogle(() async => session), same(session));
      expect(storage.stored, same(session));
      expect(auth.loading, isFalse);
      auth.dispose();
      api.dispose();
    },
  );
  test('an old Google selection cannot restore a logged-out session', () async {
    final api = GoogleApi();
    final storage = MemorySessionStore();
    final auth = AuthState(
      api: api,
      sessionStore: storage,
      telegramLoginStore: TelegramLoginStore(),
    );
    final selected = Completer<AuthSession>();
    final signingIn = auth.loginGoogle(() => selected.future);
    await Future<void>.delayed(Duration.zero);
    await auth.logout();
    selected.complete(session);
    await signingIn;
    expect(auth.current, isNull);
    expect(storage.stored, isNull);
    auth.dispose();
    api.dispose();
  });
  test(
    'iOS missing callback configuration is rejected before native SDK can throw',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      const channel = MethodChannel('surprising/google-login');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => false);
      await expectLater(
        NativeGoogleLogin().authenticate(configuration()),
        throwsStateError,
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );
}
