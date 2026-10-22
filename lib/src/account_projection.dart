import 'models.dart';
import 'realtime_state.dart';

/// A read-only projection of one authoritative account snapshot and its marks.
/// No balances are invented when a field, scale, or valuation is unavailable.
class AccountProjection {
  const AccountProjection({
    required this.complete,
    required this.balances,
    required this.positions,
    required this.risks,
    required this.pnlByPosition,
  });

  final bool complete;
  final List<ProductBalance> balances;
  final List<Map<String, dynamic>> positions;
  final List<Map<String, dynamic>> risks;
  final Map<String, int> pnlByPosition;

  static AccountProjection? fromView({
    required ProductMode product,
    required PrivateView view,
    required List<Instrument> instruments,
    required int? Function(Instrument) markTicks,
    required int? Function(String) scaleFor,
  }) {
    try {
      var complete = view.ready;
      final cash = view.rows('balance');
      final equity = <String, BigInt>{};
      for (final balance in cash) {
        final asset = balance['asset'];
        if (asset is! String || asset.isEmpty) return null;
        equity[asset] =
            BigInt.from(
              requireInt64(balance['availableUnits'], 'availableUnits'),
            ) +
            BigInt.from(requireInt64(balance['lockedUnits'], 'lockedUnits'));
      }
      final positions = view
          .rows('position')
          .where(
            (position) =>
                requireInt64(
                  position['signedQuantitySteps'],
                  'signedQuantitySteps',
                ) !=
                0,
          )
          .toList();
      final risks = view.rows('risk');
      final pnlByPosition = <String, int>{};
      for (final position in positions) {
        final instrument = instruments
            .where(
              (candidate) =>
                  candidate.mode == product &&
                  candidate.symbol == position['symbol'] &&
                  (position['instrumentChangeId'] == null ||
                      candidate.changeId ==
                          requireInt64(
                            position['instrumentChangeId'],
                            'instrumentChangeId',
                          )),
            )
            .firstOrNull;
        final risk = risks
            .where(
              (candidate) => positionKey(candidate) == positionKey(position),
            )
            .firstOrNull;
        final valuation = instrument == null
            ? null
            : positionValuation(
                position,
                instrument,
                markTicks(instrument) ?? 0,
              );
        final riskPnl = risk == null
            ? null
            : parseInt64(risk['unrealizedPnlUnits']);
        final pnl = valuation?.pnl ?? (view.ready ? riskPnl : null);
        if (pnl != null && view.ready) {
          pnlByPosition[positionKey(position)] = pnl;
        }
        final contribution =
            valuation?.value ?? (!product.isOption ? riskPnl : null);
        final asset = position['marginAsset'];
        if (contribution == null ||
            asset is! String ||
            !equity.containsKey(asset)) {
          complete = false;
        } else {
          equity[asset] = equity[asset]! + BigInt.from(contribution);
        }
      }
      final balances = <ProductBalance>[];
      for (final balance in cash) {
        final asset = balance['asset'] as String;
        final amount = equity[asset]!;
        // Validate after exact accumulation: native int addition may wrap on VM.
        if (amount < BigInt.from(-9223372036854775808) ||
            amount > BigInt.from(9223372036854775807)) {
          return null;
        }
        final projected = ProductBalance(
          accountType: product.accountType,
          asset: asset,
          availableUnits: requireInt64(
            balance['availableUnits'],
            'availableUnits',
          ),
          lockedUnits: requireInt64(balance['lockedUnits'], 'lockedUnits'),
          equityUnits: amount.toInt(),
          scaleUnits: scaleFor(asset),
        );
        if (!projected.hasScale) complete = false;
        balances.add(projected);
      }
      return AccountProjection(
        complete: complete,
        balances: balances,
        positions: positions,
        risks: risks,
        pnlByPosition: pnlByPosition,
      );
    } on FormatException {
      return null;
    }
  }
}
