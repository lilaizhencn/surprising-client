import 'dart:async';
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../exchange_widgets.dart';
import '../ui/client_colors.dart';
import '../ui/client_components.dart';
import 'wallet_components.dart';

class WithdrawalPage extends StatefulWidget {
  const WithdrawalPage({this.initialSymbol, this.initialChain, super.key});
  final String? initialSymbol, initialChain;

  @override
  State<WithdrawalPage> createState() => _WithdrawalPageState();
}

class _WithdrawalPageState extends State<WithdrawalPage> {
  final addressController = TextEditingController();
  final amountController = TextEditingController();
  final emailCodeController = TextEditingController();
  final totpCodeController = TextEditingController();
  String? selectedSymbol;
  String? selectedChain;
  String? localError;
  int? owner;
  bool ownerCaptured = false;

  @override
  void initState() {
    super.initState();
    selectedSymbol = widget.initialSymbol;
    selectedChain = widget.initialChain;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!ownerCaptured) {
      ownerCaptured = true;
      owner = AppScope.of(context).userId;
    }
  }

  Widget _unavailable(AppState state, String message) => Scaffold(
    backgroundColor: exchangeBackground(context),
    appBar: AppBar(title: const Text('提币')),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            TextButton(
              onPressed: () => unawaited(state.refreshWallet()),
              child: const Text('刷新资产'),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    addressController.dispose();
    amountController.dispose();
    emailCodeController.dispose();
    totpCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isLoggedIn || owner != state.userId) {
      return _unavailable(state, '账户已变化，请重新打开提币');
    }
    if (!state.walletReady) {
      return _unavailable(state, state.walletError ?? '可提币余额暂不可用，请刷新');
    }
    if (!state.withdrawalRulesReady) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              const RechargeHeader(title: '提币'),
              const SizedBox(height: 40),
              const EmptyState(text: '提币规则暂不可用，请刷新后重试'),
              const SizedBox(height: 16),
              PrimaryAction(
                label: state.withdrawalRulesLoading ? '刷新中…' : '刷新提币规则',
                icon: Icons.refresh,
                onPressed: state.withdrawalRulesLoading
                    ? null
                    : () => unawaited(state.refreshWithdrawalRules()),
              ),
            ],
          ),
        ),
      );
    }
    final assets = state.walletPortfolio.assets
        .where((item) => item.symbol.trim().isNotEmpty)
        .toList();
    if (assets.isEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              const RechargeHeader(title: '提币'),
              const SizedBox(height: 40),
              const EmptyState(text: '暂无可提币资产，请先刷新资金账户'),
              const SizedBox(height: 16),
              PrimaryAction(
                label: state.loadingPrivate ? '刷新中…' : '刷新资产',
                icon: Icons.refresh,
                onPressed: state.loadingPrivate
                    ? null
                    : () => unawaited(state.refreshWallet()),
              ),
            ],
          ),
        ),
      );
    }

    final symbolValues = assets.map((item) => item.symbol).toList();
    if (selectedSymbol != null && !symbolValues.contains(selectedSymbol)) {
      return _unavailable(state, '所选币种已不可用，请返回重新选择');
    }
    final symbol = symbolValues.contains(selectedSymbol)
        ? selectedSymbol!
        : symbolValues.first;
    final asset = assets.firstWhere((item) => item.symbol == symbol);
    final chainAssets = state.withdrawalRules
        .where((rule) => rule.symbol == symbol && rule.withdrawalEnabled)
        .toList();
    final chainValues = chainAssets.map((item) => item.chain).toList();
    if (selectedChain != null && !chainValues.contains(selectedChain)) {
      return _unavailable(state, '所选网络已不可用，请返回重新选择');
    }
    final chain = chainValues.contains(selectedChain)
        ? selectedChain!
        : chainValues.isEmpty
        ? ''
        : chainValues.first;
    final rule = state.withdrawalRuleFor(chain, symbol);
    final locked = state.withdrawalSubmitting || state.withdrawalOutcomeLocked;
    final minimum = rule?.minimumAmount;
    final previewReceived = rule?.receivedAmount(amountController.text.trim());

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            RechargeHeader(
              title: '提币',
              trailing: IconButton(
                tooltip: '刷新提币规则',
                onPressed: state.withdrawalRulesLoading
                    ? null
                    : () => unawaited(state.refreshWithdrawalRules()),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                ),
                icon: state.withdrawalRulesLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 26),
              ),
            ),
            const SizedBox(height: 18),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.initialSymbol != null)
                    Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: CoinIcon(symbol),
                        title: Text(symbol),
                        subtitle: Text(
                          state.withdrawalRuleFor(chain, symbol)?.network ??
                              chain,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: locked
                            ? null
                            : () => Navigator.maybePop(context),
                      ),
                    )
                  else ...[
                    const SectionTitle(title: '资产与网络'),
                    Row(
                      children: [
                        Expanded(
                          child: SmallDropdown(
                            value: symbol,
                            values: symbolValues,
                            enabled: !locked,
                            onChanged: (next) => setState(() {
                              selectedSymbol = next;
                              selectedChain = null;
                              addressController.clear();
                              amountController.clear();
                              emailCodeController.clear();
                              totpCodeController.clear();
                              localError = null;
                            }),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: chainValues.isEmpty
                              ? Text(
                                  '无可用网络',
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : SmallDropdown(
                                  value: chain,
                                  values: chainValues,
                                  enabled: !locked,
                                  labelBuilder: (value) {
                                    final selected = chainAssets.firstWhere(
                                      (item) => item.chain == value,
                                    );
                                    return selected.network.isEmpty
                                        ? value
                                        : '$value · ${selected.network}';
                                  },
                                  onChanged: (next) => setState(() {
                                    selectedChain = next;
                                    addressController.clear();
                                    amountController.clear();
                                    localError = null;
                                  }),
                                ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  InfoLine(
                    label: '可用余额',
                    value: chain.isEmpty
                        ? '--'
                        : '${asset.availableAmount ?? '—'} $symbol',
                  ),
                  if (minimum != null)
                    InfoLine(
                      label: rule?.configuredMinimum == null
                          ? '最小单位'
                          : '最低提币数量',
                      value: '$minimum $symbol',
                    ),
                  if (rule?.decimals != null)
                    InfoLine(label: '数量精度', value: '${rule!.decimals} 位小数'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(title: '接收信息'),
                  TextField(
                    controller: addressController,
                    enabled: !locked,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.text,
                    onChanged: (_) => setState(() => localError = null),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: '提币地址',
                      hintText: '请粘贴并逐字核对接收地址',
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: amountController,
                          label: '提币数量',
                          enabled: !locked,
                          onChanged: (_) => setState(() => localError = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: locked || chain.isEmpty
                            ? null
                            : () => setState(() {
                                amountController.text =
                                    state.withdrawalMaximum(chain, symbol) ??
                                    '';
                                localError = null;
                              }),
                        child: const Text('全部'),
                      ),
                    ],
                  ),
                  if (rule?.feeAmount != null)
                    InfoLine(label: '手续费', value: '${rule!.feeAmount} $symbol'),
                  if (previewReceived != null &&
                      !previewReceived.startsWith('-'))
                    InfoLine(label: '预计到账', value: '$previewReceived $symbol'),
                  const SizedBox(height: 8),
                  Text(
                    '请确认网络与收款地址一致，转出后无法撤回。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (state.withdrawalVerificationRequired) ...[
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionTitle(title: '安全验证'),
                    AppTextField(
                      controller: emailCodeController,
                      label: '邮箱验证码',
                      enabled: !locked,
                    ),
                    if (state.withdrawalTotpRequired) ...[
                      const SizedBox(height: 8),
                      AppTextField(
                        controller: totpCodeController,
                        label: '验证器动态码',
                        enabled: !locked,
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: state.withdrawalSubmitting
                            ? null
                            : () =>
                                  unawaited(state.requestWithdrawalChallenge()),
                        child: const Text('重新发送邮箱验证码'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (localError != null) ...[
              const SizedBox(height: 10),
              Text(
                localError!,
                key: const ValueKey('withdrawal-local-error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            if (state.withdrawalConfirmation != null) ...[
              const SizedBox(height: 12),
              WithdrawalConfirmationPanel(
                confirmation: state.withdrawalConfirmation!,
              ),
            ],
            const SizedBox(height: 14),
            PrimaryAction(
              label: state.withdrawalSubmitting
                  ? '提交中…'
                  : state.withdrawalOutcomeUnknown
                  ? '结果待核对'
                  : state.withdrawalOutcomeLocked
                  ? '提币已受理'
                  : '核对并确认提币',
              icon: Icons.verified_user_outlined,
              onPressed: locked || chain.isEmpty
                  ? null
                  : () =>
                        unawaited(_reviewAndSubmit(state, symbol, chain, rule)),
            ),
            if (state.withdrawalOutcomeUnknown) ...[
              const SizedBox(height: 10),
              const Text(
                '本次请求可能已到达钱包服务。为避免重复扣款，当前提币意图已锁定，请先核对提币记录。',
                style: TextStyle(
                  color: ClientColors.warning,
                  fontSize: 11,
                  height: 1.45,
                ),
              ),
            ] else if (state.withdrawalOutcomeLocked) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => unawaited(_startAnotherWithdrawal(state)),
                  child: const Text('发起另一笔提币'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reviewAndSubmit(
    AppState state,
    String symbol,
    String chain,
    WithdrawalAssetRule? rule,
  ) async {
    final error = state.validateWithdrawal(
      chain: chain,
      symbol: symbol,
      toAddress: addressController.text,
      amount: amountController.text,
    );
    if (error != null) {
      setState(() => localError = error);
      return;
    }
    if (state.withdrawalVerificationRequired &&
        emailCodeController.text.trim().length != 6) {
      setState(() => localError = '请输入 6 位邮箱验证码');
      return;
    }
    if (state.withdrawalTotpRequired &&
        totpCodeController.text.trim().length != 6) {
      setState(() => localError = '请输入 6 位验证器动态码');
      return;
    }
    final amount = amountController.text.trim();
    final fee = rule?.feeAmount;
    final received = rule?.receivedAmount(amount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认提币信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoLine(
              label: '网络',
              value: rule?.network.isNotEmpty == true
                  ? '$chain · ${rule!.network}'
                  : chain,
            ),
            InfoLine(label: '地址', value: addressController.text.trim()),
            InfoLine(label: '数量', value: '$amount $symbol'),
            if (fee != null) InfoLine(label: '手续费', value: '$fee $symbol'),
            if (received != null)
              InfoLine(label: '预计到账', value: '$received $symbol'),
            const SizedBox(height: 10),
            const Text(
              '请确认网络与接收地址完全一致。提交后不可撤销。',
              style: TextStyle(color: ClientColors.muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await state.withdrawWallet(
      chain: chain,
      symbol: symbol,
      toAddress: addressController.text,
      amount: amount,
      emailCode: emailCodeController.text,
      totpCode: totpCodeController.text,
    );
  }

  Future<void> _startAnotherWithdrawal(AppState state) async {
    await state.resetWithdrawalIntent();
    if (!mounted) return;
    setState(() {
      addressController.clear();
      amountController.clear();
      emailCodeController.clear();
      totpCodeController.clear();
      localError = null;
    });
  }
}

class WithdrawalConfirmationPanel extends StatelessWidget {
  const WithdrawalConfirmationPanel({required this.confirmation, super.key});

  final WithdrawalConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '提币确认摘要'),
          InfoLine(
            label: '网络',
            value: confirmation.network.isEmpty
                ? confirmation.chain
                : '${confirmation.chain} · ${confirmation.network}',
          ),
          InfoLine(label: '地址', value: confirmation.toAddress),
          InfoLine(
            label: '数量',
            value: '${confirmation.amount} ${confirmation.symbol}',
          ),
          if (confirmation.fee != null)
            InfoLine(
              label: '手续费',
              value: '${confirmation.fee} ${confirmation.symbol}',
            ),
          if (confirmation.receivedAmount != null)
            InfoLine(
              label: '到账数量',
              value: '${confirmation.receivedAmount} ${confirmation.symbol}',
            ),
          InfoLine(label: '状态', value: confirmation.status),
          if (confirmation.reference.isNotEmpty)
            InfoLine(label: '提币编号', value: confirmation.reference),
        ],
      ),
    );
  }
}
