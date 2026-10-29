import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api.dart';
import '../models.dart';
import '../session_store.dart';
import '../telegram_login.dart';
import '../google_login.dart';

enum AuthSessionChange { signedIn, tokenRefreshed, signedOut, expired }

/// Owns authentication, local unlocking and secure-session persistence.
/// Trading data and realtime connections remain with their business owners.
class AuthState extends ChangeNotifier {
  AuthState({
    required this.api,
    required this.sessionStore,
    required this.telegramLoginStore,
    AuthSession? initialSession,
    this.offline = false,
    this.onSessionChanged,
    this.onSessionReady,
    this.onFeedback,
  }) {
    if (initialSession != null) {
      _checkSession(initialSession);
      _current = initialSession;
      _restored = true;
      api.setSession(initialSession);
    }
    api.onSessionRefreshed = persistRefreshedSession;
    api.onSessionExpired = expire;
  }

  final ApiClient api;
  final SessionStore sessionStore;
  final TelegramLoginStore telegramLoginStore;
  final bool offline;

  /// Clear/invalidate account projections synchronously when identity changes.
  final void Function(
    AuthSession? previous,
    AuthSession? next,
    AuthSessionChange change,
  )?
  onSessionChanged;

  /// Refresh dependent business state after secure storage has completed.
  /// The coordinator must check [isCurrentRevision] after each asynchronous hop.
  final Future<void> Function(
    AuthSession? previous,
    AuthSession? next,
    AuthSessionChange change,
    int revision,
  )?
  onSessionReady;
  final void Function(String? error, String? notice)? onFeedback;

  AuthSession? _current;
  AuthSession? get current => _current;

  bool get isLoggedIn => _current != null;
  int? get userId => _current?.user.userId;
  int get revision => _revision;
  bool isCurrentRevision(int value) => !_disposed && value == _revision;

  LoginChallenge? pendingLoginChallenge;
  AuthSession? pendingVerificationSession;
  AuthSession? pendingBiometricSession;
  bool loading = false;
  String? lastError;
  String? lastNotice;
  bool biometricLoginAvailable = false;
  bool biometricLoginEnabled = false;
  bool biometricLoginUpdating = false;
  bool biometricSessionLocked = false;
  bool biometricUnlocking = false;
  String? biometricUnlockError;

  int _revision = 0;
  int _biometricVersion = 0;
  bool _biometricAppForeground = true;
  bool _biometricAppBackgrounded = false;
  bool _disposed = false;
  bool _restored = false;
  Future<void>? _restoring;
  Future<void> _storageTail = Future<void>.value();

  bool get requiresBiometricUnlock =>
      biometricSessionLocked || pendingBiometricSession != null;
  bool get canUnlockBiometricSession =>
      requiresBiometricUnlock &&
      (pendingBiometricSession != null ||
          (biometricLoginEnabled && _current != null));

  Future<T> _writeStorage<T>(Future<T> Function() action) {
    final result = _storageTail.then((_) => action());
    _storageTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

  void _feedback({String? error, String? notice}) {
    lastError = error;
    lastNotice = notice;
    if (!_disposed) onFeedback?.call(error, notice);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  AuthSession? _changeSession(AuthSession? next, AuthSessionChange change) {
    final previous = _current;
    _current = next;
    api.setSession(next);
    if (!_disposed) onSessionChanged?.call(previous, next, change);
    return previous;
  }

  Future<void> _sessionReady(
    AuthSession? previous,
    AuthSession? next,
    AuthSessionChange change,
    int operation,
  ) async {
    if (isCurrentRevision(operation) && identical(_current, next)) {
      await onSessionReady?.call(previous, next, change, operation);
    }
  }

  void _checkSession(AuthSession session) {
    if (session.user.userId <= 0) {
      throw StateError('登录响应缺少有效用户标识');
    }
    if (session.accessToken.trim().isEmpty ||
        session.refreshToken.trim().isEmpty) {
      throw StateError('登录响应缺少令牌');
    }
  }

  Future<bool> _activate(AuthSession next, int operation) async {
    if (!isCurrentRevision(operation)) return false;
    _checkSession(next);
    _restored = true;
    final previous = _changeSession(next, AuthSessionChange.signedIn);
    pendingBiometricSession = null;
    await _saveSession(next, operation);
    if (!isCurrentRevision(operation) || !identical(_current, next)) {
      return false;
    }
    await _sessionReady(previous, next, AuthSessionChange.signedIn, operation);
    return isCurrentRevision(operation) && identical(_current, next);
  }

  Future<void> _saveSession(AuthSession next, int operation) async {
    try {
      await _writeStorage(() async {
        if (isCurrentRevision(operation) && identical(_current, next)) {
          await sessionStore.saveSession(next);
        }
      });
    } catch (error, stack) {
      if (isCurrentRevision(operation) && identical(_current, next)) {
        final closedRevision = _revision + 1;
        final closing = _close(AuthSessionChange.expired);
        if (isCurrentRevision(closedRevision)) {
          _feedback(error: '无法安全保存登录状态，请重新登录');
          _changed();
        }
        try {
          await closing;
        } catch (_) {
          // The original save failure remains the reported operation failure.
          // The account and API were already invalidated synchronously.
        }
      }
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> restore() {
    if (offline || _restored || _disposed || _current != null) {
      return Future<void>.value();
    }
    final restoring = _restoring;
    if (restoring != null) return restoring;
    final operation = _revision;
    final future = _restore(operation).catchError((Object _) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '无法读取安全登录资料，请重试或使用账号登录');
        _changed();
      }
    });
    _restoring = future;
    return future.whenComplete(() {
      if (identical(_restoring, future)) _restoring = null;
    });
  }

  Future<void> _restore(int operation) async {
    try {
      final available = await sessionStore.canUseBiometrics();
      if (!isCurrentRevision(operation)) return;
      biometricLoginAvailable = available;
    } catch (_) {
      if (!isCurrentRevision(operation)) return;
      biometricLoginAvailable = false;
    }
    await _storageTail;
    if (!isCurrentRevision(operation)) return;
    final stored = await sessionStore.readSession();
    if (!isCurrentRevision(operation)) return;
    if (stored == null) {
      _restored = true;
      return;
    }
    final enabled = await sessionStore.biometricEnabled();
    if (!isCurrentRevision(operation)) return;
    biometricLoginEnabled = enabled;
    if (enabled) {
      pendingBiometricSession = stored;
      biometricSessionLocked = true;
      biometricUnlockError = null;
      _restored = true;
      _changed();
      return;
    }
    final restored = await _refreshStoredSession(stored, operation);
    if (isCurrentRevision(operation)) _restored = restored;
  }

  Future<bool> _refreshStoredSession(AuthSession stored, int operation) async {
    if (stored.refreshTokenExpired) {
      await _writeStorage(() async {
        if (isCurrentRevision(operation)) await sessionStore.clear();
      });
      if (isCurrentRevision(operation)) {
        _feedback(error: '登录状态已失效，请使用账号登录');
        _changed();
      }
      return true;
    }
    try {
      final refreshed = await api.refresh(stored.refreshToken);
      if (!isCurrentRevision(operation)) return false;
      if (refreshed.user.userId != stored.user.userId) {
        throw const FormatException('登录用户与已保存会话不匹配');
      }
      if (await _activate(refreshed, operation)) {
        _feedback(notice: '已恢复登录状态');
        _changed();
        return true;
      }
    } on ApiException catch (error) {
      if (!isCurrentRevision(operation)) return false;
      if (error.statusCode == 401 || error.statusCode == 403) {
        await _writeStorage(() async {
          if (isCurrentRevision(operation)) await sessionStore.clear();
        });
        if (isCurrentRevision(operation)) {
          _feedback(error: '登录状态已失效，请重新登录');
          _changed();
        }
        return true;
      }
      _feedback(notice: '网络暂不可用，请连接恢复后重试登录');
      _changed();
    } catch (_) {
      if (!isCurrentRevision(operation)) return false;
      _feedback(notice: '网络暂不可用，请连接恢复后重试登录');
      _changed();
    }
    return false;
  }

  Future<AuthSession?> login(String identifier, String password) =>
      _authenticate(
        () => api.login(username: identifier.trim(), password: password),
        failure: '登录失败',
        success: (session) =>
            session.requiresEmailVerification ? '请完成邮箱验证' : '登录成功',
      );

  Future<AuthSession?> register(
    String identifier,
    String password, {
    bool phone = false,
    String? inviteCode,
  }) => _authenticate(
    () => api.register(
      password: password,
      email: identifier.trim(),
      phone: phone,
      inviteCode: inviteCode,
    ),
    failure: '注册失败',
    success: (session) =>
        session.requiresEmailVerification ? '注册成功，请先完成邮箱验证' : '注册成功',
  );

  Future<AuthSession?> loginTelegram(
    Future<AuthSession> Function() authenticate,
  ) => _authenticate(
    authenticate,
    failure: 'Telegram 登录失败',
    success: (_) => '登录成功',
  );

  Future<AuthSession?> loginGoogle(
    Future<AuthSession> Function() authenticate,
  ) => _authenticate(
    authenticate,
    failure: 'Google 登录失败',
    success: (_) => '登录成功',
  );

  Future<AuthSession?> _authenticate(
    Future<AuthSession> Function() authenticate, {
    required String failure,
    required String Function(AuthSession session) success,
  }) async {
    if (offline || _disposed) return null;
    final operation = ++_revision;
    pendingLoginChallenge = null;
    loading = true;
    _feedback();
    _changed();
    try {
      // An older logout must finish clearing a saved OAuth flow before a new
      // login writes one. The session save itself is queued separately below.
      await _storageTail;
      if (!isCurrentRevision(operation)) return null;
      final authenticated = await authenticate();
      if (!isCurrentRevision(operation)) return null;
      if (!await _acceptLogin(authenticated, operation)) return null;
      if (!isCurrentRevision(operation)) return null;
      _feedback(notice: success(authenticated));
      return authenticated;
    } on GoogleLoginCancelled {
      return null;
    } on TelegramLoginCancelled {
      return null;
    } on LoginChallenge catch (challenge) {
      if (isCurrentRevision(operation)) pendingLoginChallenge = challenge;
      return null;
    } catch (error) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '$failure：${clientErrorMessage(error)}');
      }
      return null;
    } finally {
      if (isCurrentRevision(operation)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<bool> _acceptLogin(AuthSession authenticated, int operation) async {
    if (!isCurrentRevision(operation)) return false;
    _checkSession(authenticated);
    pendingLoginChallenge = null;
    if (authenticated.requiresEmailVerification) {
      pendingVerificationSession = authenticated;
      api.setSession(authenticated);
      return true;
    }
    pendingVerificationSession = null;
    _resetBiometricUnlock();
    return _activate(authenticated, operation);
  }

  Future<bool> verifyLogin(Map<String, String> codes) async {
    if (_disposed) return false;
    final challenge = pendingLoginChallenge;
    if (challenge == null || challenge.expired) {
      _feedback(error: '验证已过期，请重新登录');
      _changed();
      return false;
    }
    final operation = ++_revision;
    try {
      final authenticated = await api.verifyLogin(challenge, codes);
      if (!isCurrentRevision(operation) ||
          !identical(challenge, pendingLoginChallenge)) {
        return false;
      }
      if (!await _acceptLogin(authenticated, operation)) return false;
      _feedback();
      _changed();
      return true;
    } catch (error) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '安全验证失败：${clientErrorMessage(error)}');
        _changed();
      }
      return false;
    }
  }

  Future<bool> verifyPendingEmail(String code) async {
    if (_disposed) return false;
    final pending = pendingVerificationSession;
    if (pending == null) {
      _feedback(error: '验证会话已失效，请重新注册');
      _changed();
      return false;
    }
    final operation = ++_revision;
    loading = true;
    _feedback();
    _changed();
    try {
      final verified = await api.verifyEmail(pending, code.trim());
      if (!isCurrentRevision(operation) ||
          !identical(pending, pendingVerificationSession)) {
        return false;
      }
      if (!verified) throw StateError('验证码无效或已过期');
      if (!await _activate(pending, operation)) return false;
      pendingVerificationSession = null;
      _feedback(notice: '邮箱验证成功');
      return true;
    } catch (error) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '邮箱验证失败：${clientErrorMessage(error)}');
      }
      return false;
    } finally {
      if (isCurrentRevision(operation)) {
        loading = false;
        _changed();
      }
    }
  }

  Future<bool> resendPendingEmail() async {
    if (_disposed) return false;
    final pending = pendingVerificationSession;
    if (pending == null) {
      _feedback(error: '验证会话已失效，请重新注册');
      _changed();
      return false;
    }
    final operation = _revision;
    try {
      await api.resendEmailVerification(pending);
      if (!isCurrentRevision(operation) ||
          !identical(pending, pendingVerificationSession)) {
        return false;
      }
      _feedback(notice: '新的验证码已发送');
      _changed();
      return true;
    } catch (error) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '验证码发送失败：${clientErrorMessage(error)}');
        _changed();
      }
      return false;
    }
  }

  Future<bool> requestPasswordReset(String identifier) async {
    if (_disposed) return false;
    final operation = _revision;
    try {
      await api.forgotPassword(identifier.trim());
      if (!isCurrentRevision(operation)) return false;
      _feedback(notice: '如果该邮箱已注册，验证码已发送');
      _changed();
      return true;
    } catch (error) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '验证码发送失败：${clientErrorMessage(error)}');
        _changed();
      }
      return false;
    }
  }

  Future<bool> resetPassword({
    required String identifier,
    required String code,
    required String newPassword,
  }) async {
    if (_disposed) return false;
    final operation = _revision;
    try {
      await api.resetPassword(
        identifier: identifier.trim(),
        code: code.trim(),
        newPassword: newPassword,
      );
      if (!isCurrentRevision(operation)) return false;
      _feedback(notice: '密码已更新，请使用新密码登录');
      _changed();
      return true;
    } catch (error) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '密码更新失败：${clientErrorMessage(error)}');
        _changed();
      }
      return false;
    }
  }

  Future<bool> resumeTelegramLogin(Uri link) async {
    if (!TelegramLoginFlow.isReturnLink(link) || offline || _disposed) {
      return false;
    }
    final operation = _revision;
    await restore();
    if (!isCurrentRevision(operation) ||
        loading ||
        _current != null ||
        pendingBiometricSession != null ||
        pendingVerificationSession != null ||
        pendingLoginChallenge != null) {
      return false;
    }
    final flow = await telegramLoginStore.read(api);
    if (flow == null ||
        !flow.matches(link) ||
        !isCurrentRevision(operation) ||
        loading ||
        _current != null) {
      return false;
    }
    await loginTelegram(
      () => signInWithTelegram(
        api: api,
        openBrowser: (_) async => false,
        cancelled: () => !isCurrentRevision(operation + 1),
        store: telegramLoginStore,
        resume: flow,
      ),
    );
    return true;
  }

  void updateBiometricAppVisibility({
    required bool foreground,
    bool lockSession = false,
  }) {
    _biometricAppForeground = foreground;
    _biometricAppBackgrounded = lockSession;
    if (lockSession &&
        biometricLoginEnabled &&
        !biometricLoginUpdating &&
        _current != null &&
        !biometricSessionLocked) {
      biometricSessionLocked = true;
      biometricUnlockError = null;
      _changed();
    }
  }

  void _resetBiometricUnlock() {
    ++_biometricVersion;
    biometricSessionLocked = false;
    biometricUnlocking = false;
    biometricUnlockError = null;
    pendingBiometricSession = null;
  }

  Future<bool> unlockBiometricSession() async {
    if (!canUnlockBiometricSession ||
        biometricUnlocking ||
        !_biometricAppForeground ||
        _disposed) {
      return false;
    }
    final operation = _revision;
    final unlock = _biometricVersion;
    final pending = pendingBiometricSession;
    bool current() =>
        isCurrentRevision(operation) && unlock == _biometricVersion;
    biometricUnlocking = true;
    biometricUnlockError = null;
    _changed();
    try {
      final accepted = await sessionStore.authenticateBiometric();
      if (!current()) return false;
      if (!accepted) {
        biometricUnlockError = '验证已取消或未通过，请重试';
        return false;
      }
      if (_biometricAppBackgrounded) return false;
      if (pending != null) await _refreshStoredSession(pending, operation);
      if (!current()) return false;
      if (_current == null) {
        biometricUnlockError = lastError ?? lastNotice ?? '登录状态无法恢复，请重试或使用账号登录';
        return false;
      }
      if (_biometricAppBackgrounded) return false;
      biometricSessionLocked = false;
      biometricUnlockError = null;
      _feedback();
      return true;
    } catch (_) {
      if (current()) biometricUnlockError = '生物识别暂不可用，请重试或使用账号登录';
      return false;
    } finally {
      if (current()) {
        biometricUnlocking = false;
        _changed();
      }
    }
  }

  Future<bool> enableBiometricLogin() async {
    final active = _current;
    if (active == null || biometricLoginUpdating || _disposed) return false;
    final operation = _revision;
    biometricLoginUpdating = true;
    _changed();
    try {
      await _writeStorage(() async {
        if (isCurrentRevision(operation)) await sessionStore.enableBiometric();
      });
      if (!isCurrentRevision(operation)) return false;
      biometricLoginAvailable = true;
      biometricLoginEnabled = true;
      _feedback(notice: '已启用生物识别登录');
      return true;
    } catch (error) {
      if (isCurrentRevision(operation)) {
        _feedback(error: '启用生物识别失败：${clientErrorMessage(error)}');
      }
      return false;
    } finally {
      if (isCurrentRevision(operation)) {
        biometricLoginUpdating = false;
        _changed();
      }
    }
  }

  Future<bool> disableBiometricLogin() async {
    if (_disposed ||
        _current == null ||
        !biometricLoginEnabled ||
        biometricLoginUpdating) {
      return false;
    }
    final operation = _revision;
    biometricLoginUpdating = true;
    _changed();
    try {
      await _writeStorage(() async {
        if (!isCurrentRevision(operation)) return;
        await sessionStore.clear();
        if (!isCurrentRevision(operation)) return;
        // A refresh may replace the token while the preference is being cleared.
        final latest = _current;
        if (latest != null) await sessionStore.saveSession(latest);
      });
      if (!isCurrentRevision(operation)) return false;
      biometricLoginEnabled = false;
      _resetBiometricUnlock();
      _feedback(notice: '已关闭生物识别登录');
      return true;
    } catch (error) {
      if (!isCurrentRevision(operation)) return false;
      try {
        final enabled = await sessionStore.biometricEnabled();
        if (isCurrentRevision(operation)) biometricLoginEnabled = enabled;
      } catch (_) {
        // Secure-storage failure cannot authorize an unlock.
      }
      if (isCurrentRevision(operation)) {
        _feedback(error: '关闭生物识别失败：${clientErrorMessage(error)}');
      }
      return false;
    } finally {
      if (isCurrentRevision(operation)) {
        biometricLoginUpdating = false;
        _changed();
      }
    }
  }

  Future<void> persistRefreshedSession(AuthSession next) async {
    final previous = _current;
    if (_disposed) return;
    if (previous == null) {
      api.setSession(pendingVerificationSession);
      return;
    }
    if (previous.user.userId != next.user.userId) {
      api.setSession(previous);
      throw const FormatException('刷新会话与当前账户不匹配');
    }
    try {
      _checkSession(next);
    } catch (_) {
      api.setSession(previous);
      rethrow;
    }
    final operation = _revision;
    _changeSession(next, AuthSessionChange.tokenRefreshed);
    await _saveSession(next, operation);
    await _sessionReady(
      previous,
      next,
      AuthSessionChange.tokenRefreshed,
      operation,
    );
    if (isCurrentRevision(operation)) _changed();
  }

  Future<void> logout() => _close(AuthSessionChange.signedOut);
  Future<void> expire() => _close(AuthSessionChange.expired);

  Future<void> _close(AuthSessionChange change) async {
    if (_disposed) return;
    final wasLocked = requiresBiometricUnlock;
    final locked = wasLocked && change == AuthSessionChange.expired;
    final operation = ++_revision;
    api.cancelPendingRequests();
    _resetBiometricUnlock();
    biometricSessionLocked = locked;
    if (locked) biometricUnlockError = '登录状态已失效，请使用账号登录';
    biometricLoginEnabled = false;
    biometricLoginUpdating = false;
    pendingVerificationSession = null;
    pendingLoginChallenge = null;
    loading = false;
    final previous = _changeSession(null, change);
    // Queue the clear immediately. A save already inside secure storage may
    // finish, but cannot become the final write after this logout.
    final cleared = _writeStorage(sessionStore.clear);
    _changed();
    try {
      await cleared;
    } catch (error, stack) {
      if (isCurrentRevision(operation)) {
        biometricSessionLocked = wasLocked;
        if (wasLocked) biometricUnlockError = '无法清除安全登录资料，请重试或使用账号登录';
        _feedback(error: '无法清除本机登录资料，请重试退出');
        _changed();
      }
      Error.throwWithStackTrace(error, stack);
    }
    await _sessionReady(previous, null, change, operation);
    if (isCurrentRevision(operation)) _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_revision;
    _resetBiometricUnlock();
    api.onSessionRefreshed = null;
    api.onSessionExpired = null;
    super.dispose();
  }
}
