import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'api.dart';
import 'models.dart';
import 'session_store.dart' show telegramLoginStorageKey;

class TelegramLoginCancelled implements Exception {
  const TelegramLoginCancelled();
}

/// The verifier stays on this device, including while Android reclaims the app.
class TelegramLoginFlow {
  TelegramLoginFlow.fromJson(Map<String, dynamic> json)
    : flowId = asString(json['flowId']),
      verifier = asString(json['verifier']),
      authorizationUrl = Uri.parse(asString(json['authorizationUrl'])),
      expiresAt = DateTime.tryParse(asString(json['expiresAt'])) {
    final token = RegExp(r'^[A-Za-z0-9_-]{43}$');
    if (!token.hasMatch(flowId) ||
        !token.hasMatch(verifier) ||
        expiresAt == null ||
        authorizationUrl.scheme != 'https' ||
        authorizationUrl.host != 'oauth.telegram.org' ||
        authorizationUrl.path != '/auth' ||
        authorizationUrl.userInfo.isNotEmpty ||
        authorizationUrl.hasPort ||
        authorizationUrl.hasFragment) {
      throw const FormatException('Telegram 登录响应无效');
    }
  }

  final String flowId, verifier;
  final Uri authorizationUrl;
  final DateTime? expiresAt;
  bool get expired => !DateTime.now().isBefore(expiresAt!);

  static bool isReturnLink(Uri uri) =>
      uri.scheme == 'surprising' &&
      uri.host == 'auth' &&
      uri.path == '/telegram' &&
      uri.userInfo.isEmpty &&
      !uri.hasPort &&
      !uri.hasFragment &&
      uri.queryParametersAll.length == 1 &&
      uri.queryParametersAll['flowId']?.length == 1 &&
      RegExp(
        r'^[A-Za-z0-9_-]{43}$',
      ).hasMatch(uri.queryParameters['flowId'] ?? '');

  bool matches(Uri uri) =>
      isReturnLink(uri) && uri.queryParameters['flowId'] == flowId;

  Map<String, dynamic> toJson() => {
    'flowId': flowId,
    'verifier': verifier,
    'authorizationUrl': authorizationUrl.toString(),
    'expiresAt': expiresAt!.toUtc().toIso8601String(),
  };
}

/// One pending login, bound to its API and device. All mutations are serialized
/// so a cancelled older attempt cannot erase a newer attempt's verifier.
class TelegramLoginStore {
  TelegramLoginStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const _key = telegramLoginStorageKey;
  Future<void> _tail = Future<void>.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  Future<void> save(ApiClient api, TelegramLoginFlow flow) async {
    final device = await api.resolveDeviceId();
    await _serial(
      () => _storage.write(
        key: _key,
        value: jsonEncode({
          ...flow.toJson(),
          'api': api.config.gatewayBaseUrl,
          'device': device,
        }),
      ),
    );
  }

  Future<TelegramLoginFlow?> read(ApiClient api) async {
    final device = await api.resolveDeviceId();
    return _serial(() async {
      final value = await _storage.read(key: _key);
      if (value == null) return null;
      try {
        final json = asMap(jsonDecode(value));
        final flow = TelegramLoginFlow.fromJson(json);
        if (json['api'] == api.config.gatewayBaseUrl &&
            json['device'] == device &&
            !flow.expired) {
          return flow;
        }
      } catch (_) {
        // Invalid or expired local state cannot authorize an incoming link.
      }
      await _storage.delete(key: _key);
      return null;
    });
  }

  Future<void> clear(String flowId) => _serial(() async {
    final value = await _storage.read(key: _key);
    if (value != null && asMap(jsonDecode(value))['flowId'] == flowId) {
      await _storage.delete(key: _key);
    }
  });
}

Future<AuthSession> signInWithTelegram({
  required ApiClient api,
  required Future<bool> Function(Uri) openBrowser,
  required bool Function() cancelled,
  TelegramLoginStore? store,
  TelegramLoginFlow? resume,
  Duration pollInterval = const Duration(milliseconds: 1500),
}) async {
  void checkCancelled() {
    if (cancelled()) throw const TelegramLoginCancelled();
  }

  checkCancelled();
  final flow =
      resume ??
      TelegramLoginFlow.fromJson(
        await api.post('/api/v1/auth/telegram/start', const {
          'returnToApp': true,
        }),
      );
  try {
    checkCancelled();
    if (flow.expired) throw StateError('Telegram 登录已过期，请重试');
    if (resume == null) {
      await store?.save(api, flow);
      checkCancelled();
      if (!await openBrowser(flow.authorizationUrl)) {
        throw StateError('无法打开 Telegram 授权页面');
      }
    }
    checkCancelled();
    while (!flow.expired) {
      final result = await api.post('/api/v1/auth/telegram/complete', {
        'flowId': flow.flowId,
        'verifier': flow.verifier,
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
  } finally {
    await store?.clear(flow.flowId);
  }
}
