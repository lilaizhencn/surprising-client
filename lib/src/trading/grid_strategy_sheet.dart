import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../app_state.dart';
import '../models.dart';

class GridStrategySheet extends StatefulWidget {
  const GridStrategySheet({
    required this.instrument,
    required this.state,
    super.key,
  });

  final Instrument instrument;
  final AppState state;

  @override
  State<GridStrategySheet> createState() => _GridStrategySheetState();
}

class _GridStrategySheetState extends State<GridStrategySheet> {
  final _lowerPriceController = TextEditingController();
  final _upperPriceController = TextEditingController();
  final _gridCountController = TextEditingController(text: '10');
  final _investmentController = TextEditingController();

  bool _isArithmetic = true;
  bool _submitting = false;
  bool _loadingList = false;
  List<GridStrategyRecord> _strategies = [];
  int? _stoppingId;

  @override
  void initState() {
    super.initState();
    _loadStrategies();
  }

  @override
  void dispose() {
    _lowerPriceController.dispose();
    _upperPriceController.dispose();
    _gridCountController.dispose();
    _investmentController.dispose();
    super.dispose();
  }

  Future<void> _loadStrategies() async {
    if (!widget.state.isLoggedIn) return;
    setState(() => _loadingList = true);
    try {
      final list = await widget.state.api.loadGridStrategies(
        userId: widget.state.userId,
        productLine: widget.instrument.mode.productLine,
      );
      if (mounted) setState(() => _strategies = list);
    } catch (_) {
      // 容错降级
    } finally {
      if (mounted) setState(() => _loadingList = false);
    }
  }

  Future<void> _createStrategy() async {
    if (!widget.state.isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先登录')),
      );
      return;
    }
    final lowTicks = widget.instrument.priceTicksFromText(_lowerPriceController.text);
    final highTicks = widget.instrument.priceTicksFromText(_upperPriceController.text);
    final count = int.tryParse(_gridCountController.text) ?? 0;
    final investUnits = widget.instrument.isSpot
        ? decimalIncrement(
            _investmentController.text,
            widget.instrument.quantityStepUnits,
            scaleUnits: widget.instrument.quoteScaleUnits ?? 2,
          )
        : int.tryParse(_investmentController.text);

    if (lowTicks == null || lowTicks <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效区间下限价格')),
      );
      return;
    }
    if (highTicks == null || highTicks <= lowTicks) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('区间上限必须大于下限价格')),
      );
      return;
    }
    if (count < 2 || count > 150) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('网格数量须在 2 ~ 150 之间')),
      );
      return;
    }
    if (investUnits == null || investUnits <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效投资金额')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final latest = widget.state.latestPriceFor(widget.instrument);
      final currentTicks = latest != null
          ? (widget.instrument.priceTicksFromText('$latest') ?? 0)
          : 0;

      await widget.state.api.createGridStrategy(
        userId: widget.state.userId!,
        instrumentId: widget.instrument.instrumentId,
        productLine: widget.instrument.mode.productLine,
        lowerPriceTicks: lowTicks,
        upperPriceTicks: highTicks,
        gridCount: count,
        totalInvestmentUnits: investUnits,
        isArithmetic: _isArithmetic,
        currentPriceTicks: currentTicks,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网格策略机器人已成功部署运行！')),
        );
        _lowerPriceController.clear();
        _upperPriceController.clear();
        _investmentController.clear();
      }
      await _loadStrategies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建网格失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _stopStrategy(int strategyId) async {
    setState(() => _stoppingId = strategyId);
    try {
      await widget.state.api.stopGridStrategy(
        strategyId,
        userId: widget.state.userId,
        productLine: widget.instrument.mode.productLine,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('网格策略已终止并撤销所有挂单')),
        );
      }
      await _loadStrategies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('终止策略失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _stoppingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xE612121E),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '网格策略机器人',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0x3300C6FF),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0x6600C6FF)),
                          ),
                          child: Text(
                            widget.instrument.symbol,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF00C6FF),
                            ),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20, color: Colors.white54),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // 模式切换
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: const Color(0x800A0A12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _isArithmetic = true),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              gradient: _isArithmetic
                                  ? const LinearGradient(
                                      colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '等差网格 (固定差额)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _isArithmetic ? Colors.white : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _isArithmetic = false),
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(
                              gradient: !_isArithmetic
                                  ? const LinearGradient(
                                      colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '等比网格 (固定比例)',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: !_isArithmetic ? Colors.white : Colors.white60,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _GridInput(
                        controller: _lowerPriceController,
                        hint: '区间下限',
                        suffix: widget.instrument.quoteAsset,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GridInput(
                        controller: _upperPriceController,
                        hint: '区间上限',
                        suffix: widget.instrument.quoteAsset,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _GridInput(
                        controller: _gridCountController,
                        hint: '网格数 (2~150)',
                        suffix: '格',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GridInput(
                        controller: _investmentController,
                        hint: '投入资金',
                        suffix: widget.instrument.quoteAsset,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF00C6FF),
                    foregroundColor: const Color(0xFF0A0A12),
                    minimumSize: const Size.fromHeight(42),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _submitting ? null : _createStrategy,
                  child: _submitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          '创建网格策略机器人',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '运行中的策略',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, size: 18, color: Colors.white54),
                      onPressed: _loadingList ? null : _loadStrategies,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_strategies.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    alignment: Alignment.center,
                    child: Text(
                      _loadingList ? '加载中...' : '暂无运行中的网格策略',
                      style: const TextStyle(fontSize: 12, color: Colors.white38),
                    ),
                  )
                else
                  ..._strategies.map((st) {
                    final isRunning = st.status == 'RUNNING';
                    final isStopping = _stoppingId == st.strategyId;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0x401E1E2E),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                st.instrumentId,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isRunning
                                      ? const Color(0x3300E08F)
                                      : Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  st.status,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: isRunning
                                        ? const Color(0xFF00E08F)
                                        : Colors.white54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '网格数: ${st.gridCount} 格 · 成交: ${st.matchedTradeCount} 笔',
                            style: const TextStyle(fontSize: 12, color: Colors.white70),
                          ),
                          const SizedBox(height: 8),
                          if (isRunning)
                            Align(
                              alignment: Alignment.centerRight,
                              child: OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFFFF5555),
                                  side: const BorderSide(color: Color(0x66FF5555)),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                onPressed: isStopping
                                    ? null
                                    : () => _stopStrategy(st.strategyId),
                                child: Text(isStopping ? '终止中...' : '终止策略'),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GridInput extends StatelessWidget {
  const _GridInput({
    required this.controller,
    required this.hint,
    required this.suffix,
  });

  final TextEditingController controller;
  final String hint;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: Color(0xFF00C6FF), fontSize: 11),
        filled: true,
        fillColor: const Color(0x660A0A12),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    );
  }
}
