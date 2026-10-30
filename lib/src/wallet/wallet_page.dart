import '../i18n/client_messages.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import '../account/security_sheet.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../asset_overview.dart';
import '../auth/auth_sheet.dart';
import '../deposit_page.dart';
import '../exchange_widgets.dart';
import '../funding_records_page.dart';
import '../sensitive_screen.dart';
import '../transfer_page.dart';
import '../ui/client_components.dart';
import '../ui/client_navigation.dart';
import '../withdrawal_selection_page.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Material(
      color: exchangeBackground(context),
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            state.refreshPrivateData(),
            state.refreshValuation(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            AssetOverview(
              state: state,
              onSecurity: () => showSecuritySheet(context),
              onDeposit: () => _openRechargeFlow(context, state),
              onWithdraw: () => _openWithdrawalFlow(context, state),
              onTools: () {
                if (!state.isLoggedIn) {
                  showAuthSheet(context);
                  return;
                }
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TransferPage()),
                );
              },
              onRecords: state.isLoggedIn
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => FundingRecordsPage(state: state),
                      ),
                    )
                  : null,
            ),
            if (!state.isLoggedIn) ...[
              const SizedBox(height: 24),
              PrimaryAction(
                label: clientLabel(context, '登录 / 注册'),
                icon: Icons.login,
                onPressed: () => showAuthSheet(context),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _openRechargeFlow(BuildContext context, AppState state) {
    if (!state.isLoggedIn) {
      showAuthSheet(context);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 16,
                ),
                leading: const Icon(Icons.south, size: 30),
                title: const LText(
                  '充币',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                subtitle: const LText('从链上钱包或交易所转入数字货币'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheet);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => MobileDepositPage(state: state),
                    ),
                  );
                },
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 16,
                ),
                leading: const Icon(Icons.handshake_outlined, size: 30),
                title: const LText(
                  'C2C 交易',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.pop(sheet);
                  ClientNavigation.maybeOf(context)?.openBuyCrypto();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openWithdrawalFlow(BuildContext context, AppState state) {
    if (!state.isLoggedIn) {
      showAuthSheet(context);
      return;
    }
    unawaited(() async {
      final identity = state.session?.accessToken;
      await state.refreshWithdrawalRules();
      if (!context.mounted ||
          identity != state.session?.accessToken ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              const SensitiveScreen(child: WithdrawalSelectionPage()),
        ),
      );
    }());
  }
}
