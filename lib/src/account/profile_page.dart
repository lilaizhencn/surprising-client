import 'dart:async';
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../affiliate/affiliate_page.dart';
import '../app_state.dart';
import '../auth/auth_sheet.dart';
import '../models.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';
import 'security_sheet.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        PageHeader(
          title: '账户',
          subtitle: state.isLoggedIn ? state.session!.user.name : '未登录',
        ),
        Panel(
          child: Row(
            children: [
              const SparkleMark(size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isLoggedIn ? state.session!.user.name : '游客',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      state.isLoggedIn
                          ? 'UID ${state.userId} · ${state.session!.user.status}'
                          : '登录后同步订单、持仓和资产',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.isLoggedIn)
                IconButton.filledTonal(
                  onPressed: () async {
                    try {
                      await state.logout();
                    } catch (_) {
                      // Authentication owns the failure feedback and local lock.
                    }
                  },
                  icon: const Icon(Icons.logout),
                )
              else
                FilledButton(
                  onPressed: () => showAuthSheet(context),
                  child: const Text('登录'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('主题'),
                subtitle: const Text('切换交易终端的明暗外观'),
                trailing: DropdownButton<ClientTheme>(
                  value: state.clientTheme,
                  underline: const SizedBox.shrink(),
                  items: ClientTheme.values
                      .map(
                        (theme) => DropdownMenuItem(
                          value: theme,
                          child: Text(theme.label),
                        ),
                      )
                      .toList(),
                  onChanged: (next) {
                    if (next != null) state.selectTheme(next);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('语言 / Language'),
                subtitle: const Text('应用界面语言'),
                trailing: DropdownButton<ClientLanguage>(
                  value: state.language,
                  underline: const SizedBox.shrink(),
                  items: ClientLanguage.values
                      .map(
                        (language) => DropdownMenuItem(
                          value: language,
                          child: Text(language.label),
                        ),
                      )
                      .toList(),
                  onChanged: (next) {
                    if (next != null) state.selectLanguage(next);
                  },
                ),
              ),
            ],
          ),
        ),
        if (state.isLoggedIn) ...[
          const SizedBox(height: 12),
          Panel(
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.group_add_outlined),
                title: const Text('邀请与合作'),
                subtitle: const Text('邀请好友、团队贡献与返佣结算'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AffiliatePage(),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.security,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                title: const Text('安全中心'),
                subtitle: const Text('邮箱与手机绑定、密码、2FA、设备和 API 密钥'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showSecuritySheet(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  clientText(state.language, '身份认证', 'Identity verification'),
                ),
                subtitle: Text(
                  clientText(
                    state.language,
                    '提交认证资料与查看审核结果',
                    'Submit documents and review verification status',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showSecuritySheet(context, kycOnly: true),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(
                Icons.fingerprint,
                color: ClientColors.warning,
              ),
              title: Text(
                state.biometricLoginEnabled ? '生物识别登录已启用' : '启用生物识别登录',
              ),
              subtitle: Text(
                state.biometricLoginEnabled
                    ? '下次打开 App 使用面容或指纹解锁'
                    : state.biometricLoginAvailable
                    ? '只保存加密 refresh token，不保存 access token'
                    : '设备未检测到可用的生物识别能力',
              ),
              trailing: state.biometricLoginEnabled
                  ? OutlinedButton(
                      onPressed: state.biometricLoginUpdating
                          ? null
                          : () => unawaited(
                              _confirmDisableBiometric(context, state),
                            ),
                      child: Text(state.biometricLoginUpdating ? '处理中…' : '关闭'),
                    )
                  : FilledButton.tonal(
                      onPressed:
                          state.biometricLoginAvailable &&
                              !state.biometricLoginUpdating
                          ? () => unawaited(state.enableBiometricLogin())
                          : null,
                      child: Text(state.biometricLoginUpdating ? '处理中…' : '启用'),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _confirmDisableBiometric(
    BuildContext context,
    AppState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关闭生物识别登录？'),
        content: const Text('关闭后，下次打开 App 将直接使用已保存的登录会话，不再要求面容或指纹解锁。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认关闭'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.disableBiometricLogin();
  }
}
