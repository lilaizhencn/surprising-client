import 'package:material_ui/material_ui.dart';
import '../app_state.dart';
import '../models.dart';
import '../i18n/client_messages.dart';

Future<void> showAccountSwitchSheet(BuildContext context, AppState state) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AccountSwitchSheet(state: state),
    );

/// A small second-level list under the existing profile entry, not a login flow.
class AccountSwitchSheet extends StatefulWidget {
  const AccountSwitchSheet({super.key, required this.state});
  final AppState state;
  @override
  State<AccountSwitchSheet> createState() => _AccountSwitchSheetState();
}

class _AccountSwitchSheetState extends State<AccountSwitchSheet> {
  List<SubAccountModel>? accounts;
  String? error;
  bool busy = false;
  late final int? loginUserId;

  @override
  void initState() {
    super.initState();
    loginUserId = widget.state.loginUserId;
    _load();
  }

  Future<void> _load() async {
    if (loginUserId == null) return;
    try {
      final rows = await widget.state.api.loadSubAccounts(loginUserId!);
      if (!mounted || widget.state.loginUserId != loginUserId) return;
      if (rows.any(
        (row) => row.parentUserId != loginUserId || row.subUserId <= 0,
      )) {
        throw const FormatException('子账号列表不匹配');
      }
      setState(() {
        accounts = rows;
        error = null;
      });
    } catch (reason) {
      if (mounted) setState(() => error = '$reason');
    }
  }

  Future<void> _select(int id) async {
    if (busy || widget.state.loginUserId != loginUserId) return;
    if (widget.state.userId == id) return;
    setState(() {
      busy = true;
      error = null;
    });
    final ok = await widget.state.auth.switchOperatingAccount(id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        busy = false;
        error = widget.state.auth.lastError ?? '切换未完成，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.state.session;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .65,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const LText(
              '切换账户',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ListTile(
              title: const LText('主账号'),
              subtitle: Text(session?.user.name ?? ''),
              trailing: widget.state.userId == loginUserId
                  ? const Icon(Icons.check)
                  : null,
              enabled: !busy && session != null,
              onTap: () => _select(loginUserId!),
            ),
            for (final account in accounts ?? <SubAccountModel>[])
              ListTile(
                title: Text(account.subAccountName),
                subtitle: LText(
                  'UID ${account.subUserId} · ${account.status == 'FROZEN'
                      ? '已冻结（仅查看）'
                      : account.permissions == 'READONLY'
                      ? '只读'
                      : '子账号'}',
                ),
                trailing: widget.state.userId == account.subUserId
                    ? const Icon(Icons.check)
                    : null,
                enabled: !busy && session != null,
                onTap: () => _select(account.subUserId),
              ),
            if (busy || (accounts == null && error == null))
              const Center(child: CircularProgressIndicator()),
            if (error != null) ...[
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              TextButton(
                onPressed: busy ? null : _load,
                child: const LText('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
