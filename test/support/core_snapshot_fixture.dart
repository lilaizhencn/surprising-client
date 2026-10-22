/// Builds ordinary fixtures with the fields emitted by CoreUserStateView/UserReadView.
/// Negative boundary tests deliberately construct raw incomplete payloads instead.
Map<String, dynamic> completeCoreRow(String kind, Map<String, dynamic> row) => {
  if (kind != 'balance') 'instrumentId': row['symbol'] ?? '42',
  if (['position', 'order', 'trigger', 'risk'].contains(kind))
    'positionSide': 'NET',
  if (['position', 'order', 'trigger', 'leverage'].contains(kind))
    'marginMode': 'CROSS',
  if (kind == 'balance') 'lockedUnits': 0,
  if (kind == 'position') ...{
    'marginAsset': 'USDT',
    'entryPriceTicks': 100,
    'entryValueTicks': 0,
    'realizedPnlUnits': 0,
    'positionMarginUnits': 0,
  },
  if (kind == 'trigger') 'userId': 1,
  if (kind == 'order' || kind == 'trigger') ...{
    'side': 'BUY',
    'orderType': 'LIMIT',
    'timeInForce': 'GTC',
    'priceTicks': 100,
    'quantitySteps': 1,
  },
  if (kind == 'order') ...{
    'executedQuantitySteps': 0,
    'remainingQuantitySteps': 1,
    'cumulativeFeeUnits': 0,
  },
  if (kind == 'trigger') ...{
    'triggerType': 'TAKE_PROFIT',
    'triggerPriceTicks': 100,
    'activationPriceTicks': 0,
    'callbackRatePpm': 0,
    'highestPriceTicks': 0,
    'lowestPriceTicks': 0,
  },
  if (kind == 'risk') ...{
    'equityUnits': 0,
    'maintenanceMarginUnits': 0,
    'marginRatioPpm': 0,
    'status': 'NORMAL',
  },
  ...row,
};

List<dynamic> _rows(String kind, dynamic rows) => [
  for (final row in (rows as List? ?? []))
    completeCoreRow(kind, Map<String, dynamic>.from(row as Map)),
];

Map<String, dynamic> completeCoreSnapshot(Map<String, dynamic> message) {
  final data = Map<String, dynamic>.from(message['data'] as Map);
  final account = Map<String, dynamic>.from(data['account'] as Map);
  return {
    ...message,
    'data': {
      ...data,
      'account': {
        'positionMode': 'ONE_WAY',
        ...account,
        'balances': _rows('balance', account['balances']),
        'reservations': account['reservations'] ?? <dynamic>[],
        'positions': _rows('position', account['positions']),
        'leverages': account['leverages'] ?? <dynamic>[],
      },
      'openOrders': _rows('order', data['openOrders']),
      'triggerOrders': _rows('trigger', data['triggerOrders']),
      'positionRisks': _rows('risk', data['positionRisks']),
    },
  };
}

Map<String, dynamic> completeCoreEvent(Map<String, dynamic> message) {
  final data = Map<String, dynamic>.from(message['data'] as Map);
  final raw = data['value'];
  final value = switch (message['channel']) {
    'accountState' => {
      ...Map<String, dynamic>.from(raw as Map),
      if (raw.containsKey('balances'))
        'balances': _rows('balance', raw['balances']),
    },
    'positions' => {'positions': _rows('position', (raw as Map)['positions'])},
    'orders' => completeCoreRow('order', Map<String, dynamic>.from(raw as Map)),
    'triggerOrders' => _rows('trigger', raw),
    'positionRisk' || 'accountRisk' => completeCoreRow(
      'risk',
      Map<String, dynamic>.from(raw as Map),
    ),
    _ => raw,
  };
  return {
    ...message,
    'data': {...data, 'value': value},
  };
}
