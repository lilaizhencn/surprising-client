import 'package:flutter/material.dart';

import '../models.dart';

String tradingRecoveryLabel(PendingTradingOrder? pending) {
  if (pending?.clientAlgoOrderId != null) return '查询算法单请求';
  if (pending?.cancelPlan != null) return '确认并继续撤单';
  if (pending?.amendRequestId != null) return '查询改单结果';
  if (pending?.cancelOrderId != null) return '查询撤单结果';
  return '查询委托结果';
}

String tradingPendingMessage(PendingTradingOrder? pending) {
  if (pending?.clientAlgoOrderId != null) return '算法单创建结果待确认，请勿重复提交';
  final plan = pending?.cancelPlan;
  if (plan != null) {
    return '现货批量撤单：已确认 ${plan.completed + plan.failed}/${plan.requested} 笔，请确认后继续';
  }
  if (pending?.amendRequestId != null) return '改单结果待确认，请勿重复提交';
  if (pending?.cancelOrderId != null) return '撤单结果待确认，请勿重复提交';
  return '委托结果待确认，请勿重复提交';
}

String tradingQuantity(
  Instrument instrument,
  int steps, {
  bool absolute = false,
}) {
  final quantity = absolute ? BigInt.from(steps).abs() : BigInt.from(steps);
  return instrument.isSpot
      ? '${scaledAmount(quantity * BigInt.from(instrument.quantityStepUnits), instrument.baseScaleUnits)} ${instrument.baseAsset}'
      : '$quantity 张';
}

String tradingAmount(Object? units, Instrument instrument, [String? asset]) {
  final amount = units == null ? null : BigInt.tryParse('$units');
  final text = scaledAmount(
    amount,
    instrument.isSpot
        ? instrument.quoteScaleUnits
        : instrument.settleScaleUnits,
  );
  return text == '--'
      ? text
      : '$text ${asset == null || asset.isEmpty ? (instrument.isSpot ? instrument.quoteAsset : instrument.settleAsset) : asset}';
}

String tradingTime(DateTime? time) => time == null
    ? '--'
    : time.toLocal().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
String tradingStatus(OrderModel order) {
  final status = order.status == 'OPEN'
      ? (order.executedQuantitySteps > 0 ? 'PARTIALLY_FILLED' : 'NEW')
      : order.status;
  return const {
        'NEW': '未成交',
        'ACCEPTED': '未成交',
        'PARTIALLY_FILLED': '部分成交',
        'FILLED': '已成交',
        'CANCELED': '已撤销',
        'CANCELLED': '已撤销',
        'REJECTED': '已拒绝',
        'CANCEL_REQUESTED': '撤销中',
        'PENDING_RESERVE': '处理中',
      }[status] ??
      status;
}

class TradingDetails extends StatelessWidget {
  const TradingDetails({required this.values, super.key});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        for (final entry in values.entries)
          SizedBox(
            width: (constraints.maxWidth - 12) / 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  entry.value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
