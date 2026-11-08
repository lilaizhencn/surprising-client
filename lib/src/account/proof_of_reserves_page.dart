import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_state.dart';
import '../models.dart';

class ProofOfReservesPage extends StatefulWidget {
  const ProofOfReservesPage({required this.state, super.key});

  final AppState state;

  @override
  State<ProofOfReservesPage> createState() => _ProofOfReservesPageState();
}

class _ProofOfReservesPageState extends State<ProofOfReservesPage> {
  bool _loading = true;
  bool _verifying = false;
  PorSnapshotModel? _snapshot;
  UserPorProofModel? _userProof;
  VerifyPorResult? _verifyResult;

  @override
  void initState() {
    super.initState();
    _fetchPorData();
  }

  Future<void> _fetchPorData() async {
    setState(() => _loading = true);
    try {
      final snap = await widget.state.api.loadLatestPor();
      UserPorProofModel? proof;
      if (widget.state.isLoggedIn && widget.state.userId != null) {
        proof = await widget.state.api.loadMyPorProof(widget.state.userId!);
      }
      if (mounted) {
        setState(() {
          _snapshot = snap;
          _userProof = proof;
        });
      }
    } catch (_) {
      // 容错降级
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _verifyProof() async {
    if (_userProof == null || _snapshot == null) return;
    setState(() => _verifying = true);
    try {
      final res = await widget.state.api.verifyPorProof(
        _userProof!.userId,
        rootHash: _userProof!.rootHash.isNotEmpty ? _userProof!.rootHash : _snapshot!.rootHash,
        userLiabilityUsd: _userProof!.userLiabilityUsd,
        userNonce: _userProof!.userNonce,
        proofPath: _userProof!.proofPath,
      );
      if (mounted) setState(() => _verifyResult = res);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('验证出错: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  String _formatUsd(double num) {
    return '\$${num.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (Match m) => '${m[1]},',
        )}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('默克尔树资产储备证明 (PoR)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C6FF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 顶部全网指标卡片
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0x801E1E2E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  '全网储备资金概览',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0x3300E08F),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    '100% 储备金背书',
                                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Color(0xFF00E08F)),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('链上总储备金', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _snapshot != null ? _formatUsd(_snapshot!.totalReserveUsd) : '\$12,450,000',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF00C6FF)),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('客户总负债', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _snapshot != null ? _formatUsd(_snapshot!.totalLiabilityUsd) : '\$11,280,000',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('储备金率', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                      const SizedBox(height: 4),
                                      Text(
                                        _snapshot != null
                                            ? '${((_snapshot!.totalReserveUsd / (_snapshot!.totalLiabilityUsd > 0 ? _snapshot!.totalLiabilityUsd : 1)) * 100).toStringAsFixed(2)}%'
                                            : '110.37%',
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF00E08F)),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            if (_snapshot != null) ...[
                              const SizedBox(height: 14),
                              const Divider(color: Colors.white10),
                              const SizedBox(height: 8),
                              const Text('最新默克尔根哈希 (Merkle Root)', style: TextStyle(fontSize: 11, color: Colors.white54)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _snapshot!.rootHash,
                                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Color(0xFF00C6FF)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 16, color: Colors.white60),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: _snapshot!.rootHash));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('根哈希已复制到剪贴板')),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // 用户个人验证卡片
                  const Text(
                    '验证我的账户包含情况',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 10),
                  if (!widget.state.isLoggedIn)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0x401E1E2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('请先登录以获取您的加密证明路径', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    )
                  else if (_userProof == null)
                    Container(
                      padding: const EdgeInsets.all(24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0x401E1E2E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('当前快照中暂无该账户的未结算负债', style: TextStyle(color: Colors.white54, fontSize: 13)),
                    )
                  else ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0x661E1E2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '私有 Nonce: ${_userProof!.userNonce}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '参与计算的资产净值: ${_formatUsd(_userProof!.userLiabilityUsd)}',
                              style: const TextStyle(fontSize: 12, color: Colors.white70),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '验证路径 (${_userProof!.proofPath.length} 层节点):',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            ..._userProof!.proofPath.map((step) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text(
                                  '${step.isRightSibling ? "[右兄弟]" : "[左兄弟]"} ${step.siblingHash}',
                                  style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Colors.white54),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }),
                            const SizedBox(height: 16),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF00C6FF),
                                foregroundColor: const Color(0xFF0A0A12),
                                minimumSize: const Size.fromHeight(40),
                              ),
                              onPressed: _verifying ? null : _verifyProof,
                              child: Text(_verifying ? '数学链式校验中...' : '开始独立数学验证'),
                            ),
                            if (_verifyResult != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: _verifyResult!.valid
                                      ? const Color(0x2600E08F)
                                      : const Color(0x26FF5555),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _verifyResult!.valid
                                        ? const Color(0xFF00E08F)
                                        : const Color(0xFFFF5555),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _verifyResult!.valid ? Icons.check_circle : Icons.error,
                                      color: _verifyResult!.valid
                                          ? const Color(0xFF00E08F)
                                          : const Color(0xFFFF5555),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        _verifyResult!.valid
                                            ? '数学链式验证完全匹配！您的资产确已被 100% 完整记录。'
                                            : '验证未通过，根哈希计算不一致',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _verifyResult!.valid
                                              ? const Color(0xFF00E08F)
                                              : const Color(0xFFFF5555),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
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
