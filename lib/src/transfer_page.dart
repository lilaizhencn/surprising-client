import 'dart:async';
import 'package:flutter/material.dart';
import 'app.dart' show AppScope;
import 'app_state.dart';
import 'exchange_widgets.dart';
import 'funding_records_page.dart';
import 'models.dart';
import 'account_records.dart' show exactAmountUnits;

class TransferPage extends StatefulWidget {
  const TransferPage({super.key});
  @override
  State<TransferPage> createState() => _TransferPageState();
}

class _TransferPageState extends State<TransferPage> {
  final amount = TextEditingController(),
      email = TextEditingController(),
      totp = TextEditingController();
  String source = 'FUNDING', target = 'USDT_PERPETUAL', asset = 'USDT';
  Map<String, String> scales = {};
  int? owner;
  int generation = 0;
  bool started = false, loading = true;
  String? error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    if (!started || owner != state.userId) {
      started = true;
      owner = state.userId;
      amount.clear();
      email.clear();
      totp.clear();
      scales = {};
      unawaited(_load(state));
    }
  }

  Future<void> _load(AppState state) async {
    final identity = owner, version = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      if (!await state.restorePendingTransfers()) {
        throw StateError('无法读取划转恢复资料');
      }
      final result = await state.api.assetScales();
      if (!mounted || version != generation || identity != state.userId) return;
      setState(() {
        scales = result;
        if (!result.containsKey(asset)) asset = result.keys.firstOrNull ?? '';
        final pending = state.pendingTransfer;
        if (pending != null) {
          source = pending.source;
          target = pending.target;
          asset = pending.asset;
          amount.text = scaledAmount(
            BigInt.from(pending.amountUnits),
            int.tryParse(scales[asset] ?? ''),
          );
        }
      });
    } catch (_) {
      if (mounted && version == generation) setState(() => error = '币种资料暂不可用');
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  ProductMode? _mode(String account) => account == 'FUNDING'
      ? ProductMode.spot
      : ProductMode.values.where((p) => p.accountType == account).firstOrNull;

  BigInt? _available(AppState state, String currency) {
    final product = _mode(source);
    if (product == null ||
        !state.productAssetsReady(product) ||
        !scales.containsKey(currency)) {
      return null;
    }
    return (state.productBalances[product] ?? <ProductBalance>[])
        .where((b) => b.asset == currency)
        .fold<BigInt>(
          BigInt.zero,
          (sum, b) => sum + BigInt.from(b.availableUnits),
        );
  }

  void _key(String key) {
    final old = amount.text;
    final scale = scales[asset];
    if (key == 'delete') {
      setState(
        () => amount.text = old.isEmpty ? '' : old.substring(0, old.length - 1),
      );
      return;
    }
    if (scale == null ||
        !RegExp(r'^10*$').hasMatch(scale) ||
        old.length >= 40) {
      return;
    }
    final decimals = scale.length - 1;
    if (key == '.') {
      if (decimals == 0 || old.contains('.')) return;
      setState(() => amount.text = old.isEmpty ? '0.' : '$old.');
      return;
    }
    if (old.contains('.') && old.split('.').last.length >= decimals) return;
    setState(() => amount.text = old == '0' ? key : old + key);
  }

  Future<void> _account(AppState state, {required bool from}) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final entry in [
                  'FUNDING',
                  ...ProductMode.values
                      .where(
                        (p) => !p.isSpot && !state.disabledProducts.contains(p),
                      )
                      .map((p) => p.accountType),
                ])
                  ListTile(
                    title: Text(
                      entry == 'FUNDING' ? '资金账户' : productAccountLabel(entry),
                    ),
                    enabled: entry != (from ? target : source),
                    onTap: () {
                      setState(() {
                        if (from) {
                          source = entry;
                        } else {
                          target = entry;
                        }
                        amount.clear();
                      });
                      Navigator.pop(sheet);
                    },
                  ),
              ],
            ),
          ),
        ),
      );

  Future<void> _asset(AppState state) {
    var query = '';
    final entries = scales.keys.toList()..sort();
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheet) => StatefulBuilder(
        builder: (sheet, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheet).height * .65,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                children: [
                  ExchangeSearchField(
                    hintText: '搜索数字货币',
                    onChanged: (value) => update(() => query = value),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final currency in entries.where(
                          (s) => s.toLowerCase().contains(query.toLowerCase()),
                        ))
                          ListTile(
                            leading: CoinIcon(currency),
                            title: Text(currency),
                            trailing: Text(
                              scaledAmount(
                                _available(state, currency),
                                int.tryParse(scales[currency] ?? ''),
                              ),
                            ),
                            onTap: () {
                              setState(() {
                                asset = currency;
                                amount.clear();
                              });
                              Navigator.pop(sheet);
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    generation++;
    amount.dispose();
    email.dispose();
    totp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final colors = Theme.of(context).colorScheme;
    final fill = exchangePanel(context);
    final locked = state.transferSubmitting || state.pendingTransfer != null;
    final available = _available(state, asset);
    final scale = int.tryParse(scales[asset] ?? '');
    var valid = false;
    try {
      final units = BigInt.from(
        exactAmountUnits(amount.text, scales[asset] ?? ''),
      );
      valid = available != null && units > BigInt.zero && units <= available;
    } on FormatException {
      /* Invalid input stays visible until edited. */
    }
    final targetMode = _mode(target);
    valid =
        valid &&
        source != target &&
        targetMode != null &&
        !state.disabledProducts.contains(targetMode);
    Widget accountCard(String value, String label, VoidCallback onTap) =>
        Expanded(
          child: Material(
            key: ValueKey('transfer-account-$label'),
            color: fill,
            borderRadius: BorderRadius.circular(22),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: locked ? null : onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 10, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colors.onSurfaceVariant,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            value == 'FUNDING' ? '资金账户' : '交易账户',
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                        const Icon(Icons.keyboard_arrow_down, size: 18),
                      ],
                    ),
                    if (value != 'FUNDING')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          productAccountLabel(value),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
    return Scaffold(
      backgroundColor: exchangeBackground(context),
      appBar: AppBar(
        backgroundColor: exchangeBackground(context),
        leading: BackButton(style: exchangeIconStyle(context)),
        centerTitle: true,
        title: const Text('划转'),
        actions: [
          IconButton(
            style: exchangeIconStyle(context),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => FundingRecordsPage(
                  state: state,
                  initialCategory: 'transfer',
                ),
              ),
            ),
            tooltip: '划转记录',
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: !state.isLoggedIn
          ? const Center(child: Text('请先登录'))
          : SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const SizedBox(height: 18),
                            IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  accountCard(source, '从', () {
                                    _account(state, from: true);
                                  }),
                                  Center(
                                    child: IconButton(
                                      key: const ValueKey('transfer-swap'),
                                      tooltip: '互换账户',
                                      style: IconButton.styleFrom(
                                        minimumSize: const Size.square(44),
                                        backgroundColor: colors.onSurface,
                                        foregroundColor: colors.surface,
                                        shape: const CircleBorder(),
                                        side: BorderSide.none,
                                      ),
                                      onPressed: locked
                                          ? null
                                          : () => setState(() {
                                              final old = source;
                                              source = target;
                                              target = old;
                                              amount.clear();
                                            }),
                                      icon: const Icon(
                                        Icons.swap_horiz,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                  accountCard(target, '到', () {
                                    _account(state, from: false);
                                  }),
                                ],
                              ),
                            ),
                            const SizedBox(height: 30),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '数量',
                                    style: TextStyle(fontSize: 16),
                                  ),
                                ),
                                TextButton(
                                  style: TextButton.styleFrom(
                                    foregroundColor: colors.onSurface,
                                  ),
                                  onPressed: locked || loading
                                      ? null
                                      : () {
                                          _asset(state);
                                        },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      CoinIcon(asset, size: 22),
                                      const SizedBox(width: 6),
                                      Text(asset),
                                      const Icon(Icons.arrow_drop_down),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const ValueKey('transfer-amount'),
                                    controller: amount,
                                    readOnly: true,
                                    enabled: !locked,
                                    style: const TextStyle(
                                      fontSize: 36,
                                      fontWeight: FontWeight.w500,
                                      fontFeatures: exchangeNumberFeatures,
                                    ),
                                    decoration: InputDecoration(
                                      hintText: '0 $asset',
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed:
                                      locked ||
                                          available == null ||
                                          available <= BigInt.zero ||
                                          scale == null
                                      ? null
                                      : () => setState(
                                          () => amount.text = scaledAmount(
                                            available,
                                            scale,
                                          ),
                                        ),
                                  style: TextButton.styleFrom(
                                    backgroundColor: fill,
                                    foregroundColor: colors.onSurface,
                                    shape: const StadiumBorder(),
                                  ),
                                  child: const Text('最大'),
                                ),
                              ],
                            ),
                            if (loading) const LinearProgressIndicator(),
                            if (error != null)
                              TextButton(
                                onPressed: () => _load(state),
                                child: Text('$error，重试'),
                              ),
                            if (state.transferVerificationRequired) ...[
                              const SizedBox(height: 12),
                              TextField(
                                controller: email,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '邮箱验证码',
                                ),
                              ),
                              TextField(
                                controller: totp,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: '2FA 验证码',
                                ),
                              ),
                            ],
                            const Spacer(),
                            if (state.transferOutcomeLocked)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                                child: Text(
                                  state.transferOutcomeTerminalFailure
                                      ? '本次划转未完成，请查看资金记录'
                                      : '划转结果待确认，请勿重复提交',
                                ),
                              ),
                            if (state.transferOutcomeTerminalFailure)
                              TextButton(
                                onPressed: state.resetTransferIntent,
                                child: const Text('重新填写'),
                              ),
                            if (state.pendingTransfer != null &&
                                !state.transferOutcomeTerminalFailure)
                              TextButton(
                                key: const ValueKey('transfer-resume'),
                                onPressed: state.transferSubmitting
                                    ? null
                                    : () => unawaited(
                                        state.resumePendingTransfer(
                                          emailCode: email.text,
                                          totpCode: totp.text,
                                        ),
                                      ),
                                child: Text(
                                  state.transferVerificationRequired
                                      ? '验证并继续原划转'
                                      : '确认原划转结果',
                                ),
                              ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '可用',
                                  style: TextStyle(fontSize: 15),
                                ),
                                Flexible(
                                  child: Text(
                                    '${scaledAmount(available, scale)} $asset',
                                    textAlign: TextAlign.end,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.onSurface,
                                foregroundColor: colors.surface,
                                minimumSize: const Size.fromHeight(46),
                                shape: const StadiumBorder(),
                              ),
                              onPressed: locked || loading || !valid
                                  ? null
                                  : () => unawaited(
                                      state.transfer(
                                        sourceAccountType: source,
                                        targetAccountType: target,
                                        asset: asset,
                                        amount:
                                            double.tryParse(amount.text) ?? 0,
                                        amountText: amount.text,
                                        emailCode: email.text,
                                        totpCode: totp.text,
                                      ),
                                    ),
                              child: Text(
                                state.transferSubmitting
                                    ? '提交中…'
                                    : state.transferOutcomeLocked
                                    ? '等待结果确认'
                                    : '确认转出',
                              ),
                            ),
                            const SizedBox(height: 12),
                            for (final row in const [
                              ['1', '2', '3'],
                              ['4', '5', '6'],
                              ['7', '8', '9'],
                              ['.', '0', 'delete'],
                            ])
                              Row(
                                children: [
                                  for (final key in row)
                                    Expanded(
                                      child: SizedBox(
                                        height: (constraints.maxHeight * .08)
                                            .clamp(42.0, 58.0),
                                        child: TextButton(
                                          onPressed: locked || loading
                                              ? null
                                              : () => _key(key),
                                          style: TextButton.styleFrom(
                                            foregroundColor: colors.onSurface,
                                          ),
                                          child: key == 'delete'
                                              ? const Icon(
                                                  Icons.backspace_outlined,
                                                  semanticLabel: '删除数量末位',
                                                )
                                              : Text(
                                                  key,
                                                  style: const TextStyle(
                                                    fontSize: 26,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: 10),
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
}
