import '../i18n/client_messages.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../affiliate/affiliate_page.dart';
import '../app_state.dart';
import '../auth/auth_sheet.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';
import '../ui/theme_picker.dart';
import '../ui/language_picker.dart';
import 'security_sheet.dart';
import '../legal/legal_pages.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        PageHeader(
          title: clientLabel(context, '账户'),
          subtitle: state.isLoggedIn
              ? state.session!.user.name
              : clientLabel(context, '未登录'),
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
                      state.isLoggedIn
                          ? state.session!.user.name
                          : clientLabel(context, '游客'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    LText(
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
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 120),
                  child: FilledButton(
                    onPressed: () => showAuthSheet(context),
                    child: const LText('登录'),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              Material(
                color: Colors.transparent,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LText('主题'),
                  subtitle: LText(state.clientTheme.label),
                  trailing: const Icon(Icons.palette_outlined),
                  onTap: () => showClientThemePicker(context),
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const LText('语言 / Language'),
                subtitle: const LText('应用界面语言'),
                trailing: Semantics(
                  identifier: 'client.language.select',
                  child: SizedBox(
                    width: 120,
                    child: TextButton(
                      onPressed: () => showClientLanguagePicker(context),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              state.language.label,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const Icon(Icons.expand_more),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Panel(
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.policy_outlined),
              title: LText(
                clientText(state.language, '协议与隐私', 'Legal and privacy'),
              ),
              subtitle: LText(
                clientText(
                  state.language,
                  '用户协议、隐私政策及风险披露',
                  'Agreements, privacy and risk disclosures',
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const LegalCenterPage(),
                ),
              ),
            ),
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
                title: const LText('邀请返佣'),
                subtitle: const LText('邀请好友、团队贡献与返佣结算'),
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
                title: const LText('安全中心'),
                subtitle: const LText('邮箱与手机绑定、密码、2FA、设备和 API 密钥'),
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
                title: LText(
                  clientText(state.language, '身份认证', 'Identity verification'),
                ),
                subtitle: LText(
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
              leading: Icon(
                Icons.fingerprint,
                color: ClientColors.warningFor(context),
              ),
              title: LText(
                state.biometricLoginEnabled ? '生物识别登录已启用' : '启用生物识别登录',
              ),
              subtitle: LText(
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
                      child: LText(
                        state.biometricLoginUpdating ? '处理中…' : '关闭',
                      ),
                    )
                  : FilledButton.tonal(
                      onPressed:
                          state.biometricLoginAvailable &&
                              !state.biometricLoginUpdating
                          ? () => unawaited(state.enableBiometricLogin())
                          : null,
                      child: LText(
                        state.biometricLoginUpdating ? '处理中…' : '启用',
                      ),
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
        title: const LText('关闭生物识别登录？'),
        content: const LText('关闭后，下次打开 App 将直接使用已保存的登录会话，不再要求面容或指纹解锁。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const LText('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const LText('确认关闭'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.disableBiometricLogin();
  }
}
