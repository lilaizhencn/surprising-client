import 'i18n/client_messages.dart';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';
import 'spot_order.dart';

Future<void> showSpotAlgoOrderSheet(BuildContext context, AppState state) {
  final ownerId = state.userId;
  final instrument = state.selectedInstrument;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => SpotAlgoOrderSheet(
      state: state,
      ownerId: ownerId,
      instrument: instrument,
    ),
  );
}

class SpotAlgoOrderSheet extends StatefulWidget {
  const SpotAlgoOrderSheet({
    required this.state,
    required this.ownerId,
    required this.instrument,
    super.key,
  });
  final AppState state;
  final int? ownerId;
  final Instrument instrument;
  @override
  State<SpotAlgoOrderSheet> createState() => _SpotAlgoOrderSheetState();
}

class _SpotAlgoOrderSheetState extends State<SpotAlgoOrderSheet> {
  bool ownsSelection() =>
      widget.ownerId != null &&
      widget.ownerId == widget.state.userId &&
      widget.state.mode.isSpot &&
      widget.state.selectedInstrument.instrumentId ==
          widget.instrument.instrumentId;
  final price = TextEditingController(),
      quantity = TextEditingController(),
      child = TextEditingController();
  final interval = TextEditingController(text: '5'),
      duration = TextEditingController(text: '60');
  String type = 'TWAP', side = 'BUY';
  bool market = true, postOnly = false;
  @override
  void dispose() {
    for (final c in [price, quantity, child, interval, duration]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final state = widget.state, instrument = widget.instrument;
      final owns = ownsSelection();
      final busy = state.submittingOrder || state.tradingCommandPending;
      AlgoOrderDraft? draft;
      String? error;
      try {
        draft = spotAlgoTerms(
          instrument: instrument,
          type: type,
          side: side,
          price: price.text,
          quantity: quantity.text,
          childQuantity: child.text,
          interval: type == 'ICEBERG' ? '1' : interval.text,
          duration: duration.text,
          market: market,
          postOnly: postOnly,
        );
      } on FormatException catch (e) {
        error = e.message;
      }
      Widget field(
        String label,
        TextEditingController c,
        String key, {
        bool integer = false,
      }) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: TextField(
          key: ValueKey(key),
          controller: c,
          enabled: owns && !busy,
          keyboardType: TextInputType.numberWithOptions(decimal: !integer),
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
        ),
      );
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LText(
                '创建现货策略 · ${instrument.symbol}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (!owns) const LText('账户或交易对已变化，请关闭后重新打开'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const ValueKey('spot-algo-type'),
                initialValue: type,
                items: const [
                  DropdownMenuItem(value: 'TWAP', child: LText('TWAP 定时切片')),
                  DropdownMenuItem(value: 'ICEBERG', child: LText('冰山委托')),
                ],
                onChanged: owns && !busy
                    ? (v) => setState(() {
                        type = v!;
                        postOnly = false;
                      })
                    : null,
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'BUY', label: LText('买入')),
                  ButtonSegment(value: 'SELL', label: LText('卖出')),
                ],
                selected: {side},
                onSelectionChanged: owns && !busy
                    ? (v) => setState(() => side = v.first)
                    : null,
              ),
              if (type == 'TWAP')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LText('市价切片'),
                  value: market,
                  onChanged: owns && !busy
                      ? (v) => setState(() => market = v)
                      : null,
                ),
              if (type == 'ICEBERG' || !market)
                field('价格（${instrument.quoteAsset}）', price, 'spot-algo-price'),
              field(
                '总数量（${instrument.baseAsset}）',
                quantity,
                'spot-algo-quantity',
              ),
              field('单片数量（${instrument.baseAsset}）', child, 'spot-algo-child'),
              if (type == 'TWAP')
                field('切片间隔（秒）', interval, 'spot-algo-interval', integer: true),
              field('执行时长（秒）', duration, 'spot-algo-duration', integer: true),
              if (type == 'ICEBERG')
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const LText('只挂单'),
                  value: postOnly,
                  onChanged: owns && !busy
                      ? (v) => setState(() => postOnly = v ?? false)
                      : null,
                ),
              const SizedBox(height: 12),
              if (error != null)
                LText(
                  error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              if (state.lastNotice != null) LText(state.lastNotice!),
              if (state.lastError != null)
                LText(
                  state.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                key: const ValueKey('spot-algo-submit'),
                onPressed: !owns || state.submittingOrder
                    ? null
                    : state.tradingCommandPending
                    ? () {
                        if (ownsSelection()) state.checkPendingTradingCommand();
                      }
                    : draft == null
                    ? null
                    : () async {
                        if (!ownsSelection()) return;
                        final accepted = await state.placeAlgoOrder(draft!);
                        if (accepted && ownsSelection() && context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                child: LText(
                  state.submittingOrder
                      ? '处理中'
                      : state.tradingCommandPending
                      ? '查询原请求'
                      : '创建策略',
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
