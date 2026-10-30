import '../i18n/client_messages.dart';
import 'package:flutter/material.dart';
import '../api.dart';
import '../models.dart';

typedef ApiKeySettings = ({
  String label,
  List<String> permissions,
  List<String> ipAllowlist,
  String emailCode,
  String totpCode,
});

class ApiKeyEditDialog extends StatefulWidget {
  const ApiKeyEditDialog({
    required this.apiKey,
    required this.mfaRequired,
    required this.onSendCode,
    required this.onSave,
    super.key,
  });

  final Map<String, dynamic> apiKey;
  final bool mfaRequired;
  final Future<void> Function() onSendCode;
  final Future<void> Function(ApiKeySettings) onSave;

  @override
  State<ApiKeyEditDialog> createState() => _ApiKeyEditDialogState();
}

class _ApiKeyEditDialogState extends State<ApiKeyEditDialog> {
  late final name = TextEditingController(
    text: asString(widget.apiKey['label']),
  );
  late final ips = TextEditingController(
    text: asList(widget.apiKey['ipAllowlist']).join(', '),
  );
  final email = TextEditingController();
  final totp = TextEditingController();
  late bool trade = asString(
    widget.apiKey['permissions'],
  ).split(',').contains('TRADE');
  late bool withdraw = asString(
    widget.apiKey['permissions'],
  ).split(',').contains('WITHDRAW');
  bool busy = false;
  bool uncertain = false;
  String? error;
  String? notice;

  @override
  void dispose() {
    name.dispose();
    ips.dispose();
    email.dispose();
    totp.dispose();
    super.dispose();
  }

  Future<void> sendCode() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await widget.onSendCode();
      if (mounted) setState(() => notice = '验证码已发送，请查看邮箱');
    } catch (cause) {
      if (mounted) setState(() => error = '$cause');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (busy || uncertain) return;
    final addresses = ips.text
        .split(RegExp(r'[\s,]+'))
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList();
    if (name.text.trim().isEmpty ||
        name.text.trim().length > 80 ||
        email.text.trim().isEmpty ||
        (widget.mfaRequired && totp.text.trim().isEmpty)) {
      setState(() => error = '请填写名称和所需验证码');
      return;
    }
    if (addresses.length > 100 ||
        addresses.any((ip) => ip.length > 64) ||
        ((trade || withdraw) && addresses.isEmpty)) {
      setState(() => error = '交易或提币权限必须设置 IP 白名单，最多 100 条地址或 CIDR');
      return;
    }
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await widget.onSave((
        label: name.text.trim(),
        permissions: ['READ', if (trade) 'TRADE', if (withdraw) 'WITHDRAW'],
        ipAllowlist: addresses,
        emailCode: email.text.trim(),
        totpCode: totp.text.trim(),
      ));
      if (mounted) Navigator.pop(context, true);
    } catch (cause) {
      if (mounted) {
        setState(() {
          uncertain =
              cause is! FormatException &&
              (cause is! ApiException ||
                  cause.statusCode >= 500 ||
                  cause.statusCode == 408);
          error = uncertain
              ? '操作结果尚未确认，请关闭并刷新密钥列表后核对'
              : cause is FormatException
              ? cause.message
              : '$cause';
          email.clear();
          totp.clear();
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: const LText('编辑 API 密钥'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(asString(widget.apiKey['apiKey'])),
              TextField(
                controller: name,
                enabled: !busy,
                maxLength: 80,
                decoration: InputDecoration(
                  labelText: clientLabel(context, '名称'),
                ),
              ),
              const LText('读取权限始终开启。交易和提币权限必须绑定 IP。'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LText('允许交易'),
                value: trade,
                onChanged: busy
                    ? null
                    : (value) => setState(() => trade = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const LText('允许提币'),
                value: withdraw,
                onChanged: busy
                    ? null
                    : (value) => setState(() => withdraw = value),
              ),
              TextField(
                controller: ips,
                enabled: !busy,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: clientLabel(context, 'IP 白名单'),
                  helperText: clientLabel(context, 'IP 地址或 CIDR，以逗号分隔'),
                ),
              ),
              TextField(
                controller: email,
                enabled: !busy,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: clientLabel(context, '邮箱验证码'),
                ),
              ),
              if (widget.mfaRequired)
                TextField(
                  controller: totp,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: clientLabel(context, '2FA 验证码'),
                  ),
                ),
              TextButton(
                onPressed: busy || uncertain ? null : sendCode,
                child: const LText('发送验证码'),
              ),
              if (notice != null) LText(notice!, semanticsLabel: notice),
              if (error != null)
                LText(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context, false),
          child: const LText('关闭'),
        ),
        FilledButton(
          onPressed: busy || uncertain ? null : save,
          child: LText(busy ? '处理中…' : '保存'),
        ),
      ],
    ),
  );
}
