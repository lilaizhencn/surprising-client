import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';
import '../ui/client_components.dart';

class SubAccountPage extends StatefulWidget {
  const SubAccountPage({required this.state, super.key});

  final AppState state;

  @override
  State<SubAccountPage> createState() => _SubAccountPageState();
}

class _SubAccountPageState extends State<SubAccountPage> {
  bool _loading = false;
  List<SubAccountModel> _subAccounts = [];

  @override
  void initState() {
    super.initState();
    _loadSubAccounts();
  }

  Future<void> _loadSubAccounts() async {
    if (!widget.state.isLoggedIn || widget.state.session == null) return;
    setState(() => _loading = true);
    try {
      final list = await widget.state.api.loadSubAccounts(widget.state.userId!);
      if (mounted) setState(() => _subAccounts = list);
    } catch (_) {
      // 容错降级
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showCreateDialog() {
    final nameController = TextEditingController();
    var permissions = 'TRADING';
    var creating = false;

    showDialog<void>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E1E2E),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
              ),
              title: const Text('创建子账户', style: TextStyle(color: Colors.white, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: '例如: 量化网格1号',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0x660A0A12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SmallDropdown(
                    value: permissions,
                    values: const ['TRADING', 'READONLY', 'ALL'],
                    labelBuilder: (v) => switch (v) {
                      'TRADING' => '仅限交易与划转',
                      'READONLY' => '只读审计权限',
                      'ALL' => '完全权限',
                      _ => v,
                    },
                    onChanged: (v) => setDialogState(() => permissions = v),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogCtx).pop(),
                  child: const Text('取消', style: TextStyle(color: Colors.white54)),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00C6FF),
                    foregroundColor: const Color(0xFF0A0A12),
                  ),
                  onPressed: creating
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          final messenger = ScaffoldMessenger.of(context);
                          final nav = Navigator.of(dialogCtx);
                          setDialogState(() => creating = true);
                          try {
                            await widget.state.api.createSubAccount(
                              widget.state.userId!,
                              subAccountName: name,
                              permissions: permissions,
                            );
                            if (mounted) {
                              nav.pop();
                              messenger.showSnackBar(
                                const SnackBar(content: Text('子账户创建成功！')),
                              );
                              _loadSubAccounts();
                            }
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(content: Text('创建失败: $e')),
                              );
                            }
                          } finally {
                            setDialogState(() => creating = false);
                          }
                        },
                  child: Text(creating ? '创建中...' : '确定创建'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showTransferSheet(SubAccountModel subAccount, bool fromParentToSub) {
    final amountController = TextEditingController();
    var asset = 'USDT';
    var transferring = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                child: Container(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).viewInsets.bottom + 24),
                  color: const Color(0xE612121E),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        fromParentToSub ? '主账户 → 子账户划转' : '子账户 → 主账户划转',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '子账户: ${subAccount.subAccountName} (UID: ${subAccount.subUserId}) · 0手续费秒级到账',
                        style: const TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                      const SizedBox(height: 14),
                      SmallDropdown(
                        value: asset,
                        values: const ['USDT', 'USDC', 'BTC', 'ETH'],
                        labelBuilder: (v) => v,
                        onChanged: (v) => setSheetState(() => asset = v),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: '划转数量',
                          hintStyle: const TextStyle(color: Colors.white38),
                          suffixText: asset,
                          suffixStyle: const TextStyle(color: Color(0xFF00C6FF)),
                          filled: true,
                          fillColor: const Color(0x660A0A12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00C6FF),
                          foregroundColor: const Color(0xFF0A0A12),
                          minimumSize: const Size.fromHeight(42),
                        ),
                        onPressed: transferring
                            ? null
                            : () async {
                                final amt = double.tryParse(amountController.text) ?? 0;
                                if (amt <= 0) return;
                                final messenger = ScaffoldMessenger.of(context);
                                final nav = Navigator.of(sheetCtx);
                                setSheetState(() => transferring = true);
                                try {
                                  final units = (amt * 10000).toInt();
                                  final res = await widget.state.api.transferSubAccount(
                                    widget.state.userId!,
                                    subUserId: subAccount.subUserId,
                                    fromParentToSub: fromParentToSub,
                                    asset: asset,
                                    amountUnits: units,
                                  );
                                  if (mounted) {
                                    nav.pop();
                                    messenger.showSnackBar(
                                      SnackBar(content: Text('划转成功！流水号: ${res.transferId}')),
                                    );
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    messenger.showSnackBar(
                                      SnackBar(content: Text('划转失败: $e')),
                                    );
                                  }
                                } finally {
                                  setSheetState(() => transferring = false);
                                }
                              },
                        child: Text(transferring ? '划转中...' : '确认划转'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('子账户管理', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF00C6FF)),
            onPressed: _showCreateDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C6FF)))
          : _subAccounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.group_outlined, size: 48, color: Colors.white24),
                      const SizedBox(height: 12),
                      const Text('暂无子账户', style: TextStyle(color: Colors.white54, fontSize: 14)),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF00C6FF),
                          foregroundColor: const Color(0xFF0A0A12),
                        ),
                        onPressed: _showCreateDialog,
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新建第一个子账户'),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _subAccounts.length,
                  itemBuilder: (context, index) {
                    final acc = _subAccounts[index];
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0x661E1E2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  acc.subAccountName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0x3300E08F),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    acc.status,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF00E08F),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'UID: ${acc.subUserId} · 权限: ${acc.permissions}',
                              style: const TextStyle(fontSize: 12, color: Colors.white60),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF00C6FF),
                                    side: const BorderSide(color: Color(0x6600C6FF)),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => _showTransferSheet(acc, true),
                                  child: const Text('转入'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    side: const BorderSide(color: Colors.white24),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  onPressed: () => _showTransferSheet(acc, false),
                                  child: const Text('转出'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
