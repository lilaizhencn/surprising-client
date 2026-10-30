import 'i18n/client_messages.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'account_records.dart';
import 'app_state.dart';
import 'models.dart';

typedef _RecordFilters = ({
  String asset,
  String referenceType,
  String instrumentId,
  String status,
  DateTime? from,
  DateTime? to,
});

class FundingRecordsPage extends StatefulWidget {
  const FundingRecordsPage({
    required this.state,
    this.initialCategory = 'funding-ledger',
    this.initialInstrumentId = '',
    super.key,
  });
  final AppState state;
  final String initialCategory;
  final String initialInstrumentId;
  @override
  State<FundingRecordsPage> createState() => _FundingRecordsPageState();
}

class _FundingRecordsPageState extends State<FundingRecordsPage> {
  static const categories = {
    'funding-ledger': '资金账户流水',
    'product-ledger': '交易账户流水',
    'delivery-ledger': '交割现金流水',
    'option-exercise': '期权行权现金流水',
    'transfer': '账户划转',
    'funding-payment': '资金费',
    'deposit': '充值记录',
    'withdrawal': '提现记录',
    'external-transfer': '外部充提记录',
    'trade': '成交记录',
    'order': '历史委托',
  };
  String category = 'funding-ledger';
  ProductMode product = ProductMode.linear;
  final asset = TextEditingController(), reference = TextEditingController();
  final instrument = TextEditingController(), status = TextEditingController();
  DateTime? from, to;
  String? cursor, token, error;
  Map<String, String> scales = {};
  Map<String, Instrument> recordInstruments = {};
  List<Map<String, dynamic>> rows = [];
  bool loading = false;
  int generation = 0;
  _RecordFilters? appliedFilters;

  @override
  void initState() {
    super.initState();
    category = widget.initialCategory;
    instrument.text = widget.initialInstrumentId;
    product = widget.state.mode;
    if (category == 'option-exercise') product = ProductMode.option;
    if (category == 'delivery-ledger' &&
        product != ProductMode.linearDelivery &&
        product != ProductMode.inverseDelivery) {
      product = ProductMode.linearDelivery;
    }
    widget.state.addListener(_identityChanged);
    _identityChanged();
  }

  void _identityChanged() {
    final next = widget.state.session?.accessToken;
    if (next == token) return;
    token = next;
    generation++;
    setState(() {
      rows = [];
      cursor = null;
      scales = {};
      recordInstruments = {};
      appliedFilters = null;
      loading = false;
      error = null;
    });
    if (next != null) _load();
  }

  Future<void> _load({bool more = false}) async {
    final identity = token, id = widget.state.userId;
    if (identity == null ||
        id == null ||
        (more && (cursor == null || appliedFilters == null || loading))) {
      return;
    }
    if (!more && from != null && to != null && from!.isAfter(to!)) {
      generation++;
      setState(() {
        error = '开始日期不能晚于结束日期';
        loading = false;
        rows = [];
        cursor = null;
        appliedFilters = null;
        recordInstruments = {};
      });
      return;
    }
    final queryCategory = category, queryProduct = product;
    final filters = more
        ? appliedFilters!
        : (
            asset: asset.text.trim(),
            referenceType: reference.text.trim(),
            instrumentId: instrument.text.trim(),
            status: status.text.trim(),
            from: from,
            to: to == null
                ? null
                : DateTime(
                    to!.year,
                    to!.month,
                    to!.day + 1,
                  ).subtract(const Duration(milliseconds: 1)),
          );
    final version = ++generation;
    setState(() {
      loading = true;
      error = null;
      if (!more) {
        appliedFilters = filters;
        rows = [];
        cursor = null;
      }
    });
    try {
      final loadedScales = scales.isEmpty
          ? await widget.state.api.assetScales()
          : scales;
      if (!mounted ||
          version != generation ||
          identity != widget.state.session?.accessToken) {
        return;
      }
      scales = loadedScales;
      final page = await widget.state.api.accountRecords(
        category: queryCategory,
        userId: id,
        product: queryProduct,
        asset: filters.asset,
        referenceType: filters.referenceType,
        instrumentId: filters.instrumentId,
        status: filters.status,
        from: filters.from,
        to: filters.to,
        cursor: more ? cursor : null,
      );
      if (!mounted ||
          version != generation ||
          identity != widget.state.session?.accessToken) {
        return;
      }
      final metadata = more
          ? Map<String, Instrument>.of(recordInstruments)
          : <String, Instrument>{};
      if (queryCategory == 'order' || queryCategory == 'trade') {
        for (final row in page.rows) {
          final instrumentId = asString(row['instrumentId']);
          final key = '${queryProduct.productLine}:$instrumentId';
          if (metadata.containsKey(key)) continue;
          final known = widget.state.instruments
              .where(
                (i) => i.instrumentId == instrumentId && i.mode == queryProduct,
              )
              .firstOrNull;
          metadata[key] =
              known ??
              await widget.state.api.instrumentLatest(
                instrumentId,
                queryProduct,
              );
          if (!mounted ||
              version != generation ||
              identity != widget.state.session?.accessToken) {
            return;
          }
        }
      }
      setState(() {
        recordInstruments = metadata;
        String key(Map<String, dynamic> row) => queryCategory == 'order'
            ? '${row['orderId']}'
            : queryCategory == 'trade'
            ? '${row['tradeId']}:${row['liquidityRole']}:${row['orderId']}'
            : jsonEncode(row);
        rows = {
          for (final row in [if (more) ...rows, ...page.rows]) key(row): row,
        }.values.toList();
        cursor = page.hasMore ? page.nextCursor : null;
      });
    } catch (_) {
      if (mounted && version == generation) {
        setState(() => error = '记录暂时无法加载，请重试');
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  Future<void> _date(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (start ? from : to) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (!mounted || picked == null) return;
    setState(() {
      if (start) {
        from = picked;
      } else {
        to = picked;
      }
    });
  }

  bool _visible(Map<String, dynamic> row) {
    final filters = appliedFilters;
    if (filters == null) return false;
    final wantedAsset = filters.asset.toUpperCase();
    if (wantedAsset.isNotEmpty &&
        asString(
              row['asset'] ?? row['assetSymbol'] ?? row['currency'],
            ).toUpperCase() !=
            wantedAsset) {
      return false;
    }
    if (filters.referenceType.isNotEmpty &&
        asString(row['referenceType']).toUpperCase() !=
            filters.referenceType.toUpperCase()) {
      return false;
    }
    if (filters.instrumentId.isNotEmpty &&
        asString(row['instrumentId']) != filters.instrumentId) {
      return false;
    }
    final wantedStatus = filters.status.toUpperCase();
    if (wantedStatus.isNotEmpty &&
        asString(row['status']).toUpperCase() != wantedStatus) {
      return false;
    }
    final date = DateTime.tryParse(
      asString(
        row['createdAt'] ??
            row['updatedAt'] ??
            row['eventTime'] ??
            row['tradeTime'],
      ),
    );
    if (filters.from != null &&
        (date == null || date.isBefore(filters.from!))) {
      return false;
    }
    if (filters.to != null && (date == null || date.isAfter(filters.to!))) {
      return false;
    }
    return true;
  }

  Widget _record(Map<String, dynamic> row) {
    if (category == 'trade') {
      return _tradeRecord(
        row,
        recordInstruments['${product.productLine}:${row['instrumentId']}'],
      );
    }
    if (category == 'order') {
      return _orderRecord(
        row,
        recordInstruments['${product.productLine}:${row['instrumentId']}'],
      );
    }

    final contract = widget.state.instruments
        .where(
          (i) =>
              i.instrumentId == asString(row['instrumentId']) &&
              i.mode == product,
        )
        .firstOrNull;
    final currency = asString(
      row['asset'] ??
          row['assetSymbol'] ??
          row['currency'] ??
          row['settleAsset'],
    );
    String amount;
    if (row['amountUnits'] != null ||
        row['paymentUnits'] != null ||
        row['deltaUnits'] != null) {
      amount = formatAccountUnits(
        row['amountUnits'] ?? row['paymentUnits'] ?? row['deltaUnits'],
        scales[currency.toUpperCase()],
      );
    } else {
      amount = asString(row['amount'] ?? row['quantity'], fallback: '—');
    }
    final created =
        row['createdAt'] ??
        row['eventTime'] ??
        row['tradeTime'] ??
        row['updatedAt'] ??
        '—';
    final quantitySteps = parseInt64(row['quantitySteps']);
    final priceTicks = parseInt64(row['priceTicks']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '$currency $amount',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            LText(
              '${row['referenceType'] == 'DELIVERY_SETTLEMENT' ? '交割结算' : row['status'] ?? row['referenceType'] ?? row['side'] ?? '—'} · $created',
            ),
            if (category == 'delivery-ledger' &&
                row['balanceAfterUnits'] != null)
              LText(
                '变动后余额：${formatAccountUnits(row['balanceAfterUnits'], scales[currency.toUpperCase()])} $currency',
              ),
            if (row['sourceAccountType'] != null)
              Text(
                '${productAccountLabel(asString(row['sourceAccountType']))} → ${productAccountLabel(asString(row['targetAccountType']))}',
              ),
            if (row['instrumentId'] != null)
              LText(contract?.symbol ?? '合约 ${row['instrumentId']}'),
            if (row['quantitySteps'] != null)
              LText(
                contract == null || quantitySteps == null
                    ? '数量：—'
                    : contract.isSpot
                    ? '数量：${formatAccountUnits(BigInt.from(quantitySteps) * BigInt.from(contract.quantityStepUnits), scales[contract.baseAsset])} ${contract.baseAsset}'
                    : '数量：$quantitySteps 张',
              ),
            if (row['priceTicks'] != null)
              LText(
                '价格：${contract == null || priceTicks == null ? '—' : formatAccountUnits(BigInt.from(priceTicks) * BigInt.from(contract.priceTickUnits), scales[contract.quoteAsset])}',
              ),
            for (final pair in {
              'availableDeltaUnits': '可用余额变动',
              'lockedDeltaUnits': '冻结余额变动',
              'feeUnits': '手续费',
            }.entries)
              if (row[pair.key] != null)
                Text(
                  '${pair.value}：${formatAccountUnits(row[pair.key], scales[asString(row['feeAsset'] ?? currency).toUpperCase()])} ${row['feeAsset'] ?? currency}',
                ),
            for (final pair in <String, String>{
              'referenceId': '参考号',
              'transferId': '流水号',
              'orderId': '订单号',
              'transactionHash': '链上交易',
              'txHash': '链上交易',
              'toAddress': '收款地址',
            }.entries)
              if (row[pair.key] != null)
                SelectableText('${pair.value}：${row[pair.key]}'),
          ],
        ),
      ),
    );
  }

  Widget _orderRecord(Map<String, dynamic> row, Instrument? contract) {
    String quantity(String field) {
      final steps = parseInt64(row[field]);
      if (contract == null || steps == null) return '—';
      if (!contract.isSpot) return '$steps 张';
      return '${formatAccountUnits(BigInt.from(steps) * BigInt.from(contract.quantityStepUnits), scales[contract.baseAsset])} ${contract.baseAsset}';
    }

    String price(Object? ticks) => contract == null
        ? '—'
        : '${formatExecutionPrice(ticks, contract.priceTickUnits, scales[contract.quoteAsset])} ${contract.quoteAsset}';
    final feeAsset = contract == null
        ? null
        : contract.isSpot
        ? contract.quoteAsset
        : contract.settleAsset;
    final label =
        const {
          'FILLED': '全部成交',
          'CANCELED': '已撤销',
          'REJECTED': '已拒绝',
        }[row['status']] ??
        asString(row['status']);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LText(
              contract?.symbol ?? '合约 ${row['instrumentId']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            LText(
              '${row['side'] == 'BUY' ? '买入' : '卖出'} · ${row['orderType'] == 'MARKET' ? '市价' : '限价'} · $label',
            ),
            LText(
              '委托价格：${row['orderType'] == 'MARKET' ? '市价' : price(row['priceTicks'])}',
            ),
            LText(
              '成交均价：${asString(row['executedQuantitySteps']) == '0' ? '—' : price(row['averagePriceTicks'])}',
            ),
            LText('委托数量：${quantity('quantitySteps')}'),
            LText('已成交：${quantity('executedQuantitySteps')}'),
            LText('剩余：${quantity('remainingQuantitySteps')}'),
            LText(
              '累计手续费：${formatAccountUnits(row['cumulativeFeeUnits'], scales[feeAsset])}${feeAsset == null ? '' : ' $feeAsset'}',
            ),
            LText('有效方式：${row['timeInForce']}'),
            LText('创建时间：${row['createdAt']}'),
            LText('更新时间：${row['updatedAt']}'),
            SelectableText(clientLabel(context, '订单号：${row['orderId']}')),
          ],
        ),
      ),
    );
  }

  Widget _tradeRecord(Map<String, dynamic> row, Instrument? contract) {
    String amount(String field, int? step, String? asset) {
      final count = BigInt.tryParse('${row[field]}');
      if (count == null || step == null || step <= 0) return '—';
      return formatAccountUnits(count * BigInt.from(step), scales[asset]);
    }

    final price = amount(
      'priceTicks',
      contract?.priceTickUnits,
      contract?.quoteAsset,
    );
    final quantity = contract == null
        ? '—'
        : contract.isSpot
        ? '${amount('quantitySteps', contract.quantityStepUnits, contract.baseAsset)} ${contract.baseAsset}'
        : '${row['quantitySteps']} 张';
    final role = row['liquidityRole'] == 'MAKER' ? 'Maker' : 'Taker';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LText(
              contract?.symbol ?? '合约 ${row['instrumentId']}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            LText('${row['side'] == 'BUY' ? '买入' : '卖出'} · $role'),
            LText(
              '成交价：$price${contract == null ? '' : ' ${contract.quoteAsset}'}',
            ),
            LText('成交数量：$quantity'),
            LText('成交费率：${formatAccountUnits(row['feeRatePpm'], '10000')}%'),
            Text(asString(row['eventTime'], fallback: '—')),
            SelectableText(clientLabel(context, '订单号：${row['orderId']}')),
            SelectableText(clientLabel(context, '成交号：${row['tradeId']}')),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(_identityChanged);
    asset.dispose();
    reference.dispose();
    instrument.dispose();
    status.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const LText('资金与交易记录')),
    body: !widget.state.isLoggedIn
        ? const Center(child: LText('请先登录查看记录'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: category,
                  decoration: InputDecoration(
                    labelText: clientLabel(context, '记录类型'),
                  ),
                  items: categories.entries
                      .map(
                        (e) => DropdownMenuItem(
                          value: e.key,
                          child: LText(e.value),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() {
                      category = v;
                      if (v == 'option-exercise') product = ProductMode.option;
                      reference.clear();
                      asset.clear();
                      status.clear();
                      instrument.clear();
                      if (v == 'delivery-ledger' &&
                          product != ProductMode.linearDelivery &&
                          product != ProductMode.inverseDelivery) {
                        product = ProductMode.linearDelivery;
                      }
                      if (v == 'funding-payment' && !product.isPerpetual) {
                        product = ProductMode.linear;
                      }
                    });
                    _load();
                  },
                ),
                const SizedBox(height: 12),
                if ([
                  'product-ledger',
                  'delivery-ledger',
                  'option-exercise',
                  'transfer',
                  'funding-payment',
                  'trade',
                  'order',
                ].contains(category))
                  DropdownButtonFormField<ProductMode>(
                    key: ValueKey('$category:$product'),
                    initialValue: product,
                    decoration: InputDecoration(
                      labelText: clientLabel(context, '产品线'),
                    ),
                    items: ProductMode.values
                        .where(
                          (p) => category == 'option-exercise'
                              ? p.isOption
                              : category == 'delivery-ledger'
                              ? p == ProductMode.linearDelivery ||
                                    p == ProductMode.inverseDelivery
                              : category != 'funding-payment' || p.isPerpetual,
                        )
                        .map(
                          (p) =>
                              DropdownMenuItem(value: p, child: LText(p.label)),
                        )
                        .toList(),
                    onChanged: (p) {
                      if (p != null) {
                        setState(() {
                          product = p;
                          instrument.clear();
                        });
                        _load();
                      }
                    },
                  ),
                if (category != 'trade' && category != 'order')
                  TextField(
                    controller: asset,
                    decoration: InputDecoration(
                      labelText: clientLabel(context, '币种（可留空）'),
                    ),
                  ),
                if (category.endsWith('ledger'))
                  TextField(
                    controller: reference,
                    decoration: InputDecoration(
                      labelText: clientLabel(context, '流水类型（可留空）'),
                    ),
                  ),
                if (['funding-payment', 'trade', 'order'].contains(category))
                  TextField(
                    controller: instrument,
                    decoration: InputDecoration(
                      labelText: clientLabel(context, '合约 ID（可留空）'),
                    ),
                  ),
                if (category == 'order')
                  DropdownButtonFormField<String>(
                    key: ValueKey('history-status-${status.text}'),
                    initialValue: status.text,
                    decoration: InputDecoration(
                      labelText: clientLabel(context, '委托状态'),
                    ),
                    items: const [
                      DropdownMenuItem(value: '', child: LText('全部状态')),
                      DropdownMenuItem(value: 'FILLED', child: LText('全部成交')),
                      DropdownMenuItem(value: 'CANCELED', child: LText('已撤销')),
                      DropdownMenuItem(value: 'REJECTED', child: LText('已拒绝')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => status.text = value);
                    },
                  ),
                if (category != 'trade' && category != 'order')
                  TextField(
                    controller: status,
                    decoration: InputDecoration(
                      labelText: clientLabel(context, '状态（可留空）'),
                    ),
                  ),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton(
                      onPressed: () => _date(true),
                      child: LText(
                        from == null
                            ? '开始日期'
                            : '${from!.year}-${from!.month}-${from!.day}',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _date(false),
                      child: LText(
                        to == null
                            ? '结束日期'
                            : '${to!.year}-${to!.month}-${to!.day}',
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          from = null;
                          to = null;
                        });
                      },
                      child: const LText('清除日期'),
                    ),
                  ],
                ),
                FilledButton(
                  onPressed: loading
                      ? null
                      : () {
                          _load();
                        },
                  child: const LText('筛选 / 刷新'),
                ),
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: LText(error!),
                  ),
                if (!loading && error == null && rows.where(_visible).isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: LText('暂无相关记录'),
                  ),
                ...rows.where(_visible).map(_record),
                if (cursor != null)
                  OutlinedButton(
                    onPressed: loading ? null : () => _load(more: true),
                    child: const LText('加载更多'),
                  ),
              ],
            ),
          ),
  );
}
