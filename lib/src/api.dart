import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'models.dart';
import 'option_market.dart';
import 'account_records.dart';

class ApiClient {
  ApiClient(this.config, {HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 5);
  }

  final AppConfig config;
  List<Instrument> instrumentCatalog = [];
  final HttpClient _httpClient;
  String? _accessToken;
  int? _sessionUserId;
  String? _refreshToken;
  Future<AuthSession?>? _refreshInFlight;

  Future<void> Function(AuthSession session)? onSessionRefreshed;
  Future<void> Function()? onSessionExpired;

  void setSession(AuthSession? session) {
    _sessionUserId = session?.user.userId;
    _accessToken = session?.accessToken;
    _refreshToken = session?.refreshToken;
  }

  void setAccessToken(String? accessToken) {
    _sessionUserId = null;
    _accessToken = accessToken == null || accessToken.trim().isEmpty
        ? null
        : accessToken.trim();
  }

  Future<AuthSession> refresh(String refreshToken) async {
    final response = await _sendOnce(
      'POST',
      '/api/v1/auth/refresh',
      body: {'refreshToken': refreshToken},
    );
    final session = AuthSession.fromJson(asMap(response));
    return session;
  }

  Future<AuthSession> register({
    required String password,
    required String email,
    bool phone = false,
  }) async {
    final json = await post('/api/v1/auth/register', {
      'password': password,
      if (phone) 'phone': email else 'email': email,
    });
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> login({
    required String username,
    required String password,
  }) async {
    final json = await post('/api/v1/auth/login', {
      'identifier': username,
      'password': password,
    });
    if (json['requiresVerification'] == true) {
      throw LoginChallenge.fromJson(json);
    }
    return AuthSession.fromJson(json);
  }

  Future<AuthSession> verifyLogin(
    LoginChallenge challenge,
    Map<String, String> codes,
  ) async {
    return AuthSession.fromJson(
      await post('/api/v1/auth/login/verify', {
        'challengeToken': challenge.token,
        ...codes,
      }),
    );
  }

  Future<bool> verifyEmail(AuthSession session, String code) async {
    setAccessToken(session.accessToken);
    final response = await _send(
      'POST',
      '/api/v1/auth/verify-email',
      body: {'email': session.user.email, 'code': code},
    );
    return response == true ||
        (response is Map && response['verified'] == true);
  }

  Future<Map<String, dynamic>> resendEmailVerification(AuthSession session) {
    setAccessToken(session.accessToken);
    return post('/api/v1/auth/resend-email-verification', {});
  }

  Future<bool> forgotPassword(String identifier) async {
    final json = await post('/api/v1/auth/forgot-password', {
      'identifier': identifier,
    });
    return json['accepted'] != false;
  }

  Future<bool> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    final json = await post('/api/v1/auth/reset-password', {
      'identifier': identifier,
      'code': code,
      'newPassword': newPassword,
    });
    return json['accepted'] == true || json.isEmpty;
  }

  Future<List<Map<String, dynamic>>> loginVerificationMethods() async => asList(
    await _send('GET', '/api/v1/security/login-verification'),
  ).map(asMap).toList();

  Future<Map<String, dynamic>> beginLoginMethod({
    required String method,
    required String currentPassword,
    required bool enabled,
    String? destination,
  }) => post('/api/v1/security/login-verification/$method/bind', {
    'currentPassword': currentPassword,
    'enabled': enabled,
    if (destination != null && destination.trim().isNotEmpty)
      'destination': destination.trim(),
  });

  Future<void> confirmLoginMethod({
    required String method,
    required String currentPassword,
    required String challengeToken,
    String? emailCode,
    String? phoneCode,
    String? totpCode,
  }) async {
    await post('/api/v1/security/login-verification/$method/confirm', {
      'currentPassword': currentPassword,
      'codes': {
        'challengeToken': challengeToken,
        if (emailCode != null && emailCode.isNotEmpty) 'emailCode': emailCode,
        if (phoneCode != null && phoneCode.isNotEmpty) 'phoneCode': phoneCode,
        if (totpCode != null && totpCode.isNotEmpty) 'totpCode': totpCode,
      },
    });
  }

  Future<Map<String, dynamic>> userSessions({String? cursor}) => get(
    '/api/v1/security/sessions',
    query: {'active': 'true', 'limit': '100', 'cursor': ?cursor},
  );

  Future<Map<String, dynamic>> loginHistory({String? cursor}) => get(
    '/api/v1/security/login-history',
    query: {'limit': '100', 'cursor': ?cursor},
  );

  Future<void> revokeUserSession(String sessionId) async {
    await post(
      '/api/v1/security/sessions/${Uri.encodeComponent(sessionId)}/revoke',
      const {},
    );
  }

  Future<void> revokeOtherSessions(String refreshToken) async {
    await post('/api/v1/security/sessions/revoke-all', {
      'refreshToken': refreshToken,
    });
  }

  Future<List<Map<String, dynamic>>> devices() async => asList(
    await _send('GET', '/api/v1/security/devices'),
  ).map(asMap).toList();

  Future<void> revokeDevice(String deviceId) async {
    await post(
      '/api/v1/security/devices/${Uri.encodeComponent(deviceId)}/revoke',
      const {},
    );
  }

  Future<void> setDeviceBlocked(
    String deviceId,
    bool blocked,
    String emailCode,
    String totpCode,
  ) async {
    await post(
      '/api/v1/security/devices/${Uri.encodeComponent(deviceId)}/${blocked ? 'block' : 'unblock'}',
      {'emailCode': emailCode, 'totpCode': totpCode},
    );
  }

  Future<List<Map<String, dynamic>>> loginIps() async =>
      asList(await _send('GET', '/api/v1/security/ips')).map(asMap).toList();

  Future<void> setIpBlocked(
    String ipAddress,
    bool blocked,
    String emailCode,
    String totpCode,
  ) async {
    await post('/api/v1/security/ips/${blocked ? 'block' : 'unblock'}', {
      'ipAddress': ipAddress,
      'emailCode': emailCode,
      'totpCode': totpCode,
    });
  }

  Future<Map<String, String>> assetScales() async {
    final result = await get('/api/v1/gateway/instrument/asset-scales');
    return result.map((key, value) => MapEntry(key.toUpperCase(), '$value'));
  }

  Future<({int takerFeeRatePpm, int marketMaxSlippagePpm})> spotOrderTerms(
    int userId,
    Instrument instrument,
  ) async {
    if (!instrument.isSpot || instrument.changeId == null) {
      throw const FormatException('下单资料未就绪');
    }
    return _tradingOrderTerms(userId, instrument);
  }

  Future<({int takerFeeRatePpm, int marketMaxSlippagePpm})> optionOrderTerms(
    int userId,
    Instrument instrument,
  ) async {
    if (!instrument.isOption || instrument.changeId == null) {
      throw const FormatException('下单资料未就绪');
    }
    return _tradingOrderTerms(userId, instrument);
  }

  Future<({int takerFeeRatePpm, int marketMaxSlippagePpm})> _tradingOrderTerms(
    int userId,
    Instrument instrument,
  ) async {
    final line = instrument.mode.productLine;
    final results = await Future.wait([
      get(
        '/api/v1/gateway/trading-fees/effective',
        userId: userId,
        productLine: line,
        query: {'instrumentId': instrument.instrumentId, 'productLine': line},
      ),
      get(
        '/api/v1/gateway/trading/price-protection',
        userId: userId,
        productLine: line,
      ),
    ]);
    final fee = int.tryParse('${results[0]['takerFeeRatePpm']}');
    final slip = int.tryParse('${results[1]['marketMaxSlippagePpm']}');
    if (results[0]['productLine'] != line ||
        asString(results[0]['instrumentId']) != instrument.instrumentId ||
        asInt(results[0]['userId']) != userId ||
        asInt(results[0]['changeId']) != instrument.changeId ||
        results[1]['productLine'] != line ||
        fee == null ||
        fee.abs() > 1000000 ||
        slip == null ||
        slip < 0 ||
        slip >= 1000000) {
      throw const FormatException('下单资料不匹配，请刷新后重试');
    }
    return (takerFeeRatePpm: fee, marketMaxSlippagePpm: slip);
  }

  Future<OptionReference> optionReference(Instrument instrument) async {
    if (!instrument.isOption) throw const FormatException('期权产品线不匹配');
    final quote = OptionReference.fromJson(
      await get(
        '/api/v1/gateway/candlestick/options/quote',
        query: {'instrumentId': instrument.instrumentId},
        productLine: 'OPTION',
      ),
    );
    if (!quote.matches(instrument)) {
      throw const FormatException('期权参考报价已过期或合约不匹配');
    }
    return quote;
  }

  Future<AccountRecordPage> accountRecords({
    required String category,
    required int userId,
    required ProductMode product,
    String asset = '',
    String referenceType = '',
    String instrumentId = '',
    String status = '',
    DateTime? from,
    DateTime? to,
    String? cursor,
  }) async {
    if (category == 'external-transfer') {
      final pages = await Future.wait(
        ['deposit', 'withdrawal'].map(
          (kind) => accountRecords(
            category: kind,
            userId: userId,
            product: product,
            asset: asset,
          ),
        ),
      );
      final rows = [
        for (var i = 0; i < pages.length; i++)
          ...pages[i].rows.map(
            (row) => {
              ...row,
              'referenceType': i == 0 ? 'DEPOSIT' : 'WITHDRAWAL',
            },
          ),
      ];
      int time(Map<String, dynamic> row) =>
          DateTime.tryParse(
            asString(row['createdAt'] ?? row['updatedAt']),
          )?.millisecondsSinceEpoch ??
          0;
      rows.sort((left, right) => time(right).compareTo(time(left)));
      return AccountRecordPage(rows, null, false);
    }
    final query = <String, String>{
      'limit': '100',
      if (asset.trim().isNotEmpty) 'asset': asset.trim().toUpperCase(),
      if (referenceType.trim().isNotEmpty)
        'referenceType': referenceType.trim().toUpperCase(),
      if (status.trim().isNotEmpty) 'status': status.trim().toUpperCase(),
      if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
    };
    late String path, key;
    String? line;
    switch (category) {
      case 'funding-ledger':
        path = '/api/v1/gateway/account/ledger';
        key = 'entries';
      case 'option-exercise':
        if (!product.isOption) throw const FormatException('期权流水产品线不匹配');
        query['referenceType'] = 'OPTION_EXERCISE';
        continue productLedger;
      case 'delivery-ledger':
        if (product != ProductMode.linearDelivery &&
            product != ProductMode.inverseDelivery) {
          throw const FormatException('交割流水产品线不匹配');
        }
        query['referenceType'] = 'DELIVERY_SETTLEMENT';
        continue productLedger;
      productLedger:
      case 'product-ledger':
        path = '/api/v1/gateway/account/product-ledger';
        key = 'entries';
        query['accountType'] = product.accountType;
        line = product.productLine;
      case 'transfer':
        path = '/api/v1/gateway/account/transfers';
        key = 'transfers';
        query['accountType'] = product.accountType;
        line = product.productLine;
      case 'deposit':
        path = '/api/v1/wallet/deposits';
        key = 'deposits';
        query['limit'] = '50';
      case 'withdrawal':
        path = '/api/v1/wallet/withdrawals';
        key = 'withdrawals';
        query['limit'] = '50';
      case 'funding-payment':
        path = '/api/v1/gateway/funding/payments';
        key = 'payments';
        query['userId'] = '$userId';
        line = product.productLine;
        if (instrumentId.isNotEmpty) query['instrumentId'] = instrumentId;
      case 'trade':
        path = '/api/v1/gateway/trading/trades';
        key = 'trades';
        query['userId'] = '$userId';
        line = product.productLine;
        if (instrumentId.isNotEmpty) query['instrumentId'] = instrumentId;
        if (from != null) query['startTime'] = '${from.millisecondsSinceEpoch}';
        if (to != null) query['endTime'] = '${to.millisecondsSinceEpoch}';
      case 'order':
        path = '/api/v1/gateway/trading/history';
        key = 'orders';
        query['userId'] = '$userId';
        line = product.productLine;
        if (instrumentId.isNotEmpty) query['instrumentId'] = instrumentId;
        if (from != null) query['startTime'] = '${from.millisecondsSinceEpoch}';
        if (to != null) query['endTime'] = '${to.millisecondsSinceEpoch}';
      default:
        throw const FormatException('暂不支持该记录类型');
    }
    final response = await _send(
      'GET',
      path,
      query: query,
      userId: userId,
      productLine: line,
    );
    if (category == 'trade') {
      final page = asMap(response);
      final trades = asList(page['trades']);
      final next = asString(page['nextCursor']).trim();
      bool positive(Object? value) => (int.tryParse('$value') ?? 0) > 0;
      if (int.tryParse('${page['userId']}') != userId ||
          page['productLine'] != line ||
          page['trades'] is! List ||
          page['count'] != trades.length ||
          page['hasMore'] is! bool ||
          (page['hasMore'] == true && (next.isEmpty || next == cursor)) ||
          trades.any((raw) {
            final fill = asMap(raw);
            final fee = int.tryParse('${fill['feeRatePpm']}');
            return !asString(fill['tradeId']).startsWith('$line:') ||
                fill['productLine'] != line ||
                !positive(fill['instrumentId']) ||
                (instrumentId.isNotEmpty &&
                    asString(fill['instrumentId']) != instrumentId) ||
                !positive(fill['orderId']) ||
                !positive(fill['priceTicks']) ||
                !positive(fill['quantitySteps']) ||
                !['BUY', 'SELL'].contains(fill['side']) ||
                !['MAKER', 'TAKER'].contains(fill['liquidityRole']) ||
                !['NET', 'LONG', 'SHORT'].contains(fill['positionSide']) ||
                fee == null ||
                fee.abs() > 1000000 ||
                DateTime.tryParse(asString(fill['eventTime'])) == null;
          })) {
        throw const FormatException('成交记录身份、内容或分页资料不匹配');
      }
    }
    if (category == 'order') {
      final page = asMap(response);
      final orders = asList(page['orders']);
      final next = page['nextCursor'];
      bool integer(Object? value, {bool positive = false}) {
        final n = BigInt.tryParse('$value');
        return n != null &&
            n >= (positive ? BigInt.one : BigInt.zero) &&
            n <= BigInt.parse('9223372036854775807');
      }

      if (page['orders'] is! List ||
          page['count'] != orders.length ||
          page['limit'] is! int ||
          (page['limit'] as int) < orders.length ||
          (page['limit'] as int) < 1 ||
          (page['limit'] as int) > 1000 ||
          page['sort'] != 'updatedAt.desc' ||
          page['hasMore'] is! bool ||
          (page['hasMore'] == true
              ? next is! String || next.trim().isEmpty || next == cursor
              : next != null) ||
          orders.any((raw) {
            final order = asMap(raw);
            final average = order['averagePriceTicks'];
            return asString(order['userId']) != '$userId' ||
                !integer(order['orderId'], positive: true) ||
                !integer(order['instrumentId'], positive: true) ||
                (instrumentId.isNotEmpty &&
                    asString(order['instrumentId']) != instrumentId) ||
                (status.trim().isNotEmpty &&
                    order['status'] != status.trim().toUpperCase()) ||
                !['BUY', 'SELL'].contains(order['side']) ||
                !['LIMIT', 'MARKET'].contains(order['orderType']) ||
                !['REJECTED', 'CANCELED', 'FILLED'].contains(order['status']) ||
                !integer(order['priceTicks']) ||
                !integer(order['quantitySteps'], positive: true) ||
                !integer(order['executedQuantitySteps']) ||
                !integer(order['remainingQuantitySteps']) ||
                BigInt.parse('${order['executedQuantitySteps']}') >
                    BigInt.parse('${order['quantitySteps']}') ||
                BigInt.parse('${order['remainingQuantitySteps']}') >
                    BigInt.parse('${order['quantitySteps']}') ||
                int.tryParse('${order['cumulativeFeeUnits']}') == null ||
                (average != null &&
                    (average is! String ||
                        !RegExp(r'^\d+(?:\.\d+)?$').hasMatch(average))) ||
                DateTime.tryParse(asString(order['createdAt'])) == null ||
                DateTime.tryParse(asString(order['updatedAt'])) == null;
          })) {
        throw const FormatException('历史委托身份、内容或分页资料不匹配');
      }
    }
    return AccountRecordPage.fromJson(response, key);
  }

  Future<List<Map<String, dynamic>>> kycCountries() async => asList(
    await _send('GET', '/api/v1/compliance/countries'),
  ).map(asMap).toList();

  Future<void> deleteKycDocument(int id) async {
    await _send('DELETE', '/api/v1/compliance/kyc/documents/$id');
  }

  Future<Map<String, dynamic>> mfaStatus() => get('/api/v1/security/mfa');

  Future<Map<String, dynamic>> enrollMfa(String currentPassword) =>
      post('/api/v1/security/mfa/enroll', {'currentPassword': currentPassword});

  Future<Map<String, dynamic>> confirmMfa({
    required String challengeToken,
    required String currentPassword,
    String? emailCode,
    String? phoneCode,
    required String totpCode,
  }) => post('/api/v1/security/mfa/confirm', {
    'currentPassword': currentPassword,
    'codes': {
      'challengeToken': challengeToken,
      if (emailCode != null && emailCode.isNotEmpty) 'emailCode': emailCode,
      if (phoneCode != null && phoneCode.isNotEmpty) 'phoneCode': phoneCode,
      'totpCode': totpCode,
    },
  });

  Future<Map<String, dynamic>> beginMfaDisable(String currentPassword) => post(
    '/api/v1/security/mfa/disable',
    {'currentPassword': currentPassword},
  );

  Future<Map<String, dynamic>> confirmMfaDisable({
    required String challengeToken,
    required String currentPassword,
    String? emailCode,
    String? phoneCode,
    required String totpCode,
  }) => post('/api/v1/security/mfa/disable/confirm', {
    'currentPassword': currentPassword,
    'codes': {
      'challengeToken': challengeToken,
      if (emailCode != null && emailCode.isNotEmpty) 'emailCode': emailCode,
      if (phoneCode != null && phoneCode.isNotEmpty) 'phoneCode': phoneCode,
      'totpCode': totpCode,
    },
  });

  Future<Map<String, dynamic>> mfaRecoveryStatus() =>
      get('/api/v1/security/mfa/recovery');

  Future<Map<String, dynamic>> issueMfaRecoveryChallenge(
    String currentPassword,
  ) => post('/api/v1/security/mfa/recovery/challenge', {
    'currentPassword': currentPassword,
  });

  Future<Map<String, dynamic>> submitMfaRecovery({
    required int challengeId,
    required String currentPassword,
    required String code,
    required String reason,
  }) => post('/api/v1/security/mfa/recovery', {
    'challengeId': challengeId,
    'currentPassword': currentPassword,
    'code': code,
    'reason': reason,
  });

  Future<List<Map<String, dynamic>>> securityScenes() async {
    final response = await _send('GET', '/api/v1/security/scenes');
    return asList(response).map(asMap).toList();
  }

  Future<Map<String, dynamic>> updateSecurityScene(
    String sceneCode,
    bool enabled, {
    String? emailCode,
    String? totpCode,
  }) {
    return _sendMap(
      'PUT',
      '/api/v1/security/scenes/$sceneCode',
      body: {
        'enabled': enabled,
        if (emailCode != null && emailCode.isNotEmpty) 'emailCode': emailCode,
        if (totpCode != null && totpCode.isNotEmpty) 'totpCode': totpCode,
      },
    );
  }

  Future<Map<String, dynamic>> issueSecurityChallenge(String sceneCode) {
    return post('/api/v1/security/verification/challenge', {
      'sceneCode': sceneCode,
    });
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    String? emailCode,
    String? totpCode,
  }) async {
    await post('/api/v1/security/password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
      if (emailCode != null && emailCode.trim().isNotEmpty)
        'emailCode': emailCode.trim(),
      if (totpCode != null && totpCode.trim().isNotEmpty)
        'totpCode': totpCode.trim(),
    });
  }

  Future<List<Map<String, dynamic>>> apiKeys() async {
    final response = await _send('GET', '/api/v1/security/api-keys');
    return asList(response).map(asMap).toList();
  }

  Future<Map<String, dynamic>> createApiKey({
    required String label,
    required List<String> permissions,
    List<String> ipAllowlist = const [],
    required String emailCode,
    required String totpCode,
  }) {
    return post(
      '/api/v1/security/api-keys',
      {'label': label, 'permissions': permissions, 'ipAllowlist': ipAllowlist},
      headers: {
        'X-Security-Email-Code': emailCode,
        'X-Security-TOTP-Code': totpCode,
      },
    );
  }

  Future<void> updateApiKeyAllowlist({
    required String apiKey,
    required List<String> ipAllowlist,
    required String emailCode,
    required String totpCode,
  }) async {
    await _sendMap(
      'PATCH',
      '/api/v1/security/api-keys',
      body: {'apiKey': apiKey, 'ipAllowlist': ipAllowlist},
      headers: {
        'X-Security-Email-Code': emailCode,
        'X-Security-TOTP-Code': totpCode,
      },
    );
  }

  Future<void> revokeApiKey({
    required String apiKey,
    required String emailCode,
    required String totpCode,
  }) async {
    await _sendMap(
      'DELETE',
      '/api/v1/security/api-keys',
      body: {'apiKey': apiKey},
      headers: {
        'X-Security-Email-Code': emailCode,
        'X-Security-TOTP-Code': totpCode,
      },
    );
  }

  Future<Map<String, dynamic>> kycStatus() async {
    final response = await _send('GET', '/api/v1/compliance/kyc');
    return asMap(response);
  }

  Future<Map<String, dynamic>> announcements({
    required String locale,
    required String productLine,
    required String platform,
    required String placement,
    int offset = 0,
    int limit = 50,
  }) {
    return get(
      '/api/v1/announcements',
      query: {
        'locale': locale,
        'productLine': productLine,
        'platform': platform,
        'placement': placement,
        'offset': '$offset',
        'limit': '$limit',
      },
    );
  }

  Future<Map<String, dynamic>> markAnnouncementRead({
    required int announcementId,
    required String productLine,
    required String platform,
    required String placement,
  }) {
    final query = Uri(
      queryParameters: {
        'productLine': productLine,
        'platform': platform,
        'placement': placement,
      },
    ).query;
    return post('/api/v1/announcements/$announcementId/read?$query', const {});
  }

  Future<Map<String, dynamic>> markAllAnnouncementsRead({
    required String productLine,
    required String platform,
    String placement = 'CENTER',
  }) {
    final query = Uri(
      queryParameters: {
        'productLine': productLine,
        'platform': platform,
        'placement': placement,
      },
    ).query;
    return post('/api/v1/announcements/read-all?$query', const {});
  }

  Future<List<Map<String, dynamic>>> kycDocuments() async {
    final response = await _send('GET', '/api/v1/compliance/kyc/documents');
    return asList(response).map(asMap).toList();
  }

  Future<Uint8List> downloadKycDocument(int id) async {
    Future<Uint8List> read() async {
      final uri = Uri.parse(
        config.gatewayBaseUrl,
      ).replace(path: '/api/v1/compliance/kyc/documents/$id');
      final request = await _httpClient
          .getUrl(uri)
          .timeout(const Duration(seconds: 6));
      request.headers.set(
        'X-Trace-Id',
        'mobile-${DateTime.now().microsecondsSinceEpoch}',
      );
      if (_accessToken != null) {
        request.headers.set('Authorization', 'Bearer $_accessToken');
      }
      final response = await request.close().timeout(
        const Duration(seconds: 20),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(
          response.statusCode,
          await utf8.decodeStream(response),
        );
      }
      final bytes = await response
          .fold<List<int>>([], (all, chunk) => all..addAll(chunk))
          .timeout(const Duration(seconds: 30));
      return Uint8List.fromList(bytes);
    }

    try {
      return await read();
    } on ApiException catch (error) {
      if (error.statusCode != 401 || _refreshToken == null) rethrow;
      if (await _refreshAccessToken() == null) rethrow;
      return read();
    }
  }

  Future<Map<String, dynamic>> uploadKycDocument({
    required String documentType,
    required String fileName,
    required List<int> bytes,
  }) async {
    final base = Uri.parse(config.gatewayBaseUrl);
    final uri = base.replace(path: '/api/v1/compliance/kyc/documents');
    final boundary = 'surprising-${DateTime.now().microsecondsSinceEpoch}';
    final request = await _httpClient
        .openUrl('POST', uri)
        .timeout(const Duration(seconds: 6));
    request.headers.contentType = ContentType(
      'multipart',
      'form-data',
      parameters: {'boundary': boundary},
    );
    request.headers.set(
      'X-Trace-Id',
      'mobile-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (_accessToken != null) {
      request.headers.set('Authorization', 'Bearer $_accessToken');
    }
    final contentType = _kycContentType(fileName);
    request.write('--$boundary\r\n');
    request.write(
      'Content-Disposition: form-data; name="documentType"\r\n\r\n',
    );
    request.write(documentType);
    request.write('\r\n--$boundary\r\n');
    request.write(
      'Content-Disposition: form-data; name="file"; filename="${_safeFileName(fileName)}"\r\n',
    );
    request.write('Content-Type: $contentType\r\n\r\n');
    request.add(bytes);
    request.write('\r\n--$boundary--\r\n');
    final response = await request.close().timeout(const Duration(seconds: 30));
    final payload = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        payload.isEmpty ? response.reasonPhrase : payload,
      );
    }
    return asMap(payload.isEmpty ? <String, dynamic>{} : jsonDecode(payload));
  }

  Future<Map<String, dynamic>> submitKyc({
    required String applicantType,
    required String kycLevel,
    required String country,
    required String documentType,
    required String provider,
    required String providerReference,
    required String faceVerificationStatus,
    required List<int> documentIds,
    String? documentExpiresOn,
    String? documentIssuedOn,
    String? addressIssuedOn,
  }) {
    return post('/api/v1/compliance/kyc', {
      'applicantType': applicantType,
      'kycLevel': kycLevel,
      'country': country,
      'documentType': documentType,
      'provider': provider,
      if (providerReference.trim().isNotEmpty)
        'providerReference': providerReference.trim(),
      'faceVerificationStatus': faceVerificationStatus,
      'documentIds': documentIds,
      'documentExpiresOn': documentExpiresOn,
      'documentIssuedOn': documentIssuedOn,
      'addressIssuedOn': addressIssuedOn,
    });
  }

  Future<Map<String, dynamic>> kycProvider() =>
      get('/api/v1/compliance/kyc/provider');

  Future<Map<String, dynamic>> completeKycSimulation(String decision) => post(
    '/api/v1/compliance/kyc/simulation/complete',
    {'decision': decision},
  );

  Future<Map<String, dynamic>> refreshKycSession() =>
      post('/api/v1/compliance/kyc/session/refresh', const {});

  // AppState publishes a complete, validated catalog after all required requests finish.
  /// Explicitly disabled products are different from enabled services that are offline.
  Future<Set<ProductMode>> disabledProducts() async {
    final runtime = await get('/api/v1/runtime');
    final disabled = runtime['disabledProductLines'];
    if (disabled is! List) throw const FormatException('产品线状态尚未同步');
    final result = <ProductMode>{};
    for (final value in disabled) {
      final mode = ProductMode.values
          .where((p) => p.productLine == value)
          .firstOrNull;
      if (mode == null || !result.add(mode)) {
        throw const FormatException('产品线状态无效');
      }
    }
    return result;
  }

  Future<List<Instrument>> instruments() =>
      _loadInstruments({'status': 'TRADING'});

  /// Visible lifecycle states remain selectable for existing expiring positions and orders.
  Future<List<Instrument>> expiringInstruments(ProductMode product) async {
    if (!product.isExpiring) throw const FormatException('到期合约目录产品线不匹配');
    final loaded = await _loadInstruments({'productLine': product.productLine});
    if (loaded.any((i) => i.mode != product)) {
      throw const FormatException('到期合约目录产品线不匹配');
    }
    return loaded;
  }

  /// Read historical metadata by identity without adding ended contracts to the default catalog.
  Future<Instrument> instrumentLatest(String id, ProductMode product) async {
    final scales = await assetScales();
    final raw = await get(
      '/api/v1/gateway/instrument/latest',
      query: {'instrumentId': id, 'productLine': product.productLine},
      productLine: product.productLine,
    );
    final instrument = Instrument.fromJson({
      ...raw,
      'baseScaleUnits': scales[asString(raw['baseAsset']).toUpperCase()],
      'quoteScaleUnits': scales[asString(raw['quoteAsset']).toUpperCase()],
      'settleScaleUnits': scales[asString(raw['settleAsset']).toUpperCase()],
    });
    if (instrument.instrumentId != id || instrument.mode != product) {
      throw const FormatException('合约资料产品线不匹配');
    }
    return instrument;
  }

  Future<List<Instrument>> _loadInstruments(Map<String, String> filters) async {
    final scales = await assetScales();
    final loaded = <String, Instrument>{};
    final cursors = <String>{};
    String? cursor;
    while (true) {
      final json = await get(
        '/api/v1/gateway/instrument/list',
        query: {...filters, 'includeMarketSummary': 'true', 'cursor': ?cursor},
      );
      for (final row in asList(json['instruments'] ?? json['items'])) {
        final raw = asMap(row);
        final instrument = Instrument.fromJson({
          ...raw,
          'baseScaleUnits': scales[asString(raw['baseAsset']).toUpperCase()],
          'quoteScaleUnits': scales[asString(raw['quoteAsset']).toUpperCase()],
          'settleScaleUnits':
              scales[asString(raw['settleAsset']).toUpperCase()],
        });
        loaded['${instrument.mode.productLine}:${instrument.instrumentId.isEmpty ? instrument.symbol : instrument.instrumentId}'] =
            instrument;
      }
      if (!asBool(json['hasMore'])) break;
      cursor = asString(json['nextCursor']);
      if (cursor.isEmpty || !cursors.add(cursor)) {
        throw const FormatException('合约列表分页游标无效');
      }
    }
    return loaded.values.toList();
  }

  Future<List<Map<String, dynamic>>> recentTrades(
    String symbol, {
    String? productLine,
  }) async {
    final json = await get(
      '/api/v1/gateway/candlestick/trades/recent',
      query: {'symbol': symbol, 'limit': '50'},
      productLine: productLine,
    );
    return asList(json['trades']).map(asMap).toList();
  }

  // Domain widgets retain display symbols; the current wire contract uses IDs.
  Object? normalizeInstruments(Object? value, String? productLine) {
    if (value is List) {
      return value.map((v) => normalizeInstruments(v, productLine)).toList();
    }
    if (value is! Map) return value;
    final row = Map<String, dynamic>.from(value);
    final product = asString(row['productLine'], fallback: productLine ?? '');
    final id = asString(row['instrumentId']);
    final instrument = instrumentCatalog
        .where(
          (i) =>
              i.instrumentId == id &&
              id.isNotEmpty &&
              (product.isEmpty || i.mode.productLine == product),
        )
        .firstOrNull;
    return {
      for (final entry in row.entries)
        entry.key: normalizeInstruments(entry.value, product),
      if (instrument != null && !row.containsKey('symbol'))
        'symbol': instrument.symbol,
    };
  }

  Future<OrderBook> orderBook(
    String symbol, {
    int depth = 50,
    String? productLine,
  }) async {
    final json = await get(
      '/api/v1/gateway/trading-market/orderbook',
      query: {'symbol': symbol, 'depth': '$depth'},
      productLine: productLine,
    );
    return OrderBook.fromJson(json);
  }

  Future<List<Candle>> candles(
    String symbol,
    String period, {
    String? productLine,
  }) async {
    final end = DateTime.now().toUtc();
    final interval = switch (period) {
      '1m' => const Duration(minutes: 1),
      '5m' => const Duration(minutes: 5),
      '15m' => const Duration(minutes: 15),
      '1h' => const Duration(hours: 1),
      '4h' => const Duration(hours: 4),
      _ => throw ArgumentError.value(
        period,
        'period',
        'Unsupported candle period',
      ),
    };
    final start = end.subtract(interval * 300);
    final json = await get(
      '/api/v1/gateway/candlestick/candles',
      query: {
        'symbol': symbol,
        'period': period,
        'startTime': start.toIso8601String(),
        'endTime': end.toIso8601String(),
        'limit': '300',
      },
      productLine: productLine,
    );
    return asList(
      json['candles'],
    ).map((item) => Candle.fromJson(asMap(item))).toList();
  }

  Future<double> exchangeRateConversion({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final json = await get(
      '/api/v1/gateway/price-fx/convert',
      query: {
        'amount': '1',
        'fromCurrency': fromCurrency,
        'toCurrency': toCurrency,
      },
    );
    final convertedAmount = asDouble(json['convertedAmount']);
    if (!convertedAmount.isFinite || convertedAmount <= 0) {
      throw const FormatException('估值汇率不可用');
    }
    return convertedAmount;
  }

  Future<List<ProductBalance>> productBalances(
    int userId, {
    String? accountType,
    String? productLine,
  }) async {
    final query = {'userId': '$userId'};
    if (accountType != null) query['accountType'] = accountType;
    final json = await get(
      '/api/v1/gateway/account/product-balances',
      query: query,
      productLine: productLine,
    );
    return asList(
      json['balances'],
    ).map((item) => ProductBalance.fromJson(asMap(item))).toList();
  }

  Future<Map<String, dynamic>> leverageSetting(
    int userId,
    Instrument instrument,
    String marginMode,
  ) => get(
    '/api/v1/gateway/trading-leverage/settings',
    query: {
      'userId': '$userId',
      'instrumentId': instrument.instrumentId,
      'productLine': instrument.mode.productLine,
      'marginMode': marginMode,
    },
    productLine: instrument.mode.productLine,
  );

  Future<Map<String, dynamic>> updateLeverage(
    int userId,
    Instrument instrument,
    String marginMode,
    int leveragePpm,
  ) => post(
    '/api/v1/gateway/trading-leverage/settings',
    {
      'userId': userId,
      'instrumentId': instrument.instrumentId,
      'productLine': instrument.mode.productLine,
      'marginMode': marginMode,
      'leveragePpm': leveragePpm,
      'reason': 'mobile trading ticket',
    },
    productLine: instrument.mode.productLine,
  );

  Future<List<Position>> positions(int userId, {String? productLine}) async {
    final json = await get(
      '/api/v1/gateway/account/positions',
      query: {'userId': '$userId'},
      productLine: productLine,
    );
    return asList(
      json['positions'],
    ).map((item) => Position.fromJson(asMap(item))).toList();
  }

  Future<String> positionMode(int userId, {String? productLine}) async {
    final json = await get(
      '/api/v1/gateway/account/position-mode',
      query: {'userId': '$userId'},
      userId: userId,
      productLine: productLine,
    );
    return asString(json['positionMode'], fallback: 'ONE_WAY');
  }

  Future<String> updatePositionMode(
    int userId,
    String positionMode, {
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/account/position-mode',
      {
        'userId': userId,
        if (productLine != null && productLine.isNotEmpty)
          'productLine': productLine,
        'positionMode': positionMode,
      },
      userId: userId,
      productLine: productLine,
    );
    return asString(json['positionMode'], fallback: positionMode);
  }

  Future<OpenOrdersPage> openOrders(
    int userId, {
    String? symbol,
    String? productLine,
    String? cursor,
    int limit = 100,
  }) async {
    final query = {'userId': '$userId', 'limit': '$limit'};
    if (symbol != null) query['symbol'] = symbol;
    if (cursor != null && cursor.isNotEmpty) query['cursor'] = cursor;
    final json = await get(
      '/api/v1/gateway/trading/open',
      query: query,
      productLine: productLine,
    );
    final nextCursor = asString(json['nextCursor']).trim();
    return OpenOrdersPage(
      orders: asList(
        json['orders'],
      ).map((item) => OrderModel.fromJson(asMap(item))).toList(),
      nextCursor: nextCursor.isEmpty ? null : nextCursor,
      hasMore: asBool(json['hasMore']) && nextCursor.isNotEmpty,
      sort: asString(json['sort'], fallback: 'orderId.desc'),
      limit: asInt(json['limit'], fallback: limit),
    );
  }

  Future<OrderModel> placeOrder({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? bboPriceMode,
    String? productLine,
    String? clientOrderId,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading',
      _orderPayload(
        userId: userId,
        symbol: symbol,
        side: side,
        orderType: orderType,
        timeInForce: timeInForce,
        priceTicks: priceTicks,
        quantitySteps: quantitySteps,
        marginMode: marginMode,
        positionSide: positionSide,
        reduceOnly: reduceOnly,
        postOnly: postOnly,
        bboPriceMode: bboPriceMode,
        clientOrderId: clientOrderId,
      ),
      userId: userId,
      productLine: productLine,
    );
    return OrderModel.fromJson(json);
  }

  Future<TestOrderResult> testOrder({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? bboPriceMode,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/test',
      _orderPayload(
        userId: userId,
        symbol: symbol,
        side: side,
        orderType: orderType,
        timeInForce: timeInForce,
        priceTicks: priceTicks,
        quantitySteps: quantitySteps,
        marginMode: marginMode,
        positionSide: positionSide,
        reduceOnly: reduceOnly,
        postOnly: postOnly,
        bboPriceMode: bboPriceMode,
        clientOrderId: 'app-test-${DateTime.now().microsecondsSinceEpoch}',
      ),
      userId: userId,
      productLine: productLine,
    );
    return TestOrderResult.fromJson(json);
  }

  Future<OrderBatchResult> placeOrderBatch(
    int userId,
    List<Map<String, dynamic>> orders, {
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/batch',
      {'orders': orders},
      userId: userId,
      productLine: productLine,
    );
    return OrderBatchResult.fromJson(json);
  }

  Future<AmendOrderResult> amendOrder({
    required int userId,
    required int orderId,
    int? priceTicks,
    int? quantitySteps,
    String? timeInForce,
    bool? postOnly,
    String? newClientOrderId,
    String? clientRequestId,
    String? productLine,
  }) async {
    final replacementKey =
        newClientOrderId ??
        'app-amend-$userId-${DateTime.now().microsecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'userId': userId,
      'orderId': orderId,
      'newClientOrderId': replacementKey,
      'clientRequestId': clientRequestId ?? replacementKey,
    };
    if (priceTicks != null) {
      payload['priceTicks'] = priceTicks;
    }
    if (quantitySteps != null) {
      payload['quantitySteps'] = quantitySteps;
    }
    if (timeInForce != null) {
      payload['timeInForce'] = timeInForce;
    }
    if (postOnly != null) {
      payload['postOnly'] = postOnly;
    }
    final json = await post(
      '/api/v1/gateway/trading/amend',
      payload,
      userId: userId,
      productLine: productLine,
    );
    return AmendOrderResult.fromJson(json);
  }

  Future<AmendOrderBatchResult> amendOrderBatch(
    int userId,
    List<Map<String, dynamic>> orders, {
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/batch-amend',
      {'orders': orders},
      userId: userId,
      productLine: productLine,
    );
    return AmendOrderBatchResult.fromJson(json);
  }

  Future<OrderModel> cancelOrder(
    int userId,
    int orderId, {
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/cancel',
      {'userId': userId, 'orderId': orderId},
      userId: userId,
      productLine: productLine,
    );
    return OrderModel.fromJson(json);
  }

  Future<OrderBatchResult> cancelOrderBatch(
    int userId,
    List<int> orderIds, {
    String? productLine,
    String? batchKey,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/batch-cancel',
      {
        'batchKey':
            batchKey ??
            'app-cancel-batch-$userId-${DateTime.now().microsecondsSinceEpoch}',
        'orders': orderIds
            .map((orderId) => {'userId': userId, 'orderId': orderId})
            .toList(),
      },
      userId: userId,
      productLine: productLine,
    );
    return OrderBatchResult.fromCancellationJson(json);
  }

  Future<List<int>> cancellationPlan(int userId, {String? instrumentId}) async {
    final json = await get(
      '/api/v1/gateway/trading/cancellation-plan',
      userId: userId,
      productLine: 'SPOT',
      query: {'userId': '$userId', 'instrumentId': ?instrumentId},
    );
    if (asInt(json['userId']) != userId ||
        json['productLine'] != 'SPOT' ||
        json['instrumentId'] != instrumentId ||
        json['orderIds'] is! List) {
      throw const FormatException('批量撤单范围不匹配');
    }
    final ids = asList(json['orderIds']).map(asInt).toList();
    if (ids.any((id) => id <= 0) || ids.toSet().length != ids.length) {
      throw const FormatException('批量撤单目标无效');
    }
    return ids;
  }

  Future<OrderBatchResult> cancelOpenOrders(
    int userId, {
    String? symbol,
    int limit = 1000,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/cancel-open',
      {
        'userId': userId,
        ...?symbol == null ? null : {'symbol': symbol},
        'limit': limit,
      },
      userId: userId,
      productLine: productLine,
    );
    return OrderBatchResult.fromJson(json);
  }

  Future<List<AlgoOrderModel>> openAlgoOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    final product = _algoProduct(productLine);
    final instrument = symbol == null
        ? null
        : instrumentCatalog
              .where(
                (i) =>
                    i.mode == product &&
                    i.symbol == symbol &&
                    i.instrumentId.isNotEmpty,
              )
              .firstOrNull;
    if (userId <= 0 || (symbol != null && instrument == null)) {
      throw const FormatException('算法单查询归属未就绪');
    }
    final query = {
      'userId': '$userId',
      'limit': '1000',
      if (instrument != null) 'instrumentId': instrument.instrumentId,
    };
    final json = await get(
      '/api/v1/gateway/trading/algo/open',
      query: query,
      userId: userId,
      productLine: productLine,
    );
    if (json['orders'] is! List) throw const FormatException('算法单列表无效');
    final orders = asList(json['orders'])
        .map((item) => AlgoOrderModel.fromJson(asMap(item), product: product))
        .toList();
    if (int.tryParse('${json['count']}') != orders.length ||
        orders.length > 1000 ||
        orders.map((o) => o.algoOrderId).toSet().length != orders.length ||
        orders.any(
          (o) =>
              o.userId != userId ||
              !o.isOpen ||
              (instrument != null && o.instrumentId != instrument.instrumentId),
        )) {
      throw const FormatException('算法单列表归属或状态无效');
    }
    return orders;
  }

  ProductMode _algoProduct(String? productLine) =>
      ProductMode.values
          .where((p) => p.productLine == productLine)
          .firstOrNull ??
      (throw const FormatException('算法单产品线无效'));

  Future<AlgoOrderModel> placeAlgoOrder({
    required int userId,
    required String symbol,
    required String algoType,
    required String side,
    required int priceTicks,
    required int quantitySteps,
    required int childQuantitySteps,
    required int intervalSeconds,
    required int durationSeconds,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/algo',
      {
        'userId': userId,
        'clientAlgoOrderId':
            'app-algo-$userId-${DateTime.now().microsecondsSinceEpoch}',
        'symbol': symbol,
        'algoType': algoType,
        'side': side,
        'priceTicks': algoType == 'TWAP' && priceTicks <= 0 ? 0 : priceTicks,
        'quantitySteps': quantitySteps,
        'childQuantitySteps': childQuantitySteps,
        'intervalSeconds': intervalSeconds,
        'durationSeconds': durationSeconds,
        'marginMode': marginMode,
        'positionSide': positionSide,
        'reduceOnly': reduceOnly,
        'postOnly': algoType == 'ICEBERG' && postOnly,
        'timeInForce': algoType == 'TWAP'
            ? 'IOC'
            : postOnly
            ? 'GTX'
            : 'GTC',
      },
      userId: userId,
      productLine: productLine,
    );
    final order = AlgoOrderModel.fromJson(
      json,
      product: _algoProduct(productLine),
    );
    if (order.userId != userId) throw const FormatException('算法单账户不匹配');
    return order;
  }

  Future<AlgoOrderModel> cancelAlgoOrder(
    int userId,
    int algoOrderId, {
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/algo/cancel',
      {'userId': userId, 'algoOrderId': algoOrderId},
      userId: userId,
      productLine: productLine,
    );
    final order = AlgoOrderModel.fromJson(
      json,
      product: _algoProduct(productLine),
    );
    if (order.userId != userId || order.algoOrderId != algoOrderId) {
      throw const FormatException('算法单撤销目标不匹配');
    }
    return order;
  }

  Future<AlgoOrderBatchResult> cancelOpenAlgoOrders(
    int userId, {
    String? symbol,
    int limit = 1000,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/algo/cancel-open',
      {
        'userId': userId,
        ...?symbol == null ? null : {'symbol': symbol},
        'limit': limit,
      },
      userId: userId,
      productLine: productLine,
    );
    return AlgoOrderBatchResult.fromJson(
      json,
      product: _algoProduct(productLine),
    );
  }

  Future<CancelAllAfterResult> cancelAllAfter(
    int userId, {
    String? symbol,
    required int countdownMs,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/cancel-all-after',
      {
        'userId': userId,
        ...?symbol == null ? null : {'symbol': symbol},
        'countdownMs': countdownMs,
      },
      userId: userId,
      productLine: productLine,
    );
    return CancelAllAfterResult.fromJson(json);
  }

  Future<OrderModel> closePosition(
    int userId, {
    required String symbol,
    required String marginMode,
    required String positionSide,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading/close-position',
      {
        'userId': userId,
        'clientOrderId':
            'app-close-$userId-${DateTime.now().microsecondsSinceEpoch}',
        'symbol': symbol,
        'marginMode': marginMode,
        'positionSide': positionSide,
      },
      userId: userId,
      productLine: productLine,
    );
    return OrderModel.fromJson(json);
  }

  Future<List<TriggerOrderModel>> openTriggerOrders(
    int userId, {
    String? symbol,
    String? productLine,
  }) async {
    final query = {'userId': '$userId', 'limit': '100'};
    if (symbol != null) query['symbol'] = symbol;
    final json = await get(
      '/api/v1/gateway/trading-trigger/open',
      query: query,
      userId: userId,
      productLine: productLine,
    );
    return asList(
      json['orders'] ?? json['items'],
    ).map((item) => TriggerOrderModel.fromJson(asMap(item))).toList();
  }

  Future<TriggerOrderModel> placeTriggerOrder({
    required int userId,
    required String instrumentId,
    required String side,
    required String triggerType,
    required int triggerPriceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    String? clientTriggerOrderId,
    int? activationPriceTicks,
    int? callbackRatePpm,
    String priceSource = 'MARK',
    String orderType = 'MARKET',
    int priceTicks = 0,
    String? productLine,
  }) async {
    final payload = <String, Object?>{
      'userId': userId,
      'clientTriggerOrderId':
          clientTriggerOrderId ??
          'app-trigger-$userId-${DateTime.now().microsecondsSinceEpoch}',
      'instrumentId': instrumentId,
      'side': side,
      'triggerType': triggerType,
      'triggerPriceTicks': triggerPriceTicks,
      'activationPriceTicks': activationPriceTicks,
      'callbackRatePpm': callbackRatePpm,
      'priceSource': priceSource,
      'orderType': orderType,
      'timeInForce': orderType == 'MARKET' ? 'IOC' : 'GTC',
      'priceTicks': orderType == 'MARKET' ? 0 : priceTicks,
      'quantitySteps': quantitySteps,
      'marginMode': marginMode,
      'positionSide': positionSide,
    }..removeWhere((_, value) => value == null);
    final json = await post(
      '/api/v1/gateway/trading-trigger',
      payload,
      userId: userId,
      productLine: productLine,
    );
    return TriggerOrderModel.fromJson(json);
  }

  Future<TriggerOrderBatchResult> placeTriggerOrderBatch(
    int userId,
    List<Map<String, dynamic>> orders, {
    bool atomic = false,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading-trigger/batch',
      {'atomic': atomic, 'orders': orders},
      userId: userId,
      productLine: productLine,
    );
    return atomic &&
            ProductMode.values.any(
              (mode) =>
                  mode.productLine == productLine && mode.tracksTriggerIntent,
            )
        ? TriggerOrderBatchResult.fromAtomicOcoJson(json)
        : TriggerOrderBatchResult.fromJson(json);
  }

  Future<TriggerOrderModel> cancelTriggerOrder(
    int userId,
    int triggerOrderId, {
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading-trigger/cancel',
      {'userId': userId, 'triggerOrderId': triggerOrderId},
      userId: userId,
      productLine: productLine,
    );
    return TriggerOrderModel.fromJson(json);
  }

  Future<TriggerOrderBatchResult> cancelTriggerOrderBatch(
    int userId,
    List<int> triggerOrderIds, {
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading-trigger/batch-cancel',
      {
        'orders': triggerOrderIds
            .map(
              (triggerOrderId) => {
                'userId': userId,
                'triggerOrderId': triggerOrderId,
              },
            )
            .toList(),
      },
      userId: userId,
      productLine: productLine,
    );
    return TriggerOrderBatchResult.fromJson(json);
  }

  Future<TriggerOrderBatchResult> cancelOpenTriggerOrders(
    int userId, {
    String? symbol,
    int limit = 1000,
    String? productLine,
  }) async {
    final json = await post(
      '/api/v1/gateway/trading-trigger/cancel-open',
      {
        'userId': userId,
        ...?symbol == null ? null : {'symbol': symbol},
        'limit': limit,
      },
      userId: userId,
      productLine: productLine,
    );
    return TriggerOrderBatchResult.fromJson(json);
  }

  Future<Map<String, dynamic>> transfer({
    required int userId,
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required int amountUnits,
    required String idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) {
    return _transferWithStableKey(
      userId: userId,
      sourceAccountType: sourceAccountType,
      targetAccountType: targetAccountType,
      asset: asset,
      amountUnits: amountUnits,
      idempotencyKey: idempotencyKey,
      emailCode: emailCode,
      totpCode: totpCode,
    );
  }

  Future<Map<String, dynamic>> _transferWithStableKey({
    required int userId,
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required int amountUnits,
    required String idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) async {
    final body = {
      'userId': userId,
      'sourceAccountType': sourceAccountType,
      'targetAccountType': targetAccountType,
      'asset': asset,
      'amountUnits': amountUnits,
      'referenceId': idempotencyKey,
      'reason': 'mobile client transfer',
    };
    try {
      return await post(
        '/api/v1/gateway/account/transfers',
        body,
        userId: userId,
        headers: {
          'Idempotency-Key': idempotencyKey,
          if (emailCode != null && emailCode.trim().isNotEmpty)
            'X-Security-Email-Code': emailCode.trim(),
          if (totpCode != null && totpCode.trim().isNotEmpty)
            'X-Security-TOTP-Code': totpCode.trim(),
        },
      );
    } on ApiException catch (error) {
      final payload = asMap(_decodeJson(error.message));
      final status = payload['status'];
      if (status is String && status.trim().isNotEmpty) return payload;
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> fundingAssets(String operation) async =>
      asList(
        await _send(
          'GET',
          '/api/v1/wallet/assets',
          query: {'operation': operation},
        ),
      ).map(asMap).toList();

  Future<List<Map<String, dynamic>>> walletChains(int userId) async {
    final values = await Future.wait([
      fundingAssets('withdraw'),
      assetScales(),
    ]);
    final catalog = values[0] as List<Map<String, dynamic>>,
        scales = values[1] as Map<String, String>;
    return [
      for (final asset in catalog)
        for (final network in asList(asset['networks']).map(asMap))
          {
            'chain': network['networkCode'],
            'network': network['displayName'],
            'withdrawalEnabled': true,
            'tokens': [
              {
                'symbol': asset['asset'],
                'platformEnabled': true,
                'decimals':
                    RegExp(r'^10*$').hasMatch(scales[asset['asset']] ?? '')
                    ? scales[asset['asset']]!.length - 1
                    : null,
                'minWithdraw': network['minWithdrawal'],
                'withdrawalFee': network['withdrawalFee'],
              },
            ],
          },
    ];
  }

  Future<WalletPortfolio> walletPortfolio(
    int userId, {
    bool hideZero = false,
  }) async {
    final values = await Future.wait([
      get(
        '/api/v1/gateway/account/balances',
        query: {'userId': '$userId'},
        userId: userId,
        productLine: ProductMode.spot.productLine,
      ),
      assetScales(),
    ]);
    final balances = asMap(values[0]);
    final scales = values[1] as Map<String, String>;
    final assets = asList(balances['balances'] ?? balances['items'])
        .map((value) {
          final row = asMap(value),
              asset = asString(asMap(value)['asset']).toUpperCase();
          final available = BigInt.tryParse(asString(row['availableUnits'])),
              locked = BigInt.tryParse(asString(row['lockedUnits']));
          if (asset.isEmpty ||
              available == null ||
              locked == null ||
              !scales.containsKey(asset)) {
            throw const FormatException('资金余额或币种精度尚未同步，请刷新后重试');
          }
          double units(BigInt amount) =>
              double.parse(formatAccountUnits(amount, scales[asset]));
          return WalletAssetSummary(
            symbol: asset,
            availableBalance: units(available),
            lockedBalance: units(locked),
            totalBalance: units(available + locked),
            chains: const [],
          );
        })
        .where((row) => !hideZero || row.totalBalance != 0)
        .toList();
    return WalletPortfolio(
      generatedAt: DateTime.now().toUtc().toIso8601String(),
      assets: assets,
      assetCount: assets.length,
    );
  }

  Future<List<WalletOrderRecord>> walletOrders(
    int userId, {
    int limit = 30,
  }) async {
    final page = await accountRecords(
      category: 'external-transfer',
      userId: userId,
      product: ProductMode.spot,
    );
    return page.rows
        .take(limit)
        .map(
          (row) => WalletOrderRecord.fromJson({
            ...row,
            'type': row['referenceType'],
            'refNo': row['withdrawalId'] ?? row['id'] ?? row['orderNo'],
            'updatedAt': row['updatedAt'] ?? row['createdAt'],
          }),
        )
        .toList();
  }

  Future<WalletDepositAddress> walletDepositAddress(
    int userId, {
    required String chain,
    required String symbol,
    bool forceNew = false,
  }) async {
    if (forceNew) throw const FormatException('当前网络不支持更换充值地址，请继续使用已分配地址');
    final value = await post('/api/v1/wallet/deposit-address', {
      'asset': symbol,
      'network': chain,
    }, userId: userId);
    if (value['asset'] != symbol ||
        value['network'] != chain ||
        asString(value['address']).isEmpty) {
      throw const FormatException('充值地址与所选币种或网络不一致，请重新加载');
    }
    return WalletDepositAddress.fromJson({
      ...value,
      'chain': chain,
      'symbol': symbol,
    });
  }

  Future<Map<String, dynamic>> walletWithdraw(
    int userId, {
    required String chain,
    required String symbol,
    required String toAddress,
    required String amount,
    required String idempotencyKey,
    String? emailCode,
    String? totpCode,
  }) {
    return post(
      '/api/v1/wallet/withdrawals',
      {
        'chain': chain,
        'assetSymbol': symbol,
        'toAddress': toAddress,
        'amount': amount,
        'externalReference': 'mobile-withdrawal:$idempotencyKey',
      },
      userId: userId,
      headers: {
        'Idempotency-Key': idempotencyKey,
        if (emailCode != null && emailCode.trim().isNotEmpty)
          'X-Security-Email-Code': emailCode.trim(),
        if (totpCode != null && totpCode.trim().isNotEmpty)
          'X-Security-TOTP-Code': totpCode.trim(),
      },
    );
  }

  Future<AccountRisk?> accountRisk(
    int userId,
    String settleAsset, {
    String? accountType,
    String? productLine,
  }) async {
    try {
      final query = {'userId': '$userId', 'settleAsset': settleAsset};
      if (accountType != null) query['accountType'] = accountType;
      final json = await get(
        '/api/v1/gateway/risk/account/latest',
        query: query,
        userId: userId,
        productLine: productLine,
      );
      return AccountRisk.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  Future<List<PositionRisk>> positionRisks(
    int userId, {
    String? productLine,
  }) async {
    try {
      final json = await get(
        '/api/v1/gateway/risk/positions/latest',
        query: {'userId': '$userId'},
        userId: userId,
        productLine: productLine,
      );
      return asList(
        json['positions'],
      ).map((item) => PositionRisk.fromJson(asMap(item))).toList();
    } catch (_) {
      return const [];
    }
  }

  Future<List<LiquidationOrder>> liquidationOrders(
    int userId, {
    String? productLine,
  }) async {
    try {
      final json = await get(
        '/api/v1/gateway/liquidation/orders',
        query: {'userId': '$userId', 'limit': '30'},
        userId: userId,
        productLine: productLine,
      );
      return asList(
        json['orders'],
      ).map((item) => LiquidationOrder.fromJson(asMap(item))).toList();
    } catch (_) {
      return const [];
    }
  }

  Map<String, dynamic> _orderPayload({
    required int userId,
    required String symbol,
    required String side,
    required String orderType,
    required String timeInForce,
    required int priceTicks,
    required int quantitySteps,
    required String marginMode,
    required String positionSide,
    required bool reduceOnly,
    required bool postOnly,
    String? bboPriceMode,
    String? clientOrderId,
  }) {
    validateOrderPolicy(orderType, timeInForce, postOnly, bboPriceMode);
    return {
      'userId': userId,
      'clientOrderId':
          clientOrderId ?? 'app-${DateTime.now().microsecondsSinceEpoch}',
      'symbol': symbol,
      'side': side,
      'orderType': orderType,
      'timeInForce': timeInForce,
      'priceTicks': orderType == 'MARKET' || bboPriceMode != null
          ? 0
          : priceTicks,
      'bboPriceMode': ?bboPriceMode,
      'quantitySteps': quantitySteps,
      'marginMode': marginMode,
      'positionSide': positionSide,
      'reduceOnly': reduceOnly,
      'postOnly': postOnly,
    };
  }

  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    return asMap(
      await _send(
        'GET',
        path,
        query: query,
        headers: headers,
        userId: userId,
        productLine: productLine,
        unwrapResponseResult: unwrapResponseResult,
      ),
    );
  }

  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = false,
  }) async {
    return asMap(
      await _send(
        'POST',
        path,
        body: body,
        headers: headers,
        userId: userId,
        productLine: productLine,
        unwrapResponseResult: unwrapResponseResult,
      ),
    );
  }

  Future<Map<String, dynamic>> _sendMap(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    return asMap(await _send(method, path, body: body, headers: headers));
  }

  String _kycContentType(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    return switch (extension) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      _ => 'image/jpeg',
    };
  }

  String _safeFileName(String fileName) {
    final value = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return value.isEmpty ? 'document' : value;
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    final originalToken = _accessToken;
    final originalUser = _sessionUserId;
    try {
      return await _sendOnce(
        method,
        path,
        query: query,
        body: body,
        headers: headers,
        userId: userId,
        productLine: productLine,
        unwrapResponseResult: unwrapResponseResult,
      );
    } on ApiException catch (error) {
      if (error.statusCode != 401 ||
          originalToken != _accessToken ||
          originalUser != _sessionUserId ||
          _refreshToken == null ||
          path.startsWith('/api/v1/auth/')) {
        rethrow;
      }
      final refreshed = await _refreshAccessToken();
      if (refreshed == null) rethrow;
      return _sendOnce(
        method,
        path,
        query: query,
        body: body,
        headers: headers,
        userId: userId,
        productLine: productLine,
        unwrapResponseResult: unwrapResponseResult,
      );
    }
  }

  Future<AuthSession?> _refreshAccessToken() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final token = _refreshToken;
    if (token == null || token.isEmpty) return null;
    final future = _refreshAccessTokenOnce(token);
    _refreshInFlight = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshInFlight, future)) _refreshInFlight = null;
    }
  }

  Future<AuthSession?> _refreshAccessTokenOnce(String refreshToken) async {
    try {
      final session = await refresh(refreshToken);
      if (_refreshToken != refreshToken) return null;
      setSession(session);
      await onSessionRefreshed?.call(session);
      return session;
    } on ApiException catch (error) {
      if (error.statusCode == 401 || error.statusCode == 403) {
        if (_refreshToken != refreshToken) return null;
        setSession(null);
        await onSessionExpired?.call();
        return null;
      }
      rethrow;
    }
  }

  Future<Object?> _sendOnce(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    Map<String, String>? headers,
    int? userId,
    String? productLine,
    bool unwrapResponseResult = false,
  }) async {
    final token = _accessToken;
    if (userId != null && _sessionUserId != null && userId != _sessionUserId) {
      throw ApiException(401, '登录账户已变化，未发送请求');
    }
    if (path.startsWith('/api/v1/gateway/') && !path.contains('/wallet/')) {
      final symbol = asString(body?['symbol'] ?? query?['symbol']);
      final instrument = instrumentCatalog
          .where(
            (i) =>
                i.symbol == symbol &&
                (productLine == null || i.mode.productLine == productLine),
          )
          .firstOrNull;
      if (instrument != null && instrument.instrumentId.isNotEmpty) {
        if (query?.containsKey('symbol') == true) {
          query = {...query!}..remove('symbol');
          query['instrumentId'] = instrument.instrumentId;
        }
        if (body?.containsKey('symbol') == true) {
          body = {...body!}..remove('symbol');
          body['instrumentId'] = instrument.instrumentId;
        }
      }
    }
    final base = Uri.parse(config.gatewayBaseUrl);
    final uri = base.replace(
      path: path,
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final request = await _httpClient
        .openUrl(method, uri)
        .timeout(const Duration(seconds: 6));
    if (token != _accessToken) {
      request.abort();
      throw ApiException(401, '登录账户已变化，未发送请求');
    }
    request.headers.contentType = ContentType.json;
    request.headers.set(
      'X-Trace-Id',
      'mobile-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (_accessToken != null) {
      request.headers.set('Authorization', 'Bearer $_accessToken');
    }
    headers?.forEach(request.headers.set);
    if (userId != null) request.headers.set('X-User-Id', '$userId');
    if (productLine != null && productLine.isNotEmpty) {
      request.headers.set('X-Product-Line', productLine);
    }
    if (body != null) {
      request.write(jsonEncode(body));
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    final payload = await utf8.decodeStream(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        payload.isEmpty ? response.reasonPhrase : payload,
      );
    }
    if (payload.isEmpty) return <String, dynamic>{};
    final decoded = jsonDecode(payload);
    if (method == 'POST' &&
        path.startsWith('/api/v1/gateway/trading') &&
        decoded is Map &&
        decoded.containsKey('outcome')) {
      final receipt = asMap(decoded);
      final result = receipt['result'];
      if (receipt['outcome'] == 'TERMINAL' && result is Map) {
        return normalizeInstruments(result, productLine);
      }
      if (['MATCHING_PENDING', 'RESULT_UNKNOWN'].contains(receipt['outcome'])) {
        throw PendingTradingCommand(asString(receipt['commandId']));
      }
      throw ApiException(409, jsonEncode(receipt));
    }
    if (unwrapResponseResult) {
      final json = asMap(decoded);
      return _unwrapResponseResult(json);
    }
    return normalizeInstruments(decoded, productLine);
  }

  Map<String, dynamic> _unwrapResponseResult(Map<String, dynamic> json) {
    if (!json.containsKey('code') ||
        !json.containsKey('message') ||
        !json.containsKey('data')) {
      return json;
    }
    final code = asInt(json['code']);
    if (code != 0) {
      throw ApiException(
        code,
        asString(json['message'], fallback: 'request failed'),
      );
    }
    final data = json['data'];
    if (data is List) return {'items': data};
    if (data == null) return <String, dynamic>{};
    return asMap(data);
  }
}

Object? _decodeJson(String value) {
  try {
    return jsonDecode(value);
  } on FormatException {
    return null;
  }
}

String clientErrorMessage(Object error) {
  if (error is ApiException) return error.toString();
  if (error is FormatException) return error.message;
  if (error is TimeoutException) return '请求超时，请检查网络后重试';
  if (error is SocketException) return '网络连接失败，请检查网络后重试';
  final detail = error.toString();
  if (RegExp(r'[\u4e00-\u9fff]').hasMatch(detail) &&
      detail.length <= 200 &&
      !RegExp(
        r'Aeron|Exception|Kafka|SQL|stack|<html',
        caseSensitive: false,
      ).hasMatch(detail)) {
    return detail;
  }
  return '操作未完成，请稍后重试';
}

class PendingTradingCommand extends ApiException {
  PendingTradingCommand(this.commandId) : super(202, '委托已受理，结果待确认，请勿重复提交');
  final String commandId;
  @override
  String toString() => message;
}

bool isDefinitiveOrderRejection(Object error) {
  if (error is! ApiException) return false;
  final receipt = asMap(_decodeJson(error.message));
  if (receipt['commandId'] is String &&
      receipt['code'] is String &&
      (receipt['outcome'] == 'NOT_ACCEPTED' ||
          (receipt['outcome'] == 'TERMINAL' && receipt['code'] != 'NONE'))) {
    return true;
  }
  return error.statusCode >= 400 &&
      error.statusCode < 500 &&
      ![408, 409, 425, 429].contains(error.statusCode);
}

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() {
    String code = '', detail = message;
    try {
      final payload = asMap(jsonDecode(message));
      final error = payload['error'];
      final value = error is Map ? asMap(error) : payload;
      code = asString(value['code']);
      detail = asString(value['message'] ?? value['detail']);
    } catch (_) {}
    const messages = {
      'INVALID_COMMAND': '操作未完成，请刷新状态后重试',
      'INSUFFICIENT_BALANCE': '可用余额不足',
      'INVALID_VERIFICATION_CODE': '验证码不正确或已过期',
      'INVALID_CREDENTIALS': '账号或密码不正确',
      'SECURITY_HOLD': '账户处于安全保护期，请稍后重试',
    };
    if (messages.containsKey(code)) return messages[code]!;
    if (RegExp(r'[\u4e00-\u9fff]').hasMatch(detail) &&
        !RegExp(
          r'Aeron|Exception|Kafka|SQL|stack|<html',
          caseSensitive: false,
        ).hasMatch(detail) &&
        detail.length <= 240) {
      return detail;
    }
    return switch (statusCode) {
      401 => '登录已失效，请重新登录',
      403 => '当前账户暂不允许此操作，请检查认证与安全状态',
      409 => '状态已变化，请刷新后重试',
      423 => '账户处于安全保护期，请稍后重试',
      428 => '请先完成所需的安全验证',
      429 => '操作过于频繁，请稍后重试',
      >= 500 => '服务暂时不可用，请稍后重试',
      _ => '操作未完成，请检查输入后重试',
    };
  }
}

class RealtimeClient {
  RealtimeClient(this.config);

  final AppConfig config;
  WebSocket? _socket;
  StreamSubscription<dynamic>? _subscription;
  bool _closing = false;
  int _connectionGeneration = 0;
  bool _authenticated = false;
  bool _authenticationRequested = false;
  int? _expectedUserId;
  static const _privateChannels = {
    'accountState',
    'orders',
    'triggerOrders',
    'executionReports',
    'positions',
    'accountRisk',
    'positionRisk',
  };

  bool _isPrivate(Map<String, dynamic> message) =>
      message['op'] == 'snapshot' ||
      _privateChannels.contains(message['channel']);
  final _desired = <String, Map<String, String>>{};
  final _installed = <String, Map<String, String>>{};

  void replaceSubscriptions(List<Map<String, String>> subscriptions) {
    _desired.clear();
    for (final s in subscriptions) {
      _desired['${s['productLine']}:${s['channel']}:${s['instrumentId'] ?? s['symbol'] ?? '*'}:${s['period'] ?? ''}'] =
          s;
    }
    _reconcileSubscriptions();
  }

  void _reconcileSubscriptions() {
    final socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    final allowed = <String, Map<String, String>>{
      for (final entry in _desired.entries)
        if (!_privateChannels.contains(entry.value['channel']) ||
            _authenticated)
          entry.key: entry.value,
    };
    for (final e in _installed.entries) {
      if (!allowed.containsKey(e.key)) {
        socket.add(jsonEncode({'op': 'unsubscribe', 'id': e.key, ...e.value}));
      }
    }
    for (final e in allowed.entries) {
      if (!_installed.containsKey(e.key)) {
        socket.add(jsonEncode({'op': 'subscribe', 'id': e.key, ...e.value}));
      }
    }
    _installed
      ..clear()
      ..addAll(allowed);
  }

  /// Request a fresh baseline for one installed channel without disturbing others.
  void resubscribe(Map<String, String> subscription) {
    final key =
        '${subscription['productLine']}:${subscription['channel']}:${subscription['instrumentId'] ?? subscription['symbol'] ?? '*'}:${subscription['period'] ?? ''}';
    final installed = _installed[key];
    final socket = _socket;
    if (installed == null ||
        socket == null ||
        socket.readyState != WebSocket.open) {
      return;
    }
    socket.add(jsonEncode({'op': 'unsubscribe', 'id': key, ...installed}));
    socket.add(jsonEncode({'op': 'subscribe', 'id': key, ...installed}));
  }

  Future<void> connect({
    int? userId,
    String? accessToken,
    required void Function(Map<String, dynamic>) onEvent,
    required void Function(Object error) onError,
    void Function()? onDone,
  }) async {
    final generation = ++_connectionGeneration;
    await _closeCurrent();
    if (generation != _connectionGeneration) return;
    _closing = false;
    final base = Uri.parse(config.websocketUrl);
    final query = <String, String>{...base.queryParameters}
      ..remove('token')
      ..remove('userId')
      ..remove('productLine');
    if (userId != null) {
      if (config.localWebSocketUserFallback) {
        query['userId'] = '$userId';
      }
    }
    final uri = base.replace(queryParameters: query);
    var expired = false;
    final pending = WebSocket.connect(uri.toString());
    unawaited(
      pending.then((socket) async {
        if (expired || generation != _connectionGeneration) {
          await socket.close();
        }
      }, onError: (Object _) {}),
    );
    final socket = await pending.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        expired = true;
        throw TimeoutException('实时连接超时');
      },
    );
    if (generation != _connectionGeneration) {
      await socket.close();
      return;
    }
    _socket = socket;
    _installed.clear();
    _desired.clear();
    _authenticated = false;
    _authenticationRequested = accessToken != null && accessToken.isNotEmpty;
    _expectedUserId = userId;
    _subscription = socket.listen(
      (message) {
        if (generation != _connectionGeneration) return;
        try {
          final decoded = asMap(jsonDecode(message as String));
          if (decoded['op'] == 'authenticated' &&
              _authenticationRequested &&
              asInt(decoded['userId']) > 0 &&
              (_expectedUserId == null ||
                  asInt(decoded['userId']) == _expectedUserId)) {
            _authenticated = true;
            _reconcileSubscriptions();
          }
          if (decoded['op'] == 'authenticated' && !_authenticated) return;
          if (_isPrivate(decoded) &&
              (!_authenticated ||
                  (_expectedUserId != null &&
                      asInt(decoded['userId']) != _expectedUserId))) {
            return;
          }
          onEvent(decoded);
        } catch (error) {
          onError(error);
        }
      },
      onError: (Object error) {
        if (generation == _connectionGeneration) onError(error);
      },
      onDone: () {
        if (generation != _connectionGeneration) return;
        _socket = null;
        _subscription = null;
        _authenticated = false;
        _installed.clear();
        if (!_closing) onDone?.call();
      },
      cancelOnError: false,
    );
    if (_authenticationRequested) {
      socket.add(
        jsonEncode({'op': 'authenticate', 'id': 'auth', 'token': accessToken}),
      );
    }
  }

  void subscribeDefaults({
    String symbol = 'BTC-USDT',
    String period = '1m',
    String? productLine,
  }) {
    subscribe('depth', symbol: symbol, productLine: productLine);
    subscribe('trades', symbol: symbol, productLine: productLine);
    subscribe(
      'candles',
      symbol: symbol,
      period: period,
      productLine: productLine,
    );
    subscribe('orders', productLine: productLine);
    subscribe('triggerOrders', productLine: productLine);
    subscribe('accountState', productLine: productLine);
    subscribe('executionReports', productLine: productLine);
    subscribe('positions', productLine: productLine);
    subscribe('accountRisk', productLine: productLine);
    subscribe('positionRisk', productLine: productLine);
  }

  void subscribe(
    String channel, {
    String? symbol,
    String? period,
    String? productLine,
  }) {
    final command = <String, String>{'channel': channel};
    if (symbol != null) command['symbol'] = symbol;
    if (period != null) command['period'] = period;
    if (productLine != null && productLine.isNotEmpty) {
      command['productLine'] = productLine;
    }
    _desired['$productLine:$channel:${symbol ?? '*'}:${period ?? ''}'] =
        command;
    _reconcileSubscriptions();
  }

  Future<void> close() async {
    _connectionGeneration++;
    await _closeCurrent();
  }

  Future<void> _closeCurrent() async {
    _closing = true;
    final subscription = _subscription;
    final socket = _socket;
    _subscription = null;
    _socket = null;
    _authenticated = false;
    _authenticationRequested = false;
    _expectedUserId = null;
    _installed.clear();
    await subscription?.cancel();
    await socket?.close();
    _closing = false;
  }
}
