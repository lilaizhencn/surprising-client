import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'app_state.dart';
import 'models.dart';

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
  int generation = 0, addressVersion = 0;
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
        symbol = rows.isEmpty ? null : asString(rows.first['asset']);
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
    try {
      final boundary =
          qrKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null || currentAddress == null) return;
      final image = await boundary.toImage(pixelRatio: 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (!mounted ||
          identity != widget.state.session?.accessToken ||
          address != currentAddress ||
          data == null) {
        return;
      }
      await FilePicker.platform.saveFile(
        dialogTitle: '保存充值二维码',
        fileName:
            'deposit-${currentAddress.symbol}-${currentAddress.chain}.png',
        bytes: data.buffer.asUint8List(),
      );
    } catch (_) {
      if (mounted) setState(() => error = '二维码无法保存，请重试');
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_identityChanged);
    generation++;
    addressVersion++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('充值')),
    body: token == null
        ? const Center(child: Text('请先登录'))
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (notice != null) Text(notice!),
              TextButton(
                onPressed: loading ? null : _load,
                child: const Text('刷新可充值币种'),
              ),
              if (!loading && assets.isEmpty && error == null)
                const Text('暂无可充值币种'),
              DropdownButtonFormField<String>(
                key: ValueKey('asset:$symbol:$generation'),
                initialValue: symbol,
                decoration: const InputDecoration(labelText: '币种'),
                items: assets
                    .map(
                      (row) => DropdownMenuItem(
                        value: asString(row['asset']),
                        child: Text(asString(row['asset'])),
                      ),
                    )
                    .toList(),
                onChanged: loading
                    ? null
                    : (value) {
                        addressVersion++;
                        setState(() {
                          symbol = value;
                          network = null;
                          address = null;
                          addressLoading = false;
                          error = null;
                          notice = null;
                        });
                      },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                key: ValueKey('network:$symbol:$network'),
                initialValue: network,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '充值网络'),
                items: networks
                    .map(
                      (row) => DropdownMenuItem(
                        value: asString(row['networkCode']),
                        child: Text(
                          asString(
                            row['displayName'],
                            fallback: asString(row['networkCode']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: loading
                    ? null
                    : (value) {
                        setState(() => network = value);
                        _address();
                      },
              ),
              const SizedBox(height: 16),
              const Text('请确保汇出平台或钱包使用相同的币种和网络。充错网络可能导致资产无法找回。'),
              if (selectedNetwork != null) ...[
                Text('最低充值：${selectedNetwork!['minDeposit']} $symbol'),
                Text('所需确认数：${selectedNetwork!['confirmations']}'),
              ],
              if (addressLoading) const LinearProgressIndicator(),
              if (address != null) ...[
                Center(
                  child: RepaintBoundary(
                    key: qrKey,
                    child: QrImageView(
                      data: address!.address,
                      size: 232,
                      backgroundColor: Colors.white,
                      semanticsLabel: '充值地址二维码',
                    ),
                  ),
                ),
                TextButton(onPressed: _saveQr, child: const Text('保存二维码')),
                const Text('充值账户：资金账户'),
                SelectableText(
                  address!.address,
                  key: const ValueKey('deposit-address'),
                ),
                FilledButton.icon(
                  onPressed: () => _copy(address!.address),
                  icon: const Icon(Icons.copy),
                  label: const Text('复制地址'),
                ),
                if (address!.memo.isNotEmpty) ...[
                  SelectableText('Memo / Tag：${address!.memo}'),
                  TextButton(
                    onPressed: () => _copy(address!.memo),
                    child: const Text('复制 Memo / Tag'),
                  ),
                  const Text('转账时必须同时填写地址和 Memo / Tag。'),
                ],
              ],
              if (network != null)
                TextButton(
                  onPressed: addressLoading ? null : _address,
                  child: const Text('重新加载地址'),
                ),
            ],
          ),
  );
}
