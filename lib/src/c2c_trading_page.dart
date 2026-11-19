import 'i18n/client_messages.dart';
import 'dart:async';
import 'dart:io' show File;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'api.dart';
import 'app_scope.dart';
import 'app_state.dart';
import 'auth/auth_sheet.dart';
import 'c2c_chat_page.dart';
import 'c2c_models.dart';
import 'c2c_trade_request.dart';
import 'models.dart';
import 'ui/theme/tokens.dart';

class C2cTradingPage extends StatelessWidget {
  const C2cTradingPage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context), owner = state.session?.user.userId;
    if (owner == null) return _PublicC2cPreview(state: state);
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
      orderScope = 'ONGOING',
      error = '',
      notice = '',
      receiptState = '';
  bool busy = false,
      loaded = false,
      enabled = true,
      visible = true,
      onlyPremium = false,
      onlyFreezeGuarantee = false;
  Set<String> selectedMethods = {};
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
      minAmount = TextEditingController(),
      maxAmount = TextEditingController(),
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
    for (final value in [quantity, minAmount, maxAmount, email, totp, reason]) {
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
        get('/orders', query: {'state': orderScope, 'limit': '30'}),
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
        orders = asList(values[5]['items']).map(asMap).toList()
          ..sort(
            (a, b) => asString(
              b['createdAt'] ?? b['updatedAt'],
            ).compareTo(asString(a['createdAt'] ?? a['updatedAt'])),
          );
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
      if (original != null) {
        unawaited(_reconcilePending(original));
      }
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
        query: {
          'marketId': requestedMarket,
          'side': requestedSide,
          if (selectedMethods.length == 1) 'methodCode': selectedMethods.first,
        },
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
    String? success,
  ]) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = '';
    });
    try {
      await action();
      if (current) {
        if (success != null && success.isNotEmpty && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: LText(success)),
          );
        }
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
  Future<void> _reconcilePending(C2cTradeRequest original) async {
    try {
      await receipt(original, pollAttempts: 2);
      if (current && pending != null && receiptState == 'UNKNOWN') {
        await C2cTradeRequest.clear(widget.owner);
        if (current) {
          setState(() {
            pending = null;
            receiptState = '';
          });
        }
      }
    } catch (_) {}
  }

  Future<void> receipt(
    C2cTradeRequest original, {
    int pollAttempts = 10,
  }) async {
    for (var attempt = 0; attempt < pollAttempts; attempt++) {
      final value = await get(
        '/submissions/${original.key}',
        query: {'kind': original.kind, 'requestHash': original.hash},
      );
      if (!current) return;
      final status = asString(value['status']);
      setState(() => receiptState = status);
      if (['SUCCEEDED', 'REJECTED', 'STOPPED'].contains(status)) {
        await C2cTradeRequest.clear(widget.owner);
        if (!current) return;
        setState(() => pending = null);
        if (status == 'REJECTED') {
          throw StateError(
            asString(value['errorMessage'], fallback: '下单未成功，请刷新后重试'),
          );
        }
        if (original.kind == 'ORDER_CREATE' && value['resultId'] != null) {
          final orderId = asString(value['resultId']);
          final detail = await get('/orders/$orderId');
          if (current) {
            setState(() {
              order = detail;
              selected = null;
              quote = null;
              tab = 1;
            });
          }
        }
        return;
      }
      if (status == 'UNKNOWN') return;
      if (attempt + 1 < pollAttempts) {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
  }

  Future<void> sendOriginal(C2cTradeRequest original) async {
    try {
      await post(original.kind == 'ORDER_CREATE' ? '/orders' : '/ads', {
        ...original.body,
        'verification': verification,
      });
    } on ApiException catch (failure) {
      if (failure.statusCode >= 400 && failure.statusCode < 500) {
        await C2cTradeRequest.clear(widget.owner);
        if (current) {
          setState(() {
            pending = null;
            receiptState = '';
          });
        }
      }
      rethrow;
    }
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
    if (!current || !mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _C2cTradeOrderSheet(
        ad: detail,
        accounts: accounts,
        methodLabel: _methodLabel,
        pendingBlocked: pending != null,
        onQuote: (amountText, paymentAccountId) => post('/quotes', {
          'adId': detail['adId'],
          'amountType': 'CRYPTO',
          'amount': amountText,
          'paymentAccountId': paymentAccountId,
        }),
        onIssueChallenge: () => api.issueSecurityChallenge('WITHDRAWAL'),
        onGoAccounts: () {
          Navigator.of(context).pop();
          setState(() => tab = 3);
        },
        onSubmitOrder: (quoteId, emailCode, totpCode) async {
          email.text = emailCode;
          totp.text = totpCode;
          await submit('ORDER_CREATE', {'quoteId': quoteId});
        },
      ),
    );
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
                    padding: EdgeInsets.fromLTRB(
                      12,
                      12,
                      12,
                      16 + MediaQuery.paddingOf(context).bottom,
                    ),
                    children: [
                      if (me['blacklisted'] == true) _blacklistBanner(),
                      if (error.isNotEmpty)
                        LText(
                          error,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      if (pending != null && receiptState != 'UNKNOWN')
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: LText('订单正在处理中，请稍候…'),
                                ),
                                TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => unawaited(
                                          act(() => receipt(pending!)),
                                        ),
                                  child: const LText('刷新'),
                                ),
                              ],
                            ),
                          ),
                        ),
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

  Widget _blacklistBanner() {
    final colors = Theme.of(context).colorScheme;
    final reasonText = asString(
      me['blacklistReason'],
      fallback: '由于您累计超过一次 C2C 订单付款超时未确认，当前仅可查看，不可发起下单。',
    );
    final appealStatus = asString(me['unblockAppealStatus']);
    final reviewNote = asString(me['unblockReviewNote']);
    return Card(
      color: colors.errorContainer,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'C2C 下单已受限：$reasonText',
              style: TextStyle(
                color: colors.onErrorContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (appealStatus == 'PENDING')
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '（解除申请审核中）',
                  style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
                ),
              ),
            if (appealStatus == 'REJECTED' && reviewNote.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '（上次申请未通过：$reviewNote）',
                  style: TextStyle(color: colors.onErrorContainer, fontSize: 12),
                ),
              ),
            if (appealStatus != 'PENDING')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: FilledButton.tonal(
                  onPressed: busy ? null : _openUnblockAppealDialog,
                  child: const LText('申请解除'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openUnblockAppealDialog() async {
    final controller = TextEditingController();
    final submitted = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LText('申请解除 C2C 限制'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: '申诉说明',
            hintText: '请说明超时原因及后续承诺（至少 5 个字）',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const LText('取消'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.length < 5) return;
              Navigator.pop(dialog, text);
            },
            child: const LText('提交申请'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (submitted != null && submitted.isNotEmpty) {
      await act(
        () => post('/me/unblock-appeal', {'reason': submitted}),
        '解除申请已提交，请等待审核',
      );
    }
  }

  String _methodLabel(String code) => asString(
    methods.where((m) => m['code'] == code).firstOrNull?['label'],
    fallback: code,
  );

  List<Widget> marketView() {
    final currentFiat = asString(market['fiat']);
    final availableMethods = methods
        .where(
          (m) =>
              currentFiat.isEmpty ||
              asList(m['currencies']).contains(currentFiat),
        )
        .toList();
    final minVal = double.tryParse(minAmount.text.trim());
    final maxVal = double.tryParse(maxAmount.text.trim());
    final visibleOffers = offers.where((ad) {
      final merchant = asMap(ad['merchant']);
      if (onlyPremium && merchant['premiumVerified'] != true) return false;
      if (onlyFreezeGuarantee && merchant['freezeCompensation'] != true) {
        return false;
      }
      if (selectedMethods.isNotEmpty) {
        final codes = asList(ad['methodCodes']).map((e) => '$e').toList();
        if (!codes.any(selectedMethods.contains)) return false;
      }
      final adMin = double.tryParse(asString(ad['minFiat']));
      final adMax = double.tryParse(asString(ad['maxFiat']));
      if (minVal != null && adMax != null && adMax < minVal) return false;
      if (maxVal != null && adMin != null && adMin > maxVal) return false;
      return true;
    }).toList();
    final blacklisted = me['blacklisted'] == true;
    return [
      _C2cSideTabs(
        side: side,
        onChanged: (nextSide) {
          if (nextSide == side) return;
          setState(() {
            side = nextSide;
            selected = null;
            quote = null;
            offers = [];
          });
          unawaited(loadOffers());
        },
      ),
      const SizedBox(height: 12),
      _C2cFilterBar(
        markets: markets,
        selectedMarketId: marketId,
        fiat: currentFiat,
        availableMethods: availableMethods,
        selectedMethods: selectedMethods,
        minAmount: minAmount,
        maxAmount: maxAmount,
        onlyPremium: onlyPremium,
        onlyFreezeGuarantee: onlyFreezeGuarantee,
        onMarketSelected: (value) {
          setState(() {
            marketId = value;
            selected = null;
            quote = null;
            selectedMethods.clear();
          });
          unawaited(loadOffers());
        },
        onMethodsChanged: (next) {
          setState(() => selectedMethods = next);
          unawaited(loadOffers());
        },
        onFiltersChanged: (premium, freeze) {
          setState(() {
            onlyPremium = premium;
            onlyFreezeGuarantee = freeze;
          });
        },
      ),
      const SizedBox(height: 12),
      if (visibleOffers.isEmpty)
        const Padding(padding: EdgeInsets.all(20), child: LText('暂无符合条件的广告')),
      ...visibleOffers.map(
        (ad) => _C2cAdCard(
          ad: ad,
          methodLabel: _methodLabel,
          disabled:
              blacklisted ||
              pending != null ||
              '${ad['makerUserId']}' == '${widget.owner}',
          onAction: () => unawaited(openOffer(ad)),
        ),
      ),
    ];
  }
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
        if (ad['side'] == 'BUY' && options.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '您尚未设置并审核通过支持该交易方式的收款账户，请先设置。',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          button('去设置收款方式', () async => setState(() => tab = 3)),
        ],
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
            final merchant = asMap(ad['merchant']);
            final chosen = options
                .where((a) => asString(a['accountId']) == paymentId)
                .firstOrNull;
            final methodText = chosen == null
                ? paymentId
                : '${_methodLabel(asString(chosen['methodCode']))} ${chosen['maskedLabel']}';
            final badges = [
              if (merchant['premiumVerified'] == true) '优质商户',
              if (merchant['freezeCompensation'] == true) '冻结必赔',
            ].join(' · ');
            final windowMins =
                ((int.tryParse(asString(m['paymentWindowSeconds'])) ?? 900) /
                        60)
                    .round()
                    .clamp(1, 60);
            final ok = await showDialog<bool>(
              context: context,
              builder: (dialog) => AlertDialog(
                title: const LText('确认下单并遵守交易规则'),
                content: Text(
                  '商户：${asString(merchant['nickname'], fallback: '商家 ${ad['makerUserId']}')}${badges.isEmpty ? '' : '（$badges）'}\n'
                  '收付款方式：$methodText\n'
                  '金额：${c2cDecimal(asString(quote!['fiatAmount']))} ${m['fiat']}（数量：${quote!['quantity']} ${m['asset']}）\n'
                  '付款有效期：$windowMins 分钟\n\n'
                  '重要提醒：请在有效期内完成付款并点击确认；未及时付款或未点击确认导致超时，将冻结相关币种；若累计超过一次超时违约，将被系统拉黑（禁止 C2C 下单，仅可查看）。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialog, false),
                    child: const LText('返回'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialog, true),
                    child: const LText('我已知晓，确认下单'),
                  ),
                ],
              ),
            );
            if (ok == true) {
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
          Wrap(
            spacing: 8,
            children: [
              for (final entry in const [
                ('ONGOING', '实时订单'),
                ('ENDED', '已结束'),
                ('APPEALED', '争议单'),
              ])
                ChoiceChip(
                  label: LText(entry.$2),
                  selected: orderScope == entry.$1,
                  onSelected: (_) {
                    if (orderScope == entry.$1) return;
                    setState(() {
                      orderScope = entry.$1;
                      orders = [];
                    });
                    unawaited(load());
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
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
    final payment = asMap(row['payment']);
    final t = context.tokens;
    final colors = Theme.of(context).colorScheme;
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.bgElevated1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: t.borderDefault.withValues(alpha: 0.7),
            width: 0.7,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: LText(
                    c2cOrderStatus(state),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (state == 'PAYMENT_PENDING' &&
                    row['paymentExpiresAt'] != null)
                  _CountdownText(
                    expiresAtIso: asString(row['paymentExpiresAt']),
                    serverTimeIso: nullableString(row['serverTime']),
                    prefix: '剩余 ',
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${buyer ? '购买' : '出售'} ${row['quantity']} ${m['asset']} · ${c2cDecimal(asString(row['fiatAmount']))} ${m['fiat']}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 4),
            LText(
              '单价 ${c2cDecimal(asString(row['price']))} ${m['fiat']} · 手续费 ${amount(row['buyerFeeUnits'], m)} · 买方实收 ${amount(row['buyerReceivesUnits'], m)}',
              style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '订单号 ${row['orderId']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 15),
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () {
                    unawaited(
                      Clipboard.setData(
                        ClipboardData(text: asString(row['orderId'])),
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: LText('已复制订单号')),
                    );
                  },
                ),
              ],
            ),
            if (asString(row['terms']).isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                asString(row['terms']),
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
            ],
            if (buyer && payment.isNotEmpty) ...[
              const Divider(height: 20),
              const LText(
                '对方收款信息',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              _CopyableDetailRow(
                label: '收款方式',
                value: _methodLabel(asString(payment['methodCode'])),
              ),
              _CopyableDetailRow(
                label: '收款人姓名',
                value: asString(payment['holderName']),
              ),
              _CopyableDetailRow(
                label: '收款账号',
                value: asString(payment['accountNumber']),
              ),
              if (asString(payment['bankName']).isNotEmpty)
                _CopyableDetailRow(
                  label: '开户行',
                  value: asString(payment['bankName']),
                ),
            ],
            if (state == 'PAYMENT_PENDING' && buyer) ...[
              const SizedBox(height: 12),
              Text(
                '请使用本人实名账户向上述收款信息完成转账，转账完成后请点击下方“我已付款”。',
                style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: colors.tertiary,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(44),
                  shape: const StadiumBorder(),
                ),
                onPressed: busy
                    ? null
                    : () => unawaited(
                        act(() async {
                          if (await confirm('已按本订单收款资料实际完成付款？')) {
                            await post('/orders/${row['orderId']}/paid', {
                              'proofId': null,
                            });
                            final detail = await get(
                              '/orders/${row['orderId']}',
                            );
                            if (current) setState(() => order = detail);
                          }
                        }, '已标记为已付款，等待卖家放币'),
                      ),
                child: const LText('我已付款'),
              ),
              const SizedBox(height: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(42),
                  shape: const StadiumBorder(),
                ),
                onPressed: busy
                    ? null
                    : () => unawaited(
                        act(() async {
                          if (await confirm('确认取消未付款订单？已付款请勿取消。')) {
                            await post('/orders/${row['orderId']}/cancel', {
                              'reason': reason.text.isEmpty
                                  ? '买家取消未付款订单'
                                  : reason.text,
                            });
                            final detail = await get(
                              '/orders/${row['orderId']}',
                            );
                            if (current) setState(() => order = detail);
                          }
                        }, '订单已取消'),
                      ),
                child: const LText('取消未付款订单'),
              ),
            ],
            if (state == 'PAID' && !buyer) ...[
              const Divider(height: 20),
              const LText('务必核对收款账户实际到账，再确认放币。'),
              security(),
              const SizedBox(height: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  shape: const StadiumBorder(),
                ),
                onPressed: busy
                    ? null
                    : () => unawaited(
                        act(() async {
                          if (await confirm('已核实实际到账，确认放币？')) {
                            await post(
                              '/orders/${row['orderId']}/release',
                              verification,
                            );
                            final detail = await get(
                              '/orders/${row['orderId']}',
                            );
                            if (current) setState(() => order = detail);
                          }
                        }, '已确认放币'),
                      ),
                child: const LText('确认到账并放币'),
              ),
            ],
            if (['PAYMENT_PENDING', 'PAID'].contains(state)) ...[
              const SizedBox(height: 10),
              input('申诉原因', reason),
              button('提交申诉', () async {
                await post('/orders/${row['orderId']}/appeal', {
                  'reason': reason.text,
                });
                final detail = await get('/orders/${row['orderId']}');
                if (current) setState(() => order = detail);
              }, disabled: reason.text.trim().length < 5),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => setState(() => order = null),
                    child: const LText('返回订单列表'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonalIcon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 17),
                    label: const LText('订单聊天'),
                    onPressed: () async {
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
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

  String _accountStatusLabel(String status) => switch (status) {
    'APPROVED' => '已通过',
    'PENDING' => '待审核',
    'REJECTED' => '未通过',
    'DISABLED' => '已停用',
    _ => status,
  };

  IconData _methodIcon(String code) => switch (code) {
    'ALIPAY' => Icons.account_balance_wallet_outlined,
    'WECHAT' => Icons.chat_bubble_outline,
    _ => Icons.account_balance_outlined,
  };

  Color _methodColor(String code) => switch (code) {
    'ALIPAY' => const Color(0xFF1677FF),
    'WECHAT' => const Color(0xFF07C160),
    _ => const Color(0xFFF59E0B),
  };

  List<Widget> accountsView() {
    final t = context.tokens;
    final colors = Theme.of(context).colorScheme;
    return [
      Row(
        children: [
          const Expanded(
            child: LText(
              '本人实名收款账户',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF00D2FF),
                  Color(0xFF6366F1),
                  Color(0xFFEC4899),
                ],
              ),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: busy ? null : () => unawaited(_openPaymentAccountForm()),
                child: const SizedBox(
                  width: 36,
                  height: 36,
                  child: Icon(Icons.add, color: Colors.white, size: 22),
                ),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      if (accounts.isEmpty)
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: t.bgElevated1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: t.borderDefault.withValues(alpha: 0.65),
              width: 0.6,
            ),
          ),
          child: const Center(
            child: LText('暂无收款账户，点击右上角 + 添加'),
          ),
        ),
      for (final account in accounts)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: busy
                ? null
                : () => unawaited(
                    _openPaymentAccountDetail(asString(account['accountId'])),
                  ),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.bgElevated1,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: t.borderDefault.withValues(alpha: 0.65),
                  width: 0.6,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _methodColor(
                        asString(account['methodCode']),
                      ).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _methodIcon(asString(account['methodCode'])),
                      color: _methodColor(asString(account['methodCode'])),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '${_methodLabel(asString(account['methodCode']))} · ${account['fiat']}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (account['status'] == 'APPROVED'
                                        ? colors.tertiary
                                        : account['status'] == 'REJECTED' ||
                                              account['status'] == 'DISABLED'
                                        ? colors.error
                                        : colors.primary)
                                    .withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: LText(
                                _accountStatusLabel(asString(account['status'])),
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w600,
                                  color: account['status'] == 'APPROVED'
                                      ? colors.tertiary
                                      : account['status'] == 'REJECTED' ||
                                            account['status'] == 'DISABLED'
                                      ? colors.error
                                      : colors.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          asString(account['maskedLabel']),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: colors.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
    ];
  }

  Future<void> _openPaymentAccountDetail(String accountId) async {
    try {
      final detail = await get('/payment-accounts/$accountId');
      if (!current || !mounted) return;
      final colors = Theme.of(context).colorScheme;
      final qrId = nullableString(detail['qrAttachmentId']);
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      _methodIcon(asString(detail['methodCode'])),
                      color: _methodColor(asString(detail['methodCode'])),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${_methodLabel(asString(detail['methodCode']))} · ${detail['fiat']}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    LText(
                      _accountStatusLabel(asString(detail['status'])),
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
                const Divider(height: 20),
                _CopyableDetailRow(
                  label: '本人姓名',
                  value: asString(detail['holderName']),
                ),
                _CopyableDetailRow(
                  label: '收款账号',
                  value: asString(detail['accountNumber']),
                ),
                if (asString(detail['bankName']).isNotEmpty)
                  _CopyableDetailRow(
                    label: '开户行',
                    value: asString(detail['bankName']),
                  ),
                if (qrId != null && qrId.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const LText(
                    '收款二维码',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Center(
                    child: FutureBuilder(
                      future: api.c2cDownload(widget.owner, qrId),
                      builder: (context, snapshot) {
                        if (snapshot.hasData) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              snapshot.data!,
                              width: 180,
                              height: 180,
                              fit: BoxFit.contain,
                            ),
                          );
                        }
                        if (snapshot.hasError) {
                          return const LText('二维码加载失败');
                        }
                        return const SizedBox.square(
                          dimension: 120,
                          child: Center(child: CircularProgressIndicator()),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    if (detail['status'] != 'DISABLED') ...[
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colors.error,
                            side: BorderSide(color: colors.error),
                            minimumSize: const Size.fromHeight(44),
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () {
                            Navigator.pop(sheet);
                            unawaited(_deletePaymentAccount(detail));
                          },
                          child: const LText('删除'),
                        ),
                      ),
                      const SizedBox(width: 10),
                    ],
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          Navigator.pop(sheet);
                          unawaited(_openPaymentAccountForm(existing: detail));
                        },
                        child: const LText('更新'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (failure) {
      if (current) setState(() => error = clientErrorMessage(failure));
    }
  }

  Future<void> _deletePaymentAccount(Map<String, dynamic> detail) async {
    final emailCtrl = TextEditingController();
    final totpCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const LText('确认删除该收款账户？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${_methodLabel(asString(detail['methodCode']))} · ${detail['accountNumber'] ?? detail['maskedLabel']}',
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () =>
                  unawaited(api.issueSecurityChallenge('SECURITY_SETTINGS')),
              child: const LText('获取安全验证码'),
            ),
            TextField(
              controller: emailCtrl,
              decoration: const InputDecoration(labelText: '邮箱验证码'),
            ),
            TextField(
              controller: totpCtrl,
              decoration: const InputDecoration(labelText: '验证器验证码（已绑定时）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const LText('返回'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialog, true),
            child: const LText('确认删除'),
          ),
        ],
      ),
    );
    final emailCode = emailCtrl.text.trim();
    final totpCode = totpCtrl.text.trim();
    emailCtrl.dispose();
    totpCtrl.dispose();
    if (ok == true) {
      await act(
        () => post('/payment-accounts/${detail['accountId']}/disable', {
          'revision': detail['revision'],
          'verification': {'emailCode': emailCode, 'totpCode': totpCode},
        }),
        '收款账户已删除',
      );
    }
  }

  Future<void> _openPaymentAccountForm({Map<String, dynamic>? existing}) async {
    final isEdit = existing != null;
    final fiats = markets
        .map((m) => asString(m['fiat']))
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList();
    var selectedFiat = asString(
      existing?['fiat'],
      fallback: asString(market['fiat'], fallback: fiats.firstOrNull ?? 'CNY'),
    );
    var selectedMethod = asString(existing?['methodCode']);
    final holderCtrl = TextEditingController(
      text: asString(existing?['holderName']),
    );
    final accountCtrl = TextEditingController(
      text: asString(existing?['accountNumber']),
    );
    final bankCtrl = TextEditingController(
      text: asString(existing?['bankName']),
    );
    final emailCtrl = TextEditingController();
    final totpCtrl = TextEditingController();
    String? qrAttachmentId = nullableString(existing?['qrAttachmentId']);
    Uint8List? qrPreviewBytes;
    var uploadingQr = false;
    String? formError;
    var saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheetState) {
          final fiatMethods = methods
              .where(
                (m) =>
                    selectedFiat.isEmpty ||
                    asList(m['currencies']).contains(selectedFiat),
              )
              .toList();
          if (!fiatMethods.any((m) => asString(m['code']) == selectedMethod)) {
            selectedMethod = asString(fiatMethods.firstOrNull?['code']);
          }
          final activeMethodObj = fiatMethods
              .where((m) => asString(m['code']) == selectedMethod)
              .firstOrNull;
          final requiresBank = activeMethodObj?['requiresBankName'] == true;
          final supportsQr =
              activeMethodObj?['supportsQr'] == true ||
              ['ALIPAY', 'WECHAT'].contains(selectedMethod);
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
              top: false,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.88,
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(
                    18,
                    0,
                    18,
                    20 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: LText(
                              isEdit ? '更新收款账户' : '添加收款账户',
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '关闭',
                            onPressed: saving
                                ? null
                                : () => Navigator.of(sheet).pop(),
                            icon: const Icon(Icons.close, size: 22),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: fiats.contains(selectedFiat)
                            ? selectedFiat
                            : null,
                        decoration: const InputDecoration(
                          labelText: '法币币种',
                          isDense: true,
                        ),
                        items: fiats
                            .map(
                              (f) => DropdownMenuItem(value: f, child: Text(f)),
                            )
                            .toList(),
                        onChanged: isEdit
                            ? null
                            : (v) => setSheetState(
                                () => selectedFiat = v ?? selectedFiat,
                              ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue:
                            fiatMethods.any(
                              (m) => asString(m['code']) == selectedMethod,
                            )
                            ? selectedMethod
                            : null,
                        decoration: const InputDecoration(
                          labelText: '收款方式',
                          isDense: true,
                        ),
                        items: fiatMethods
                            .map(
                              (m) => DropdownMenuItem(
                                value: asString(m['code']),
                                child: Text(
                                  asString(
                                    m['label'],
                                    fallback: asString(m['code']),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: isEdit
                            ? null
                            : (v) => setSheetState(
                                () => selectedMethod = v ?? selectedMethod,
                              ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: holderCtrl,
                        decoration: const InputDecoration(labelText: '本人姓名'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: accountCtrl,
                        decoration: const InputDecoration(labelText: '收款账号'),
                      ),
                      if (requiresBank || bankCtrl.text.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: bankCtrl,
                          decoration: const InputDecoration(
                            labelText: '银行名称（银行转账必填）',
                          ),
                        ),
                      ],
                      if (supportsQr) ...[
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size.fromHeight(42),
                                  shape: const StadiumBorder(),
                                ),
                                onPressed: uploadingQr || saving
                                    ? null
                                    : () async {
                                        FocusScope.of(context).unfocus();
                                        final file = await FilePicker.pickFile(
                                          type: FileType.custom,
                                          allowedExtensions: const [
                                            'jpg',
                                            'jpeg',
                                            'png',
                                          ],
                                        );
                                        final path = file?.path;
                                        if (file == null || path == null) {
                                          return;
                                        }
                                        final bytes = await File(
                                          path,
                                        ).readAsBytes();
                                        final lower = file.name.toLowerCase();
                                        final mime = lower.endsWith('.png')
                                            ? 'image/png'
                                            : 'image/jpeg';
                                        setSheetState(() {
                                          uploadingQr = true;
                                          formError = null;
                                        });
                                        try {
                                          final uploaded = await api
                                              .c2cUploadPaymentQr(
                                                widget.owner,
                                                c2cUuid(),
                                                file.name,
                                                mime,
                                                bytes,
                                              );
                                          if (sheet.mounted) {
                                            setSheetState(() {
                                              qrAttachmentId = uploaded.id;
                                              qrPreviewBytes = bytes;
                                            });
                                          }
                                        } catch (e) {
                                          if (sheet.mounted) {
                                            setSheetState(
                                              () => formError =
                                                  clientErrorMessage(e),
                                            );
                                          }
                                        } finally {
                                          if (sheet.mounted) {
                                            setSheetState(
                                              () => uploadingQr = false,
                                            );
                                          }
                                        }
                                      },
                                icon: uploadingQr
                                    ? const SizedBox.square(
                                        dimension: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.qr_code_2, size: 18),
                                label: LText(
                                  uploadingQr
                                      ? '上传中…'
                                      : (qrAttachmentId != null
                                            ? '更换收款二维码'
                                            : '上传收款二维码'),
                                ),
                              ),
                            ),
                            if (qrAttachmentId != null) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                tooltip: '清除二维码',
                                onPressed: uploadingQr || saving
                                    ? null
                                    : () => setSheetState(() {
                                        qrAttachmentId = null;
                                        qrPreviewBytes = null;
                                      }),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ],
                        ),
                        if (qrPreviewBytes != null) ...[
                          const SizedBox(height: 8),
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: Image.memory(
                                qrPreviewBytes!,
                                width: 120,
                                height: 120,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ],
                      ],
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(42),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: () {
                          FocusScope.of(context).unfocus();
                          unawaited(
                            api.issueSecurityChallenge('SECURITY_SETTINGS'),
                          );
                        },
                        child: const LText('获取安全验证码'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: emailCtrl,
                        decoration: const InputDecoration(labelText: '邮箱验证码'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: totpCtrl,
                        decoration: const InputDecoration(
                          labelText: '验证器验证码（已绑定时）',
                        ),
                      ),
                      if (formError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          formError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(46),
                          shape: const StadiumBorder(),
                        ),
                        onPressed: saving || uploadingQr
                            ? null
                            : () async {
                                FocusScope.of(context).unfocus();
                                setSheetState(() {
                                  saving = true;
                                  formError = null;
                                });
                                try {
                                  await post('/payment-accounts', {
                                    'accountId': isEdit
                                        ? existing['accountId']
                                        : null,
                                    'revision': isEdit
                                        ? existing['revision']
                                        : '0',
                                    'fiat': selectedFiat,
                                    'methodCode': selectedMethod,
                                    'details': {
                                      'holderName': holderCtrl.text.trim(),
                                      'accountNumber': accountCtrl.text.trim(),
                                      'bankName': bankCtrl.text.trim(),
                                      'qrAttachmentId': qrAttachmentId,
                                    },
                                    'verification': {
                                      'emailCode': emailCtrl.text.trim(),
                                      'totpCode': totpCtrl.text.trim(),
                                    },
                                  });
                                  if (sheet.mounted) Navigator.pop(sheet);
                                  await load();
                                } catch (e) {
                                  if (sheet.mounted) {
                                    setSheetState(
                                      () => formError = clientErrorMessage(e),
                                    );
                                  }
                                } finally {
                                  if (sheet.mounted) {
                                    setSheetState(() => saving = false);
                                  }
                                }
                              },
                        child: LText(
                          saving ? '保存中…' : (isEdit ? '更新收款账户' : '保存收款账户'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    holderCtrl.dispose();
    accountCtrl.dispose();
    bankCtrl.dispose();
    emailCtrl.dispose();
    totpCtrl.dispose();
  }
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

class _PublicC2cPreview extends StatefulWidget {
  const _PublicC2cPreview({required this.state});
  final AppState state;

  @override
  State<_PublicC2cPreview> createState() => _PublicC2cPreviewState();
}

class _PublicC2cPreviewState extends State<_PublicC2cPreview> {
  bool loading = true, enabled = true;
  String marketId = '', side = 'BUY', error = '';
  bool onlyPremium = false, onlyFreezeGuarantee = false;
  Set<String> selectedMethods = {};
  List<Map<String, dynamic>> markets = [], methods = [], offers = [];
  final minAmount = TextEditingController();
  final maxAmount = TextEditingController();

  ApiClient get api => widget.state.api;
  Map<String, dynamic> get market =>
      markets.where((row) => row['marketId'] == marketId).firstOrNull ?? {};

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  @override
  void dispose() {
    minAmount.dispose();
    maxAmount.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = '';
    });
    try {
      final status = await api.c2cStatus();
      if (!mounted) return;
      if (status['runtimeEnabled'] != true || status['available'] != true) {
        setState(() {
          enabled = false;
          loading = false;
        });
        return;
      }
      final catalog = await api.c2cPublicMarkets();
      if (!mounted) return;
      final loadedMarkets = asList(catalog['markets']).map(asMap).toList();
      final nextMarketId =
          loadedMarkets.any((m) => m['marketId'] == marketId)
          ? marketId
          : asString(loadedMarkets.firstOrNull?['marketId']);
      setState(() {
        enabled = true;
        markets = loadedMarkets;
        methods = asList(catalog['paymentMethods']).map(asMap).toList();
        marketId = nextMarketId;
        loading = false;
      });
      if (nextMarketId.isNotEmpty) {
        await loadOffers();
      }
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = clientErrorMessage(failure);
          loading = false;
        });
      }
    }
  }

  Future<void> loadOffers() async {
    if (marketId.isEmpty) return;
    try {
      final page = await api.c2cPublicAds(
        marketId: marketId,
        side: side,
        methodCode: selectedMethods.length == 1 ? selectedMethods.first : null,
      );
      if (mounted) {
        setState(() => offers = asList(page['items']).map(asMap).toList());
      }
    } catch (failure) {
      if (mounted) setState(() => error = clientErrorMessage(failure));
    }
  }

  String _methodLabel(String code) => asString(
    methods.where((m) => m['code'] == code).firstOrNull?['label'],
    fallback: code,
  );

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (!enabled) return const Center(child: LText('C2C 市场暂未开放'));
    final currentFiat = asString(market['fiat']);
    final availableMethods = methods
        .where(
          (m) =>
              currentFiat.isEmpty ||
              asList(m['currencies']).contains(currentFiat),
        )
        .toList();
    final minVal = double.tryParse(minAmount.text.trim());
    final maxVal = double.tryParse(maxAmount.text.trim());
    final visibleOffers = offers.where((ad) {
      final merchant = asMap(ad['merchant']);
      if (onlyPremium && merchant['premiumVerified'] != true) return false;
      if (onlyFreezeGuarantee && merchant['freezeCompensation'] != true) {
        return false;
      }
      if (selectedMethods.isNotEmpty) {
        final codes = asList(ad['methodCodes']).map((e) => '$e').toList();
        if (!codes.any(selectedMethods.contains)) return false;
      }
      final adMin = double.tryParse(asString(ad['minFiat']));
      final adMax = double.tryParse(asString(ad['maxFiat']));
      if (minVal != null && adMax != null && adMax < minVal) return false;
      if (maxVal != null && adMin != null && adMin > maxVal) return false;
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: load,
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          12,
          12,
          12,
          16 + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: LText(
                error,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          _C2cSideTabs(
            side: side,
            onChanged: (nextSide) {
              if (nextSide == side) return;
              setState(() {
                side = nextSide;
                offers = [];
              });
              unawaited(loadOffers());
            },
          ),
          const SizedBox(height: 12),
          _C2cFilterBar(
            markets: markets,
            selectedMarketId: marketId,
            fiat: currentFiat,
            availableMethods: availableMethods,
            selectedMethods: selectedMethods,
            minAmount: minAmount,
            maxAmount: maxAmount,
            onlyPremium: onlyPremium,
            onlyFreezeGuarantee: onlyFreezeGuarantee,
            onMarketSelected: (value) {
              setState(() {
                marketId = value;
                selectedMethods.clear();
              });
              unawaited(loadOffers());
            },
            onMethodsChanged: (next) {
              setState(() => selectedMethods = next);
              unawaited(loadOffers());
            },
            onFiltersChanged: (premium, freeze) {
              setState(() {
                onlyPremium = premium;
                onlyFreezeGuarantee = freeze;
              });
            },
          ),
          const SizedBox(height: 12),
          if (visibleOffers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: LText('暂无符合条件的广告')),
            ),
          ...visibleOffers.map(
            (ad) => _C2cAdCard(
              ad: ad,
              methodLabel: _methodLabel,
              onAction: () => showAuthSheet(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _C2cSideTabs extends StatelessWidget {
  const _C2cSideTabs({required this.side, required this.onChanged});

  final String side;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.bgElevated1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: t.borderDefault.withValues(alpha: 0.7),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SideTabPill(
              label: '我要买',
              selected: side == 'BUY',
              activeColor: colors.tertiary,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged('BUY');
              },
            ),
            const SizedBox(width: 4),
            _SideTabPill(
              label: '我要卖',
              selected: side == 'SELL',
              activeColor: colors.error,
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged('SELL');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _SideTabPill extends StatelessWidget {
  const _SideTabPill({
    required this.label,
    required this.selected,
    required this.activeColor,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: LText(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            color: selected ? Colors.white : colors.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _C2cFilterBar extends StatelessWidget {
  const _C2cFilterBar({
    required this.markets,
    required this.selectedMarketId,
    required this.fiat,
    required this.availableMethods,
    required this.selectedMethods,
    required this.minAmount,
    required this.maxAmount,
    required this.onlyPremium,
    required this.onlyFreezeGuarantee,
    required this.onMarketSelected,
    required this.onMethodsChanged,
    required this.onFiltersChanged,
  });

  final List<Map<String, dynamic>> markets;
  final String selectedMarketId;
  final String fiat;
  final List<Map<String, dynamic>> availableMethods;
  final Set<String> selectedMethods;
  final TextEditingController minAmount;
  final TextEditingController maxAmount;
  final bool onlyPremium;
  final bool onlyFreezeGuarantee;
  final ValueChanged<String> onMarketSelected;
  final ValueChanged<Set<String>> onMethodsChanged;
  final void Function(bool premium, bool freeze) onFiltersChanged;

  String _methodText() {
    if (selectedMethods.isEmpty) return '支付方式';
    if (selectedMethods.length == 1) {
      final code = selectedMethods.first;
      final match = availableMethods
          .where((m) => asString(m['code']) == code)
          .firstOrNull;
      return asString(match?['label'], fallback: code);
    }
    return '支付方式 (${selectedMethods.length})';
  }

  String _amountText() {
    final min = minAmount.text.trim();
    final max = maxAmount.text.trim();
    if (min.isEmpty && max.isEmpty) return '金额';
    if (min.isNotEmpty && max.isNotEmpty) return '$min–$max';
    if (min.isNotEmpty) return '≥ $min';
    return '≤ $max';
  }

  Future<void> _openOptionSheet(
    BuildContext context, {
    required String title,
    required List<String> options,
    required String current,
    required ValueChanged<String> onPick,
  }) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LText(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              for (final option in options)
                ListTile(
                  dense: true,
                  title: Text(option),
                  trailing: option == current
                      ? Icon(
                          Icons.check,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(sheet, option),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != current) onPick(picked);
  }

  Future<void> _openMethodsSheet(BuildContext context) async {
    final draft = Set<String>.from(selectedMethods);
    final result = await showModalBottomSheet<Set<String>>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: LText(
                        '选择支付方式（可多选）',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setSheetState(draft.clear),
                      child: const LText('全部'),
                    ),
                  ],
                ),
                for (final m in availableMethods)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: draft.contains(asString(m['code'])),
                    title: Text(
                      asString(m['label'], fallback: asString(m['code'])),
                    ),
                    onChanged: (checked) {
                      final code = asString(m['code']);
                      setSheetState(() {
                        if (checked == true) {
                          draft.add(code);
                        } else {
                          draft.remove(code);
                        }
                      });
                    },
                  ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, draft),
                  child: const LText('确定'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (result != null) onMethodsChanged(result);
  }

  Future<void> _openFilterSheet(BuildContext context) async {
    var draftPremium = onlyPremium;
    var draftFreeze = onlyFreezeGuarantee;
    final minCtrl = TextEditingController(text: minAmount.text);
    final maxCtrl = TextEditingController(text: maxAmount.text);
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LText(
                  '金额与商户筛选',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: fiat.isEmpty ? '最小金额' : '最小金额 ($fiat)',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: maxCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: fiat.isEmpty ? '最大金额' : '最大金额 ($fiat)',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: draftPremium,
                  title: const LText('优质商户'),
                  onChanged: (v) =>
                      setSheetState(() => draftPremium = v == true),
                ),
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: draftFreeze,
                  title: const LText('冻结必赔'),
                  onChanged: (v) =>
                      setSheetState(() => draftFreeze = v == true),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          minCtrl.clear();
                          maxCtrl.clear();
                          setSheetState(() {
                            draftPremium = false;
                            draftFreeze = false;
                          });
                        },
                        child: const LText('重置'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(sheet, true),
                        child: const LText('应用筛选'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (applied == true) {
      minAmount.text = minCtrl.text.trim();
      maxAmount.text = maxCtrl.text.trim();
      onFiltersChanged(draftPremium, draftFreeze);
    }
    minCtrl.dispose();
    maxCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current =
        markets.where((m) => m['marketId'] == selectedMarketId).firstOrNull ??
        markets.firstOrNull;
    final currentAsset = asString(current?['asset'], fallback: 'USDT');
    final currentFiat = asString(current?['fiat'], fallback: 'CNY');
    final assets = markets
        .map((m) => asString(m['asset']))
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList();
    final fiats = markets
        .where((m) => asString(m['asset']) == currentAsset)
        .map((m) => asString(m['fiat']))
        .where((f) => f.isNotEmpty)
        .toSet()
        .toList();
    final filterCount =
        (minAmount.text.trim().isNotEmpty || maxAmount.text.trim().isNotEmpty
            ? 1
            : 0) +
        (onlyPremium ? 1 : 0) +
        (onlyFreezeGuarantee ? 1 : 0);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _FilterDropdownChip(
            label: currentAsset,
            active: false,
            onTap: () {
              if (assets.isEmpty) return;
              unawaited(
                _openOptionSheet(
                  context,
                  title: '选择交易币种',
                  options: assets,
                  current: currentAsset,
                  onPick: (nextAsset) {
                    final target =
                        markets
                            .where(
                              (m) =>
                                  asString(m['asset']) == nextAsset &&
                                  asString(m['fiat']) == currentFiat,
                            )
                            .firstOrNull ??
                        markets
                            .where((m) => asString(m['asset']) == nextAsset)
                            .firstOrNull;
                    if (target != null) {
                      onMarketSelected(asString(target['marketId']));
                    }
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          _FilterDropdownChip(
            label: currentFiat,
            active: false,
            onTap: () {
              if (fiats.isEmpty) return;
              unawaited(
                _openOptionSheet(
                  context,
                  title: '选择法币',
                  options: fiats,
                  current: currentFiat,
                  onPick: (nextFiat) {
                    final target = markets
                        .where(
                          (m) =>
                              asString(m['asset']) == currentAsset &&
                              asString(m['fiat']) == nextFiat,
                        )
                        .firstOrNull;
                    if (target != null) {
                      onMarketSelected(asString(target['marketId']));
                    }
                  },
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          _FilterDropdownChip(
            label: _amountText(),
            active:
                minAmount.text.trim().isNotEmpty ||
                maxAmount.text.trim().isNotEmpty,
            onTap: () => _openFilterSheet(context),
          ),
          const SizedBox(width: 8),
          _FilterDropdownChip(
            label: _methodText(),
            active: selectedMethods.isNotEmpty,
            onTap: () => _openMethodsSheet(context),
          ),
          const SizedBox(width: 8),
          _FilterDropdownChip(
            label: filterCount > 0 ? '筛选 ($filterCount)' : '筛选',
            icon: Icons.tune,
            active: filterCount > 0,
            onTap: () => _openFilterSheet(context),
          ),
        ],
      ),
    );
  }
}

class _FilterDropdownChip extends StatelessWidget {
  const _FilterDropdownChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.auroraCyan.withValues(alpha: 0.12) : t.bgElevated1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active
                ? t.auroraCyan
                : t.borderDefault.withValues(alpha: 0.7),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 13,
                color: active ? t.auroraCyan : colors.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                color: active ? t.auroraCyan : colors.onSurface,
              ),
            ),
            if (icon == null) ...[
              const SizedBox(width: 2),
              Icon(
                Icons.keyboard_arrow_down,
                size: 15,
                color: active ? t.auroraCyan : colors.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _C2cAdCard extends StatelessWidget {
  const _C2cAdCard({
    required this.ad,
    required this.methodLabel,
    required this.onAction,
    this.disabled = false,
  });

  final Map<String, dynamic> ad;
  final String Function(String code) methodLabel;
  final VoidCallback onAction;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = Theme.of(context).colorScheme;
    final merchant = asMap(ad['merchant']);
    final m = asMap(ad['market']);
    final nickname = asString(
      merchant['nickname'],
      fallback: '商家 ${ad['makerUserId']}',
    );
    final isBuyAction = ad['side'] == 'SELL';
    final methodCodes = asList(ad['methodCodes']).map((e) => '$e').toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.bgElevated1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: t.borderDefault.withValues(alpha: 0.65),
          width: 0.6,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  nickname.isEmpty ? 'M' : nickname.characters.first,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (merchant['premiumVerified'] == true)
                Tooltip(
                  message: clientLabel(context, '优质商户'),
                  child: const Padding(
                    padding: EdgeInsets.only(left: 6),
                    child: Icon(
                      Icons.verified,
                      size: 17,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ),
              if (merchant['freezeCompensation'] == true)
                Tooltip(
                  message: clientLabel(context, '冻结必赔'),
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Icon(Icons.gpp_good, size: 17, color: t.auroraCyan),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                c2cDecimal(asString(ad['price'])),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w700,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(width: 4),
              Text(
                asString(m['fiat']),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      '数量 ${ad['availableQuantity']} ${m['asset']}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 2),
                    LText(
                      '限额 ${c2cDecimal(asString(ad['minFiat']))} – ${c2cDecimal(asString(ad['maxFiat']))} ${m['fiat']}',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                    if (methodCodes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        children: [
                          for (final code in methodCodes)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  switch (code) {
                                    'ALIPAY' =>
                                      Icons.account_balance_wallet_outlined,
                                    'WECHAT' => Icons.chat_bubble_outline,
                                    _ => Icons.account_balance_outlined,
                                  },
                                  size: 13,
                                  color: switch (code) {
                                    'ALIPAY' => const Color(0xFF1677FF),
                                    'WECHAT' => const Color(0xFF07C160),
                                    _ => const Color(0xFFF59E0B),
                                  },
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  methodLabel(code),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: isBuyAction ? colors.tertiary : colors.error,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(74, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: disabled ? null : onAction,
                child: LText(isBuyAction ? '购买' : '出售'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CopyableDetailRow extends StatelessWidget {
  const _CopyableDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 82,
            child: LText(
              label,
              style: TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 15),
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            padding: EdgeInsets.zero,
            onPressed: () {
              unawaited(Clipboard.setData(ClipboardData(text: value)));
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: LText('已复制$label')));
            },
          ),
        ],
      ),
    );
  }
}

class _CountdownText extends StatefulWidget {
  const _CountdownText({
    required this.expiresAtIso,
    this.serverTimeIso,
    this.prefix = '',
    this.onExpired,
  });

  final String expiresAtIso;
  final String? serverTimeIso;
  final String prefix;
  final VoidCallback? onExpired;

  @override
  State<_CountdownText> createState() => _CountdownTextState();
}

class _CountdownTextState extends State<_CountdownText> {
  Timer? _timer;
  int _remainingSeconds = 0;
  bool _notifiedExpired = false;

  @override
  void initState() {
    super.initState();
    _sync();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_remainingSeconds > 0) _remainingSeconds--;
      });
      if (_remainingSeconds == 0 && !_notifiedExpired) {
        _notifiedExpired = true;
        widget.onExpired?.call();
      }
    });
  }

  @override
  void didUpdateWidget(covariant _CountdownText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expiresAtIso != widget.expiresAtIso ||
        oldWidget.serverTimeIso != widget.serverTimeIso) {
      _notifiedExpired = false;
      _sync();
    }
  }

  void _sync() {
    final expires = DateTime.tryParse(widget.expiresAtIso);
    final server = widget.serverTimeIso == null
        ? DateTime.now()
        : (DateTime.tryParse(widget.serverTimeIso!) ?? DateTime.now());
    if (expires == null) {
      _remainingSeconds = 0;
      return;
    }
    final diff = expires.difference(server).inSeconds;
    _remainingSeconds = diff < 0 ? 0 : diff;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mins = (_remainingSeconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_remainingSeconds % 60).toString().padLeft(2, '0');
    final expired = _remainingSeconds <= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (expired ? colors.error : colors.primary).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        expired ? '已超时' : '${widget.prefix}$mins:$secs',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: expired ? colors.error : colors.primary,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _C2cTradeOrderSheet extends StatefulWidget {
  const _C2cTradeOrderSheet({
    required this.ad,
    required this.accounts,
    required this.methodLabel,
    required this.pendingBlocked,
    required this.onQuote,
    required this.onIssueChallenge,
    required this.onGoAccounts,
    required this.onSubmitOrder,
  });

  final Map<String, dynamic> ad;
  final List<Map<String, dynamic>> accounts;
  final String Function(String code) methodLabel;
  final bool pendingBlocked;
  final Future<Map<String, dynamic>> Function(
    String amount,
    String paymentAccountId,
  )
  onQuote;
  final Future<void> Function() onIssueChallenge;
  final VoidCallback onGoAccounts;
  final Future<void> Function(String quoteId, String emailCode, String totpCode)
  onSubmitOrder;

  @override
  State<_C2cTradeOrderSheet> createState() => _C2cTradeOrderSheetState();
}

class _C2cTradeOrderSheetState extends State<_C2cTradeOrderSheet> {
  final _quantity = TextEditingController();
  final _email = TextEditingController();
  final _totp = TextEditingController();
  String _paymentId = '';
  Map<String, dynamic>? _quote;
  Timer? _quoteDebounce;
  bool _quoting = false;
  bool _submitting = false;
  bool _quoteExpired = false;
  String? _error;

  bool get _isBuying => widget.ad['side'] == 'SELL';

  List<Map<String, dynamic>> get _paymentOptions {
    final m = asMap(widget.ad['market']);
    if (_isBuying) {
      return asList(widget.ad['paymentOptions']).map(asMap).toList();
    }
    final codes = asList(widget.ad['methodCodes']).map((e) => '$e').toList();
    return widget.accounts
        .where(
          (a) =>
              a['status'] == 'APPROVED' &&
              a['fiat'] == m['fiat'] &&
              codes.contains(a['methodCode']),
        )
        .toList();
  }

  @override
  void initState() {
    super.initState();
    final opts = _paymentOptions;
    if (opts.isNotEmpty) {
      _paymentId = asString(opts.first['accountId']);
    }
  }

  @override
  void dispose() {
    _quoteDebounce?.cancel();
    _quantity.dispose();
    _email.dispose();
    _totp.dispose();
    super.dispose();
  }

  void _scheduleQuote() {
    _quoteDebounce?.cancel();
    setState(() {
      _quote = null;
      _quoteExpired = false;
      _error = null;
    });
    final parsed = double.tryParse(_quantity.text.trim());
    if (parsed == null || parsed <= 0 || _paymentId.isEmpty) return;
    _quoteDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) unawaited(_fetchQuote());
    });
  }

  Future<void> _fetchQuote() async {
    final qty = _quantity.text.trim();
    final parsed = double.tryParse(qty);
    if (parsed == null || parsed <= 0 || _paymentId.isEmpty || _quoting) return;
    setState(() {
      _quoting = true;
      _error = null;
      _quoteExpired = false;
    });
    try {
      final res = await widget.onQuote(qty, _paymentId);
      if (!mounted) return;
      setState(() {
        _quote = res;
        _quoteExpired = res['valid'] != true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = clientErrorMessage(e));
    } finally {
      if (mounted) setState(() => _quoting = false);
    }
  }

  Future<void> _confirmAndSubmit() async {
    final q = _quote;
    if (q == null || _quoteExpired || q['valid'] != true || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await widget.onSubmitOrder(
        asString(q['quoteId']),
        _email.text.trim(),
        _totp.text.trim(),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = clientErrorMessage(e));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final colors = Theme.of(context).colorScheme;
    final ad = widget.ad;
    final m = asMap(ad['market']);
    final merchant = asMap(ad['merchant']);
    final options = _paymentOptions;
    final windowMins =
        ((int.tryParse(asString(m['paymentWindowSeconds'])) ?? 900) / 60)
            .round()
            .clamp(1, 60);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          0,
          18,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: LText(
                    '${_isBuying ? '购买' : '出售'} ${m['asset']}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (_quote != null && _quote!['expiresAt'] != null)
                  _CountdownText(
                    expiresAtIso: asString(_quote!['expiresAt']),
                    serverTimeIso: nullableString(_quote!['serverTime']),
                    prefix: '报价倒计时 ',
                    onExpired: () {
                      if (mounted) setState(() => _quoteExpired = true);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.bgElevated1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: t.borderDefault.withValues(alpha: 0.65),
                  width: 0.6,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          asString(
                            merchant['nickname'],
                            fallback: '商家 ${ad['makerUserId']}',
                          ),
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      if (merchant['premiumVerified'] == true)
                        const Icon(
                          Icons.verified,
                          size: 16,
                          color: Color(0xFFF59E0B),
                        ),
                      if (merchant['freezeCompensation'] == true)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.gpp_good,
                            size: 16,
                            color: t.auroraCyan,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '单价 ${c2cDecimal(asString(ad['price']))} ${m['fiat']} · 限额 ${c2cDecimal(asString(ad['minFiat']))} – ${c2cDecimal(asString(ad['maxFiat']))} ${m['fiat']}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '可交易 ${ad['availableQuantity']} ${m['asset']} · 付款有效期 $windowMins 分钟',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _quantity,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: '${_isBuying ? '购买' : '出售'}数量 (${m['asset']})',
                suffixIcon: TextButton(
                  onPressed: () {
                    _quantity.text = asString(ad['availableQuantity']);
                    _scheduleQuote();
                  },
                  child: const LText('全部'),
                ),
              ),
              onChanged: (_) => _scheduleQuote(),
            ),
            if (!_isBuying) ...[
              const SizedBox(height: 10),
              if (options.isEmpty) ...[
                Text(
                  '您尚未设置并审核通过支持该交易方式的收款账户，请先设置。',
                  style: TextStyle(color: colors.error, fontSize: 12),
                ),
                const SizedBox(height: 6),
                OutlinedButton(
                  onPressed: widget.onGoAccounts,
                  child: const LText('去设置收款方式'),
                ),
              ] else
                DropdownButtonFormField<String>(
                  initialValue: options.any((a) => a['accountId'] == _paymentId)
                      ? _paymentId
                      : null,
                  decoration: const InputDecoration(
                    labelText: '我的收款方式',
                    isDense: true,
                  ),
                  items: options
                      .map(
                        (a) => DropdownMenuItem(
                          value: asString(a['accountId']),
                          child: Text(
                            '${widget.methodLabel(asString(a['methodCode']))} ${a['maskedLabel']}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    _paymentId = value ?? '';
                    _scheduleQuote();
                  },
                ),
            ] else if (options.length > 1) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  for (final opt in options)
                    ChoiceChip(
                      label: Text(
                        widget.methodLabel(asString(opt['methodCode'])),
                      ),
                      selected: _paymentId == asString(opt['accountId']),
                      onSelected: (_) {
                        _paymentId = asString(opt['accountId']);
                        _scheduleQuote();
                      },
                    ),
                ],
              ),
            ],
            if ((double.tryParse(_quantity.text.trim()) ?? 0) > 0) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.bgElevated2,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _quote != null
                                ? '${_isBuying ? '应付总额' : '应收总额'}：${c2cDecimal(asString(_quote!['fiatAmount']))} ${m['fiat']}'
                                : '${_isBuying ? '预计应付' : '预计应收'}：${((double.tryParse(_quantity.text.trim()) ?? 0) * (double.tryParse(asString(ad['price'])) ?? 0)).toStringAsFixed(2)} ${m['fiat']}',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        if (_quoting)
                          const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '数量：${_quote?['quantity'] ?? _quantity.text.trim()} ${m['asset']}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isBuying && _quote != null) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => unawaited(widget.onIssueChallenge()),
                  child: const LText('获取安全验证码'),
                ),
                TextField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: '邮箱验证码'),
                ),
                TextField(
                  controller: _totp,
                  decoration: const InputDecoration(labelText: '验证器验证码（已绑定时）'),
                ),
              ],
            ],
            const SizedBox(height: 10),
            Text(
              '提示：请在 $windowMins 分钟内完成付款并点击确认；超时未处理将冻结相关币种，累计超一次违约将被限制 C2C 下单。',
              style: TextStyle(
                fontSize: 11.5,
                color: colors.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            if (_quoteExpired)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '报价倒计时已结束，无法下单。',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.error,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _quoting ? null : _fetchQuote,
                      child: const LText('刷新报价'),
                    ),
                  ],
                ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: colors.error),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _isBuying ? colors.tertiary : colors.error,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(46),
                shape: const StadiumBorder(),
              ),
              onPressed:
                  (_quote == null ||
                      _quoteExpired ||
                      _quote!['valid'] != true ||
                      _submitting ||
                      widget.pendingBlocked)
                  ? null
                  : _confirmAndSubmit,
              child: LText(_submitting ? '提交中…' : '确认下单'),
            ),
          ],
        ),
      ),
    );
  }
}
