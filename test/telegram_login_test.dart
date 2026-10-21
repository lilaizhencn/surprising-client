import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/telegram_login.dart';

Map<String, dynamic> flow({String? url}) => {
  'flowId': 's' * 43,
  'verifier': 'v' * 43,
  'authorizationUrl': url ?? 'https://oauth.telegram.org/auth?state=test',
  'expiresAt': DateTime.now()
      .add(const Duration(minutes: 5))
      .toUtc()
      .toIso8601String(),
};

Map<String, dynamic> session() => {
  'user': {
    'userId': 7,
    'username': null,
    'email': null,
    'displayName': '小李 🚀',
    'status': 'NORMAL',
  },
  'accessToken': 'access',
  'refreshToken': 'refresh',
};

class TelegramApi extends ApiClient {
  TelegramApi(this.start, this.results) : super(const AppConfig());
  final Map<String, dynamic> start;
  final List<Map<String, dynamic>> results;
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
    if (path.endsWith('/start')) return start;
    return results.removeAt(0);
  }
}

void main() {
  test(
    'system browser authorization preserves nickname without password or email',
    () async {
      final api = TelegramApi(flow(), [
        {'pending': true},
        session(),
      ]);
      Uri? opened;
      final result = await signInWithTelegram(
        api: api,
        openBrowser: (uri) async {
          opened = uri;
          return true;
        },
        cancelled: () => false,
        pollInterval: Duration.zero,
      );
      expect(opened!.host, 'oauth.telegram.org');
      expect(result.user.name, '小李 🚀');
      expect(result.user.email, isEmpty);
      expect(result.requiresEmailVerification, isFalse);
      expect(AuthSession.fromJson(result.toJson()).user.name, '小李 🚀');
      expect(api.requests.first.$2, {'returnToApp': true});
      expect(api.requests[1].$2, {'flowId': 's' * 43, 'verifier': 'v' * 43});
      expect(api.requests.every((r) => !r.$2.containsKey('password')), isTrue);
    },
  );

  test(
    'rejects an untrusted authorization URL before opening browser',
    () async {
      final api = TelegramApi(flow(url: 'https://attacker.example/auth'), []);
      var opened = false;
      await expectLater(
        signInWithTelegram(
          api: api,
          openBrowser: (_) async {
            opened = true;
            return true;
          },
          cancelled: () => false,
        ),
        throwsFormatException,
      );
      expect(opened, isFalse);
    },
  );

  test(
    'configured MFA remains required after Telegram authorization',
    () async {
      final api = TelegramApi(flow(), [
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
      ]);
      await expectLater(
        signInWithTelegram(
          api: api,
          openBrowser: (_) async => true,
          cancelled: () => false,
        ),
        throwsA(isA<LoginChallenge>()),
      );
    },
  );

  test('closing the sheet cannot activate a late session', () async {
    final api = TelegramApi(flow(), [session()]);
    var cancelled = false;
    await expectLater(
      signInWithTelegram(
        api: api,
        openBrowser: (_) async {
          cancelled = true;
          return true;
        },
        cancelled: () => cancelled,
      ),
      throwsA(isA<TelegramLoginCancelled>()),
    );
    expect(api.requests, hasLength(1));
  });

  test('expired flow cannot redeem a session', () async {
    final expired = flow()
      ..['expiresAt'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
    final api = TelegramApi(expired, [session()]);
    await expectLater(
      signInWithTelegram(
        api: api,
        openBrowser: (_) async => true,
        cancelled: () => false,
      ),
      throwsStateError,
    );
    expect(api.requests, hasLength(1));
  });
}
