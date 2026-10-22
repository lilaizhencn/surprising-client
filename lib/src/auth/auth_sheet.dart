import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../models.dart';
import '../telegram_login.dart';

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key});
  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  final codes = <String, String>{};
  String mode = 'login';
  bool phone = false;
  bool busy = false;
  bool showPassword = false;
  String? message;
  bool telegramEnabled = false;
  bool telegramBusy = false;
  int telegramAttempt = 0;
  bool checkedTelegram = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (checkedTelegram) return;
    checkedTelegram = true;
    final api = AppScope.of(context).api;
    unawaited(
      api
          .get('/api/v1/auth/telegram/config')
          .then((config) {
            if (mounted) {
              setState(() => telegramEnabled = config['enabled'] == true);
            }
          })
          .catchError((Object _) {}),
    );
  }

  Future<void> telegramLogin(AppState state) async {
    if (busy) return;
    final attempt = ++telegramAttempt;
    final initialSession = state.session;
    setState(() {
      busy = true;
      telegramBusy = true;
      message = null;
    });
    await state.loginTelegram(
      () => signInWithTelegram(
        api: state.api,
        store: state.telegramLoginStore,
        openBrowser: (url) =>
            launchUrl(url, mode: LaunchMode.externalApplication),
        cancelled: () =>
            !mounted ||
            telegramAttempt != attempt ||
            state.session != initialSession,
      ),
    );
    if (!mounted || telegramAttempt != attempt) return;
    setState(() {
      busy = false;
      telegramBusy = false;
      message = state.lastError;
      password.clear();
    });
    if (state.isLoggedIn) Navigator.pop(context);
  }

  @override
  void dispose() {
    ++telegramAttempt;
    identifier.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit(AppState state) async {
    if (busy) return;
    final challenge = state.pendingLoginChallenge;
    final needsPassword =
        ['login', 'register', 'reset'].contains(mode) && challenge == null;
    if (challenge == null &&
            mode != 'verify' &&
            identifier.text.trim().isEmpty ||
        needsPassword && password.text.isEmpty ||
        ['verify', 'reset'].contains(mode) && code.text.trim().isEmpty) {
      setState(() => message = '请填写所有必填信息');
      return;
    }
    if (challenge != null &&
        (challenge.expired ||
            challenge.methods.any(
              (m) => !RegExp(
                r'^\d{6}$',
              ).hasMatch(codes[asString(m['type'])] ?? ''),
            ))) {
      setState(
        () => message = challenge.expired ? '验证已过期，请返回登录' : '请输入全部六位验证码',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    var close = false;
    var clearCredentials = false;
    var next = mode;
    if (challenge != null) {
      await state.verifyLogin({
        for (final entry in codes.entries)
          switch (entry.key) {
            'EMAIL' => 'emailCode',
            'PHONE' => 'phoneCode',
            _ => 'totpCode',
          }: entry.value,
      });
      if (state.pendingVerificationSession != null) next = 'verify';
      close = state.isLoggedIn;
    } else if (mode == 'forgot') {
      if (await state.requestPasswordReset(identifier.text)) next = 'reset';
    } else if (mode == 'reset') {
      if (await state.resetPassword(
        identifier: identifier.text,
        code: code.text,
        newPassword: password.text,
      )) {
        next = 'login';
        clearCredentials = true;
      }
    } else if (mode == 'verify') {
      close = await state.verifyPendingEmail(code.text);
    } else {
      if (mode == 'register') {
        await state.register(identifier.text, password.text, phone: phone);
      } else {
        await state.login(identifier.text, password.text);
      }
      if (state.pendingVerificationSession != null) next = 'verify';
      if (state.pendingLoginChallenge != null) clearCredentials = true;
      close = state.isLoggedIn;
    }
    if (!mounted) return;
    if (clearCredentials) {
      password.clear();
      code.clear();
    }
    setState(() {
      busy = false;
      mode = next;
      message = state.lastError ?? state.lastNotice;
    });
    if (close) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final challenge = state.pendingLoginChallenge;
    final title = challenge != null
        ? '安全验证'
        : switch (mode) {
            'register' => '注册账户',
            'forgot' => '找回密码',
            'reset' => '设置新密码',
            'verify' => '验证邮箱',
            _ => '登录账户',
          };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Surprising',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            if (challenge != null) ...[
              const Text('输入所有要求的验证码以完成登录'),
              for (final method in challenge.methods)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (v) => codes[asString(method['type'])] = v,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: switch (method['type']) {
                        'EMAIL' => '邮箱验证码',
                        'PHONE' => '短信验证码',
                        _ => '身份验证器验证码',
                      },
                      helperText: nullableString(method['destination']),
                    ),
                  ),
                ),
            ] else ...[
              if (mode == 'register') ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('邮箱')),
                    ButtonSegment(value: true, label: Text('手机号')),
                  ],
                  selected: {phone},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() => phone = v.first),
                ),
                const SizedBox(height: 16),
              ],
              if (mode != 'verify')
                TextField(
                  controller: identifier,
                  enabled: !busy,
                  keyboardType: mode == 'register' && phone
                      ? TextInputType.phone
                      : TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: mode == 'login'
                        ? '邮箱或手机号'
                        : phone && mode == 'register'
                        ? '国际手机号'
                        : '邮箱',
                  ),
                ),
              if (['login', 'register', 'reset'].contains(mode)) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: !showPassword,
                  autofillHints: [
                    mode == 'login'
                        ? AutofillHints.password
                        : AutofillHints.newPassword,
                  ],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: mode == 'reset' ? '新密码' : '密码',
                    suffixIcon: IconButton(
                      tooltip: showPassword ? '隐藏密码' : '显示密码',
                      onPressed: () =>
                          setState(() => showPassword = !showPassword),
                      icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => submit(state),
                ),
              ],
              if (['verify', 'reset'].contains(mode)) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: code,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '邮箱验证码',
                  ),
                ),
              ],
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!, key: const ValueKey('auth-message')),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : () => submit(state),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  busy
                      ? '处理中…'
                      : challenge != null
                      ? '确认验证'
                      : switch (mode) {
                          'forgot' => '发送验证码',
                          'reset' => '更新密码',
                          'verify' => '完成邮箱验证',
                          'register' => '创建账户',
                          _ => '登录',
                        },
                ),
              ),
            ),
            if (challenge == null && ['login', 'register'].contains(mode)) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: telegramBusy
                    ? () => setState(() {
                        ++telegramAttempt;
                        telegramBusy = false;
                        busy = false;
                      })
                    : !busy && telegramEnabled
                    ? () => telegramLogin(state)
                    : null,
                icon: const Icon(Icons.send_outlined),
                label: Text(telegramBusy ? '取消 Telegram 登录' : '通过 Telegram 继续'),
              ),
            ],
            if (mode == 'verify')
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        await state.resendPendingEmail();
                        if (mounted) {
                          setState(() {
                            busy = false;
                            message = state.lastError ?? state.lastNotice;
                          });
                        }
                      },
                child: const Text('重新发送验证码'),
              ),
            if (mode == 'login' && challenge == null) ...[
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        mode = 'forgot';
                        message = null;
                        password.clear();
                      }),
                child: const Text('忘记密码？'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        mode = 'register';
                        message = null;
                      }),
                child: const Text('没有账户，去注册'),
              ),
              if (state.pendingBiometricSession != null)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          final ok = await state.unlockBiometricSession();
                          if (!context.mounted) return;
                          setState(() {
                            busy = false;
                            message =
                                state.biometricUnlockError ?? state.lastError;
                          });
                          if (ok) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('使用生物识别登录'),
                ),
            ] else
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        state.pendingLoginChallenge = null;
                        mode = 'login';
                        codes.clear();
                        code.clear();
                        password.clear();
                        message = null;
                      }),
                child: const Text('返回登录'),
              ),
          ],
        ),
      ),
    );
  }
}

void showAuthSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        AppScope(notifier: AppScope.of(context), child: const AuthSheet()),
  );
}
