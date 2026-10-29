import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'api.dart';
import 'models.dart';

class GoogleLoginCancelled implements Exception {
  const GoogleLoginCancelled();
}

class GoogleLoginConfig {
  GoogleLoginConfig.fromJson(Map<String, dynamic> json)
    : webClientId = asString(json['webClientId']),
      iosClientId = asString(json['iosClientId']),
      androidEnabled =
          json['enabled'] == true && json['androidEnabled'] == true,
      iosEnabled = json['enabled'] == true && json['iosEnabled'] == true;

  final String webClientId, iosClientId;
  final bool androidEnabled, iosEnabled;
  bool get enabled =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android => androidEnabled && webClientId.isNotEmpty,
        TargetPlatform.iOS =>
          iosEnabled && webClientId.isNotEmpty && iosClientId.isNotEmpty,
        _ => false,
      };
}

/// One SDK initialization per process; trading sessions remain owned by AuthState.
class NativeGoogleLogin {
  static final instance = NativeGoogleLogin();
  Future<void>? _initializing;
  String? _configuration;

  Future<String> authenticate(GoogleLoginConfig config) async {
    if (!config.enabled) throw StateError('Google 登录暂不可用');
    if (defaultTargetPlatform == TargetPlatform.iOS &&
        await const MethodChannel(
              'surprising/google-login',
            ).invokeMethod<bool>('isConfigured', config.iosClientId) !=
            true) {
      throw StateError('Google 登录暂不可用，请更新应用后重试');
    }
    final configuration = '${config.webClientId}:${config.iosClientId}';
    if (_configuration != null && configuration != _configuration) {
      throw StateError('Google 登录配置已更新，请重启应用后重试');
    }
    _configuration = configuration;
    _initializing ??= GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS
          ? config.iosClientId
          : null,
      serverClientId: config.webClientId,
    );
    try {
      await _initializing;
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw StateError('未能获取 Google 授权，请重试');
      }
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw const GoogleLoginCancelled();
      }
      throw StateError('Google 授权未完成，请检查网络和设备的 Google 服务后重试');
    }
  }
}

Future<AuthSession> signInWithGoogle({
  required ApiClient api,
  required GoogleLoginConfig config,
  required bool Function() cancelled,
  Future<String> Function(GoogleLoginConfig)? authenticate,
  String? inviteCode,
}) async {
  void checkCancelled() {
    if (cancelled()) throw const GoogleLoginCancelled();
  }

  checkCancelled();
  final token = await (authenticate ?? NativeGoogleLogin.instance.authenticate)(
    config,
  );
  checkCancelled();
  final result = await api.post('/api/v1/auth/google/login', {
    'credential': token,
    if (inviteCode != null && inviteCode.trim().isNotEmpty)
      'inviteCode': inviteCode.trim(),
    'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'IOS' : 'ANDROID',
  });
  checkCancelled();
  if (result['requiresVerification'] == true) {
    throw LoginChallenge.fromJson(result);
  }
  return AuthSession.fromJson(result);
}
