import 'dart:math';
import 'models.dart';

String c2cId(Object? value) {
  if (value is! String ||
      !RegExp(r'^(0|[1-9][0-9]{0,18})$').hasMatch(value) ||
      BigInt.parse(value) > BigInt.parse('9223372036854775807')) {
    throw const FormatException('聊天标识资料不完整');
  }
  return value;
}

String c2cUuid() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

String c2cMaximum(Iterable<String> values) => values.fold(
  '0',
  (max, id) => BigInt.parse(c2cId(id)) > BigInt.parse(max) ? id : max,
);

class C2cAttachment {
  C2cAttachment.fromJson(Map<String, dynamic> json)
    : id = asString(json['attachmentId']),
      name = asString(json['name']),
      contentType = asString(json['contentType']),
      status = asString(json['status']),
      bytes = asInt(json['byteCount']);
  final String id, name, contentType, status;
  final int bytes;
  bool get isImage => contentType == 'image/jpeg' || contentType == 'image/png';
}

class C2cMessage {
  C2cMessage.fromJson(Map<String, dynamic> json)
    : id = c2cId(json['messageId']),
      conversationId = asString(json['conversationId']),
      requestId = asString(json['requestId']),
      sender = json['senderUserId'] == null
          ? null
          : c2cId(json['senderUserId']),
      authorKind = asString(json['authorKind']),
      text = asString(json['text']),
      createdAt = DateTime.parse(asString(json['createdAt'])),
      attachment = json['attachment'] == null
          ? null
          : C2cAttachment.fromJson(asMap(json['attachment'])) {
    if (!['USER', 'SUPPORT', 'SYSTEM'].contains(authorKind) ||
        json['status'] != 'SENT') {
      throw const FormatException('聊天消息资料不完整');
    }
  }
  final String id, conversationId, requestId, authorKind, text;
  final String? sender;
  final DateTime createdAt;
  final C2cAttachment? attachment;
}

class C2cConversation {
  C2cConversation.fromJson(Map<String, dynamic> json)
    : id = asString(json['conversationId']),
      orderId = json['orderId'] as String?,
      peerId = c2cId(asMap(json['peer'])['userId']),
      nickname = asString(asMap(json['peer'])['nickname']),
      unread = c2cId(json['unreadCount']),
      lastText = asString(asMap(json['lastMessage'])['text']),
      hasAttachment = asMap(json['lastMessage'])['hasAttachment'] == true,
      orderStatus = asString(asMap(json['order'])['status']);
  final String id, peerId, nickname, unread, lastText, orderStatus;
  final String? orderId;
  final bool hasAttachment;
}

class C2cMessagePage {
  C2cMessagePage.fromJson(Map<String, dynamic> json)
    : conversationId = asString(json['conversationId']),
      messages = asList(
        json['messages'],
      ).map((value) => C2cMessage.fromJson(asMap(value))).toList(),
      events = asList(json['orderEvents']).map(asMap).toList(),
      reads = asList(json['reads']).map(asMap).toList(),
      hasOlder = json['hasMore'] == true {
    if (json['messages'] is! List ||
        json['orderEvents'] is! List ||
        json['reads'] is! List) {
      throw const FormatException('聊天分页资料不完整');
    }
    for (final event in events) {
      c2cId(event['eventId']);
      DateTime.parse(asString(event['createdAt']));
    }
    for (final read in reads) {
      for (final key in ['userId', 'messageId', 'eventId', 'revision']) {
        c2cId(read[key]);
      }
    }
  }
  final String conversationId;
  final List<C2cMessage> messages;
  final List<Map<String, dynamic>> events, reads;
  final bool hasOlder;
}

List<C2cMessage> mergeC2cMessages(
  Iterable<C2cMessage> previous,
  Iterable<C2cMessage> next,
) =>
    {
        for (final message in [...previous, ...next]) message.id: message,
      }.values.toList()
      ..sort((a, b) => BigInt.parse(a.id).compareTo(BigInt.parse(b.id)));
String c2cOrderStatus(String status) =>
    const {
      'RESERVING': '资金托管中',
      'PAYMENT_PENDING': '待付款',
      'PAID': '买方已标记付款',
      'APPEALED': '申诉中',
      'RELEASE_PENDING': '放币处理中',
      'REFUND_PENDING': '退款处理中',
      'COMPLETED': '已完成',
      'CANCELED': '已取消',
      'EXPIRED': '已过期',
      'FAILED': '失败',
    }[status] ??
    status;

typedef C2cTimelineItem = ({
  DateTime time,
  C2cMessage? message,
  Map<String, dynamic>? event,
});

/// PostgreSQL transaction start timestamps can precede another transaction's
/// commit. Keep message and event identities in their own authoritative order.
List<C2cTimelineItem> c2cTimeline(
  List<C2cMessage> messages,
  List<Map<String, dynamic>> events,
) {
  final result = <C2cTimelineItem>[];
  final orderedEvents = List<Map<String, dynamic>>.of(events)
    ..sort(
      (a, b) => BigInt.parse(
        c2cId(a['eventId']),
      ).compareTo(BigInt.parse(c2cId(b['eventId']))),
    );
  var nextEvent = 0;
  DateTime? messageTime, eventTime;
  for (final message in mergeC2cMessages([], messages)) {
    final previousMessageTime = messageTime;
    messageTime =
        previousMessageTime == null ||
            message.createdAt.isAfter(previousMessageTime)
        ? message.createdAt
        : previousMessageTime;
    while (nextEvent < orderedEvents.length) {
      final event = orderedEvents[nextEvent],
          date = DateTime.parse(
            asString(orderedEvents[nextEvent]['createdAt']),
          );
      final previousEventTime = eventTime;
      final time = previousEventTime == null || date.isAfter(previousEventTime)
          ? date
          : previousEventTime;
      if (time.isAfter(messageTime)) break;
      result.add((time: date, message: null, event: event));
      eventTime = time;
      nextEvent++;
    }
    result.add((time: message.createdAt, message: message, event: null));
  }
  for (final event in orderedEvents.skip(nextEvent)) {
    result.add((
      time: DateTime.parse(asString(event['createdAt'])),
      message: null,
      event: event,
    ));
  }
  return result;
}
