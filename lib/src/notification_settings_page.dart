import 'package:flutter/material.dart';
import 'app_state.dart';
import 'i18n/client_messages.dart';
import 'models.dart';

/// 通知设置页面 (暗黑科技风毛玻璃风格)
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({required this.state, super.key});
  final AppState state;

  @override
  State<NotificationSettingsPage> createState() => _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  NotificationPreferences? _prefs;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.state.api.getNotificationPreferences();
      if (!mounted) return;
      setState(() {
        _prefs = NotificationPreferences.fromJson(raw);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载通知偏好失败，请稍后重试';
        _loading = false;
      });
    }
  }

  Future<void> _savePreferences(NotificationPreferences next) async {
    setState(() {
      _prefs = next;
      _saving = true;
      _error = null;
    });
    try {
      final raw = await widget.state.api.updateNotificationPreferences(next.toJson());
      if (!mounted) return;
      setState(() {
        _prefs = NotificationPreferences.fromJson(raw);
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('通知偏好设置已更新'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存设置失败，请重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF0A0A12);

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const LText('通知设置'),
        actions: [
          if (_saving)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _prefs == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFFFF5555))),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadPreferences,
              child: const LText('重试'),
            ),
          ],
        ),
      );
    }

    final p = _prefs ?? NotificationPreferences.defaults();

    return RefreshIndicator(
      onRefresh: _loadPreferences,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          _buildSectionHeader('行情预警 (Market Alerts)'),
          _buildGlassCard(
            children: [
              _buildSwitchRow(
                title: '行情异动大变动推送',
                subtitle: '币对短时间内急涨急跌或剧烈波动时及时通知',
                value: p.marketVolatilityPush,
                onChanged: (val) => _savePreferences(p.copyWith(marketVolatilityPush: val)),
              ),
              if (p.marketVolatilityPush) ...[
                const Divider(color: Color(0xFF2F2F43), height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '波动阈值触发点',
                            style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 14),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '±${p.marketVolatilityThresholdPct.toStringAsFixed(1)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: const Color(0xFF00C6FF),
                          inactiveTrackColor: const Color(0xFF2F2F43),
                          thumbColor: Colors.white,
                        ),
                        child: Slider(
                          value: p.marketVolatilityThresholdPct.clamp(1.0, 30.0),
                          min: 1.0,
                          max: 30.0,
                          divisions: 29,
                          onChanged: (v) {
                            setState(() {
                              _prefs = p.copyWith(marketVolatilityThresholdPct: v);
                            });
                          },
                          onChangeEnd: (v) {
                            _savePreferences(p.copyWith(marketVolatilityThresholdPct: v));
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 16),
          _buildSectionHeader('账户与安全 (Security & Auth)'),
          _buildGlassCard(
            children: [
              _buildSwitchRow(
                title: '新设备 / 异地登录提醒',
                subtitle: '检测到其他设备或陌生 IP 登录时即刻警报',
                value: p.securityLoginPush,
                onChanged: (val) => _savePreferences(p.copyWith(securityLoginPush: val)),
              ),
              const Divider(color: Color(0xFF2F2F43), height: 1),
              _buildSwitchRow(
                title: '安全邮件通知',
                subtitle: '同步向注册邮箱发送登录验证与安全日志',
                value: p.securityLoginEmail,
                onChanged: (val) => _savePreferences(p.copyWith(securityLoginEmail: val)),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _buildSectionHeader('交易执行与风险 (Trade & Risk)'),
          _buildGlassCard(
            children: [
              _buildSwitchRow(
                title: '订单撮合成交推送',
                subtitle: '限价单/市价单部分成交或全部成交通知',
                value: p.tradingFillPush,
                onChanged: (val) => _savePreferences(p.copyWith(tradingFillPush: val)),
              ),
              const Divider(color: Color(0xFF2F2F43), height: 1),
              _buildSwitchRow(
                title: '强平与爆仓预警',
                subtitle: '合约保证金率不足或触发强平前极度重要风险预警',
                value: p.liquidationRiskPush,
                onChanged: (val) => _savePreferences(p.copyWith(liquidationRiskPush: val)),
              ),
            ],
          ),

          const SizedBox(height: 16),
          _buildSectionHeader('资产与 C2C (Wallet & OTC)'),
          _buildGlassCard(
            children: [
              _buildSwitchRow(
                title: '链上充值提现确认',
                subtitle: '入金确认及提现打包广播与出账进度提醒',
                value: p.assetTransferPush,
                onChanged: (val) => _savePreferences(p.copyWith(assetTransferPush: val)),
              ),
              const Divider(color: Color(0xFF2F2F43), height: 1),
              _buildSwitchRow(
                title: 'C2C 订单状态更新',
                subtitle: '买家付款、卖家放币及聊天消息即时推送',
                value: p.c2cOrderPush,
                onChanged: (val) => _savePreferences(p.copyWith(c2cOrderPush: val)),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Color(0xFFB0B0C0),
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGlassCard({required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0x801E1E2E), // 50% opacity 毛玻璃卡片
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2F2F43), width: 1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000078),
            offset: Offset(0, 4),
            blurRadius: 12,
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFFB0B0C0),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch(
            value: value,
            activeColor: const Color(0xFF00C6FF),
            activeTrackColor: const Color(0x4D00C6FF),
            inactiveThumbColor: const Color(0xFFB0B0C0),
            inactiveTrackColor: const Color(0xFF2F2F43),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
