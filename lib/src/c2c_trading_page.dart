import 'i18n/client_messages.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'api.dart';
import 'app_scope.dart';
import 'app_state.dart';
import 'c2c_chat_page.dart';
import 'c2c_models.dart';
import 'c2c_trade_request.dart';
import 'models.dart';

class C2cTradingPage extends StatelessWidget {
  const C2cTradingPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context), owner = state.session?.user.userId;
    if (owner == null) return const C2cMessagingPage();
    return _Trading(key: ValueKey(owner), state: state, owner: owner);
  }
}

class _Trading extends StatefulWidget {
  const _Trading({super.key, required this.state, required this.owner});
  final AppState state;
  final int owner;
  @override
  State<_Trading> createState() => _TradingState();
}

class _TradingState extends State<_Trading> with WidgetsBindingObserver {
  int tab = 0, generation = 0, offerRequest = 0;
  String marketId = '',
      side = 'BUY',
      error = '',
      notice = '',
      receiptState = '';
  bool busy = false, loaded = false, enabled = true, visible = true;
  List<Map<String, dynamic>> markets = [],
      methods = [],
      accounts = [],
      offers = [],
      ads = [],
      orders = [];
  Map<String, dynamic> me = {}, bond = {};
  Map<String, dynamic>? selected, quote, order;
  C2cTradeRequest? pending;
  final quantity = TextEditingController(),
      email = TextEditingController(),
      totp = TextEditingController(),
      reason = TextEditingController();
  String paymentId = '';
  Timer? timer;
  bool get current =>
      mounted && widget.state.session?.user.userId == widget.owner;
  ApiClient get api => widget.state.api;
  Map<String, dynamic> get market =>
      markets.where((row) => row['marketId'] == marketId).firstOrNull ?? {};
  Map<String, dynamic> get verification => {
    'emailCode': email.text,
    'totpCode': totp.text,
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(load());
    timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (visible &&
          current &&
          !busy &&
          tab != 4 &&
          !widget.state.requiresBiometricUnlock) {
        unawaited(load());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    visible = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    for (final value in [quantity, email, totp, reason]) {
      value.dispose();
    }
    super.dispose();
  }

  Future<Map<String, dynamic>> get(String path, {Map<String, String>? query}) =>
      api.c2cBusinessGet(widget.owner, path, query: query);
  Future<Map<String, dynamic>> post(String path, Map<String, dynamic> body) =>
      api.c2cBusinessPost(widget.owner, path, body);
  Future<void> load() async {
    final run = ++generation;
    try {
      final status = await api.c2cStatus();
      if (!current || run != generation) return;
      if (status['runtimeEnabled'] != true) {
        setState(() {
          enabled = false;
          loaded = true;
        });
        return;
      }
      final values = await Future.wait([
        get('/markets'),
        get('/payment-accounts'),
        get('/me'),
        get('/me/merchant-bond'),
        get('/me/ads'),
        get('/orders', query: {'state': 'ALL'}),
      ]);
      final pendingBondKey = 'c2c.bond.${widget.owner}';
      final pendingBondId = await C2cTradeRequest.storage.read(
        key: pendingBondKey,
      );
      if (pendingBondId != null) {
        final known = asMap(values[3]['bond'])['requestId'] == pendingBondId
            ? values[3]
            : await get(
                '/me/merchant-bond',
                query: {'requestId': pendingBondId},
              );
        if (known['bond'] != null) {
          await C2cTradeRequest.storage.delete(key: pendingBondKey);
        }
      }
      final original = await C2cTradeRequest.load(widget.owner);
      if (!current || run != generation) return;
      setState(() {
        markets = asList(values[0]['markets']).map(asMap).toList();
        methods = asList(values[0]['paymentMethods']).map(asMap).toList();
        if (marketId.isEmpty && markets.isNotEmpty) {
          marketId = asString(markets.first['marketId']);
        }
        accounts = asList(values[1]['items']).map(asMap).toList();
        me = values[2];
        bond = values[3];
        ads = asList(values[4]['items']).map(asMap).toList();
        orders = asList(values[5]['items']).map(asMap).toList();
        if (order != null) {
          order = {
            ...order!,
            ...?orders
                .where((row) => row['orderId'] == order!['orderId'])
                .firstOrNull,
          };
        }
        pending = original;
        loaded = true;
      });
      if (tab == 0 && marketId.isNotEmpty && status['available'] == true) {
        await loadOffers(run);
      }
    } catch (failure) {
      if (current && run == generation) {
        setState(() {
          error = clientErrorMessage(failure);
          loaded = true;
        });
      }
    }
  }

  Future<void> loadOffers([int? run]) async {
    final request = ++offerRequest,
        requestedSide = side,
        requestedMarket = marketId;
    try {
      final page = await get(
        '/ads',
        query: {'marketId': requestedMarket, 'side': requestedSide},
      );
      if (current &&
          request == offerRequest &&
          requestedSide == side &&
          requestedMarket == marketId &&
          (run == null || run == generation)) {
        setState(() => offers = asList(page['items']).map(asMap).toList());
      }
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    }
  }

  Future<void> act(
    Future<void> Function() action, [
    String success = '操作已提交，请核对最新状态',
  ]) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
      notice = '';
    });
    try {
      await action();
      if (current) {
        setState(() => notice = success);
        await load();
      }
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: Text(title),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const LText('返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const LText('确认'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> receipt(C2cTradeRequest original) async {
    final value = await get(
      '/submissions/${original.key}',
      query: {'kind': original.kind, 'requestHash': original.hash},
    );
    if (!current) return;
    setState(() => receiptState = asString(value['status']));
    if (['SUCCEEDED', 'REJECTED', 'STOPPED'].contains(value['status'])) {
      await C2cTradeRequest.clear(widget.owner);
      if (!current) return;
      setState(() => pending = null);
      if (value['status'] == 'REJECTED') {
        throw StateError(
          asString(value['errorMessage'], fallback: '原请求未成交，请刷新后重新操作'),
        );
      }
      if (original.kind == 'ORDER_CREATE' && value['resultId'] != null) {
        final detail = await get('/orders/${value['resultId']}');
        if (current) {
          setState(() {
            order = detail;
            selected = null;
            quote = null;
            tab = 1;
          });
        }
      }
    }
  }

  Future<void> sendOriginal(C2cTradeRequest original) async {
    await post(original.kind == 'ORDER_CREATE' ? '/orders' : '/ads', {
      ...original.body,
      'verification': verification,
    });
    await receipt(original);
  }

  Future<void> submit(String kind, Map<String, dynamic> input) async {
    final original = await C2cTradeRequest.prepare(widget.owner, kind, input);
    if (!current) return;
    setState(() {
      pending = original;
      receiptState = '';
    });
    await sendOriginal(original);
  }

  Future<void> openOffer(Map<String, dynamic> row) async {
    final detail = await get('/ads/${row['adId']}');
    if (!current) return;
    final options = row['side'] == 'SELL'
        ? asList(detail['paymentOptions']).map(asMap).toList()
        : accounts
              .where(
                (a) =>
                    a['status'] == 'APPROVED' &&
                    a['fiat'] == asMap(row['market'])['fiat'],
              )
              .toList();
    setState(() {
      selected = detail;
      quote = null;
      quantity.clear();
      paymentId = options.isEmpty ? '' : asString(options.first['accountId']);
    });
  }

  Widget input(
    String title,
    TextEditingController controller, {
    bool decimal = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: TextField(
      controller: controller,
      onChanged: (_) {
        if (mounted) {
          setState(() {
            if (controller == quantity) quote = null;
          });
        }
      },
      keyboardType: decimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(labelText: title),
    ),
  );
  Widget button(
    String title,
    Future<void> Function() action, {
    bool disabled = false,
  }) => Padding(
    padding: const EdgeInsets.all(4),
    child: OutlinedButton(
      onPressed: busy || disabled ? null : () => unawaited(act(action)),
      child: Text(title),
    ),
  );
  Widget card(List<Widget> children) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    ),
  );
  Widget security([String scene = 'WITHDRAWAL']) => Column(
    children: [
      button('获取安全验证码', () async {
        await api.issueSecurityChallenge(scene);
      }),
      input('邮箱验证码', email),
      input('验证器验证码（已绑定时）', totp),
    ],
  );
  String amount(Object? units, Map<String, dynamic> m) => scaledAmount(
    BigInt.tryParse(asString(units)),
    int.tryParse(asString(m['assetScale'])),
  );
  @override
  Widget build(BuildContext context) {
    if (!loaded) return const Center(child: CircularProgressIndicator());
    if (!enabled) return const Center(child: LText('C2C 暂未开放'));
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ['自选交易', '我的订单', '商家中心', '收款账户', '消息']
                .asMap()
                .entries
                .map(
                  (entry) => TextButton(
                    onPressed: () {
                      setState(() => tab = entry.key);
                      if (tab != 4) unawaited(load());
                    },
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontWeight: tab == entry.key
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
        Expanded(
          child: tab == 4
              ? const C2cMessagingPage()
              : RefreshIndicator(
                  onRefresh: load,
                  child: ListView(
                    key: ValueKey('$tab-${order?['orderId'] ?? 'list'}'),
                    padding: const EdgeInsets.all(12),
                    children: [
                      if (error.isNotEmpty)
                        LText(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (notice.isNotEmpty) LText(notice),
                      if (pending != null)
                        card([
                          LText(
                            '原请求结果待确认${receiptState.isEmpty ? '' : '：$receiptState'}',
                          ),
                          button('查询原请求', () => receipt(pending!)),
                          button('停止未开始的请求', () async {
                            final original = pending!;
                            await post('/submissions/${original.key}/stop', {
                              'kind': original.kind,
                              'requestHash': original.hash,
                            });
                            await receipt(original);
                          }),
                          if (receiptState == 'UNKNOWN') security(),
                          if (receiptState == 'UNKNOWN')
                            button('按原请求重试', () => sendOriginal(pending!)),
                        ]),
                      if (tab == 0) ...marketView(),
                      if (tab == 1) ...orderList(),
                      if (tab == 2) ...merchantView(),
                      if (tab == 3) ...accountsView(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  List<Widget> marketView() => [
    Wrap(
      children: [
        ChoiceChip(
          label: const LText('我要买'),
          selected: side == 'BUY',
          onSelected: (_) {
            setState(() {
              side = 'BUY';
              selected = null;
              quote = null;
              offers = [];
            });
            unawaited(loadOffers());
          },
        ),
        const SizedBox(width: 12),
        ChoiceChip(
          label: const LText('我要卖'),
          selected: side == 'SELL',
          onSelected: (_) {
            setState(() {
              side = 'SELL';
              selected = null;
              quote = null;
              offers = [];
            });
            unawaited(loadOffers());
          },
        ),
      ],
    ),
    DropdownButton<String>(
      value: marketId.isEmpty ? null : marketId,
      isExpanded: true,
      hint: const LText('交易市场'),
      items: markets
          .map(
            (m) => DropdownMenuItem(
              value: asString(m['marketId']),
              child: Text('${m['asset']} / ${m['fiat']}'),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value == null) return;
        setState(() {
          marketId = value;
          selected = null;
        });
        unawaited(loadOffers());
      },
    ),
    if (offers.isEmpty)
      const Padding(padding: EdgeInsets.all(20), child: LText('暂无符合条件的广告')),
    ...offers.map(
      (ad) => card([
        LText(
          asString(
            asMap(ad['merchant'])['nickname'],
            fallback: '商家 ${ad['makerUserId']}',
          ),
        ),
        Text(
          '${c2cDecimal(asString(ad['price']))} ${asMap(ad['market'])['fiat']}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        LText('可交易 ${ad['availableQuantity']} ${asMap(ad['market'])['asset']}'),
        LText(
          '限额 ${c2cDecimal(asString(ad['minFiat']))} – ${c2cDecimal(asString(ad['maxFiat']))}',
        ),
        Text(asList(ad['methodCodes']).join(' · ')),
        button(
          ad['side'] == 'SELL' ? '购买' : '出售',
          () => openOffer(ad),
          disabled:
              pending != null || '${ad['makerUserId']}' == '${widget.owner}',
        ),
      ]),
    ),
    if (selected != null) ...quoteView(),
  ];
  List<Widget> quoteView() {
    final ad = selected!, m = asMap(ad['market']);
    final options = ad['side'] == 'SELL'
        ? asList(ad['paymentOptions']).map(asMap).toList()
        : accounts
              .where(
                (a) =>
                    a['status'] == 'APPROVED' &&
                    a['fiat'] == m['fiat'] &&
                    asList(ad['methodCodes']).contains(a['methodCode']),
              )
              .toList();
    return [
      card([
        LText('确认${ad['side'] == 'SELL' ? '购买' : '出售'} ${m['asset']}'),
        input('交易数量', quantity, decimal: true),
        DropdownButton<String>(
          isExpanded: true,
          value: options.any((a) => a['accountId'] == paymentId)
              ? paymentId
              : null,
          hint: const LText('收款方式'),
          items: options
              .map(
                (a) => DropdownMenuItem(
                  value: asString(a['accountId']),
                  child: Text('${a['methodCode']} ${a['maskedLabel']}'),
                ),
              )
              .toList(),
          onChanged: busy
              ? null
              : (value) => setState(() {
                  paymentId = value ?? '';
                  quote = null;
                }),
        ),
        button('获取报价', () async {
          final value = await post('/quotes', {
            'adId': ad['adId'],
            'amountType': 'CRYPTO',
            'amount': quantity.text,
            'paymentAccountId': paymentId,
          });
          if (current) setState(() => quote = value);
        }, disabled: pending != null || paymentId.isEmpty),
        if (quote != null) ...[
          LText(
            '付款 ${c2cDecimal(asString(quote!['fiatAmount']))} ${m['fiat']} · 数量 ${quote!['quantity']} ${m['asset']}',
          ),
          LText(
            '手续费 ${amount(quote!['buyerFeeUnits'], m)} · 买方实收 ${amount(quote!['buyerReceivesUnits'], m)}',
          ),
          LText('有效至 ${quote!['expiresAt']}'),
          if (ad['side'] == 'BUY') security(),
          button('确认下单', () async {
            if (await confirm('核对金额、费用及收款方式后确认下单？')) {
              await submit('ORDER_CREATE', {'quoteId': quote!['quoteId']});
            }
          }, disabled: pending != null || quote!['valid'] != true),
        ],
      ]),
    ];
  }

  List<Widget> orderList() => order != null
      ? orderView()
      : [
          if (orders.isEmpty) const LText('暂无订单'),
          ...orders.map(
            (row) => card([
              LText(
                '${row['buyerUserId']}' == '${widget.owner}'
                    ? '购买 ${row['quantity']}'
                    : '出售 ${row['quantity']}',
              ),
              Text(
                '${c2cDecimal(asString(row['fiatAmount']))} ${asMap(row['market'])['fiat']} · ${c2cOrderStatus(asString(row['status']))}',
              ),
              button('查看订单', () async {
                final detail = await get('/orders/${row['orderId']}');
                if (current) setState(() => order = detail);
              }),
            ]),
          ),
        ];
  List<Widget> orderView() {
    final row = order!,
        m = asMap(row['market']),
        buyer = '${row['buyerUserId']}' == '${widget.owner}';
    final state = asString(row['status']);
    return [
      card([
        LText(
          c2cOrderStatus(state),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        SelectableText(asString(row['orderId'])),
        Text(
          '${row['quantity']} ${m['asset']} · ${c2cDecimal(asString(row['fiatAmount']))} ${m['fiat']}',
        ),
        LText(
          '手续费 ${amount(row['buyerFeeUnits'], m)} · 买方实收 ${amount(row['buyerReceivesUnits'], m)}',
        ),
        if (row['paymentExpiresAt'] != null)
          LText('付款截止 ${row['paymentExpiresAt']}'),
        Text(asString(row['terms'])),
        button('查看本订单收款资料', () async {
          final detail = await get('/orders/${row['orderId']}');
          if (current) setState(() => order = detail);
        }),
        if (row['payment'] != null)
          ...['holderName', 'accountNumber', 'bankName', 'methodCode'].map(
            (key) => SelectableText(
              clientLabel(
                context,
                '${{'holderName': '姓名', 'accountNumber': '账号', 'bankName': '银行', 'methodCode': '方式'}[key]}：${asString(asMap(row['payment'])[key])}',
              ),
            ),
          ),
        if (state == 'PAYMENT_PENDING' && buyer) ...[
          const LText('请使用本人账户完成站外转账后再确认付款。'),
          button('我已付款，通知卖家', () async {
            if (await confirm('已按本订单收款资料实际完成付款？')) {
              await post('/orders/${row['orderId']}/paid', {'proofId': null});
            }
          }),
          button('取消未付款订单', () async {
            if (await confirm('确认取消未付款订单？已付款请勿取消。')) {
              await post('/orders/${row['orderId']}/cancel', {
                'reason': reason.text.isEmpty ? '买家取消未付款订单' : reason.text,
              });
            }
          }),
        ],
        if (state == 'PAID' && !buyer) ...[
          const LText('务必核对收款账户实际到账，再确认放币。'),
          security(),
          button('确认到账并放币', () async {
            if (await confirm('已核实实际到账，确认放币？')) {
              await post('/orders/${row['orderId']}/release', verification);
            }
          }),
        ],
        if (['PAYMENT_PENDING', 'PAID'].contains(state)) ...[
          input('申诉原因', reason),
          button('提交申诉', () async {
            await post('/orders/${row['orderId']}/appeal', {
              'reason': reason.text,
            });
          }, disabled: reason.text.trim().length < 5),
        ],
        button('返回订单列表', () async {
          setState(() => order = null);
        }),
        button('订单聊天', () async {
          final conversation = await api.c2cStart(
            widget.owner,
            orderId: asString(row['orderId']),
          );
          if (!mounted || !current) return;
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => C2cChatRoom(
                state: widget.state,
                owner: widget.owner,
                conversation: conversation,
              ),
            ),
          );
        }),
      ]),
    ];
  }

  List<Widget> merchantView() {
    final merchant = asMap(me['merchant']),
        rule = asMap(bond['policy']),
        pledge = asMap(bond['bond']);
    return [
      card([
        LText('商家资格：${merchant.isEmpty ? '未申请' : merchant['status']}'),
        LText('身份认证：${me['kycVerified'] == true ? '已认证' : '待认证'}'),
        if (merchant.isEmpty ||
            ['REJECTED', 'WITHDRAWN', 'PENDING'].contains(merchant['status']))
          button(
            '申请认证商家',
            () =>
                editForm('商家申请', {'application': '申请资料（至少十字）'}, (values) async {
                  await post('/me/merchant-application', {
                    'revision': merchant['revision'] ?? '0',
                    ...values,
                  });
                }),
          ),
        LText(
          rule['configured'] == true
              ? '保证金 ${rule['amount']} ${rule['asset']}'
              : '质押规则尚未配置',
        ),
        if (pledge.isNotEmpty)
          Text('${pledge['amount']} ${pledge['asset']} · ${pledge['status']}'),
        security(),
        button(
          '确认质押',
          () async {
            final key = 'c2c.bond.${widget.owner}';
            final id =
                await C2cTradeRequest.storage.read(key: key) ?? c2cUuid();
            await C2cTradeRequest.storage.write(key: key, value: id);
            await post('/me/merchant-bond', {
              'requestId': id,
              'policyRevision': rule['revision'],
              'verification': verification,
            });
            await C2cTradeRequest.storage.delete(key: key);
          },
          disabled:
              rule['configured'] != true ||
              !['PENDING', 'APPROVED'].contains(merchant['status']) ||
              pledge.isNotEmpty &&
                  !['FAILED', 'RETURNED'].contains(pledge['status']),
        ),
        if (pledge['status'] == 'LOCKED')
          button('退出商家并退押', () async {
            if (await confirm('须先关闭广告并结清订单、申诉，确认退出商家并退回原质押？')) {
              await post('/me/merchant-bonds/${pledge['bondId']}/withdraw', {});
            }
          }),
        button(
          '发布广告',
          publishAd,
          disabled:
              merchant['status'] != 'APPROVED' ||
              pledge['status'] != 'LOCKED' ||
              pending != null,
        ),
      ]),
      ...ads.map(
        (ad) => card([
          LText(
            '${ad['side'] == 'SELL' ? '商家出售' : '商家购买'} ${asMap(ad['market'])['asset']}',
          ),
          LText(
            '${ad['price']} · 剩余 ${ad['availableQuantity']} · ${ad['status']}',
          ),
          if (['ACTIVE', 'PAUSED'].contains(ad['status']))
            Wrap(
              children: [
                button(ad['status'] == 'ACTIVE' ? '暂停广告' : '恢复广告', () async {
                  await post('/ads/${ad['adId']}/status', {
                    'revision': ad['revision'],
                    'action': ad['status'] == 'ACTIVE' ? 'PAUSE' : 'RESUME',
                    'verification': verification,
                  });
                }),
                button('关闭广告', () async {
                  if (await confirm('确认关闭此广告？原订单继续履行。')) {
                    await post('/ads/${ad['adId']}/status', {
                      'revision': ad['revision'],
                      'action': 'CLOSE',
                      'verification': verification,
                    });
                  }
                }),
              ],
            ),
        ]),
      ),
    ];
  }

  Future<void> publishAd() async {
    if (market.isEmpty) throw StateError('请先选择交易市场');
    await editForm(
      '发布广告',
      {
        'side': '广告方向',
        'price': '单价',
        'quantity': '总数量',
        'minFiat': '最低法币金额',
        'maxFiat': '最高法币金额',
        'methodCode': '付款方式',
        'accountId': '本人已审核收款账户（出售时必选）',
        'terms': '交易条款',
      },
      (v) async {
        final direction = asString(v['side']).trim().toUpperCase(),
            method = asString(v['methodCode']).trim();
        if (!['SELL', 'BUY'].contains(direction)) {
          throw StateError('广告方向必须为 SELL 或 BUY');
        }
        final account = accounts
            .where(
              (a) =>
                  a['accountId'] == v['accountId'] && a['status'] == 'APPROVED',
            )
            .firstOrNull;
        if (direction == 'SELL' && account == null) {
          throw StateError('请选择本人已审核收款账户');
        }
        await submit('AD_PUBLISH', {
          'payload': {
            'marketId': marketId,
            'side': direction,
            'price': v['price'],
            'quantity': v['quantity'],
            'minFiat': v['minFiat'],
            'maxFiat': v['maxFiat'],
            'methodCodes': [
              direction == 'SELL' ? account!['methodCode'] : method,
            ],
            'paymentAccountIds': direction == 'SELL' ? [v['accountId']] : [],
            'paymentWindowSeconds': market['paymentWindowSeconds'],
            'terms': v['terms'],
            'minCompleted': 0,
          },
        });
      },
      choices: {
        'side': {'SELL': '商家出售', 'BUY': '商家购买'},
        'methodCode': {
          for (final method in methods)
            asString(method['code']): asString(method['label']),
        },
        'accountId': {
          for (final account in accounts.where(
            (a) => a['status'] == 'APPROVED' && a['fiat'] == market['fiat'],
          ))
            asString(account['accountId']):
                '${account['methodCode']} ${account['maskedLabel']}',
        },
      },
    );
  }

  List<Widget> accountsView() => [
    const LText('本人实名收款账户'),
    ...accounts.map(
      (account) => card([
        Text('${account['methodCode']} · ${account['fiat']}'),
        Text('${account['maskedLabel']} · ${account['status']}'),
        if (account['status'] != 'DISABLED')
          button('停用账户', () async {
            await post('/payment-accounts/${account['accountId']}/disable', {
              'revision': account['revision'],
              'verification': verification,
            });
          }),
      ]),
    ),
    security('SECURITY_SETTINGS'),
    button(
      '添加收款账户',
      () => editForm(
        '实名收款资料',
        {
          'methodCode': '收款方式',
          'holderName': '本人姓名',
          'accountNumber': '收款账号',
          'bankName': '银行名称（银行卡必填）',
        },
        (v) async {
          await post('/payment-accounts', {
            'accountId': null,
            'revision': '0',
            'fiat': market['fiat'],
            'methodCode': v['methodCode'],
            'details': {
              'holderName': v['holderName'],
              'accountNumber': v['accountNumber'],
              'bankName': v['bankName'],
              'qrAttachmentId': null,
            },
            'verification': verification,
          });
        },
        choices: {
          'methodCode': {
            for (final method in methods.where(
              (m) => asList(m['currencies']).contains(market['fiat']),
            ))
              asString(method['code']): asString(method['label']),
          },
        },
      ),
    ),
  ];
  Future<void> editForm(
    String title,
    Map<String, String> fields,
    Future<void> Function(Map<String, String>) save, {
    Map<String, Map<String, String>> choices = const {},
  }) async {
    final controllers = fields.map(
      (key, value) => MapEntry(key, TextEditingController()),
    );
    String? failure;
    bool saving = false;
    try {
      if (!current) return;
      await showDialog<void>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (_, update) => AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ...fields.entries.map(
                      (field) => choices.containsKey(field.key)
                          ? DropdownButtonFormField<String>(
                              decoration: InputDecoration(
                                labelText: field.value,
                              ),
                              isExpanded: true,
                              items: choices[field.key]!.entries
                                  .map(
                                    (option) => DropdownMenuItem(
                                      value: option.key,
                                      child: Text(
                                        option.value,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: saving
                                  ? null
                                  : (value) => controllers[field.key]!.text =
                                        value ?? '',
                            )
                          : input(field.value, controllers[field.key]!),
                    ),
                    if (failure != null)
                      LText(
                        failure!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const LText('取消'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        update(() => saving = true);
                        try {
                          await save(
                            controllers.map(
                              (key, value) => MapEntry(key, value.text.trim()),
                            ),
                          );
                          if (dialog.mounted) Navigator.pop(dialog);
                        } catch (error) {
                          if (dialog.mounted) {
                            update(() => failure = clientErrorMessage(error));
                          }
                        } finally {
                          if (dialog.mounted) update(() => saving = false);
                        }
                      },
                child: const LText('确认提交'),
              ),
            ],
          ),
        ),
      );
    } finally {
      for (final c in controllers.values) {
        c.dispose();
      }
    }
  }
}
