import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';

Future<void> showSpotAmendOrderSheet(
  BuildContext context,
  AppState state,
  OrderModel order,
  Instrument instrument,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) =>
        SpotAmendOrderSheet(state: state, order: order, instrument: instrument),
  );
}

class SpotAmendOrderSheet extends StatefulWidget {
  const SpotAmendOrderSheet({
    required this.state,
    required this.order,
    required this.instrument,
    super.key,
  });
  final AppState state;
  final OrderModel order;
  final Instrument instrument;
  @override
  State<SpotAmendOrderSheet> createState() => _SpotAmendOrderSheetState();
}

class _SpotAmendOrderSheetState extends State<SpotAmendOrderSheet> {
  late final int? userId = widget.state.userId;
  late final price = TextEditingController(
    text: scaledAmount(
      BigInt.from(widget.order.priceTicks) *
          BigInt.from(widget.instrument.priceTickUnits),
      widget.instrument.quoteScaleUnits,
    ),
  );
  late final quantity = TextEditingController(
    text: scaledAmount(
      BigInt.from(widget.order.remainingQuantitySteps) *
          BigInt.from(widget.instrument.quantityStepUnits),
      widget.instrument.baseScaleUnits,
    ),
  );
  @override
  void dispose() {
    price.dispose();
    quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.state,
    builder: (context, _) {
      final state = widget.state;
      final current = state.userId == userId && state.mode == ProductMode.spot;
      final busy = state.submittingOrder || state.tradingCommandPending;
      return SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            16,
            20,
            16,
            MediaQuery.viewInsetsOf(context).bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '现货改单 · ${widget.instrument.symbol}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              const Text('改单成功后撤销原单并创建新委托。新委托数量独立于原单已成交数量；未确认时请勿重复操作。'),
              const SizedBox(height: 16),
              TextField(
                controller: price,
                enabled: current && !busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '新委托价格',
                  suffixText: widget.instrument.quoteAsset,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                enabled: current && !busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '新委托数量',
                  suffixText: widget.instrument.baseAsset,
                ),
              ),
              const SizedBox(height: 12),
              if (!current) const Text('账户或产品已变化，请关闭后重新选择订单'),
              if (current && state.lastError != null)
                Text(
                  state.lastError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: !current || busy
                    ? null
                    : () async {
                        await state.amendSpotOrder(
                          widget.order,
                          widget.instrument,
                          price.text,
                          quantity.text,
                        );
                        if (!context.mounted || state.userId != userId) return;
                        if (state.tradingCommandPending ||
                            state.lastError == null ||
                            !state.openOrders.any(
                              (o) => o.orderId == widget.order.orderId,
                            )) {
                          Navigator.of(context).pop();
                        }
                      },
                child: const Text('确认改单'),
              ),
              TextButton(
                onPressed: state.submittingOrder
                    ? null
                    : () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
