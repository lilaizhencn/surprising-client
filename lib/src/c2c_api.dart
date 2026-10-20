part of 'api.dart';

/// HTTP and uploads use the existing trading login and refresh lifecycle.
extension C2cApi on ApiClient {
  void _requireC2cOwner(int owner) {
    if (_sessionUserId != owner || _accessToken == null) {
      throw ApiException(401, '登录账户已变化，请重新打开聊天');
    }
  }

  Future<Map<String, dynamic>> _c2cGet(
    int owner,
    String path, {
    Map<String, String>? query,
  }) async {
    _requireC2cOwner(owner);
    final value = await get('/api/v1/c2c$path', userId: owner, query: query);
    _requireC2cOwner(owner);
    return value;
  }

  Future<Map<String, dynamic>> _c2cPost(
    int owner,
    String path,
    Map<String, dynamic> body,
  ) async {
    _requireC2cOwner(owner);
    final value = await post('/api/v1/c2c$path', body, userId: owner);
    _requireC2cOwner(owner);
    return value;
  }

  Future<Map<String, dynamic>> c2cStatus() => get('/api/v1/c2c/status');
  Future<({List<C2cConversation> items, bool hasMore})> c2cConversations(
    int owner, {
    String search = '',
    int offset = 0,
  }) async {
    final value = await _c2cGet(
      owner,
      '/conversations',
      query: {'search': search, 'offset': '$offset', 'limit': '30'},
    );
    return (
      items: asList(
        value['items'],
      ).map((v) => C2cConversation.fromJson(asMap(v))).toList(),
      hasMore: value['hasMore'] == true,
    );
  }

  Future<C2cConversation> c2cStart(
    int owner, {
    String? orderId,
    String? targetUserId,
  }) async => C2cConversation.fromJson(
    await _c2cPost(owner, '/conversations', {
      'orderId': ?orderId,
      'targetUserId': ?targetUserId,
    }),
  );
  Future<C2cMessagePage> c2cMessages(
    int owner,
    String conversation, {
    bool latest = false,
    String? before,
    String? after,
    String? afterEvent,
  }) async => C2cMessagePage.fromJson(
    await _c2cGet(
      owner,
      '/conversations/${Uri.encodeComponent(conversation)}/messages',
      query: {
        'limit': '50',
        if (latest) 'latest': 'true',
        'before': ?before,
        'after': ?after,
        'afterEvent': ?afterEvent,
      },
    ),
  );
  Future<C2cMessage> c2cSend(
    int owner,
    String conversation,
    Map<String, dynamic> original,
  ) async => C2cMessage.fromJson(
    await _c2cPost(
      owner,
      '/conversations/${Uri.encodeComponent(conversation)}/messages',
      original,
    ),
  );
  Future<({String status, C2cMessage? message})> c2cReceipt(
    int owner,
    String conversation,
    String request,
  ) async {
    final value = await _c2cGet(
      owner,
      '/conversations/${Uri.encodeComponent(conversation)}/requests/${Uri.encodeComponent(request)}',
    );
    if (value['status'] == 'UNKNOWN') return (status: 'UNKNOWN', message: null);
    if (value['status'] != 'SENT') throw const FormatException('消息回执无效');
    return (
      status: 'SENT',
      message: C2cMessage.fromJson(asMap(value['message'])),
    );
  }

  Future<void> c2cRead(
    int owner,
    String conversation,
    String message,
    String event,
  ) async {
    await _c2cPost(
      owner,
      '/conversations/${Uri.encodeComponent(conversation)}/read',
      {'messageId': message, 'eventId': event},
    );
  }

  Future<Map<String, dynamic>> c2cOrders(int owner, {int offset = 0}) =>
      _c2cGet(
        owner,
        '/orders',
        query: {'state': 'ALL', 'offset': '$offset', 'limit': '30'},
      );
  Future<Map<String, dynamic>> c2cOrder(int owner, String id) =>
      _c2cGet(owner, '/orders/${Uri.encodeComponent(id)}');
  Future<List<Map<String, dynamic>>> c2cQuickReplies(int owner) async => asList(
    (await _c2cGet(owner, '/me/quick-replies'))['items'],
  ).map(asMap).toList();
  Future<Map<String, dynamic>> c2cUploadReceipt(int owner, String id) =>
      _c2cGet(owner, '/attachments/${Uri.encodeComponent(id)}');

  Future<T> _c2cMedia<T>(
    int owner,
    Future<T> Function(String token) operation,
  ) async {
    _requireC2cOwner(owner);
    final originalToken = _accessToken!;
    try {
      final value = await operation(originalToken);
      _requireC2cOwner(owner);
      return value;
    } on ApiException catch (error) {
      if (error.statusCode != 401 ||
          _sessionUserId != owner ||
          _accessToken != originalToken ||
          _refreshToken == null) {
        rethrow;
      }
      await _refreshAccessToken();
      _requireC2cOwner(owner);
      final value = await operation(_accessToken!);
      _requireC2cOwner(owner);
      return value;
    }
  }

  Future<C2cAttachment> c2cUpload(
    int owner,
    C2cConversation conversation,
    String id,
    String name,
    String contentType,
    Uint8List bytes,
  ) {
    if (bytes.isEmpty ||
        bytes.length > 10485760 ||
        !['image/jpeg', 'image/png', 'application/pdf'].contains(contentType)) {
      throw const FormatException('请选择 10 MB 以内的 JPG、PNG 或 PDF');
    }
    return _c2cMedia(owner, (token) async {
      final request = await _httpClient
          .postUrl(
            Uri.parse(config.gatewayBaseUrl).replace(
              path: '/api/v1/c2c/attachments/${Uri.encodeComponent(id)}',
            ),
          )
          .timeout(const Duration(seconds: 6));
      if (_sessionUserId != owner || _accessToken != token) {
        request.abort();
        throw ApiException(401, '登录账户已变化，未上传文件');
      }
      final boundary = 'c2c-${DateTime.now().microsecondsSinceEpoch}';
      request.headers.contentType = ContentType(
        'multipart',
        'form-data',
        parameters: {'boundary': boundary},
      );
      request.headers.set('Authorization', 'Bearer $token');
      for (final entry in {
        'purpose': 'MESSAGE',
        'conversationId': conversation.id,
        if (conversation.orderId != null) 'orderId': conversation.orderId!,
      }.entries) {
        request.write(
          '--$boundary\r\nContent-Disposition: form-data; name="${entry.key}"\r\n\r\n${entry.value}\r\n',
        );
      }
      request.write(
        '--$boundary\r\nContent-Disposition: form-data; name="file"; filename="${_safeFileName(name)}"; filename*=UTF-8\'\'${Uri.encodeComponent(name)}\r\nContent-Type: $contentType\r\n\r\n',
      );
      request.add(bytes);
      request.write('\r\n--$boundary--\r\n');
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      final raw = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw ApiException(response.statusCode, raw);
      }
      final attachment = C2cAttachment.fromJson(asMap(jsonDecode(raw)));
      if (attachment.id != id || attachment.status != 'READY') {
        throw const FormatException('上传结果待确认，请查询原请求');
      }
      return attachment;
    });
  }

  Future<Uint8List> c2cDownload(int owner, String id) => _c2cMedia(owner, (
    token,
  ) async {
    final request = await _httpClient
        .getUrl(
          Uri.parse(config.gatewayBaseUrl).replace(
            path: '/api/v1/c2c/attachments/${Uri.encodeComponent(id)}/content',
          ),
        )
        .timeout(const Duration(seconds: 6));
    if (_sessionUserId != owner || _accessToken != token) {
      request.abort();
      throw ApiException(401, '登录账户已变化');
    }
    request.headers.set('Authorization', 'Bearer $token');
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException(
        response.statusCode,
        await utf8.decodeStream(response),
      );
    }
    final bytes = BytesBuilder();
    await for (final chunk in response.timeout(const Duration(seconds: 20))) {
      if (bytes.length + chunk.length > 10485760) {
        throw const FormatException('附件超过大小限制');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  });
}
