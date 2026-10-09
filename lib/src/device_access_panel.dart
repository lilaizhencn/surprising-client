import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';

/// Device controls share the application session and never create a WebSocket.
class DeviceAccessPanel extends StatefulWidget {
  const DeviceAccessPanel({required this.state, super.key});
  final AppState state;
  @override
  State<DeviceAccessPanel> createState() => _DeviceAccessPanelState();
}

class _DeviceAccessPanelState extends State<DeviceAccessPanel> {
  List<Map<String, dynamic>> devices = [], ips = [];
  String? token, error;
  int generation = 0;
  bool busy = false, loading = false, mfaEnabled = false, mfaReady = false;

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
    setState(() {
      devices = [];
      ips = [];
      error = null;
      mfaReady = false;
    });
    if (next != null) _load();
  }

  Future<void> _load() async {
    final version = ++generation, identity = token;
    if (identity == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final api = widget.state.api;
      final result = await Future.wait([
        api.devices(),
        api.loginIps(),
        api.mfaStatus(),
      ]);
      if (!mounted ||
          version != generation ||
          identity != widget.state.session?.accessToken) {
        return;
      }
      setState(() {
        devices = result[0] as List<Map<String, dynamic>>;
        ips = result[1] as List<Map<String, dynamic>>;
        mfaEnabled = asMap(result[2])['enabled'] == true;
        mfaReady = true;
      });
    } catch (_) {
      if (mounted && version == generation) {
        setState(() => error = '设备信息暂不可用，请重试');
      }
    } finally {
      if (mounted && version == generation) setState(() => loading = false);
    }
  }

  Future<void> _change(
    Map<String, dynamic> row,
    String action, {
    bool ip = false,
  }) async {
    if (busy || token == null) return;
    final identity = token;
    final verified = action != 'revoke';
    final deviceId = asString(row['deviceId']);
    final sessionId = asString(row['sessionId']);
    final name = ip
        ? asString(row['ipAddress'])
        : (deviceId.isEmpty && !verified ? sessionId : deviceId);
    if (name.isEmpty) return;
    final email = TextEditingController(), totp = TextEditingController();
    bool confirming = false;
    String? dialogError;
    try {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (dialog, update) => AlertDialog(
            title: Text(
              action == 'revoke'
                  ? '下线设备？'
                  : action == 'block'
                  ? '禁止登录？'
                  : '恢复登录？',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name),
                  if (verified) ...[
                    TextField(
                      controller: email,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '邮箱验证码'),
                    ),
                    if (mfaEnabled)
                      TextField(
                        controller: totp,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '2FA 验证码'),
                      ),
                    TextButton(
                      onPressed: confirming
                          ? null
                          : () async {
                              update(() {
                                confirming = true;
                                dialogError = null;
                              });
                              try {
                                await widget.state.api.issueSecurityChallenge(
                                  'SECURITY_SETTINGS',
                                );
                              } catch (_) {
                                if (dialog.mounted) {
                                  update(() => dialogError = '验证码发送失败，请重试');
                                }
                              } finally {
                                if (dialog.mounted) {
                                  update(() => confirming = false);
                                }
                              }
                            },
                      child: const Text('发送验证码'),
                    ),
                  ],
                  if (dialogError != null) Text(dialogError!),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: confirming
                    ? null
                    : () {
                        if (verified &&
                            (email.text.trim().isEmpty ||
                                (mfaEnabled && totp.text.trim().isEmpty))) {
                          update(() => dialogError = '请填写验证码');
                          return;
                        }
                        Navigator.pop(dialog, true);
                      },
                child: const Text('确认'),
              ),
            ],
          ),
        ),
      );
      if (accepted != true ||
          !mounted ||
          identity != widget.state.session?.accessToken) {
        return;
      }
      setState(() {
        busy = true;
        error = null;
      });
      final api = widget.state.api;
      if (ip) {
        await api.setIpBlocked(
          name,
          action == 'block',
          email.text.trim(),
          totp.text.trim(),
        );
      } else if (action == 'revoke') {
        if (deviceId.isEmpty) {
          await api.revokeUserSession(sessionId);
        } else {
          await api.revokeDevice(name);
        }
      } else {
        await api.setDeviceBlocked(
          name,
          action == 'block',
          email.text.trim(),
          totp.text.trim(),
        );
      }
      if (mounted && identity == widget.state.session?.accessToken) {
        await _load();
      }
    } catch (_) {
      if (mounted && identity == widget.state.session?.accessToken) {
        setState(() => error = '设置未完成，请刷新状态后重试');
      }
    } finally {
      email.dispose();
      totp.dispose();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_identityChanged);
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: const Text('设备与登录 IP'),
    children: [
      if (loading) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      TextButton(
        onPressed: busy || loading ? null : _load,
        child: const Text('刷新设备'),
      ),
      if (!loading && error == null && devices.isEmpty && ips.isEmpty)
        const Text('暂无设备记录'),
      for (final row in devices)
        ListTile(
          title: Text(asString(row['userAgent'], fallback: '未知设备')),
          subtitle: Text(
            '${row['ipAddress'] ?? '—'} · ${row['lastSeen'] ?? '—'}${row['current'] == true ? ' · 当前设备' : ''}',
          ),
          trailing: row['current'] == true
              ? null
              : PopupMenuButton<String>(
                  enabled: !busy && mfaReady,
                  onSelected: (v) => _change(row, v),
                  itemBuilder: (_) => [
                    if (asString(
                      row['deviceId'] ?? row['sessionId'],
                    ).isNotEmpty)
                      const PopupMenuItem(value: 'revoke', child: Text('下线')),
                    if (asString(row['deviceId']).isNotEmpty)
                      PopupMenuItem(
                        value: row['blocked'] == true ? 'unblock' : 'block',
                        child: Text(row['blocked'] == true ? '恢复登录' : '禁止登录'),
                      ),
                  ],
                ),
        ),
      for (final row in ips)
        ListTile(
          title: Text(asString(row['ipAddress'])),
          subtitle: Text(
            '${row['blocked'] == true ? '已禁止' : '允许登录'} · 登录 ${row['loginCount'] ?? 0} 次',
          ),
          trailing: TextButton(
            onPressed: busy || !mfaReady
                ? null
                : () => _change(
                    row,
                    row['blocked'] == true ? 'unblock' : 'block',
                    ip: true,
                  ),
            child: Text(row['blocked'] == true ? '恢复' : '禁止'),
          ),
        ),
    ],
  );
}
