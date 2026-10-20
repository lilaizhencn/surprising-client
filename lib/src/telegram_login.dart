import 'dart:async';

import 'api.dart';
import 'models.dart';

class TelegramLoginCancelled implements Exception {
  const TelegramLoginCancelled();
}

/// Authorization happens in the system browser; credentials stay in memory.
Future<AuthSession> signInWithTelegram({
  required ApiClient api,
  required Future<bool> Function(Uri) openBrowser,
  required bool Function() cancelled,
  Duration pollInterval = const Duration(milliseconds: 1500),
}) async {
  void checkCancelled() {
    if (cancelled()) throw const TelegramLoginCancelled();
  }

  checkCancelled();
  final flow = await api.post('/api/v1/auth/telegram/start', const {});
  checkCancelled();
  final url = Uri.parse(asString(flow['authorizationUrl']));
  final flowId = asString(flow['flowId']);
  final verifier = asString(flow['verifier']);
  final expiresAt = DateTime.tryParse(asString(flow['expiresAt']));
  final tokenPattern = RegExp(r'^[A-Za-z0-9_-]{43}$');
  if (url.scheme != 'https' ||
      url.host != 'oauth.telegram.org' ||
      url.path != '/auth' ||
      url.userInfo.isNotEmpty ||
      !tokenPattern.hasMatch(flowId) ||
      !tokenPattern.hasMatch(verifier) ||
      expiresAt == null) {
    throw const FormatException('Telegram 登录响应无效');
  }
  if (!await openBrowser(url)) throw StateError('无法打开 Telegram 授权页面');
  checkCancelled();
  while (DateTime.now().isBefore(expiresAt)) {
    final result = await api.post('/api/v1/auth/telegram/complete', {
      'flowId': flowId,
      'verifier': verifier,
    });
    checkCancelled();
    if (result['requiresVerification'] == true) {
      throw LoginChallenge.fromJson(result);
    }
    if (result['pending'] != true) return AuthSession.fromJson(result);
    await Future<void>.delayed(pollInterval);
    checkCancelled();
  }
  throw StateError('Telegram 登录已过期，请重试');
}
