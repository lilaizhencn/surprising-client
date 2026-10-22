import 'api.dart';
import 'models.dart';

/// Reads the original command's result without ever resubmitting the command.
class TradingReceiptResolver {
  const TradingReceiptResolver(this.api);

  final ApiClient api;

  Future<bool?> resolve(PendingTradingOrder pending) async {
    bool? confirmed;
    if (pending.clientAlgoOrderId != null) {
      final receipt = await api.get(
        '/api/v1/gateway/trading/algo/submission',
        userId: pending.userId,
        productLine: pending.product.productLine,
        query: {
          'userId': '${pending.userId}',
          'clientAlgoOrderId': pending.clientAlgoOrderId!,
        },
      );
      final algoId = receipt['algoOrderId'];
      final algoIdText = '$algoId';
      if ('${receipt['userId']}' != '${pending.userId}' ||
          receipt['productLine'] != pending.product.productLine ||
          receipt['clientAlgoOrderId'] != pending.clientAlgoOrderId ||
          (algoId is! int && algoId is! String) ||
          !RegExp(r'^[1-9]\d*$').hasMatch(algoIdText) ||
          BigInt.parse(algoIdText) > BigInt.from(9223372036854775807) ||
          receipt['commandId'] is! String ||
          !RegExp(
            r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
          ).hasMatch(asString(receipt['commandId'])) ||
          (pending.commandId != null &&
              pending.commandId != receipt['commandId'])) {
        throw const FormatException('算法单原请求回执身份不匹配');
      }
      if (receipt['outcome'] == 'TERMINAL' &&
          receipt['code'] is String &&
          RegExp(r'^[A-Z][A-Z0-9_]*$').hasMatch(asString(receipt['code'])) &&
          !['RESULT_UNKNOWN', 'MATCHING_PENDING'].contains(receipt['code'])) {
        confirmed = receipt['code'] == 'NONE';
        if (receipt['algoOrder'] != null) {
          final order = AlgoOrderModel.fromJson(
            asMap(receipt['algoOrder']),
            product: pending.product,
          );
          if (order.userId != pending.userId ||
              order.clientAlgoOrderId != pending.clientAlgoOrderId ||
              order.instrumentId != pending.instrumentId ||
              order.algoOrderId != parseInt64(receipt['algoOrderId']) ||
              !confirmed) {
            throw const FormatException('算法单原请求状态不匹配');
          }
        }
      } else if (receipt['outcome'] != 'RESULT_UNKNOWN' ||
          receipt['code'] != 'RESULT_UNKNOWN' ||
          receipt['algoOrder'] != null) {
        throw const FormatException('算法单原请求回执不完整');
      }
    } else if (pending.clientTriggerOrderId != null ||
        pending.cancelTriggerOrderId != null) {
      final receipt = await api.get(
        pending.cancelTriggerOrderId != null
            ? '/api/v1/gateway/trading-trigger/cancellations/${pending.cancelTriggerOrderId}'
            : '/api/v1/gateway/trading-trigger/submission',
        userId: pending.userId,
        productLine: pending.product.productLine,
        query: {
          'userId': '${pending.userId}',
          if (pending.clientTriggerOrderId != null)
            'clientTriggerOrderId': pending.clientTriggerOrderId!,
        },
      );
      if (receipt['commandId'] is! String ||
          asString(receipt['commandId']).isEmpty ||
          (pending.commandId != null &&
              receipt['commandId'] != pending.commandId)) {
        throw const FormatException('条件单回执身份不匹配');
      }
      if (receipt['outcome'] == 'TERMINAL' &&
          receipt['code'] is String &&
          asString(receipt['code']).isNotEmpty) {
        confirmed = receipt['code'] == 'NONE';
      } else if (receipt['outcome'] != 'RESULT_UNKNOWN' ||
          receipt['code'] != 'RESULT_UNKNOWN') {
        throw const FormatException('条件单回执不完整');
      }
    } else if (pending.ocoTakeProfitClientId != null &&
        pending.ocoStopLossClientId != null) {
      final receipt = await api.get(
        '/api/v1/gateway/trading-trigger/oco-submission',
        userId: pending.userId,
        productLine: pending.product.productLine,
        query: {
          'userId': '${pending.userId}',
          'takeProfitClientId': pending.ocoTakeProfitClientId!,
          'stopLossClientId': pending.ocoStopLossClientId!,
        },
      );
      if (receipt['commandId'] is! String ||
          asString(receipt['commandId']).isEmpty ||
          (pending.commandId != null &&
              receipt['commandId'] != pending.commandId)) {
        throw const FormatException('OCO 回执身份不匹配');
      }
      if (receipt['outcome'] == 'TERMINAL' &&
          receipt['code'] is String &&
          asString(receipt['code']).isNotEmpty) {
        confirmed = receipt['code'] == 'NONE';
      } else if (receipt['outcome'] != 'RESULT_UNKNOWN' ||
          receipt['code'] != 'RESULT_UNKNOWN') {
        throw const FormatException('OCO 回执不完整');
      }
    } else if (pending.amendRequestId != null) {
      final receipt = await api.get(
        '/api/v1/gateway/trading/amendments',
        userId: pending.userId,
        productLine: pending.product.productLine,
        query: {
          'userId': '${pending.userId}',
          'clientRequestId': pending.amendRequestId!,
        },
      );
      if (receipt['commandId'] is! String ||
          asString(receipt['commandId']).isEmpty ||
          (pending.commandId != null &&
              receipt['commandId'] != pending.commandId)) {
        throw const FormatException('改单回执资料不匹配');
      }
      if (receipt['outcome'] == 'TERMINAL' &&
          receipt['code'] is String &&
          asString(receipt['code']).isNotEmpty) {
        confirmed = receipt['code'] == 'NONE';
      } else if (receipt['outcome'] != 'RESULT_UNKNOWN' ||
          receipt['code'] != 'RESULT_UNKNOWN') {
        throw const FormatException('改单回执资料不完整');
      }
    } else if (pending.cancelOrderId != null) {
      final receipt = await api.get(
        '/api/v1/gateway/trading/cancellations/${pending.cancelOrderId}',
        userId: pending.userId,
        productLine: pending.product.productLine,
        query: {'userId': '${pending.userId}'},
      );
      final ids = asList(receipt['prospectiveOrderIds']);
      if (receipt['commandId'] is! String ||
          asString(receipt['commandId']).isEmpty ||
          (pending.commandId != null &&
              receipt['commandId'] != pending.commandId) ||
          ids.length != 1 ||
          parseInt64(ids.first) != pending.cancelOrderId) {
        throw const FormatException('撤单回执资料不匹配');
      }
      if (receipt['outcome'] == 'TERMINAL' &&
          receipt['code'] is String &&
          asString(receipt['code']).isNotEmpty) {
        confirmed = receipt['code'] == 'NONE';
      } else if (receipt['outcome'] != 'RESULT_UNKNOWN' ||
          receipt['code'] != 'RESULT_UNKNOWN') {
        throw const FormatException('撤单回执资料不完整');
      }
    } else if (pending.clientOrderId != null && pending.instrumentId != null) {
      final receipt = await api.get(
        '/api/v1/gateway/trading/submission',
        userId: pending.userId,
        productLine: pending.product.productLine,
        query: {
          'userId': '${pending.userId}',
          'clientOrderId': pending.clientOrderId!,
        },
      );
      if (parseInt64(receipt['userId']) != pending.userId ||
          receipt['productLine'] != pending.product.productLine ||
          receipt['clientOrderId'] != pending.clientOrderId) {
        throw const FormatException('委托回执资料不匹配');
      }
      if (receipt['outcome'] == 'TERMINAL') {
        if (receipt['instrumentId'] != pending.instrumentId ||
            receipt['commandId'] is! String ||
            asString(receipt['commandId']).isEmpty ||
            (pending.commandId != null &&
                receipt['commandId'] != pending.commandId) ||
            receipt['code'] is! String ||
            asString(receipt['code']).isEmpty) {
          throw const FormatException('委托回执资料不匹配');
        }
        confirmed = receipt['code'] == 'NONE';
      }
      if (confirmed == null) {
        if (receipt['outcome'] != 'RESULT_UNKNOWN' ||
            receipt['code'] != 'RESULT_UNKNOWN') {
          throw const FormatException('委托回执资料不完整');
        }
        try {
          final order = await api.get(
            '/api/v1/gateway/trading/by-client-order-id',
            userId: pending.userId,
            productLine: pending.product.productLine,
            query: {
              'userId': '${pending.userId}',
              'clientOrderId': pending.clientOrderId!,
            },
          );
          if (parseInt64(order['userId']) != pending.userId ||
              order['clientOrderId'] != pending.clientOrderId ||
              asString(order['instrumentId']) != pending.instrumentId ||
              (parseInt64(order['orderId']) ?? 0) <= 0 ||
              ![
                'PENDING_RESERVE',
                'ACCEPTED',
                'REJECTED',
                'CANCEL_REQUESTED',
                'CANCELED',
                'PARTIALLY_FILLED',
                'FILLED',
              ].contains(order['status'])) {
            throw const FormatException('委托恢复资料不匹配');
          }
          confirmed = order['status'] != 'REJECTED';
        } on ApiException catch (error) {
          if (error.statusCode != 404) rethrow;
        }
      }
    }
    if (confirmed == null &&
        pending.clientAlgoOrderId == null &&
        pending.clientTriggerOrderId == null &&
        pending.cancelTriggerOrderId == null &&
        pending.ocoTakeProfitClientId == null &&
        pending.clientOrderId == null &&
        pending.cancelOrderId == null &&
        pending.amendRequestId == null &&
        pending.commandId != null) {
      final receipt = await api.get(
        '/api/v1/gateway/trading/commands/${Uri.encodeComponent(pending.commandId!)}',
        userId: pending.userId,
        productLine: pending.product.productLine,
      );
      if (receipt['commandId'] != pending.commandId) {
        throw const FormatException('委托回执不匹配');
      }
      // NOT_ACCEPTED here concerns the lookup, not the original trading command.
      if (receipt['outcome'] == 'TERMINAL' &&
          receipt['code'] is String &&
          asString(receipt['code']).isNotEmpty) {
        confirmed = receipt['code'] == 'NONE';
      }
    }
    return confirmed;
  }
}
