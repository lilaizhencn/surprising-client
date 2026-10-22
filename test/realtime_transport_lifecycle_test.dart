import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  test(
    'server policy closure preserves close code for session recovery',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peer = Completer<WebSocket>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        peer.complete(socket);
      });
      final client = RealtimeClient(
        AppConfig(websocketUrl: 'ws://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      final disconnected = Completer<void>();
      await client.connect(
        onEvent: (_) {},
        onError: (error) => fail('$error'),
        onDone: disconnected.complete,
      );
      await (await peer.future).close(
        WebSocketStatus.policyViolation,
        'session revoked',
      );
      await disconnected.future.timeout(const Duration(seconds: 2));
      expect(client.closeCode, WebSocketStatus.policyViolation);
    },
  );

  for (final kind in ['binary', 'ASCII', 'UTF-8']) {
    final binary = kind == 'binary';
    test('rejects $kind realtime payload before decoding', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peer = Completer<WebSocket>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        peer.complete(socket);
      });
      final client = RealtimeClient(
        AppConfig(websocketUrl: 'ws://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      final error = Completer<Object>();
      final disconnected = Completer<void>();
      var accepted = 0;
      await client.connect(
        onEvent: (_) => accepted++,
        onError: (value) {
          if (!error.isCompleted) error.complete(value);
        },
        onDone: disconnected.complete,
      );
      final socket = await peer.future;
      socket.add(
        binary
            ? [1, 2, 3]
            : kind == 'ASCII'
            ? 'x' * (4 * 1024 * 1024 + 1)
            : '中' * (4 * 1024 * 1024 ~/ 3 + 1),
      );
      expect(
        await error.future.timeout(const Duration(seconds: 2)),
        isFormatException,
      );
      await disconnected.future.timeout(const Duration(seconds: 2));
      expect(
        client.closeCode,
        binary
            ? WebSocketStatus.unsupportedData
            : WebSocketStatus.messageTooBig,
      );
      expect(socket.closeCode, client.closeCode);
      expect(socket.closeReason, binary ? '仅支持文本消息' : '文本消息超过限制');
      expect(accepted, 0);
    });
  }
  test(
    'malformed authenticated/private user IDs are dropped before UI dispatch',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peer = Completer<WebSocket>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        peer.complete(socket);
      });
      final client = RealtimeClient(
        AppConfig(websocketUrl: 'ws://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      final events = <Map<String, dynamic>>[], errors = <Object>[];
      await client.connect(
        userId: 7,
        accessToken: 'test-only',
        onEvent: events.add,
        onError: errors.add,
      );
      final socket = await peer.future;
      final malformed = [
        null,
        0,
        -1,
        'invalid',
        '1.5',
        1.5,
        '9223372036854775808',
        {'wrong': 'type'},
      ];
      for (final id in malformed) {
        socket.add(jsonEncode({'op': 'authenticated', 'userId': id}));
        socket.add(
          jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 7}),
        );
      }
      socket.add(
        jsonEncode({'op': 'event', 'channel': 'trades', 'id': 'before-auth'}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(errors, isEmpty);
      expect(events.map((event) => event['id']), ['before-auth']);
      events.clear();
      socket.add(jsonEncode({'op': 'authenticated', 'userId': '7'}));
      for (final id in malformed) {
        socket.add(jsonEncode({'op': 'authenticated', 'userId': id}));
        socket.add(
          jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': id}),
        );
      }
      socket.add(
        jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 8}),
      );
      socket.add(
        jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 7}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(errors, isEmpty);
      expect(events, hasLength(2));
      expect(events.first['op'], 'authenticated');
      expect(events.last['channel'], 'accountState');
      expect(events.last['userId'], 7);
    },
  );

  test(
    'authentication without a supplied user binds private frames to the acknowledged owner',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final peer = Completer<WebSocket>();
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        socket.listen((_) {});
        peer.complete(socket);
      });
      final client = RealtimeClient(
        AppConfig(websocketUrl: 'ws://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      final events = <Map<String, dynamic>>[], errors = <Object>[];
      await client.connect(
        accessToken: 'test-only',
        onEvent: events.add,
        onError: errors.add,
      );
      final socket = await peer.future;
      socket.add(jsonEncode({'op': 'authenticated', 'userId': 7}));
      socket.add(
        jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 8}),
      );
      socket.add(jsonEncode({'op': 'event', 'channel': 'accountState'}));
      socket.add(
        jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 7}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(errors, isEmpty);
      expect(events, hasLength(2));
      expect(events.last['userId'], 7);
    },
  );
}
