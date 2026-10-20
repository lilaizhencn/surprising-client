import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

const conversation = '10000000-0000-4000-8000-000000000001';
const secondConversation = '10000000-0000-4000-8000-000000000002';

class ChatWire {
  late HttpServer server;
  late RealtimeClient client;
  final sockets = <WebSocket>[];
  final commands = <Map<String, dynamic>>[];
  final market = <Map<String, dynamic>>[];
  final chat = <Map<String, dynamic>>[];
  StreamSubscription<Map<String, dynamic>>? subscription;
  Future<void> open() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.queryParameters.containsKey('token'), isFalse);
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen(
        (value) => commands.add(asMap(jsonDecode(value as String))),
      );
    });
    client = RealtimeClient(
      AppConfig(websocketUrl: 'ws://127.0.0.1:${server.port}/ws/v1'),
    );
    subscription = client.c2cEvents(12).listen(chat.add);
    await connect(12);
  }

  Future<void> connect(int owner) => client.connect(
    userId: owner,
    accessToken: 'qa-$owner',
    onEvent: market.add,
    onError: (error) => fail('$error'),
  );
  void emit(Map<String, dynamic> value) => sockets.last.add(jsonEncode(value));
  Future<void> authenticate(int owner) async {
    await until(
      () =>
          commands.where((c) => c['op'] == 'authenticate').length ==
          sockets.length,
    );
    emit({'op': 'authenticated', 'userId': owner});
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  Future<void> close() async {
    await subscription?.cancel();
    await client.close();
    await server.close(force: true);
  }
}

Future<void> until(bool Function() ready) async {
  final end = DateTime.now().add(const Duration(seconds: 3));
  while (!ready() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue);
}

void main() {
  late ChatWire wire;
  setUp(() async {
    wire = ChatWire();
    await wire.open();
  });
  tearDown(() async {
    await wire.close();
  });
  test(
    'market and chat share authentication and socket; stopping chat retains market',
    () async {
      wire.client.replaceSubscriptions([
        {'channel': 'trades', 'productLine': 'SPOT', 'instrumentId': '42'},
      ]);
      wire.client.watchC2c(
        owner: 12,
        conversationId: conversation,
        after: '9223372036854775806',
        afterEvent: '9223372036854775805',
      );
      await until(() => wire.commands.any((c) => c['channel'] == 'trades'));
      expect(wire.commands.where((c) => c['op'] == 'c2c.watch'), isEmpty);
      wire.emit({
        'op': 'c2c.messages',
        'channel': 'c2c.messages',
        'data': {'conversationId': conversation},
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(wire.chat, isEmpty);
      await wire.authenticate(12);
      await until(() => wire.commands.any((c) => c['op'] == 'c2c.watch'));
      expect(wire.sockets, hasLength(1));
      expect(
        wire.commands.singleWhere((c) => c['op'] == 'c2c.watch')['after'],
        '9223372036854775806',
      );
      wire.emit({
        'op': 'c2c.messages',
        'channel': 'c2c.messages',
        'data': {'conversationId': conversation},
      });
      wire.emit({
        'op': 'event',
        'channel': 'trades',
        'data': {'price': '100'},
      });
      await until(
        () =>
            wire.chat.length == 1 &&
            wire.market.any((e) => e['channel'] == 'trades'),
      );
      expect(wire.market.any((e) => e['channel'] == 'c2c.messages'), isFalse);
      wire.client.stopC2c(12);
      await until(() => wire.commands.any((c) => c['op'] == 'c2c.stop'));
      wire.emit({
        'op': 'event',
        'channel': 'trades',
        'data': {'price': '101'},
      });
      await until(
        () => wire.market.where((e) => e['channel'] == 'trades').length == 2,
      );
      expect(wire.commands.where((c) => c['op'] == 'unsubscribe'), isEmpty);
    },
  );
  test(
    'reconnect resumes exact latest cursors without duplicate subscribe on each cursor update',
    () async {
      await wire.authenticate(12);
      wire.client.watchC2c(
        owner: 12,
        conversationId: conversation,
        after: '90',
        afterEvent: '20',
      );
      await until(() => wire.commands.any((c) => c['op'] == 'c2c.watch'));
      wire.client.watchC2c(
        owner: 12,
        conversationId: conversation,
        after: '9223372036854775807',
        afterEvent: '9223372036854775806',
      );
      await wire.connect(12);
      await wire.authenticate(12);
      await until(
        () => wire.commands.where((c) => c['op'] == 'c2c.watch').length == 2,
      );
      final resumed = wire.commands.lastWhere((c) => c['op'] == 'c2c.watch');
      expect(resumed['after'], '9223372036854775807');
      expect(resumed['afterEvent'], '9223372036854775806');
      expect(wire.sockets.first.readyState, WebSocket.closed);
    },
  );
  test(
    'another account cannot inherit a conversation or deliver to a retired listener',
    () async {
      await wire.authenticate(12);
      wire.client.watchC2c(owner: 12, conversationId: conversation);
      expect(
        () => wire.client.watchC2c(owner: 13, conversationId: conversation),
        throwsStateError,
      );
      await wire.connect(13);
      await wire.authenticate(13);
      wire.client.watchC2c(owner: 13, conversationId: secondConversation);
      wire.emit({
        'op': 'c2c.messages',
        'channel': 'c2c.messages',
        'data': {'conversationId': secondConversation},
      });
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(wire.chat, isEmpty);
      expect(
        wire.commands.where(
          (c) => c['op'] == 'c2c.watch' && c['conversationId'] == conversation,
        ),
        hasLength(1),
      );
    },
  );
  test(
    'chat errors stay separate from market and allow explicit subscription retry',
    () async {
      await wire.authenticate(12);
      wire.client.watchC2c(owner: 12, conversationId: conversation);
      await until(() => wire.commands.any((c) => c['op'] == 'c2c.watch'));
      wire.emit({
        'op': 'c2c.error',
        'channel': 'c2c.messages',
        'message': 'temporary chat outage',
      });
      await until(() => wire.chat.isNotEmpty);
      expect(wire.market.any((e) => e['op'] == 'c2c.error'), isFalse);
      wire.client.watchC2c(owner: 12, conversationId: conversation);
      await until(
        () => wire.commands.where((c) => c['op'] == 'c2c.watch').length == 2,
      );
      expect(wire.sockets, hasLength(1));
    },
  );
  test(
    'switching conversation unsubscribes only chat and malformed cursors never send',
    () async {
      await wire.authenticate(12);
      wire.client.watchC2c(owner: 12, conversationId: conversation);
      wire.client.watchC2c(owner: 12, conversationId: secondConversation);
      await until(
        () => wire.commands.where((c) => c['op'] == 'c2c.watch').length == 2,
      );
      expect(
        wire.commands.where((c) => c['op'] == 'c2c.unwatch'),
        hasLength(1),
      );
      expect(
        () => wire.client.watchC2c(
          owner: 12,
          conversationId: secondConversation,
          after: '9223372036854775808',
        ),
        throwsFormatException,
      );
      expect(
        () => wire.client.watchC2c(owner: 12, conversationId: 'foreign'),
        throwsFormatException,
      );
    },
  );
}
