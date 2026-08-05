import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'models.dart';

abstract interface class SessionStore {
  Future<AuthSession?> readSession();

  Future<void> saveSession(AuthSession session);

  Future<void> clear();

  Future<bool> biometricEnabled();

  Future<bool> canUseBiometrics();

  Future<bool> authenticateBiometric();

  Future<void> enableBiometric();
}

abstract interface class ClientSettingsStore {
  Future<Map<String, String>> read();

  Future<void> write(Map<String, String> values);
}

class SecureClientSettingsStore implements ClientSettingsStore {
  SecureClientSettingsStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'surprising.client.settings.v1';

  final FlutterSecureStorage _storage;

  @override
  Future<Map<String, String>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const {};
      return decoded.map((key, value) => MapEntry('$key', '$value'));
    } on FormatException {
      return const {};
    }
  }

  @override
  Future<void> write(Map<String, String> values) async {
    await _storage.write(key: _key, value: jsonEncode(values));
  }
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({
    FlutterSecureStorage? storage,
    LocalAuthentication? authentication,
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _authentication = authentication ?? LocalAuthentication();

  static const _sessionKey = 'surprising.auth.session.v1';
  static const _biometricKey = 'surprising.auth.biometric.v1';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _authentication;

  @override
  Future<AuthSession?> readSession() async {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final session = AuthSession.fromJson(asMap(jsonDecode(encoded)));
      if (session.refreshToken.isEmpty) {
        throw const FormatException('missing refresh token');
      }
      return session;
    } on FormatException {
      await clear();
      return null;
    }
  }

  @override
  Future<void> saveSession(AuthSession session) async {
    final securePayload = session.toJson()..['accessToken'] = '';
    await _storage.write(key: _sessionKey, value: jsonEncode(securePayload));
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _sessionKey);
    await _storage.delete(key: _biometricKey);
  }

  @override
  Future<bool> biometricEnabled() async {
    return await _storage.read(key: _biometricKey) == 'enabled';
  }

  @override
  Future<bool> canUseBiometrics() async {
    if (!await _authentication.canCheckBiometrics) return false;
    return (await _authentication.getAvailableBiometrics()).isNotEmpty;
  }

  @override
  Future<bool> authenticateBiometric() {
    return _authentication.authenticate(
      localizedReason: '验证身份后恢复你的交易账户',
      biometricOnly: true,
      persistAcrossBackgrounding: true,
    );
  }

  @override
  Future<void> enableBiometric() async {
    if (!await canUseBiometrics() || !await authenticateBiometric()) {
      throw StateError('当前设备未启用可用的生物识别');
    }
    await _storage.write(key: _biometricKey, value: 'enabled');
  }
}
