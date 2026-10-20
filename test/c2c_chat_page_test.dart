import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart' show AppScope;
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/c2c_chat_page.dart';
import 'package:surprising_client/src/c2c_models.dart';
import 'package:surprising_client/src/models.dart';

const conversationId = '10000000-0000-4000-8000-000000000001';
AuthSession ownerSession(int owner) => AuthSession.fromJson({
  'accessToken': 'qa-$owner',
  'refreshToken': 'qa-refresh-$owner',
  'user': {'userId': owner},
});
Map<String, dynamic> conversationJson() => {
  'conversationId': conversationId,
  'orderId': null,
  'peer': {
    'userId': '11',
    'nickname': 'Merchant with a very long nickname 商家名称',
  },
  'unreadCount': '2',
  'lastMessage': null,
};
Map<String, dynamic> messageJson(String request, String text) => {
  'messageId': '9223372036854775807',
  'requestId': request,
  'conversationId': conversationId,
  'senderUserId': '12',
  'authorKind': 'USER',
  'text': text,
  'attachment': null,
  'createdAt': '2026-10-20T00:00:00Z',
  'status': 'SENT',
};

class ChatApi extends ApiClient {
  ChatApi() : super(const AppConfig());
  bool enabled = true, loseResponse = false;
  int posts = 0;
  Map<String, dynamic>? saved;
  final queries = <String>[];
  final readBodies = <Map<String, dynamic>>[];
  Completer<void>? firstRead;
  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    queries.add(path);
    if (path.endsWith('/status')) return {'runtimeEnabled': enabled};
    if (path.endsWith('/conversations')) {
      return {
        'items': [conversationJson()],
        'hasMore': false,
      };
    }
    if (path.endsWith('/quick-replies')) return {'items': []};
    if (path.contains('/requests/')) {
      return {
        'status': 'SENT',
        'message': messageJson(
          asString(saved!['requestId']),
          asString(saved!['text']),
        ),
      };
    }
    if (path.endsWith('/messages')) {
      return {
        'conversationId': conversationId,
        'messages': [],
        'orderEvents': [],
        'reads': [],
        'hasMore': false,
      };
    }
    return {'items': [], 'hasMore': false};
  }

  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = false,
  }) async {
    if (path.endsWith('/read')) {
      readBodies.add(Map.of(body));
      if (readBodies.length == 1 && firstRead != null) await firstRead!.future;
      return {'reads': []};
    }
    if (path.endsWith('/messages')) {
      posts++;
      saved = Map.of(body);
      if (loseResponse) throw ApiException(503, '合成测试响应丢失');
      return messageJson(asString(body['requestId']), asString(body['text']));
    }
    return {};
  }
}

class ChatRealtime extends RealtimeClient {
  ChatRealtime() : super(const AppConfig());
  final events = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final plans = <String?>[];
  @override
  Stream<Map<String, dynamic>> c2cEvents(int owner) => events.stream;
  @override
  void watchC2c({
    required int owner,
    String? conversationId,
    String after = '0',
    String afterEvent = '0',
  }) {
    plans.add(conversationId);
  }

  @override
  void stopC2c(int owner) {}
  @override
  Future<void> close() => events.close();
}

class ChatState extends AppState {
  ChatState(ChatApi api, ChatRealtime realtime)
    : super(apiClient: api, realtimeClient: realtime, offline: true) {
    switchOwner(12);
  }
  void switchOwner(int owner) {
    session = ownerSession(owner);
    api.setSession(session);
    notifyListeners();
  }
}

void main() {
  testWidgets(
    'visible messages arriving during an in-flight read advance the final receipt',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = ChatApi()..firstRead = Completer<void>();
      final realtime = ChatRealtime();
      final state = ChatState(api, realtime);
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            home: C2cChatRoom(
              state: state,
              owner: 12,
              conversation: C2cConversation.fromJson(conversationJson()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void emit(String messageId, String text) => realtime.events.add({
        'op': 'c2c.messages',
        'channel': 'c2c.messages',
        'data': {
          'conversationId': conversationId,
          'messages': [
            {
              ...messageJson('10000000-0000-4000-8000-000000000002', text),
              'messageId': messageId,
            },
          ],
          'orderEvents': [],
          'reads': [],
          'hasMore': false,
        },
      });
      emit('9223372036854775806', 'first visible message');
      await tester.pumpAndSettle();
      expect(api.readBodies, hasLength(1));
      emit('9223372036854775807', 'second visible message');
      await tester.pumpAndSettle();
      expect(api.readBodies, hasLength(1));
      api.firstRead!.complete();
      await tester.pumpAndSettle();
      expect(api.readBodies.last['messageId'], '9223372036854775807');
      expect(api.readBodies, hasLength(2));
    },
  );
  late ChatApi api;
  late ChatRealtime realtime;
  late ChatState state;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    api = ChatApi();
    realtime = ChatRealtime();
    state = ChatState(api, realtime);
  });
  tearDown(() => state.dispose());
  Future<void> mount(
    WidgetTester tester,
    Widget child, {
    double width = 390,
    bool dark = false,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          theme: ThemeData(
            brightness: dark ? Brightness.dark : Brightness.light,
          ),
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'disabled runtime avoids querying conversations and remains a friendly empty state',
    (tester) async {
      api.enabled = false;
      await mount(tester, const Scaffold(body: C2cMessagingPage()));
      expect(find.text('C2C 聊天暂未开启'), findsOneWidget);
      expect(api.queries.where((p) => p.endsWith('/conversations')), isEmpty);
      expect(realtime.plans, isEmpty);
    },
  );
  testWidgets(
    'inbox subscription error can be retried without reopening the page',
    (tester) async {
      await mount(tester, const Scaffold(body: C2cMessagingPage()));
      expect(realtime.plans, hasLength(1));
      realtime.events.add({'op': 'c2c.error', 'channel': 'c2c.messages'});
      await tester.pumpAndSettle();
      expect(find.text('聊天订阅未完成，请重试'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(realtime.plans, hasLength(2));
    },
  );
  testWidgets(
    'resuming the visible room acknowledges messages received while backgrounded',
    (tester) async {
      await mount(
        tester,
        C2cChatRoom(
          state: state,
          owner: 12,
          conversation: C2cConversation.fromJson(conversationJson()),
        ),
      );
      for (final lifecycle in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(lifecycle);
      }
      void resume() {
        if (tester.binding.lifecycleState == AppLifecycleState.paused) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
        }
        if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        if (tester.binding.lifecycleState == AppLifecycleState.inactive) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
      }

      addTearDown(resume);
      realtime.events.add({
        'op': 'c2c.messages',
        'channel': 'c2c.messages',
        'data': {
          'conversationId': conversationId,
          'messages': [
            messageJson(
              '10000000-0000-4000-8000-000000000002',
              'received while paused',
            ),
          ],
          'orderEvents': [],
          'reads': [],
          'hasMore': false,
        },
      });
      await tester.pump();
      expect(api.readBodies, isEmpty);
      resume();
      await tester.pumpAndSettle();
      expect(api.readBodies.last['messageId'], '9223372036854775807');
    },
  );
  testWidgets(
    'inbox opens a conversation and returns to its existing subscription',
    (tester) async {
      await mount(tester, const Scaffold(body: C2cMessagingPage()));
      await tester.tap(find.text('Merchant with a very long nickname 商家名称'));
      await tester.pumpAndSettle();
      expect(find.byType(C2cChatRoom), findsOneWidget);
      expect(realtime.plans.last, conversationId);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(realtime.plans.last, isNull);
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 390.0]) {
    for (final dark in [false, true]) {
      testWidgets(
        'composer and long messages fit width $width dark $dark and a visible keyboard',
        (tester) async {
          final room = C2cChatRoom(
            state: state,
            owner: 12,
            conversation: C2cConversation.fromJson(conversationJson()),
          );
          await mount(tester, room, width: width, dark: dark);
          await tester.enterText(
            find.byType(TextField),
            '价格没有截断 ${'a long discussion ' * 12}',
          );
          await tester.tap(find.text('发送'));
          await tester.pumpAndSettle();
          expect(api.posts, 1);
          tester.view.viewInsets = const FakeViewPadding(bottom: 280);
          addTearDown(tester.view.resetViewInsets);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(find.textContaining('a long discussion'), findsOneWidget);
        },
      );
    }
  }
  testWidgets(
    'unknown send keeps a secure original request and retry recovers without another POST',
    (tester) async {
      api.loseResponse = true;
      await mount(
        tester,
        C2cChatRoom(
          state: state,
          owner: 12,
          conversation: C2cConversation.fromJson(conversationJson()),
        ),
      );
      await tester.enterText(find.byType(TextField), 'original discussion');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      final stored = await const FlutterSecureStorage().read(
        key: 'surprising.c2c.pending.12.$conversationId',
      );
      expect(stored, contains(api.saved!['requestId']));
      expect(find.text('发送结果待确认，重试会先查询原消息。'), findsOneWidget);
      await tester.tap(find.text('查询重试'));
      await tester.pumpAndSettle();
      expect(api.posts, 1);
      expect(find.text('original discussion'), findsOneWidget);
      expect(
        await const FlutterSecureStorage().read(
          key: 'surprising.c2c.pending.12.$conversationId',
        ),
        isNull,
      );
    },
  );
  testWidgets('a changed account hides the old private room and messages', (
    tester,
  ) async {
    await mount(
      tester,
      C2cChatRoom(
        state: state,
        owner: 12,
        conversation: C2cConversation.fromJson(conversationJson()),
      ),
    );
    await tester.enterText(
      find.byType(TextField),
      'private prior account message',
    );
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    state.switchOwner(13);
    await tester.pumpAndSettle();
    expect(find.text('private prior account message'), findsNothing);
    expect(find.text('登录账户已变化，请返回会话列表'), findsOneWidget);
  });
}
