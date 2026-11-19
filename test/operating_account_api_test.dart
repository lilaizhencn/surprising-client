import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

const parent = AuthSession(
  user: AuthUser(userId: 7, username: 'Owner', email: '', status: 'NORMAL'),
  accessToken: 'test-login-token',
);
AuthSession selected(int id) => AuthSession(
  user: parent.user,
  accessToken: '',
  operatingAccount: OperatingAccount(userId: id, parent: id == 7),
);
void main() {
  test(
    'HTTP uses current user for trading, parent for management and blocks withdrawals',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String>[];
      final subscription = server.listen((request) async {
        received.add(request.uri.path);
        expect(
          request.headers.value('authorization'),
          'Bearer test-login-token',
        );
        if (request.uri.path.startsWith('/api/v1/trading/') ||
            request.uri.path.startsWith('/api/v1/accounts/') ||
            request.uri.path.startsWith('/api/v1/risk/')) {
          expect(request.headers.value('x-user-id'), '21');
        }
        if (request.uri.path.endsWith('/operating-account')) {
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'userId': 21,
          });
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode(
            request.uri.path.endsWith('/operating-account')
                ? selected(21).toJson()
                : <String, dynamic>{},
          ),
        );
        await request.response.close();
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        api.dispose();
        await subscription.cancel();
        await server.close(force: true);
      });
      api.setSession(parent);
      final response = await api.switchOperatingAccount(21);
      api.setSession(parent.withServerSession(response));
      await api.get('/api/v1/accounts/balances', userId: 21);
      await api.get('/api/v1/trading/orders', userId: 21);
      await api.get('/api/v1/risk/account/latest', userId: 21);
      await api.get('/api/v1/security/mfa', userId: 7);
      await api.get('/api/v1/sub-account/list', userId: 7);
      await expectLater(
        api.get('/api/v1/accounts/balances', userId: 7),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.post('/api/v1/wallet/withdrawals', {}),
        throwsA(isA<ApiException>()),
      );
      api.switchingOperatingAccount = true;
      await expectLater(
        api.post('/api/v1/trading/orders', {}),
        throwsA(isA<ApiException>()),
      );
      expect(received.length, 6);
    },
  );

  test('pending HTTP response is discarded on account switch', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final started = Completer<void>(), release = Completer<void>();
    final subscription = server.listen((request) async {
      started.complete();
      await release.future;
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        '{"balances": [{"asset": "USDT", "availableUnits": "999"}]}',
      );
      await request.response.close();
    });
    final api = ApiClient(
      AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
    );
    addTearDown(() async {
      api.dispose();
      if (!release.isCompleted) release.complete();
      await subscription.cancel();
      await server.close(force: true);
    });
    api.setSession(parent);
    final pending = api.get('/api/v1/accounts/balances', userId: 7);
    final rejected = expectLater(pending, throwsA(isA<ApiRequestCancelled>()));
    await started.future;
    api.cancelPendingRequests();
    api.setSession(parent.withServerSession(selected(21)));
    release.complete();
    await rejected;
  });
}
