import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';

class VipCenterPage extends StatefulWidget {
  const VipCenterPage({required this.state, super.key});

  final AppState state;

  @override
  State<VipCenterPage> createState() => _VipCenterPageState();
}

class _VipCenterPageState extends State<VipCenterPage> {
  bool _loading = true;
  bool _evaluating = false;
  List<VipTierModel> _levels = [];
  UserVipStatusModel? _myStatus;

  @override
  void initState() {
    super.initState();
    _fetchVipData();
  }

  Future<void> _fetchVipData() async {
    setState(() => _loading = true);
    try {
      final levels = await widget.state.api.loadVipLevels();
      UserVipStatusModel? status;
      if (widget.state.isLoggedIn && widget.state.userId != null) {
        status = await widget.state.api.loadMyVipStatus(widget.state.userId!);
      }
      if (mounted) {
        setState(() {
          _levels = levels;
          _myStatus = status;
        });
      }
    } catch (_) {
      // 容错降级
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _evaluateVip() async {
    if (!widget.state.isLoggedIn || widget.state.userId == null) return;
    setState(() => _evaluating = true);
    try {
      final updated = await widget.state.api.evaluateMyVip(widget.state.userId!);
      if (mounted) {
        setState(() => _myStatus = updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('VIP 费率与等级评估已刷新！')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('评估失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _evaluating = false);
    }
  }

  String _formatFee(int ppm) {
    final pct = (ppm / 10000).toStringAsFixed(4);
    if (ppm < 0) return '$pct% (返佣)';
    return '$pct%';
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
        title: const Text(
          'VIP 费率与成长中心',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF00C6FF)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 当前 VIP 状态卡片
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: const Color(0x801E1E2E),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color(0x3300C6FF),
                              blurRadius: 20,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        gradient: const LinearGradient(
                                          colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        _myStatus?.currentTierCode ?? 'VIP0',
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      '尊享动态手续费折扣',
                                      style: TextStyle(fontSize: 12, color: Colors.white70),
                                    ),
                                  ],
                                ),
                                if (widget.state.isLoggedIn)
                                  InkWell(
                                    onTap: _evaluating ? null : _evaluateVip,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white24),
                                      ),
                                      child: Text(
                                        _evaluating ? '评估中...' : '刷新等级',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF00C6FF),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0x660A0A12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('挂单费率 (Maker)', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatFee(_myStatus?.makerFeeRatePpm ?? 100),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF00C6FF),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: const Color(0x660A0A12),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('吃单费率 (Taker)', style: TextStyle(fontSize: 11, color: Colors.white54)),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatFee(_myStatus?.takerFeeRatePpm ?? 150),
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (_myStatus != null) ...[
                              const SizedBox(height: 14),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '近30天交易量: ${_formatUsd(_myStatus!.rolling30DayVolumeUsd)}',
                                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                                  ),
                                  Text(
                                    _myStatus!.nextTierMinVolumeUsd > 0
                                        ? '下一级目标: ${_formatUsd(_myStatus!.nextTierMinVolumeUsd)}'
                                        : '已达最高级别',
                                    style: const TextStyle(fontSize: 11, color: Colors.white54),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: _myStatus!.nextTierMinVolumeUsd > 0
                                      ? (_myStatus!.rolling30DayVolumeUsd / _myStatus!.nextTierMinVolumeUsd).clamp(0.0, 1.0)
                                      : 1.0,
                                  minHeight: 6,
                                  backgroundColor: Colors.white10,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF00C6FF)),
                                ),
                              ),
                              if (_myStatus!.volumeNeededForNextTier > 0) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '再交易 ${_formatUsd(_myStatus!.volumeNeededForNextTier)} 即可晋升至下一等级',
                                  style: const TextStyle(fontSize: 11, color: Colors.white38),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  // VIP 等级权益表
                  const Text(
                    'VIP 等级阶梯表',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0x661E1E2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: Column(
                          children: _levels.map((lvl) {
                            final isCurrent = _myStatus?.currentTierLevel == lvl.tierLevel;
                            return Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isCurrent ? const Color(0x3300C6FF) : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                                border: isCurrent ? Border.all(color: const Color(0x6600C6FF)) : null,
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: Text(
                                      lvl.tierCode,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isCurrent ? const Color(0xFF00C6FF) : Colors.white,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '≥ ${_formatUsd(lvl.min30DayVolumeUsd)}',
                                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                                        ),
                                        Text(
                                          lvl.makerFeeRatePpm < 0
                                              ? '做市商负费率返佣 (-50 ppm)'
                                              : '标准高频撮合协议',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: lvl.makerFeeRatePpm < 0 ? const Color(0xFF00E08F) : Colors.white38,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'M: ${_formatFee(lvl.makerFeeRatePpm)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: lvl.makerFeeRatePpm < 0 ? const Color(0xFF00E08F) : Colors.white,
                                        ),
                                      ),
                                      Text(
                                        'T: ${_formatFee(lvl.takerFeeRatePpm)}',
                                        style: const TextStyle(fontSize: 11, color: Colors.white54),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
