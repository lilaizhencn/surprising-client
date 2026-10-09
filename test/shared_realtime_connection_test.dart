import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  for (final loggedIn in [false, true]) {
    test(
      'one connection: public continues while private waits ($loggedIn)',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final messages = <Map<String, dynamic>>[];
        final events = <Map<String, dynamic>>[];
        final opened = Completer<WebSocket>();
        var connections = 0;
        server.listen((request) async {
          expect(request.uri.queryParameters.containsKey('token'), isFalse);
          final socket = await WebSocketTransformer.upgrade(request);
          connections++;
          opened.complete(socket);
          socket.listen(
            (raw) => messages.add(asMap(jsonDecode(raw as String))),
          );
        });
        final client = RealtimeClient(
          AppConfig(
            websocketUrl: 'ws://127.0.0.1:${server.port}?token=removed',
          ),
        );
        addTearDown(() async {
          await client.close();
          await server.close(force: true);
        });
        await client.connect(
          userId: loggedIn ? 7 : null,
          accessToken: loggedIn ? 'test-token' : null,
          onEvent: events.add,
          onError: (e) => fail('$e'),
        );
        final plan = [
          for (final product in ProductMode.values)
            {
              'channel': 'trades',
              'productLine': product.productLine,
              'instrumentId': '42',
            },
          {'channel': 'accountState', 'productLine': 'LINEAR_PERPETUAL'},
        ];
        client.replaceSubscriptions(plan);
        final socket = await opened.future;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(connections, 1);
        expect(
          messages.where((m) => m['op'] == 'authenticate').length,
          loggedIn ? 1 : 0,
        );
        expect(messages.where((m) => m['op'] == 'subscribe').length, 6);
        socket.add(jsonEncode({'op': 'authenticated', 'userId': 99}));
        socket.add(
          jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 7}),
        );
        socket.add(
          jsonEncode({
            'op': 'event',
            'channel': 'trades',
            'productLine': 'SPOT',
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(events.map((m) => m['channel']), ['trades']);
        expect(messages.where((m) => m['channel'] == 'accountState'), isEmpty);
        if (loggedIn) {
          socket.add(jsonEncode({'op': 'authenticated', 'userId': 7}));
          await Future<void>.delayed(const Duration(milliseconds: 50));
          client.replaceSubscriptions(plan);
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(
            messages.where((m) => m['channel'] == 'accountState').length,
            1,
          );
          expect(messages.where((m) => m['op'] == 'authenticate').length, 1);
          socket.add(
            jsonEncode({
              'op': 'event',
              'channel': 'accountState',
              'userId': 99,
            }),
          );
          socket.add(
            jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 7}),
          );
          await Future<void>.delayed(const Duration(milliseconds: 50));
          expect(events.where((m) => m['channel'] == 'accountState').length, 1);
        }
        client.replaceSubscriptions([plan.first]);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(connections, 1);
        expect(
          messages.where((m) => m['op'] == 'unsubscribe').length,
          loggedIn ? 6 : 5,
        );
      },
    );
  }

  test(
    'reconnect requires fresh authentication and blocks old private identity',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <WebSocket>[];
      final commands = <Map<String, dynamic>>[];
      server.listen((request) async {
        final socket = await WebSocketTransformer.upgrade(request);
        sockets.add(socket);
        socket.listen((raw) => commands.add(asMap(jsonDecode(raw as String))));
      });
      final client = RealtimeClient(
        AppConfig(websocketUrl: 'ws://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        await client.close();
        await server.close(force: true);
      });
      final events = <Map<String, dynamic>>[];
      Future<void> connect(int user) => client.connect(
        userId: user,
        accessToken: 'test-$user',
        onEvent: events.add,
        onError: (e) => fail('$e'),
      );
      final plan = [
        {'channel': 'accountState', 'productLine': 'SPOT'},
        {'channel': 'trades', 'productLine': 'SPOT', 'instrumentId': '42'},
      ];
      await connect(7);
      client.replaceSubscriptions(plan);
      sockets.first.add(jsonEncode({'op': 'authenticated', 'userId': 7}));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await connect(8);
      client.replaceSubscriptions(plan);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(sockets.first.readyState, WebSocket.closed);
      expect(commands.where((m) => m['op'] == 'authenticate').length, 2);
      expect(
        commands
            .where(
              (m) => m['op'] == 'subscribe' && m['channel'] == 'accountState',
            )
            .length,
        1,
      );
      sockets.last.add(jsonEncode({'op': 'authenticated', 'userId': 8}));
      sockets.last.add(
        jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 7}),
      );
      sockets.last.add(
        jsonEncode({'op': 'event', 'channel': 'accountState', 'userId': 8}),
      );
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(
        commands
            .where(
              (m) => m['op'] == 'subscribe' && m['channel'] == 'accountState',
            )
            .length,
        2,
      );
      expect(
        events.where((m) => m['channel'] == 'accountState').single['userId'],
        8,
      );
    },
  );
}
