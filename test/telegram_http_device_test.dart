import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/telegram_login.dart';

void main() {
  test('a synchronous device storage failure can be retried safely', () async {
    final api = ApiClient(const AppConfig());
    var calls = 0;
    api.deviceIdLoader = () {
      calls++;
      if (calls == 1) throw StateError('storage unavailable');
      return Future.value('mobile-synthetic-recovered-device');
    };
    await expectLater(api.resolveDeviceId(), throwsStateError);
    expect(await api.resolveDeviceId(), 'mobile-synthetic-recovered-device');
    expect(await api.resolveDeviceId(), 'mobile-synthetic-recovered-device');
    expect(calls, 2);
  });

  test(
    'real HTTP sends the same persisted device through Telegram login, refresh and app restart',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final connections = <HttpClient>[];
      addTearDown(() async {
        for (final client in connections) {
          client.close(force: true);
        }
        await server.close(force: true);
      });
      final requests = <(String, String?, Map<String, dynamic>)>[];
      final response = {
        'user': {
          'userId': 7,
          'username': null,
          'email': null,
          'displayName': '小李',
          'status': 'NORMAL',
        },
        'accessToken': 'synthetic-access',
        'refreshToken': 'synthetic-refresh',
      };
      server.listen((request) async {
        final body = asMap(jsonDecode(await utf8.decoder.bind(request).join()));
        requests.add((
          request.uri.path,
          request.headers.value('x-device-id'),
          body,
        ));
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path.endsWith('/start')
                ? {
                    'flowId': 's' * 43,
                    'verifier': 'v' * 43,
                    'authorizationUrl':
                        'https://oauth.telegram.org/auth?state=synthetic',
                    'expiresAt': DateTime.now()
                        .add(const Duration(minutes: 5))
                        .toUtc()
                        .toIso8601String(),
                  }
                : response,
          ),
        );
        await request.response.close();
      });
      String? persisted;
      var created = 0;
      Future<String> loadDevice() async => persisted ??= () {
        created++;
        return ApiClient.newDeviceId();
      }();
      ApiClient client() {
        final http = HttpClient();
        connections.add(http);
        return ApiClient(
          AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
          httpClient: http,
        )..deviceIdLoader = loadDevice;
      }

      final first = client();
      final authenticated = await signInWithTelegram(
        api: first,
        openBrowser: (_) async => true,
        cancelled: () => false,
      );
      first.setSession(authenticated);
      final refreshed = await first.refresh(authenticated.refreshToken);
      final restarted = client()..setSession(refreshed);
      await restarted.refresh(refreshed.refreshToken);
      expect(requests, hasLength(4));
      expect(requests.map((request) => request.$2).toSet(), {persisted});
      expect(persisted, startsWith('mobile-'));
      expect(created, 1);
      expect(requests[1].$3, {'flowId': 's' * 43, 'verifier': 'v' * 43});
      expect(requests.last.$3, {'refreshToken': 'synthetic-refresh'});
      expect(refreshed.user.name, '小李');
    },
  );
}
