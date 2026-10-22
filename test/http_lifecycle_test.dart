import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/c2c_models.dart';
import 'package:surprising_client/src/models.dart';

const _timeout = Duration(milliseconds: 350);

Future<ApiClient> _api(
  Future<void> Function(HttpRequest) handle, {
  int responseLimit = 1024,
  int downloadLimit = 1024,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) => unawaited(handle(request)));
  final client = ApiClient(
    AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
    requestTimeout: _timeout,
    uploadTimeout: _timeout,
    maxResponseBytes: responseLimit,
    maxDownloadBytes: downloadLimit,
  );
  addTearDown(() async {
    client.dispose();
    await server.close(force: true);
  });
  return client;
}

/// A raw peer makes socket closure observable, including after HTTP headers.
Future<void> _hold(
  HttpRequest request,
  Completer<void> received,
  Completer<void> disconnected, {
  bool sendHeaders = true,
}) async {
  await request.drain<void>();
  final socket = await request.response.detachSocket(writeHeaders: false);
  addTearDown(socket.destroy);
  socket.listen(
    (_) {},
    onError: (Object _) {
      if (!disconnected.isCompleted) disconnected.complete();
    },
    onDone: () {
      if (!disconnected.isCompleted) disconnected.complete();
    },
  );
  if (sendHeaders) {
    socket.write('HTTP/1.1 200 OK\r\nContent-Length: 100\r\n\r\n{"ok":');
    await socket.flush();
  }
  received.complete();
}

void main() {
  for (final sendHeaders in [false, true]) {
    test(
      'deadline aborts ${sendHeaders ? 'partial body' : 'slow headers'} and closes socket',
      () async {
        final received = Completer<void>(), disconnected = Completer<void>();
        final api = await _api(
          (request) =>
              _hold(request, received, disconnected, sendHeaders: sendHeaders),
        );
        final result = expectLater(
          api.get('/held'),
          throwsA(isA<TimeoutException>()),
        );
        await received.future;
        await result;
        await disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  test('continuous body progress cannot extend the total deadline', () async {
    final stopped = Completer<void>();
    final api = await _api((request) async {
      final socket = await request.response.detachSocket(writeHeaders: false);
      addTearDown(socket.destroy);
      socket.write('HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n');
      final timer = Timer.periodic(const Duration(milliseconds: 40), (_) {
        socket.write('1\r\n \r\n');
      });
      socket.listen(
        (_) {},
        onError: (Object _) {},
        onDone: () {
          timer.cancel();
          if (!stopped.isCompleted) stopped.complete();
        },
      );
      addTearDown(timer.cancel);
    });
    final elapsed = Stopwatch()..start();
    await expectLater(api.get('/trickle'), throwsA(isA<TimeoutException>()));
    expect(elapsed.elapsed, lessThan(const Duration(seconds: 2)));
    await stopped.future.timeout(const Duration(seconds: 2));
  });

  for (final declaredLength in [false, true]) {
    test(
      'response cap rejects ${declaredLength ? 'Content-Length' : 'chunked'} body',
      () async {
        final api = await _api((request) async {
          if (declaredLength) request.response.contentLength = 100;
          request.response.write('x' * 100);
          await request.response.close();
        }, responseLimit: 32);
        await expectLater(
          api.get('/oversized'),
          throwsA(isA<ApiResponseTooLarge>()),
        );
      },
    );
  }

  test(
    'cancelling pending reads closes the peer and allows later requests',
    () async {
      final received = Completer<void>(), disconnected = Completer<void>();
      final api = await _api((request) async {
        if (request.uri.path == '/held') {
          await _hold(request, received, disconnected);
        } else {
          request.response.write('{"ok":true}');
          await request.response.close();
        }
      });
      final result = expectLater(
        api.get('/held'),
        throwsA(isA<ApiRequestCancelled>()),
      );
      await received.future;
      api.cancelPendingRequests();
      await result;
      await disconnected.future.timeout(const Duration(seconds: 2));
      expect(await api.get('/later'), {'ok': true});
    },
  );

  test('dispose cancels body reads and rejects new requests', () async {
    final received = Completer<void>(), disconnected = Completer<void>();
    final api = await _api((request) => _hold(request, received, disconnected));
    final result = expectLater(
      api.get('/held'),
      throwsA(isA<ApiRequestCancelled>()),
    );
    await received.future;
    api.dispose();
    api.dispose();
    await result;
    await disconnected.future.timeout(const Duration(seconds: 2));
    await expectLater(api.get('/closed'), throwsA(isA<ApiRequestCancelled>()));
  });

  test(
    'cancellation while resolving device storage does not later send',
    () async {
      var count = 0;
      final device = Completer<String>();
      final api =
          await _api((request) async {
              count++;
              await request.response.close();
            })
            ..deviceIdLoader = () => device.future;
      final result = expectLater(
        api.get('/deferred'),
        throwsA(isA<ApiRequestCancelled>()),
      );
      api.cancelPendingRequests();
      await result;
      device.complete('3105164f-5122-46be-8cb7-9c4e09825980');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(count, 0);
    },
  );

  test(
    'timed-out trading write is sent once and is not a definitive rejection',
    () async {
      var count = 0;
      final received = Completer<void>(), disconnected = Completer<void>();
      final api = await _api((request) {
        count++;
        return _hold(request, received, disconnected);
      });
      Object? failure;
      try {
        await api.post('/api/v1/gateway/trading/order', {
          'clientOrderId': 'same-intent',
        });
      } catch (error) {
        failure = error;
      }
      expect(failure, isA<TimeoutException>());
      expect(isDefinitiveOrderRejection(failure!), isFalse);
      expect(count, 1);
      await disconnected.future.timeout(const Duration(seconds: 2));
    },
  );

  for (final upload in [false, true]) {
    test(
      'KYC ${upload ? 'upload' : 'download'} body shares deadline and aborts',
      () async {
        final received = Completer<void>(), disconnected = Completer<void>();
        final api = await _api(
          (request) => _hold(request, received, disconnected),
        );
        final Future<Object?> operation = upload
            ? api.uploadKycDocument(
                documentType: 'ID',
                fileName: 'id.png',
                bytes: [1, 2],
              )
            : api.downloadKycDocument(1);
        final result = expectLater(operation, throwsA(isA<TimeoutException>()));
        await received.future;
        await result;
        await disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  test(
    'download limit applies before allocating an oversized document',
    () async {
      final api = await _api((request) async {
        request.response.contentLength = 100;
        request.response.add(Uint8List(100));
        await request.response.close();
      }, downloadLimit: 32);
      await expectLater(
        api.downloadKycDocument(1),
        throwsA(isA<ApiResponseTooLarge>()),
      );
    },
  );

  for (final upload in [false, true]) {
    test(
      'C2C ${upload ? 'upload' : 'download'} body shares deadline and aborts',
      () async {
        final received = Completer<void>(), disconnected = Completer<void>();
        final api =
            await _api((request) => _hold(request, received, disconnected))
              ..setSession(
                AuthSession.fromJson({
                  'accessToken': 'test-only-access',
                  'refreshToken': 'test-only-refresh',
                  'user': {'userId': 12},
                }),
              );
        final Future<Object?> operation = upload
            ? api.c2cUpload(
                12,
                C2cConversation.fromJson({
                  'conversationId': '10000000-0000-4000-8000-000000000001',
                  'peer': {'userId': '13'},
                  'unreadCount': '0',
                }),
                '10000000-0000-4000-8000-000000000003',
                'proof.png',
                'image/png',
                Uint8List.fromList([1, 2]),
              )
            : api.c2cDownload(12, '10000000-0000-4000-8000-000000000003');
        final result = expectLater(operation, throwsA(isA<TimeoutException>()));
        await received.future;
        await result;
        await disconnected.future.timeout(const Duration(seconds: 2));
      },
    );
  }

  test(
    'refresh and retry cannot reset the original request deadline',
    () async {
      final paths = <String>[];
      final api =
          await _api((request) async {
              paths.add(request.uri.path);
              if (request.uri.path.endsWith('/refresh')) {
                await Future<void>.delayed(const Duration(milliseconds: 220));
                request.response.write(
                  jsonEncode({
                    'accessToken': 'new-access',
                    'refreshToken': 'new-refresh',
                    'user': {'userId': 12},
                  }),
                );
              } else if (request.headers.value('Authorization') ==
                  'Bearer original') {
                request.response.statusCode = 401;
              } else {
                await Future<void>.delayed(const Duration(milliseconds: 220));
                request.response.write('{"ok":true}');
              }
              await request.response.close();
            })
            ..setSession(
              AuthSession.fromJson({
                'accessToken': 'original',
                'refreshToken': 'original-refresh',
                'user': {'userId': 12},
              }),
            );
      await expectLater(
        api.get('/requires-refresh'),
        throwsA(isA<TimeoutException>()),
      );
      expect(paths, [
        '/requires-refresh',
        '/api/v1/auth/refresh',
        '/requires-refresh',
      ]);
      // Let the test server finish its already accepted retry before teardown.
      await Future<void>.delayed(const Duration(milliseconds: 150));
    },
  );

  test('normal JSON and bounded document downloads remain supported', () async {
    final api = await _api((request) async {
      if (request.uri.path.endsWith('/1')) {
        request.response.add([1, 2, 3]);
      } else {
        request.response.write(jsonEncode({'value': '9007199254740993'}));
      }
      await request.response.close();
    });
    expect(await api.get('/normal'), {'value': '9007199254740993'});
    expect(await api.downloadKycDocument(1), [1, 2, 3]);
  });
}
