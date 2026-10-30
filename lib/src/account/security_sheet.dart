import '../i18n/client_messages.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../api.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../auth/auth_sheet.dart';
import '../device_access_panel.dart';
import '../kyc_application_page.dart';
import '../kyc_documents_page.dart';
import '../models.dart';
import '../ui/client_components.dart';
import 'kyc_webview.dart';
import 'api_key_edit_dialog.dart';
import 'kyc_status.dart';

class SecuritySheet extends StatefulWidget {
  const SecuritySheet({this.kycOnly = false, super.key});

  final bool kycOnly;

  @override
  State<SecuritySheet> createState() => _SecuritySheetState();
}

class _SecuritySheetState extends State<SecuritySheet>
    with WidgetsBindingObserver {
  Timer? _kycStatusPoll;
  bool _pollingSecurity = false;
  bool _operationCancelled = false;
  Map<String, dynamic> mfa = const {};
  Map<String, dynamic> mfaRecovery = const {};
  Map<String, dynamic> mfaRecoveryChallenge = const {};
  Map<String, dynamic> enrollment = const {};
  PrimaryAuthenticationContext? primaryAuthentication;
  List<Map<String, dynamic>> scenes = const [];
  List<Map<String, dynamic>> keys = const [];
  Map<String, dynamic> kyc = const {};
  Map<String, dynamic> kycProviderInfo = const {};
  Map<String, dynamic> kycVerificationSession = const {};
  final totp = TextEditingController();
  final emailCode = TextEditingController();
  final securityEmailCode = TextEditingController();
  final apiTotp = TextEditingController();
  final apiLabel = TextEditingController();
  final apiAllowlist = TextEditingController();
  bool apiTradeEnabled = false;
  bool apiWithdrawEnabled = false;
  String? apiSecret;
  final currentPassword = TextEditingController();
  final mfaPassword = TextEditingController();
  final mfaEmailCode = TextEditingController();
  final mfaPhoneCode = TextEditingController();
  final loginMethodDestination = TextEditingController();
  final mfaRecoveryCode = TextEditingController();
  final mfaRecoveryReason = TextEditingController();
  final newPassword = TextEditingController();
  final changePasswordEmailCode = TextEditingController();
  final changePasswordTotpCode = TextEditingController();
  List<Map<String, dynamic>> kycDocumentRecords = const [];
  String kycProvider = 'SUMSUB';
  bool get kycSimulationEnabled => kycProviderInfo['simulationEnabled'] == true;
  bool busy = false;
  String? error;
  String? notice;

  (int?, int)? loadedIdentity;
  (int?, int)? operationIdentity;
  (int?, int)? _identity(AppState state) =>
      state.isLoggedIn ? (state.userId, state.auth.revision) : null;
  bool get operationCurrent =>
      mounted &&
      operationIdentity == loadedIdentity &&
      _identity(AppScope.of(context)) == operationIdentity;
  bool loading = true;
  bool mfaLoaded = false;
  bool kycLoaded = false;
  int loadVersion = 0;
  final Map<String, String> loadErrors = {};
  List<Map<String, dynamic>> methods = const [];
  Map<String, dynamic> sessionsPage = const {};
  Map<String, dynamic> historyPage = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !loading && !busy) {
      unawaited(_load());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _kycStatusPoll ??= Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted ||
          _pollingSecurity ||
          loading ||
          busy ||
          (WidgetsBinding.instance.lifecycleState != null &&
              WidgetsBinding.instance.lifecycleState !=
                  AppLifecycleState.resumed) ||
          loadedIdentity == null) {
        return;
      }
      final state = AppScope.of(context);
      if (_identity(state) != loadedIdentity) return;
      final version = loadVersion, token = loadedIdentity;
      _pollingSecurity = true;
      unawaited(() async {
        try {
          if (kyc['status'] == 'PENDING') {
            final value = await state.api.kycStatus();
            if (mounted &&
                version == loadVersion &&
                _identity(state) == token) {
              setState(() {
                kyc = value;
                if (kyc['status'] != 'PENDING') kycVerificationSession = {};
                loadErrors.remove('认证状态更新');
              });
            }
          }
          if (mfaRecovery['status'] == 'PENDING' &&
              version == loadVersion &&
              _identity(state) == token) {
            final value = await state.api.mfaRecoveryStatus();
            if (mounted &&
                version == loadVersion &&
                _identity(state) == token) {
              setState(() => mfaRecovery = value);
            }
          }
        } catch (_) {
          if (mounted && version == loadVersion && _identity(state) == token) {
            setState(() => loadErrors['认证状态更新'] = '认证状态更新失败，请刷新重试');
          }
        } finally {
          _pollingSecurity = false;
        }
      }());
    });
    final token = _identity(AppScope.of(context));
    if (token == loadedIdentity) return;
    loadedIdentity = token;
    ++loadVersion;
    mfa = {};
    mfaRecovery = {};
    mfaRecoveryChallenge = {};
    enrollment = {};
    primaryAuthentication = null;
    scenes = [];
    keys = [];
    kyc = {};
    kycProviderInfo = {};
    kycVerificationSession = {};
    methods = [];
    sessionsPage = {};
    historyPage = {};
    kycDocumentRecords = [];
    mfaLoaded = false;
    kycLoaded = false;
    loading = true;
    error = null;
    notice = null;
    loadErrors.clear();
    totp.clear();
    emailCode.clear();
    securityEmailCode.clear();
    apiTotp.clear();
    currentPassword.clear();
    newPassword.clear();
    changePasswordEmailCode.clear();
    changePasswordTotpCode.clear();
    apiLabel.clear();
    apiAllowlist.clear();
    apiSecret = null;
    apiTradeEnabled = false;
    apiWithdrawEnabled = false;
    mfaPassword.clear();
    mfaEmailCode.clear();
    mfaPhoneCode.clear();
    mfaRecoveryCode.clear();
    mfaRecoveryReason.clear();
    loginMethodDestination.clear();
    if (token != null) unawaited(_load());
  }

  @override
  void dispose() {
    _kycStatusPoll?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    totp.dispose();
    emailCode.dispose();
    securityEmailCode.dispose();
    apiTotp.dispose();
    apiLabel.dispose();
    apiAllowlist.dispose();
    currentPassword.dispose();
    mfaPassword.dispose();
    mfaEmailCode.dispose();
    mfaPhoneCode.dispose();
    loginMethodDestination.dispose();
    mfaRecoveryCode.dispose();
    mfaRecoveryReason.dispose();
    newPassword.dispose();
    changePasswordEmailCode.dispose();
    changePasswordTotpCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    if (!state.isLoggedIn) return;
    final token = _identity(state);
    final version = ++loadVersion;
    loading = true;
    mfaLoaded = false;
    kycLoaded = false;
    methods = [];
    sessionsPage = {};
    historyPage = {};
    mfa = {};
    primaryAuthentication = null;
    kyc = {};
    kycProviderInfo = {};
    scenes = [];
    keys = [];
    kycDocumentRecords = [];
    loadErrors.clear();
    bool current() =>
        mounted && version == loadVersion && _identity(state) == token;
    Future<void> read<T>(
      String label,
      Future<T> Function() request,
      void Function(T) apply,
    ) async {
      try {
        final value = await request();
        if (current()) setState(() => apply(value));
      } catch (_) {
        if (current()) setState(() => loadErrors[label] = '$label加载失败，请重试');
      }
    }

    await Future.wait([
      if (!widget.kycOnly) ...[
        read(
          '安全身份',
          state.api.primaryAuthentication,
          (value) => primaryAuthentication = value,
        ),
        read('2FA', state.api.mfaStatus, (value) {
          mfa = value;
          mfaLoaded = true;
        }),
        read(
          '2FA 恢复',
          state.api.mfaRecoveryStatus,
          (value) => mfaRecovery = value,
        ),
        read('敏感场景', state.api.securityScenes, (value) => scenes = value),
        read('API 密钥', state.api.apiKeys, (value) => keys = value),
      ],
      read('身份认证', state.api.kycStatus, (value) {
        kyc = value;
        kycLoaded = true;
        _applyKyc(kyc);
      }),
      read('KYC 服务', state.api.kycProvider, (value) {
        kycProviderInfo = value;
        kycProvider = asString(value['provider'], fallback: 'SUMSUB');
      }),
      read(
        '认证材料',
        state.api.kycDocuments,
        (value) => kycDocumentRecords = value,
      ),
      if (!widget.kycOnly) ...[
        read(
          '登录验证方式',
          state.api.loginVerificationMethods,
          (value) => methods = value,
        ),
        read('活跃会话', state.api.userSessions, (value) => sessionsPage = value),
        read('登录历史', state.api.loginHistory, (value) => historyPage = value),
      ],
    ]);
    if (current()) setState(() => loading = false);
  }

  Future<void> _loadMoreSecurity(bool history) async {
    final state = AppScope.of(context);
    final token = _identity(state);
    final page = history ? historyPage : sessionsPage;
    final cursor = nullableString(page['nextCursor']);
    if (cursor == null) return;
    final next = history
        ? await state.api.loginHistory(cursor: cursor)
        : await state.api.userSessions(cursor: cursor);
    if (!mounted || _identity(state) != token) return;
    final field = history ? 'logs' : 'sessions';
    setState(() {
      final merged = {
        ...next,
        field: [...asList(page[field]), ...asList(next[field])],
      };
      if (history) {
        historyPage = merged;
      } else {
        sessionsPage = merged;
      }
    });
  }

  void _applyKyc(Map<String, dynamic> profile) {
    if (profile['provider'] != null) {
      kycProvider = asString(profile['provider']);
    }
  }

  Future<void> _completeKycSimulation(AppState state, String decision) async {
    final next = await state.api.completeKycSimulation(decision);
    if (!operationCurrent) return;
    setState(() {
      kyc = next;
      kycVerificationSession = {};
    });
  }

  Future<void> _launchKycProvider(AppState state) async {
    final session = kycVerificationSession;
    final token = asString(session['launchToken']);
    final redirect = asString(session['redirectUrl']);
    if (kycProvider == 'SUMSUB' && token.isNotEmpty) {
      if (Platform.isAndroid) {
        final permissions = await const MethodChannel(
          'surprising/kyc-permissions',
        ).invokeMethod<bool>('requestCameraAndMicrophone');
        if (permissions != true) {
          throw const FormatException('身份核验需要相机和麦克风权限');
        }
      }
      if (!mounted || !operationCurrent) return;
      await showDialog<void>(
        context: context,
        builder: (_) => KycSumsubWebView(
          token: token,
          language: state.language,
          refreshToken: () async {
            if (!operationCurrent) throw const FormatException('登录状态已变化');
            final refreshed = await state.api.refreshKycSession();
            final nextToken = asString(refreshed['launchToken']);
            if (nextToken.isEmpty) throw const FormatException('无法刷新核验令牌');
            return nextToken;
          },
        ),
      );
      if (operationCurrent) {
        await state.api.kycStatus().then((value) {
          if (operationCurrent) {
            setState(() {
              kyc = value;
              if (kyc['status'] != 'PENDING') kycVerificationSession = {};
            });
          }
        });
      }
      return;
    }
    if (kycProvider == 'VERIFF' && redirect.isNotEmpty) {
      final uri = Uri.tryParse(redirect);
      if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
        throw const FormatException('服务商核验链接无效');
      }
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw const FormatException('无法打开身份核验，请重试');
      }
      return;
    }
    throw const FormatException('当前核验会话暂不可启动');
  }

  Future<void> _changePassword(AppState state) async {
    if (currentPassword.text.isEmpty || newPassword.text.length < 8) {
      throw const FormatException('请输入当前密码和至少 8 位新密码');
    }
    await state.api.changePassword(
      currentPassword: currentPassword.text,
      newPassword: newPassword.text,
      emailCode: changePasswordEmailCode.text,
      totpCode: changePasswordTotpCode.text,
    );
    if (!operationCurrent) return;
    setState(() {
      currentPassword.clear();
      newPassword.clear();
      changePasswordEmailCode.clear();
      changePasswordTotpCode.clear();
    });
  }

  Future<void> _updateSecurityScene(
    AppState state,
    String code,
    bool enabled,
  ) async {
    try {
      final saved = await state.api.updateSecurityScene(
        code,
        enabled,
        emailCode: securityEmailCode.text.trim(),
        totpCode: totp.text.trim(),
      );
      if (operationCurrent) {
        setState(
          () => scenes = scenes
              .map((item) => asString(item['sceneCode']) == code ? saved : item)
              .toList(),
        );
        securityEmailCode.clear();
      }
    } on ApiException catch (cause) {
      if (cause.statusCode != 428) rethrow;
      final challenge = await state.api.issueSecurityChallenge(
        'SECURITY_SETTINGS',
      );
      if (operationCurrent) {
        setState(
          () =>
              notice = '安全设置需要验证，验证码已发送至 ${asString(challenge['destination'])}',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    if (busy) return;
    operationIdentity = loadedIdentity;
    _operationCancelled = false;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await action();
      if (operationCurrent && notice == null && !_operationCancelled) {
        setState(() => notice = message);
      }
    } catch (cause) {
      if (operationCurrent) {
        setState(
          () => error = cause is FormatException
              ? cause.message
              : cause is ApiException
              ? '$cause'
              : '操作未完成，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<String> _apiAllowlist() => apiAllowlist.text
      .split(RegExp(r'[\s,]+'))
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();

  Future<bool> _confirmSecurity(String title, String message) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: LText(title),
            content: LText(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const LText('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const LText('确认'),
              ),
            ],
          ),
        ) ==
        true;
    if (!confirmed) _operationCancelled = true;
    return confirmed;
  }

  Future<void> _beginLoginMethodChange(
    AppState state,
    String method,
    bool enabled, {
    bool changeBinding = false,
  }) => _run(() async {
    mfaPassword.clear();
    loginMethodDestination.clear();
    final primary = await state.api.primaryAuthentication();
    if (!mounted || !operationCurrent) return;
    setState(() => primaryAuthentication = primary);
    if (primary.reauthenticationRequired) {
      throw const FormatException('请重新登录后继续安全设置');
    }
    final setting = methods
        .where((entry) => entry['type'] == method)
        .firstOrNull;
    final newDestination =
        enabled && (changeBinding || setting?['bound'] != true);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: LText(changeBinding ? '更换绑定' : '安全验证方式设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LText('绑定或变更安全信息后，24 小时内不能提现。'),
            if (primary.passwordRequired)
              TextField(
                controller: mfaPassword,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: clientLabel(context, '登录密码'),
                ),
              ),
            if (newDestination)
              TextField(
                controller: loginMethodDestination,
                keyboardType: method == 'EMAIL'
                    ? TextInputType.emailAddress
                    : TextInputType.phone,
                decoration: InputDecoration(
                  labelText: clientLabel(
                    context,
                    method == 'EMAIL' ? '邮箱' : '手机号（国际区号）',
                  ),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LText('发送验证码'),
          ),
        ],
      ),
    );
    if (!operationCurrent || accepted != true) {
      _operationCancelled = true;
      return;
    }
    if (primary.passwordRequired && mfaPassword.text.isEmpty) {
      throw const FormatException('请输入登录密码');
    }
    if (newDestination && loginMethodDestination.text.trim().isEmpty) {
      throw const FormatException('请输入要绑定的邮箱或手机号');
    }
    final next = await state.api.beginLoginMethod(
      method: method,
      currentPassword: primary.passwordRequired ? mfaPassword.text : '',
      enabled: enabled,
      destination: newDestination ? loginMethodDestination.text : null,
    );
    if (operationCurrent) {
      setState(() => enrollment = {...next, 'loginMethod': method});
    }
  }, '验证码已发送，请完成安全验证');

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isLoggedIn) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: LText('登录已失效，请重新登录'),
      );
    }
    final mfaEnabled = mfa['enabled'] == true || mfa['enrolled'] == true;
    final actionsBlocked = busy || loading || !mfaLoaded;
    final kycActionsBlocked =
        busy || loading || !kycLoaded || kycProviderInfo.isEmpty;
    final enrollmentSecret = asString(enrollment['secret']);
    final mfaChallenge = asMap(enrollment['challenge']);
    final challengeMethods = asList(
      mfaChallenge['methods'],
    ).map(asMap).toList();
    final challengeToken = asString(mfaChallenge['challengeToken']);
    final disablingMfa = enrollment['disabling'] == true;
    final needsEmailCode = challengeMethods.any(
      (method) => method['type'] == 'EMAIL',
    );
    final needsPhoneCode = challengeMethods.any(
      (method) => method['type'] == 'PHONE',
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                LText(
                  widget.kycOnly
                      ? clientText(
                          state.language,
                          '身份认证',
                          'Identity verification',
                        )
                      : '安全中心',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (notice != null)
              LText(
                notice!,
                style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
              ),
            if (error != null)
              LText(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (loading) const LinearProgressIndicator(),
            for (final message in loadErrors.values) LText(message),
            TextButton.icon(
              onPressed: loading || busy
                  ? null
                  : () => _run(_load, widget.kycOnly ? '认证状态已更新' : '安全状态已更新'),
              icon: const Icon(Icons.refresh),
              label: LText(widget.kycOnly ? '刷新认证状态' : '刷新安全状态'),
            ),
            if (!widget.kycOnly) ...[
              if (primaryAuthentication?.reauthenticationRequired == true ||
                  error == '请重新登录后继续安全设置')
                TextButton.icon(
                  onPressed: busy ? null : () => showAuthSheet(context),
                  icon: const Icon(Icons.login),
                  label: const LText('重新登录验证身份'),
                ),
              SectionTitle(title: clientLabel(context, '登录验证方式')),
              for (final method in methods)
                if (method['type'] == 'TOTP')
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: InfoLine(
                        label: clientLabel(context, '谷歌验证器'),
                        value:
                            '${method['bound'] == true ? asString(method['destination'], fallback: '已绑定') : '未绑定'} · ${method['enabled'] == true ? '已启用' : '未启用'}',
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InfoLine(
                            label: switch (method['type']) {
                              'EMAIL' => '邮箱',
                              'PHONE' => '手机',
                              _ => '谷歌验证器',
                            },
                            value:
                                '${method['bound'] == true ? asString(method['destination'], fallback: '已绑定') : '未绑定'} · ${method['enabled'] == true ? '已启用' : '未启用'}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: actionsBlocked
                                    ? null
                                    : () => _beginLoginMethodChange(
                                        state,
                                        asString(method['type']),
                                        method['enabled'] != true,
                                      ),
                                child: LText(
                                  method['enabled'] == true ? '停用' : '启用/绑定',
                                ),
                              ),
                              if (method['type'] == 'EMAIL' ||
                                  method['type'] == 'PHONE')
                                TextButton(
                                  onPressed: actionsBlocked
                                      ? null
                                      : () => _beginLoginMethodChange(
                                          state,
                                          asString(method['type']),
                                          true,
                                          changeBinding: true,
                                        ),
                                  child: const LText('更换绑定'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              TextButton.icon(
                icon: const Icon(Icons.devices_outlined),
                label: const LText('下线其他设备'),
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        final confirmed = await _confirmSecurity(
                          '下线其他设备？',
                          '当前手机会保持登录，其他设备需要重新登录。',
                        );
                        if (!confirmed || !operationCurrent) return;
                        await state.api.revokeOtherSessions(
                          state.session!.refreshToken,
                        );
                        if (operationCurrent) await _load();
                      }, '其他设备已下线'),
              ),
              DeviceAccessPanel(state: state),
              ExpansionTile(
                title: const LText('活跃会话'),
                children: [
                  for (final item in asList(sessionsPage['sessions']))
                    ListTile(
                      title: LText(
                        asString(asMap(item)['userAgent'], fallback: '未知设备'),
                      ),
                      subtitle: LText(
                        '${asMap(item)['ipAddress'] ?? '—'}\n登录 ${asMap(item)['createdAt'] ?? '—'}\n到期 ${asMap(item)['expiresAt'] ?? '—'}',
                      ),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () => _run(() async {
                                final id = asString(asMap(item)['sessionId']);
                                if (id.isEmpty) {
                                  throw const FormatException('会话信息暂不可用，请刷新');
                                }
                                if (!await _confirmSecurity(
                                      '下线这个会话？',
                                      '该设备需要重新登录后才能继续使用。',
                                    ) ||
                                    !operationCurrent) {
                                  return;
                                }
                                await state.api.revokeUserSession(id);
                                if (operationCurrent) await _load();
                              }, '会话已下线'),
                        child: const LText('下线'),
                      ),
                    ),
                  if (!loading &&
                      !loadErrors.containsKey('活跃会话') &&
                      asList(sessionsPage['sessions']).isEmpty)
                    const LText('暂无活跃会话'),
                  if (sessionsPage['hasMore'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () =>
                                _run(() => _loadMoreSecurity(false), '已加载更多会话'),
                      child: const LText('加载更多会话'),
                    ),
                ],
              ),
              ExpansionTile(
                title: const LText('登录历史'),
                children: [
                  for (final item in asList(historyPage['logs']))
                    ListTile(
                      title: Text(
                        '${asMap(item)['result'] ?? '—'} · ${asMap(item)['ipAddress'] ?? '—'}',
                      ),
                      subtitle: Text(
                        '${asMap(item)['createdAt'] ?? '—'}\n${asMap(item)['userAgent'] ?? '—'}\n${asMap(item)['reason'] ?? ''}',
                      ),
                    ),
                  if (!loading &&
                      !loadErrors.containsKey('登录历史') &&
                      asList(historyPage['logs']).isEmpty)
                    const LText('暂无登录记录'),
                  if (historyPage['hasMore'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => _loadMoreSecurity(true),
                              '已加载更多登录记录',
                            ),
                      child: const LText('加载更多登录记录'),
                    ),
                ],
              ),
              SectionTitle(
                title: !mfaLoaded
                    ? '2FA 状态未获取'
                    : mfaEnabled
                    ? '2FA 已启用'
                    : '绑定 2FA',
              ),
              if (mfa['withdrawalsRestrictedUntil'] != null &&
                  DateTime.tryParse(
                        '${mfa['withdrawalsRestrictedUntil']}',
                      )?.isAfter(DateTime.now()) ==
                      true)
                LText(
                  '安全信息变更后提现暂不可用，可恢复时间：${mfa['withdrawalsRestrictedUntil']}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!mfaEnabled && enrollment.isEmpty) ...[
                const LText('绑定或变更邮箱、手机、谷歌验证码后，24 小时内不能提现。'),
                if (primaryAuthentication?.passwordRequired == true)
                  AppTextField(
                    controller: mfaPassword,
                    label: clientLabel(context, '登录密码'),
                  ),
                PrimaryAction(
                  label: clientLabel(context, '生成绑定信息'),
                  icon: Icons.qr_code_2,
                  onPressed:
                      actionsBlocked ||
                          primaryAuthentication == null ||
                          primaryAuthentication!.reauthenticationRequired
                      ? null
                      : () => _run(() async {
                          final next = await state.api.enrollMfa(
                            mfaPassword.text,
                          );
                          if (operationCurrent) {
                            setState(() => enrollment = next);
                          }
                        }, '验证码已发送，请完成双重验证'),
                ),
              ],
              if (mfaEnabled && enrollment.isEmpty) ...[
                const LText('关闭谷歌验证码后将重新生成新密钥；安全信息变更后 24 小时内不能提现。'),
                if (primaryAuthentication?.passwordRequired == true)
                  AppTextField(
                    controller: mfaPassword,
                    label: clientLabel(context, '登录密码'),
                  ),
                TextButton(
                  onPressed:
                      actionsBlocked ||
                          primaryAuthentication == null ||
                          primaryAuthentication!.reauthenticationRequired
                      ? null
                      : () => _run(() async {
                          final next = await state.api.beginMfaDisable(
                            mfaPassword.text,
                          );
                          if (operationCurrent) {
                            setState(
                              () => enrollment = {...next, 'disabling': true},
                            );
                          }
                        }, '验证码已发送，请完成双重验证'),
                  child: const LText('关闭 2FA'),
                ),
              ],
              if (enrollment.isNotEmpty) ...[
                if (enrollmentSecret.isNotEmpty) ...[
                  if (asString(
                    enrollment['qrCodeDataUrl'],
                  ).startsWith('data:image/png;base64,'))
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: Image.memory(
                          base64Decode(
                            asString(
                              enrollment['qrCodeDataUrl'],
                            ).split(',').last,
                          ),
                          width: 184,
                          height: 184,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  const LText('请使用身份验证器扫描二维码，或手动输入密钥。密钥只显示这一次，请勿截图或转发。'),
                  InfoLine(
                    label: clientLabel(context, '密钥'),
                    value: enrollmentSecret,
                  ),
                ],
                for (final method in challengeMethods)
                  if (method['type'] == 'EMAIL')
                    AppTextField(
                      controller: mfaEmailCode,
                      label: clientLabel(context, '邮箱验证码'),
                    ),
                for (final method in challengeMethods)
                  if (method['type'] == 'PHONE')
                    AppTextField(
                      controller: mfaPhoneCode,
                      label: clientLabel(context, '手机验证码'),
                    ),
                if (challengeMethods.any((method) => method['type'] == 'TOTP'))
                  AppTextField(
                    controller: totp,
                    label: disablingMfa ? '当前谷歌验证码' : '谷歌验证码',
                  ),
                LText('安全信息变更后，提现将在 24 小时后恢复。'),
                PrimaryAction(
                  label: disablingMfa ? '确认关闭' : '确认绑定',
                  icon: Icons.verified_user,
                  onPressed: actionsBlocked || challengeToken.isEmpty
                      ? null
                      : () => _run(
                          () async {
                            final args = {
                              'challengeToken': challengeToken,
                              'currentPassword': mfaPassword.text,
                              'emailCode': needsEmailCode
                                  ? mfaEmailCode.text.trim()
                                  : null,
                              'phoneCode': needsPhoneCode
                                  ? mfaPhoneCode.text.trim()
                                  : null,
                              'totpCode': totp.text.trim(),
                            };
                            final loginMethod = asString(
                              enrollment['loginMethod'],
                            );
                            final next = loginMethod.isNotEmpty
                                ? await state.api
                                      .confirmLoginMethod(
                                        method: loginMethod,
                                        currentPassword:
                                            args['currentPassword']!,
                                        challengeToken: args['challengeToken']!,
                                        emailCode: args['emailCode'],
                                        phoneCode: args['phoneCode'],
                                        totpCode: args['totpCode'],
                                      )
                                      .then((_) => state.api.mfaStatus())
                                : disablingMfa
                                ? await state.api.confirmMfaDisable(
                                    challengeToken: args['challengeToken']!,
                                    currentPassword: args['currentPassword']!,
                                    emailCode: args['emailCode'],
                                    phoneCode: args['phoneCode'],
                                    totpCode: args['totpCode']!,
                                  )
                                : await state.api.confirmMfa(
                                    challengeToken: args['challengeToken']!,
                                    currentPassword: args['currentPassword']!,
                                    emailCode: args['emailCode'],
                                    phoneCode: args['phoneCode'],
                                    totpCode: args['totpCode']!,
                                  );
                            if (operationCurrent) {
                              setState(() {
                                mfa = next;
                                enrollment = const {};
                                totp.clear();
                                mfaPassword.clear();
                                mfaEmailCode.clear();
                                mfaPhoneCode.clear();
                              });
                              if (loginMethod.isNotEmpty) unawaited(_load());
                            }
                          },
                          enrollment['loginMethod'] != null
                              ? '安全验证方式已更新'
                              : disablingMfa
                              ? '2FA 已关闭'
                              : '2FA 已启用',
                        ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => enrollment = const {}),
                  child: const LText('取消'),
                ),
              ],
              if (primaryAuthentication?.passwordRequired == true) ...[
                SectionTitle(title: clientLabel(context, '丢失谷歌验证码')),
                LText(
                  '恢复需要已通过的 KYC、登录密码、邮箱或手机验证码，并由运营人员人工审核。审核通过后会移除旧验证器，提现冻结 24 小时。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                if (mfaRecovery['status'] == 'PENDING')
                  InfoLine(
                    label: clientLabel(context, '恢复申请'),
                    value: '审核中 · ${mfaRecovery['submittedAt'] ?? ''}',
                  )
                else if (mfaRecovery['status'] == 'APPROVED')
                  InfoLine(
                    label: clientLabel(context, '恢复申请'),
                    value: '已通过，可以重新绑定新的验证器密钥',
                  )
                else ...[
                  if (mfaRecovery['status'] == 'REJECTED')
                    LText('上次申请未通过：${mfaRecovery['decisionReason'] ?? ''}'),
                  if (mfaRecoveryChallenge.isEmpty) ...[
                    AppTextField(
                      controller: mfaPassword,
                      label: clientLabel(context, '登录密码'),
                    ),
                    PrimaryAction(
                      label: clientLabel(context, '发送恢复验证码'),
                      icon: Icons.mark_email_read_outlined,
                      onPressed: actionsBlocked || !mfaEnabled
                          ? null
                          : () => _run(
                              () async {
                                final challenge = await state.api
                                    .issueMfaRecoveryChallenge(
                                      mfaPassword.text,
                                    );
                                if (operationCurrent) {
                                  setState(
                                    () => mfaRecoveryChallenge = challenge,
                                  );
                                }
                              },
                              '验证码已发送到 ${mfaRecoveryChallenge['destination'] ?? '已绑定联系方式'}',
                            ),
                    ),
                  ] else ...[
                    LText(
                      '验证码发送至 ${mfaRecoveryChallenge['destination'] ?? ''}',
                    ),
                    AppTextField(
                      controller: mfaRecoveryCode,
                      label: clientLabel(context, '恢复验证码'),
                    ),
                    AppTextField(
                      controller: mfaRecoveryReason,
                      label: clientLabel(context, '丢失原因（至少 8 个字符）'),
                    ),
                    PrimaryAction(
                      label: clientLabel(context, '提交人工审核'),
                      icon: Icons.support_agent,
                      onPressed: actionsBlocked
                          ? null
                          : () => _run(() async {
                              final id = int.tryParse(
                                '${mfaRecoveryChallenge['challengeId']}',
                              );
                              if (id == null) {
                                throw StateError('恢复验证码已失效，请重新申请');
                              }
                              final request = await state.api.submitMfaRecovery(
                                challengeId: id,
                                currentPassword: mfaPassword.text,
                                code: mfaRecoveryCode.text.trim(),
                                reason: mfaRecoveryReason.text.trim(),
                              );
                              if (operationCurrent) {
                                setState(() {
                                  mfaRecovery = request;
                                  mfaRecoveryChallenge = const {};
                                  mfaRecoveryCode.clear();
                                  mfaRecoveryReason.clear();
                                });
                              }
                            }, '已提交，请等待人工审核'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () =>
                                setState(() => mfaRecoveryChallenge = const {}),
                      child: const LText('取消'),
                    ),
                  ],
                ],
              ] else if (mfaEnabled) ...[
                SectionTitle(title: clientLabel(context, '丢失谷歌验证码')),
                const LText('快捷登录账户丢失验证器时，请联系平台支持申请恢复。'),
              ],
              SectionTitle(title: clientLabel(context, '敏感场景')),
              ...scenes.map((scene) {
                final enabled = scene['enabled'] == true;
                final code = asString(scene['sceneCode']);
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(asString(scene['label'], fallback: code)),
                  subtitle: Text(code),
                  value: enabled,
                  onChanged: actionsBlocked
                      ? null
                      : (next) => _run(() async {
                          await _updateSecurityScene(state, code, next);
                        }, '安全场景已更新'),
                );
              }),
              SectionTitle(title: clientLabel(context, '安全设置验证')),
              LText(
                '修改敏感场景前需要邮箱验证码，绑定 2FA 后还需动态验证码。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              AppTextField(
                controller: securityEmailCode,
                label: clientLabel(context, '安全设置邮箱验证码'),
              ),
              if (primaryAuthentication?.passwordRequired == true) ...[
                SectionTitle(title: clientLabel(context, '修改密码')),
                LText(
                  '修改密码后，其他设备的登录会话会失效。若开启修改密码场景，请先发送邮箱验证码。',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 8),
                AppTextField(
                  controller: currentPassword,
                  label: clientLabel(context, '当前密码'),
                  obscure: true,
                ),
                AppTextField(
                  controller: newPassword,
                  label: clientLabel(context, '新密码（至少 8 位）'),
                  obscure: true,
                ),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: changePasswordEmailCode,
                        label: clientLabel(context, '邮箱验证码'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppTextField(
                        controller: changePasswordTotpCode,
                        label: clientLabel(context, '2FA 验证码'),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: actionsBlocked
                            ? null
                            : () => _run(
                                () => state.api.issueSecurityChallenge(
                                  'CHANGE_PASSWORD',
                                ),
                                '验证码已发送到邮箱',
                              ),
                        icon: const Icon(Icons.email_outlined),
                        label: const LText('发送验证码'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PrimaryAction(
                        label: clientLabel(context, '确认修改'),
                        icon: Icons.password,
                        onPressed: actionsBlocked
                            ? null
                            : () => _run(
                                () => _changePassword(state),
                                '密码已修改，请重新登录其他设备',
                              ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
            SectionTitle(
              title: clientLabel(
                context,
                '身份认证 KYC · ${kycLoaded ? kycStatusLabel(kyc) : '状态未获取'}',
              ),
            ),
            LText(
              '提币前请完成身份认证。请提供清晰、真实且在有效期内的材料。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              onPressed: busy || loading
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => KycDocumentsPage(state: state),
                      ),
                    ),
              icon: const Icon(Icons.folder_outlined),
              label: const LText('查看认证材料'),
            ),
            if (kyc['country'] != null)
              InfoLine(
                label: clientLabel(context, '国家 / 地区'),
                value: asString(kyc['country']),
              ),
            if (kyc['kycLevel'] != null)
              InfoLine(
                label: clientLabel(context, '认证等级'),
                value:
                    const {
                      'NONE': '未认证',
                      'BASIC': '基础认证',
                      'STANDARD': '标准认证',
                      'ENHANCED': '增强认证',
                      'INSTITUTIONAL': '机构认证',
                    }[kyc['kycLevel']] ??
                    '暂不可用',
              ),
            if (kyc['expiresAt'] != null)
              InfoLine(
                label: kyc['status'] == 'VERIFIED' ? '认证有效期至' : '证件有效期至',
                value: '${kyc['expiresAt']}',
              ),
            if (kyc['rejectionReason'] != null)
              LText('审核说明：${asString(kyc['rejectionReason'])}'),
            if (!widget.kycOnly)
              TextButton.icon(
                onPressed: busy || loading
                    ? null
                    : () => _run(_load, '认证状态已更新'),
                icon: const Icon(Icons.refresh),
                label: const LText('刷新认证状态'),
              ),
            if (kycExpired(kyc) ||
                (!['PENDING', 'VERIFIED'].contains(kyc['status']) &&
                    (kyc.isEmpty || kycStatuses.contains(kyc['status']))))
              PrimaryAction(
                label: kycExpired(kyc)
                    ? '重新认证'
                    : kyc['status'] == 'REJECTED'
                    ? '补正并重新提交'
                    : '填写认证资料',
                icon: Icons.badge_outlined,
                onPressed:
                    busy || loading || !kycLoaded || kycProviderInfo.isEmpty
                    ? null
                    : () => _run(
                        () async {
                          final next = await Navigator.of(context)
                              .push<Map<String, dynamic>>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      KycApplicationPage(state: state),
                                ),
                              );
                          if (next == null || !operationCurrent) {
                            if (operationCurrent) {
                              setState(() => notice = '已返回认证页面');
                            }
                            return;
                          }
                          final profile = asMap(next['profile']);
                          setState(() {
                            kyc = profile;
                            kycVerificationSession = asMap(
                              next['verificationSession'],
                            );
                            _applyKyc(profile);
                          });
                        },
                        kycSimulationEnabled
                            ? '已提交模拟认证，请选择核验结果'
                            : kycProvider == 'SELF'
                            ? '材料已提交，请等待人工审核'
                            : '认证已提交，请继续核验',
                      ),
              ),
            if (kyc['status'] == 'PENDING' &&
                kycProvider != 'SELF' &&
                kycVerificationSession.isEmpty)
              PrimaryAction(
                label: clientText(
                  state.language,
                  '继续认证',
                  'Continue verification',
                ),
                icon: Icons.play_arrow,
                onPressed: kycActionsBlocked
                    ? null
                    : () => _run(() async {
                        final next = kycSimulationEnabled
                            ? <String, dynamic>{'simulation': true}
                            : await state.api.refreshKycSession();
                        if (!operationCurrent) return;
                        setState(() => kycVerificationSession = next);
                        if (!kycSimulationEnabled) {
                          await _launchKycProvider(state);
                        }
                      }, '认证会话已恢复'),
              ),
            if (kycSimulationEnabled && kycVerificationSession.isNotEmpty) ...[
              const SizedBox(height: 8),
              LText(
                clientText(
                  state.language,
                  '模拟模式：未调用第三方服务，可选择结果验证完整状态流转。',
                  'Simulation mode: no provider is called. Choose an outcome to test the complete status flow.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: kycActionsBlocked
                        ? null
                        : () => _run(
                            () => _completeKycSimulation(state, 'APPROVED'),
                            '模拟核验通过',
                          ),
                    child: LText(
                      clientText(state.language, '模拟自动通过', 'Simulate approval'),
                    ),
                  ),
                  TextButton(
                    onPressed: kycActionsBlocked
                        ? null
                        : () => _run(
                            () =>
                                _completeKycSimulation(state, 'MANUAL_REVIEW'),
                            '已转人工复核',
                          ),
                    child: LText(
                      clientText(
                        state.language,
                        '模拟人工复核',
                        'Simulate manual review',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: kycActionsBlocked
                        ? null
                        : () => _run(
                            () => _completeKycSimulation(state, 'REJECTED'),
                            '模拟核验拒绝',
                          ),
                    child: LText(
                      clientText(state.language, '模拟拒绝', 'Simulate rejection'),
                    ),
                  ),
                ],
              ),
            ],
            if (!kycSimulationEnabled &&
                kyc['status'] == 'PENDING' &&
                kycProvider != 'SELF' &&
                kycVerificationSession.isNotEmpty) ...[
              const SizedBox(height: 8),
              PrimaryAction(
                label: kycProvider == 'SUMSUB'
                    ? clientText(
                        state.language,
                        '打开 Sumsub 证件与人脸核验',
                        'Open Sumsub identity and face verification',
                      )
                    : clientText(
                        state.language,
                        '打开 Veriff 证件与人脸核验',
                        'Open Veriff identity and face verification',
                      ),
                icon: Icons.open_in_new,
                onPressed: kycActionsBlocked
                    ? null
                    : () => _run(() => _launchKycProvider(state), '已返回核验服务'),
              ),
            ],
            if (!widget.kycOnly) ...[
              const SectionTitle(title: 'API Key'),
              if (apiSecret != null)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const LText('Secret 仅显示这一次，请妥善保存'),
                      SelectableText(
                        apiSecret!,
                        key: const ValueKey('api-secret'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => apiSecret = null),
                        child: const LText('我已保存'),
                      ),
                    ],
                  ),
                ),
              AppTextField(
                controller: apiLabel,
                label: clientLabel(context, '名称'),
              ),
              AppTextField(
                controller: apiAllowlist,
                label: clientLabel(context, 'IP 白名单（多个地址以逗号分隔）'),
              ),
              const LText('默认只有读取权限。交易或提币权限必须设置 IP 白名单。'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LText('允许交易'),
                value: apiTradeEnabled,
                onChanged: actionsBlocked
                    ? null
                    : (v) => setState(() => apiTradeEnabled = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LText('允许提币'),
                subtitle: const LText('仅在确有自动化提币需求时开启，并妥善保管 Secret'),
                value: apiWithdrawEnabled,
                onChanged: actionsBlocked
                    ? null
                    : (enabled) => setState(() => apiWithdrawEnabled = enabled),
              ),
              AppTextField(
                controller: emailCode,
                label: clientLabel(context, '邮箱验证码'),
              ),
              AppTextField(
                controller: apiTotp,
                label: clientLabel(context, '2FA 验证码'),
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: actionsBlocked
                          ? null
                          : () => _run(() async {
                              await state.api.issueSecurityChallenge(
                                'SECURITY_SETTINGS',
                              );
                            }, '验证码已发送'),
                      child: const LText('发送邮箱验证码'),
                    ),
                  ),
                  Expanded(
                    child: PrimaryAction(
                      label: clientLabel(context, '创建 API Key'),
                      icon: Icons.key,
                      onPressed: actionsBlocked || apiSecret != null
                          ? null
                          : () => _run(() async {
                              if ((apiTradeEnabled || apiWithdrawEnabled) &&
                                  _apiAllowlist().isEmpty) {
                                throw const FormatException(
                                  '交易或提币权限必须设置 IP 白名单',
                                );
                              }
                              final created = await state.api.createApiKey(
                                label: apiLabel.text.trim(),
                                permissions: [
                                  'READ',
                                  if (apiTradeEnabled) 'TRADE',
                                  if (apiWithdrawEnabled) 'WITHDRAW',
                                ],
                                ipAllowlist: _apiAllowlist(),
                                emailCode: emailCode.text.trim(),
                                totpCode: apiTotp.text.trim(),
                              );
                              if (operationCurrent) {
                                setState(() {
                                  keys = [...keys, asMap(created['apiKey'])];
                                  apiSecret = asString(created['secret']);
                                  apiTradeEnabled = false;
                                  apiAllowlist.clear();
                                  apiLabel.clear();
                                  emailCode.clear();
                                  apiTotp.clear();
                                  apiWithdrawEnabled = false;
                                });
                              }
                            }, 'API Key 已创建，请保存 Secret'),
                    ),
                  ),
                ],
              ),
              ...keys.map(
                (apiKey) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(asString(apiKey['label'], fallback: 'API Key')),
                  subtitle: Text(
                    '${asString(apiKey['apiKey'])} · ${asString(apiKey['permissions'])}',
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled:
                        !actionsBlocked &&
                        asString(apiKey['status']) == 'ACTIVE',
                    onSelected: (action) => _run(() async {
                      final key = asString(apiKey['apiKey']);
                      if (key.isEmpty) {
                        throw const FormatException('密钥信息暂不可用，请刷新');
                      }
                      if (action == 'edit') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialog) => ApiKeyEditDialog(
                            apiKey: apiKey,
                            mfaRequired: mfaEnabled,
                            onSendCode: () async {
                              if (!operationCurrent) {
                                throw const FormatException('登录状态已变化，请重新打开');
                              }
                              await state.api.issueSecurityChallenge(
                                'SECURITY_SETTINGS',
                              );
                            },
                            onSave: (settings) async {
                              if (!operationCurrent) {
                                throw const FormatException('登录状态已变化，请重新打开');
                              }
                              await state.api.updateApiKey(
                                apiKey: key,
                                label: settings.label,
                                permissions: settings.permissions,
                                ipAllowlist: settings.ipAllowlist,
                                emailCode: settings.emailCode,
                                totpCode: settings.totpCode,
                              );
                            },
                          ),
                        );
                        if (confirmed != true || !operationCurrent) {
                          _operationCancelled = true;
                          return;
                        }
                      } else {
                        if (!await _confirmSecurity(
                              '撤销 API 密钥？',
                              '使用该密钥的应用将无法继续访问。',
                            ) ||
                            !operationCurrent) {
                          return;
                        }
                        await state.api.revokeApiKey(
                          apiKey: key,
                          emailCode: emailCode.text.trim(),
                          totpCode: apiTotp.text.trim(),
                        );
                      }
                      if (operationCurrent) await _load();
                    }, action == 'edit' ? 'API Key 设置已更新' : 'API Key 已撤销'),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: LText('编辑名称、权限与 IP')),
                      PopupMenuItem(value: 'revoke', child: LText('撤销')),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void showSecuritySheet(BuildContext context, {bool kycOnly = false}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AppScope(
      notifier: AppScope.of(context),
      child: SecuritySheet(kycOnly: kycOnly),
    ),
  );
}
