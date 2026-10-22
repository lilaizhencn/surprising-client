import 'dart:async';
import 'dart:convert';

import '../api.dart';
import '../account_records.dart';
import '../models.dart';
import '../pending_transfer.dart';
import '../session_store.dart';

/// Owns durable transfer intents. Recovery always submits the original command.
class AccountTransferState {
  AccountTransferState({
    required this.api,
    required this.settingsStore,
    required this.owner,
    required this.persist,
    required this.refreshAssets,
    required this.onChanged,
  });

  final ApiClient api;
  final ClientSettingsStore settingsStore;
  final ({int? userId, int epoch}) Function() owner;
  // The shared settings queue must call completeSaved inside its write lock,
  // after durable removal succeeds and before the next queued write starts.
  final Future<bool> Function({PendingAccountTransfer? completed}) persist;
  final Future<void> Function() refreshAssets;
  final void Function() onChanged;
  final _pending = <int, PendingAccountTransfer>{};
  final _inFlight = <int>{};
  Future<bool>? _restoring;
  bool _restored = false;
  bool _closed = false;
  ({int? userId, int epoch})? _feedbackOwner;
  String? _error, _notice;

  bool get restored => _restored;
  List<PendingAccountTransfer> get pendingSnapshot =>
      List.unmodifiable(_pending.values);
  PendingAccountTransfer? get pending => _pending[owner().userId];
  bool get submitting => _inFlight.contains(owner().userId);
  bool get verificationRequired => pending?.status == 'VERIFY';
  bool get outcomeLocked => pending != null && !verificationRequired;
  bool get terminalFailure => pending?.status == 'FAILED';
  String? get error => _feedbackOwner == owner() ? _error : null;
  String? get notice => _feedbackOwner == owner() ? _notice : null;

  bool matches(PendingAccountTransfer intent) =>
      identical(_pending[intent.userId], intent);

  /// Called only after the central settings queue durably removes this intent.
  bool completeSaved(PendingAccountTransfer intent) {
    if (!matches(intent)) return false;
    _pending.remove(intent.userId);
    return true;
  }

  void restoreFrom(Map<String, String> values) {
    if (_restored) return;
    final raw = jsonDecode(values['pendingTransfers'] ?? '[]');
    if (raw is! List || raw.length > 128) {
      throw const FormatException('划转恢复资料无效');
    }
    final restored = <int, PendingAccountTransfer>{};
    for (final row in raw) {
      if (row is! Map<String, dynamic>) {
        throw const FormatException('划转恢复资料无效');
      }
      final intent = PendingAccountTransfer.fromJson(row);
      if (restored.containsKey(intent.userId)) {
        throw const FormatException('划转恢复资料重复');
      }
      restored[intent.userId] = intent;
    }
    for (final entry in restored.entries) {
      _pending.putIfAbsent(entry.key, () => entry.value);
    }
    _restored = true;
  }

  Future<bool> restore() async {
    if (_closed) return false;
    if (_restored) return true;
    final existing = _restoring;
    if (existing != null) return existing;
    final loading = _restoreOnce();
    _restoring = loading;
    try {
      return await loading;
    } finally {
      if (identical(_restoring, loading)) _restoring = null;
    }
  }

  Future<bool> _restoreOnce() async {
    try {
      final values = await settingsStore.read();
      if (_closed) return false;
      restoreFrom(values);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _current(({int? userId, int epoch}) identity) =>
      !_closed && owner() == identity;

  void _feedback(
    ({int? userId, int epoch}) identity, {
    String? error,
    String? notice,
  }) {
    if (!_current(identity)) return;
    _feedbackOwner = identity;
    _error = error;
    _notice = notice;
    onChanged();
  }

  Future<bool> _save({PendingAccountTransfer? completed}) async {
    try {
      return await persist(completed: completed);
    } catch (_) {
      return false;
    }
  }

  Future<void> submit({
    required String sourceAccountType,
    required String targetAccountType,
    required String asset,
    required String amountText,
    String? emailCode,
    String? totpCode,
  }) async {
    if (_closed) return;
    final identity = owner();
    final id = identity.userId;
    if (id == null) {
      _feedback(identity, error: '请先登录再划转');
      return;
    }
    if (submitting || outcomeLocked) return;
    final currency = asset.toUpperCase();
    if (sourceAccountType == targetAccountType ||
        !productAccountTypes.contains(sourceAccountType) ||
        !productAccountTypes.contains(targetAccountType)) {
      _feedback(identity, error: '请选择不同的划出和划入账户');
      return;
    }
    if (!RegExp(r'^[A-Z0-9]{1,20}$').hasMatch(currency)) {
      _feedback(identity, error: '请选择有效币种');
      return;
    }
    _inFlight.add(id);
    _feedback(identity);
    try {
      final scales = await api.assetScales();
      if (!_current(identity)) return;
      final units = exactAmountUnits(amountText, scales[currency] ?? '');
      if (!await restore()) {
        throw StateError('无法读取原划转凭证，请检查安全存储后重试');
      }
      if (!_current(identity)) return;
      final original = _pending[id];
      final PendingAccountTransfer intent;
      if (original != null) {
        if (original.status != 'VERIFY' ||
            original.source != sourceAccountType ||
            original.target != targetAccountType ||
            original.asset != currency ||
            original.amountUnits != units) {
          _feedback(identity, error: '请先确认原划转结果');
          return;
        }
        intent = original;
      } else {
        intent = PendingAccountTransfer.create(
          userId: id,
          source: sourceAccountType,
          target: targetAccountType,
          asset: currency,
          amountUnits: units,
        );
        _pending[id] = intent;
      }
      if (!await _save()) {
        _feedback(identity, error: '无法安全保存划转凭证，未发送请求，请检查安全存储');
        return;
      }
      if (!_current(identity)) return;
      await _submit(intent, identity, emailCode: emailCode, totpCode: totpCode);
    } catch (error) {
      _feedback(
        identity,
        error: error is FormatException
            ? error.message
            : clientErrorMessage(error),
      );
    } finally {
      _inFlight.remove(id);
      if (_current(identity)) onChanged();
    }
  }

  /// Explicit user recovery, never an automatic retry of a monetary command.
  Future<void> resume({String? emailCode, String? totpCode}) async {
    if (_closed) return;
    final intent = pending, identity = owner();
    if (intent == null || submitting || intent.status == 'FAILED') return;
    _inFlight.add(intent.userId);
    _feedback(identity);
    try {
      if (!await _save()) {
        _feedback(identity, error: '无法安全保存划转凭证，未发送请求，请检查安全存储');
        return;
      }
      if (!_current(identity)) return;
      await _submit(intent, identity, emailCode: emailCode, totpCode: totpCode);
    } finally {
      _inFlight.remove(intent.userId);
      if (_current(identity)) onChanged();
    }
  }

  Future<void> _submit(
    PendingAccountTransfer intent,
    ({int? userId, int epoch}) identity, {
    String? emailCode,
    String? totpCode,
  }) async {
    try {
      final result = await api.transfer(
        userId: intent.userId,
        sourceAccountType: intent.source,
        targetAccountType: intent.target,
        asset: intent.asset,
        amountUnits: intent.amountUnits,
        idempotencyKey: intent.key,
        emailCode: emailCode,
        totpCode: totpCode,
      );
      if (!matches(intent)) return;
      final status = asString(
        result['status'],
        fallback: 'UNKNOWN',
      ).toUpperCase();
      final transferId = asString(result['transferId']).trim();
      if (status == 'COMPLETED') {
        if (!await _save(completed: intent) || matches(intent)) {
          _feedback(identity, error: '划转已完成，但恢复凭证未能清除，请继续确认原请求');
          return;
        }
        if (_current(identity)) {
          _feedback(
            identity,
            notice: '划转已完成${transferId.isEmpty ? '' : '，流水号 $transferId'}',
          );
          await refreshAssets();
        }
      } else {
        _pending[intent.userId] = intent.withStatus(
          const {'FAILED', 'PENDING', 'SOURCE_DEBITED'}.contains(status)
              ? status
              : 'UNKNOWN',
        );
        await _save();
        _feedback(
          identity,
          error: status == 'FAILED'
              ? '划转未完成${transferId.isEmpty ? '' : '，流水号 $transferId'}，请查看资金记录'
              : '划转处理中${transferId.isEmpty ? '' : '，流水号 $transferId'}，请勿重复提交',
        );
      }
    } catch (error) {
      if (!matches(intent)) return;
      if (error is ApiException && error.statusCode == 428) {
        _pending[intent.userId] = intent.withStatus('VERIFY');
        await _save();
        if (!_current(identity)) return;
        try {
          final challenge = await api.issueSecurityChallenge('LARGE_TRANSFER');
          _feedback(
            identity,
            notice: '大额划转需要验证，验证码已发送至 ${asString(challenge['destination'])}',
          );
        } catch (_) {
          _feedback(identity, error: '验证码发送失败，请稍后重试');
        }
      } else {
        _pending[intent.userId] = intent.withStatus('UNKNOWN');
        await _save();
        _feedback(identity, error: '划转结果未知，请勿重复提交，请确认原划转');
      }
    }
  }

  Future<void> resetFailedIntent() async {
    if (_closed) return;
    final intent = pending, identity = owner();
    if (intent == null || intent.status != 'FAILED' || submitting) return;
    if (!await _save(completed: intent) || matches(intent)) {
      _feedback(identity, error: '无法清除原划转凭证，请检查安全存储');
    } else {
      _feedback(identity);
    }
  }

  void dispose() {
    _closed = true;
  }
}
