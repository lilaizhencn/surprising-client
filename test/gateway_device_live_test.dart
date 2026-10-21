import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  final base = Platform.environment['GATEWAY_DEVICE_LIVE_URL'];
  test(
    'actual isolated gateway accepts app UUID through registration, login and refresh',
    () async {
      expect(base, 'http://127.0.0.1:19094');
      final http = HttpClient()..findProxy = (_) => 'DIRECT';
      final api = ApiClient(AppConfig(gatewayBaseUrl: base!), httpClient: http);
      final email = 'device_uuid_${ApiClient.newDeviceId()}@example.invalid';
      final password = '${ApiClient.newDeviceId()}${ApiClient.newDeviceId()}';
      final sessions = <AuthSession>[];
      int? owner;
      var passed = false;
      try {
        final registered = await api.register(password: password, email: email);
        sessions.add(registered);
        owner = registered.user.userId;
        final loggedIn = await api.login(username: email, password: password);
        sessions.add(loggedIn);
        api.setSession(loggedIn);
        expect(loggedIn.user.userId, owner);
        final primary = await api.primaryAuthentication();
        expect(primary.passwordRequired, isTrue);
        final refreshed = await api.refresh(loggedIn.refreshToken);
        sessions.remove(loggedIn);
        sessions.add(refreshed);
        api.setSession(refreshed);
        expect(refreshed.user.userId, owner);
        final summary = await api.get(
          '/api/v1/portfolio/income',
          userId: owner,
        );
        expect(summary['currency'], 'USDT');
        expect(
          (summary['groups'] as Map).keys,
          containsAll(['overview', 'funding', 'trading']),
        );
        expect(ApiClient.isDeviceId(await api.resolveDeviceId()), isTrue);
        passed = true;
      } finally {
        for (final session in sessions) {
          api.setSession(session);
          await api.post('/api/v1/auth/logout', {
            'refreshToken': session.refreshToken,
          });
        }
        http.close(force: true);
        if (owner != null) {
          File('/tmp/surprising-device-live-qa.json').writeAsStringSync(
            jsonEncode({
              'actual_gateway': true,
              'app_uuid_contract': passed,
              'passed': passed,
              'user_id': owner,
              'session_tokens_logged': false,
              'sessions_revoked': true,
            }),
          );
        }
      }
    },
    skip: base == null
        ? 'Requires the explicitly isolated local QA gateway'
        : false,
  );
}
