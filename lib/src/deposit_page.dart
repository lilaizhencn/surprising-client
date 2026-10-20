import 'dart:ui' as ui;
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_state.dart';
import 'models.dart';
import 'exchange_widgets.dart';
import 'funding_records_page.dart';

class MobileDepositPage extends StatefulWidget {
  const MobileDepositPage({required this.state, super.key});
  final AppState state;
  @override
  State<MobileDepositPage> createState() => _MobileDepositPageState();
}

class _MobileDepositPageState extends State<MobileDepositPage> {
  List<Map<String, dynamic>> assets = [];
  String? token, symbol, network, error, notice;
  WalletDepositAddress? address;
  bool loading = true, addressLoading = false;
  int generation = 0, addressVersion = 0, stage = 0;
  String query = '';
  bool exporting = false;
  final qrKey = GlobalKey();
  @override
  void initState() {
    super.initState();
    widget.state.addListener(_identityChanged);
    _identityChanged();
  }

  void _identityChanged() {
    final next = widget.state.session?.accessToken;
    if (next == token) return;
    token = next;
    generation++;
    addressVersion++;
    setState(() {
      assets = [];
      symbol = null;
      stage = 0;
      query = '';
      network = null;
      address = null;
      error = null;
      notice = null;
      loading = false;
      addressLoading = false;
    });
    if (next != null) _load();
  }

  Future<void> _load() async {
    final identity = token, version = ++generation;
    if (identity == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await widget.state.api.fundingAssets('deposit');
      if (!mounted ||
          version != generation ||
          identity != widget.state.session?.accessToken) {
        return;
      }
      setState(() {
        assets = rows;
        symbol = null;
        stage = 0;
        network = null;
        address = null;
      });
    } catch (_) {
      if (mounted && version == generation) {
        setState(() => error = '充值币种和网络暂不可用，请重试');
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  List<Map<String, dynamic>> get networks => asList(
    assets.where((row) => row['asset'] == symbol).firstOrNull?['networks'],
  ).map(asMap).toList();
  Map<String, dynamic>? get selectedNetwork =>
      networks.where((row) => row['networkCode'] == network).firstOrNull;
  Future<void> _address() async {
    final identity = token,
        currency = symbol,
        chain = network,
        version = ++addressVersion;
    if (identity == null || currency == null || chain == null) return;
    setState(() {
      addressLoading = true;
      address = null;
      error = null;
      notice = null;
    });
    try {
      final value = await widget.state.api.walletDepositAddress(
        widget.state.userId!,
        chain: chain,
        symbol: currency,
      );
      if (!mounted ||
          version != addressVersion ||
          identity != widget.state.session?.accessToken) {
        return;
      }
      setState(() => address = value);
    } catch (_) {
      if (mounted && version == addressVersion) {
        setState(() => error = '充值地址加载失败，请重试');
      }
    } finally {
      if (mounted && version == addressVersion) {
        setState(() => addressLoading = false);
      }
    }
  }

  Future<void> _copy(String value) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) setState(() => notice = '已复制');
    } catch (_) {
      if (mounted) setState(() => error = '无法复制，请长按地址手动复制');
    }
  }

  Future<void> _saveQr() async {
    final identity = token, currentAddress = address;
    if (exporting || currentAddress == null) return;
    setState(() {
      exporting = true;
      error = null;
      notice = null;
    });
    try {
      final boundary =
          qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted ||
          identity != widget.state.session?.accessToken ||
          address != currentAddress ||
          data == null) {
        return;
      }
      final saved = await FilePicker.platform.saveFile(
        dialogTitle: '保存充值二维码',
        fileName:
            'deposit-${currentAddress.symbol}-${currentAddress.chain}.png',
        bytes: data.buffer.asUint8List(),
      );
      if (mounted &&
          identity == widget.state.session?.accessToken &&
          address == currentAddress &&
          saved != null) {
        setState(() => notice = '二维码已保存');
      }
    } catch (_) {
      if (mounted && identity == widget.state.session?.accessToken) {
        setState(() => error = '二维码无法保存，请重试');
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_identityChanged);
    generation++;
    addressVersion++;
    super.dispose();
  }

  void _back() {
    if (stage == 0) {
      Navigator.maybePop(context);
      return;
    }
    addressVersion++;
    setState(() {
      stage--;
      addressLoading = false;
      error = null;
      notice = null;
      if (stage == 0) {
        symbol = null;
        network = null;
        address = null;
      }
    });
  }

  void _selectAsset(String value) {
    addressVersion++;
    setState(() {
      symbol = value;
      network = null;
      address = null;
      addressLoading = false;
      stage = 1;
      error = null;
      notice = null;
    });
  }

  void _selectNetwork(String value) {
    setState(() {
      network = value;
      stage = 2;
    });
    _address();
  }

  void _records() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) =>
          FundingRecordsPage(state: widget.state, initialCategory: 'deposit'),
    ),
  );

  void _details({bool contract = false}) {
    final route = selectedNetwork;
    final contractAddress = asString(route?['contractAddress']);
    var detail =
        '请确保汇出平台或钱包使用相同的币种和网络。充错网络可能导致资产无法找回。\n\n请核对最小充币额及所需确认数。若显示 Memo / Tag，转账时必须同时填写地址和 Memo / Tag。';
    if (contract) {
      if (contractAddress.isNotEmpty) {
        detail = contractAddress;
      } else if (route?['nativeAsset'] == true) {
        detail = '原生资产，无代币合约地址。';
      } else {
        detail = '合约资料暂不可用。';
      }
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                contract ? '代币合约' : '充值帮助',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 20),
              SelectableText(detail),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _share() async {
    final identity = token, currentAddress = address;
    if (exporting || currentAddress == null) return;
    setState(() => exporting = true);
    try {
      final boundary =
          qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted ||
          identity != widget.state.session?.accessToken ||
          address != currentAddress ||
          data == null) {
        return;
      }
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          title: '充值 ${currentAddress.symbol}',
          text:
              '${currentAddress.symbol} · ${currentAddress.chain}\n${currentAddress.address}'
              '${currentAddress.memo.isEmpty ? "" : "\nMemo / Tag：${currentAddress.memo}"}',
          files: [
            XFile.fromData(data.buffer.asUint8List(), mimeType: 'image/png'),
          ],
          fileNameOverrides: [
            'deposit-${currentAddress.symbol}-${currentAddress.chain}.png',
          ],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (mounted && identity == widget.state.session?.accessToken) {
        setState(() => error = '分享失败，请重试或复制地址');
      }
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  Future<void> _menu() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final action in <(IconData, String, VoidCallback)>[
            (Icons.history, '充币记录', _records),
            (
              Icons.ios_share,
              '分享',
              () {
                _share();
              },
            ),
            (
              Icons.download_outlined,
              '保存二维码',
              () {
                _saveQr();
              },
            ),
            (
              Icons.receipt_long_outlined,
              '代币合约',
              () => _details(contract: true),
            ),
            (Icons.help_outline, '帮助中心', () => _details()),
          ])
            ListTile(
              leading: Icon(action.$1),
              title: Text(action.$2),
              trailing: const Icon(Icons.chevron_right),
              enabled: !exporting,
              onTap: () {
                Navigator.pop(sheet);
                action.$3();
              },
            ),
        ],
      ),
    ),
  );

  Widget _info(String title, Widget value, {VoidCallback? onTap}) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 17),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Align(alignment: Alignment.centerRight, child: value),
          ),
          if (onTap != null) const Icon(Icons.keyboard_arrow_down, size: 18),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final route = selectedNetwork;
    final recent = widget.state.walletOrders
        .where((order) => order.type == 'DEPOSIT')
        .map((order) => order.symbol)
        .toSet()
        .where((asset) => assets.any((row) => row['asset'] == asset))
        .toList();
    final filtered = assets.where(
      (row) => '${row['asset']} ${row['displayName']}'.toLowerCase().contains(
        query.toLowerCase(),
      ),
    );
    final currentAddress = address;
    return PopScope(
      canPop: stage == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: exchangeBackground(context),
        appBar: AppBar(
          backgroundColor: exchangeBackground(context),
          centerTitle: true,
          leading: IconButton(
            onPressed: _back,
            style: exchangeIconStyle(context),
            tooltip: '返回',
            icon: const Icon(Icons.arrow_back_ios_new, size: 22),
          ),
          title: Text(
            stage == 0
                ? '选择资产'
                : stage == 1
                ? '选择网络'
                : '',
          ),
          actions: [
            if (stage == 0)
              IconButton(
                onPressed: () => _details(),
                style: exchangeIconStyle(context),
                tooltip: '充值帮助',
                icon: const Icon(Icons.help_outline),
              ),
            IconButton(
              onPressed: stage == 2 ? _menu : _records,
              style: exchangeIconStyle(context),
              tooltip: stage == 2 ? '更多' : '充币记录',
              icon: Icon(stage == 2 ? Icons.more_horiz : Icons.history),
            ),
          ],
        ),
        body: token == null
            ? const Center(child: Text('请先登录'))
            : ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ),
                  if (notice != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(notice!),
                    ),
                  if (loading || addressLoading)
                    const LinearProgressIndicator(),
                  if (stage == 0) ...[
                    ExchangeSearchField(
                      onChanged: (value) => setState(() => query = value),
                      hintText: '搜索数字货币',
                    ),
                    if (recent.isNotEmpty && query.isEmpty) ...[
                      const SizedBox(height: 24),
                      const Text(
                        '近期充币记录',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        children: [
                          for (final asset in recent.take(5))
                            ActionChip(
                              avatar: CoinIcon(asset, size: 22),
                              label: Text(asset),
                              onPressed: () => _selectAsset(asset),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),
                    const Text(
                      '数字货币',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final row in filtered)
                      ListTile(
                        key: ValueKey('deposit-asset-${row['asset']}'),
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        leading: CoinIcon(asString(row['asset']), size: 34),
                        title: Text(
                          asString(row['asset']),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          asString(
                            row['displayName'],
                            fallback: asString(row['asset']),
                          ),
                        ),
                        onTap: () => _selectAsset(asString(row['asset'])),
                      ),
                    if (!loading && filtered.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 30),
                        child: Center(
                          child: Text(
                            error == null
                                ? query.isEmpty
                                      ? '暂无可充值币种'
                                      : '未找到资产'
                                : '',
                          ),
                        ),
                      ),
                    if (error != null)
                      TextButton(
                        onPressed: loading ? null : _load,
                        child: const Text('重试'),
                      ),
                  ],
                  if (stage == 1) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: colors.outlineVariant),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ⓘ  不清楚如何选择网络？',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('请确保您选择的网络，与汇出平台或钱包的网络保持一致。'),
                          TextButton(
                            onPressed: () => _details(),
                            child: const Text('了解更多 →'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '网络',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        Text(
                          '所需确认数/最小充币额',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    for (final row in networks)
                      ListTile(
                        key: ValueKey('deposit-network-${row['networkCode']}'),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 12,
                        ),
                        leading: CoinIcon(
                          asString(row['networkCode']) == 'ETH'
                              ? 'ETH'
                              : asString(row['networkCode']),
                          size: 32,
                        ),
                        title: Text(
                          asString(
                            row['displayName'],
                            fallback: asString(row['networkCode']),
                          ),
                          style: const TextStyle(fontSize: 17),
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text('${row['confirmations']} 个确认'),
                            Text(
                              '${row['minDeposit']} $symbol',
                              style: TextStyle(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                        onTap: () =>
                            _selectNetwork(asString(row['networkCode'])),
                      ),
                  ],
                  if (stage == 2) ...[
                    Center(
                      child: Text(
                        '充值 $symbol',
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (currentAddress != null) ...[
                      Center(
                        child: RepaintBoundary(
                          key: qrKey,
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF222222),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Stack(
                                alignment: Alignment.center,
                                children: [
                                  QrImageView(
                                    data: currentAddress.address,
                                    size: 210,
                                    backgroundColor: Colors.white,
                                    errorCorrectionLevel: QrErrorCorrectLevel.H,
                                    semanticsLabel: '充值地址二维码',
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(3),
                                    decoration: const BoxDecoration(
                                      color: Colors.white,
                                      shape: BoxShape.circle,
                                    ),
                                    child: CoinIcon(symbol!, size: 30),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        '地址',
                        style: TextStyle(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: SelectableText(
                              currentAddress.address,
                              key: const ValueKey('deposit-address'),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            onPressed: () => _copy(currentAddress.address),
                            style: IconButton.styleFrom(
                              shape: const CircleBorder(),
                              side: BorderSide.none,
                            ),
                            tooltip: '复制地址',
                            icon: const Icon(Icons.copy),
                          ),
                        ],
                      ),
                      if (currentAddress.memo.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        SelectableText('Memo / Tag：${currentAddress.memo}'),
                        TextButton(
                          onPressed: () => _copy(currentAddress.memo),
                          child: const Text('复制 Memo / Tag'),
                        ),
                        Text(
                          '转账时必须同时填写地址和 Memo / Tag。',
                          style: TextStyle(color: colors.error),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const Divider(),
                    ],
                    _info(
                      '网络',
                      Text(
                        asString(
                          route?['displayName'],
                          fallback: network ?? '',
                        ),
                      ),
                      onTap: _back,
                    ),
                    _info('充币账户', const Text('资金账户')),
                    _info('最小充币额', Text('${route?['minDeposit']} $symbol')),
                    _info('所需确认数', Text('${route?['confirmations']}')),
                    _info(
                      '合约地址',
                      const Text('查看详情'),
                      onTap: () => _details(contract: true),
                    ),
                    if (!addressLoading && address == null)
                      TextButton(
                        onPressed: _address,
                        child: const Text('重新加载地址'),
                      ),
                  ],
                ],
              ),
      ),
    );
  }
}
