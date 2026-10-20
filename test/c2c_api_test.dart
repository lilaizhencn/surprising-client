import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/c2c_models.dart';
import 'package:surprising_client/src/models.dart';

const conversationId = '10000000-0000-4000-8000-000000000001';
const requestId = '10000000-0000-4000-8000-000000000002';
const attachmentId = '10000000-0000-4000-8000-000000000003';
Map<String, dynamic> message(String id) => {
  'messageId': id,
  'conversationId': conversationId,
  'requestId': requestId,
  'senderUserId': '12',
  'authorKind': 'USER',
  'text': 'original text',
  'createdAt': '2026-10-20T00:00:00Z',
  'attachment': null,
  'status': 'SENT',
};
Map<String, dynamic> page() => {
  'conversationId': conversationId,
  'messages': [message('9223372036854775807')],
  'orderEvents': [],
  'reads': [],
  'hasMore': false,
};
AuthSession session(int owner) => AuthSession.fromJson({
  'accessToken': 'qa-$owner',
  'refreshToken': 'qa-refresh-$owner',
  'user': {'userId': owner},
});

void main() {
  test(
    'timeline preserves committed identity order when transaction timestamps invert',
    () {
      final first = message('9223372036854775806')
        ..['createdAt'] = '2026-10-20T00:00:02Z';
      final second = message('9223372036854775807')
        ..['createdAt'] = '2026-10-20T00:00:01Z';
      final result = c2cTimeline(
        [C2cMessage.fromJson(second), C2cMessage.fromJson(first)],
        [
          {
            'eventId': '1',
            'createdAt': '2026-10-20T00:00:01.500Z',
            'type': 'ORDER_CREATED',
          },
        ],
      );
      expect(
        result
            .where((item) => item.message != null)
            .map((item) => item.message!.id),
        ['9223372036854775806', '9223372036854775807'],
      );
      expect(result.first.event?['eventId'], '1');
    },
  );
  late HttpServer server;
  late ApiClient api;
  late Future<void> Function(HttpRequest request) handler;
  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await handler(request);
    });
    api = ApiClient(
      AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
    )..setSession(session(12));
  });
  tearDown(() async {
    await server.close(force: true);
  });
  Future<void> reply(
    HttpRequest request,
    Object value, {
    int status = 200,
  }) async {
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(value));
    await request.response.close();
  }

  test(
    'recent and older history use trading auth and preserve exact int64 message IDs',
    () async {
      final queries = <Map<String, String>>[];
      handler = (request) async {
        expect(
          request.uri.path,
          '/api/v1/c2c/conversations/$conversationId/messages',
        );
        expect(request.headers.value('Authorization'), 'Bearer qa-12');
        queries.add(request.uri.queryParameters);
        await reply(request, page());
      };
      final latest = await api.c2cMessages(12, conversationId, latest: true);
      expect(latest.messages.single.id, '9223372036854775807');
      await api.c2cMessages(12, conversationId, before: '9223372036854775807');
      expect(queries, [
        {'limit': '50', 'latest': 'true'},
        {'limit': '50', 'before': '9223372036854775807'},
      ]);
    },
  );
  test('all order states and searches use actual gateway routes', () async {
    final queries = <Uri>[];
    handler = (request) async {
      queries.add(request.uri);
      await reply(request, {'items': [], 'hasMore': false});
    };
    await api.c2cOrders(12, offset: 30);
    await api.c2cConversations(12, search: 'maker /%');
    expect(queries.first.path, '/api/v1/c2c/orders');
    expect(queries.first.queryParameters, {
      'state': 'ALL',
      'offset': '30',
      'limit': '30',
    });
    expect(queries.last.queryParameters['search'], 'maker /%');
  });
  test(
    'one uncertain send is never posted again by the API and recovery only reads',
    () async {
      var posts = 0;
      final body = {
        'requestId': requestId,
        'text': 'original text',
        'attachmentId': null,
      };
      handler = (request) async {
        if (request.method == 'POST') {
          posts++;
          expect(jsonDecode(await utf8.decoder.bind(request).join()), body);
          await reply(request, {'message': 'temporary outage'}, status: 503);
        } else {
          expect(request.uri.path.endsWith('/requests/$requestId'), isTrue);
          await reply(request, {
            'status': 'SENT',
            'message': message('9223372036854775807'),
          });
        }
      };
      await expectLater(
        api.c2cSend(12, conversationId, body),
        throwsA(isA<ApiException>()),
      );
      final receipt = await api.c2cReceipt(12, conversationId, requestId);
      expect(receipt.message!.id, '9223372036854775807');
      expect(posts, 1);
    },
  );
  test(
    'another account cannot fetch or receive the previous private conversation',
    () async {
      var requests = 0;
      final opened = Completer<void>(), release = Completer<void>();
      handler = (request) async {
        requests++;
        expect(request.headers.value('Authorization'), 'Bearer qa-12');
        opened.complete();
        await release.future;
        await reply(request, page());
      };
      final result = api.c2cMessages(12, conversationId, latest: true);
      final checked = expectLater(
        result,
        throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 401)),
      );
      await opened.future;
      api.setSession(session(13));
      release.complete();
      await checked;
      await expectLater(
        api.c2cMessages(12, conversationId),
        throwsA(isA<ApiException>()),
      );
      await expectLater(
        api.c2cDownload(12, attachmentId),
        throwsA(isA<ApiException>()),
      );
      expect(requests, 1);
    },
  );
  test(
    'private multipart upload keeps fixed identity, scope and UTF-8 filename; download uses auth',
    () async {
      final bytes = Uint8List.fromList(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jp1sAAAAASUVORK5CYII=',
        ),
      );
      handler = (request) async {
        expect(request.headers.value('Authorization'), 'Bearer qa-12');
        if (request.method == 'POST') {
          expect(request.uri.path, '/api/v1/c2c/attachments/$attachmentId');
          expect(request.headers.contentType!.mimeType, 'multipart/form-data');
          final body = latin1.decode(
            await request.fold<List<int>>(
              [],
              (all, chunk) => all..addAll(chunk),
            ),
          );
          expect(body, contains('name="purpose"\r\n\r\nMESSAGE'));
          expect(
            body,
            contains('name="conversationId"\r\n\r\n$conversationId'),
          );
          expect(
            body,
            contains("filename*=UTF-8''${Uri.encodeComponent('凭证.png')}"),
          );
          await reply(request, {
            'attachmentId': attachmentId,
            'name': '凭证.png',
            'contentType': 'image/png',
            'byteCount': bytes.length,
            'status': 'READY',
          });
        } else {
          expect(
            request.uri.path,
            '/api/v1/c2c/attachments/$attachmentId/content',
          );
          request.response.add(bytes);
          await request.response.close();
        }
      };
      final conversation = C2cConversation.fromJson({
        'conversationId': conversationId,
        'orderId': null,
        'peer': {'userId': '11', 'nickname': 'Maker'},
        'unreadCount': '0',
      });
      final uploaded = await api.c2cUpload(
        12,
        conversation,
        attachmentId,
        '凭证.png',
        'image/png',
        bytes,
      );
      expect(uploaded.status, 'READY');
      expect(await api.c2cDownload(12, attachmentId), bytes);
    },
  );
  test(
    'history and replay deduplicate exact identities and UUIDs use version four',
    () {
      expect(
        mergeC2cMessages(
          [C2cMessage.fromJson(message('9223372036854775807'))],
          [
            C2cMessage.fromJson(message('9223372036854775806')),
            C2cMessage.fromJson(message('9223372036854775807')),
          ],
        ).map((m) => m.id),
        ['9223372036854775806', '9223372036854775807'],
      );
      expect(() => c2cId('9223372036854775808'), throwsFormatException);
      expect(
        c2cUuid(),
        matches(
          RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
          ),
        ),
      );
    },
  );
}
