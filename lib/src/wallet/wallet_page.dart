import '../i18n/client_messages.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
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
import '../ui/client_navigation.dart';
import '../withdrawal_selection_page.dart';

class WalletPage extends StatelessWidget {
  const WalletPage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isLoggedIn) {
      return Material(
        color: exchangeBackground(context),
        child: Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF00D2FF),
                    Color(0xFF6366F1),
                    Color(0xFFEC4899),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  key: const ValueKey('wallet-guest-login-button'),
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => showAuthSheet(context),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 34,
                      vertical: 15,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.login, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        LText(
                          clientLabel(context, '登录 / 注册'),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
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
          padding: EdgeInsets.fromLTRB(
            16,
            12,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            AssetOverview(
              state: state,
              onSecurity: () => showSecuritySheet(context),
              onDeposit: () => _openRechargeFlow(context, state),
              onWithdraw: () => _openWithdrawalFlow(context, state),
              onTools: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const TransferPage()),
                );
              },
              onRecords: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => FundingRecordsPage(state: state),
                ),
              ),
            ),
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
