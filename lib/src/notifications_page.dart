import 'package:flutter/material.dart';
import 'app_state.dart';
import 'i18n/client_messages.dart';
import 'models.dart';
import 'notification_router.dart';
import 'notification_settings_page.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.state, super.key});
  final AppState state;

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationItem> items = [];
  bool loading = false;
  String? error;
  String? owner;
  int generation = 0;
  String selectedCategory = 'ALL';

  final List<({String key, String label})> categories = const [
    (key: 'ALL', label: '全部'),
    (key: 'MARKET', label: '行情异动'),
    (key: 'SECURITY', label: '安全通知'),
    (key: 'TRADE', label: '交易成交'),
    (key: 'RISK', label: '风险预警'),
    (key: 'WALLET', label: '资产充提'),
    (key: 'C2C', label: 'C2C订单'),
    (key: 'SYSTEM', label: '系统通知'),
  ];

  @override
  void initState() {
    super.initState();
    widget.state.addListener(_identityChanged);
    _identityChanged();
  }

  void _identityChanged() {
    final next = widget.state.session?.accessToken;
    if (next == owner) return;
    owner = next;
    generation++;
    items = [];
    if (mounted) setState(() {});
    if (next != null) _load();
  }

  Future<void> _load() async {
    final request = ++generation, identity = owner;
    if (identity == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final categoryParam = selectedCategory == 'ALL' ? null : selectedCategory;
      final rawList = await widget.state.api.notifications(category: categoryParam);
      if (mounted && request == generation && identity == owner) {
        setState(() {
          items = rawList.map((e) => NotificationItem.fromJson(e)).toList();
        });
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = '通知加载失败，请重试');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  Future<void> _markAllAsRead() async {
    final identity = owner;
    if (identity == null || items.isEmpty) return;
    try {
      await widget.state.api.post('/api/v1/notifications/read-all', const {});
      if (!mounted || identity != owner) return;
      final now = DateTime.now();
      setState(() {
        items = items.map<NotificationItem>((item) => item.copyWith(readAt: now)).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已全部标记为已读'), duration: Duration(seconds: 1)),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('标记已读失败，请重试')),
        );
      }
    }
  }

  Future<void> _onNotificationTap(NotificationItem item) async {
    final identity = owner;
    // 异步标记已读
    if (!item.isRead) {
      try {
        await widget.state.api.post(
          '/api/v1/notifications/${item.notificationId}/read',
          const {},
        );
        if (mounted && identity == owner) {
          final now = DateTime.now();
          setState(() {
            final idx = items.indexWhere((it) => it.notificationId == item.notificationId);
            if (idx != -1) {
              items[idx] = items[idx].copyWith(readAt: now);
            }
          });
        }
      } catch (_) {}
    }

    // 执行深链接跳转
    if (!mounted) return;
    if (item.route != null && item.route!.isNotEmpty) {
      NotificationRouter.navigate(
        context,
        item.route,
        item.routeParams,
        widget.state,
      );
    }
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(_identityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const bgColor = Color(0xFF0A0A12);
    final unreadCount = items.where((it) => !it.isRead).length;

    return Scaffold(
      backgroundColor: bgColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LText('系统通知'),
            if (unreadCount > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (items.any((it) => !it.isRead))
            IconButton(
              icon: const Icon(Icons.done_all, size: 20),
              tooltip: '全部已读',
              onPressed: _markAllAsRead,
            ),
          IconButton(
            icon: const Icon(Icons.tune_outlined, size: 20),
            tooltip: '通知设置',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationSettingsPage(state: widget.state),
                ),
              );
            },
          ),
        ],
      ),
      body: owner == null
          ? const Center(child: LText('请先登录'))
          : Column(
              children: [
                _buildCategoryFilter(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _load,
                    child: _buildList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildCategoryFilter() {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        itemCount: categories.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = categories[index];
          final selected = selectedCategory == cat.key;
          return GestureDetector(
            onTap: () {
              if (selectedCategory == cat.key) return;
              setState(() => selectedCategory = cat.key);
              _load();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: selected
                    ? const LinearGradient(
                        colors: [Color(0xFF00C6FF), Color(0xFF7B4397)],
                      )
                    : null,
                color: selected ? null : const Color(0x801E1E2E),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? Colors.transparent : const Color(0xFF2F2F43),
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  cat.label,
                  style: TextStyle(
                    color: selected ? Colors.white : const Color(0xFFB0B0C0),
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildList() {
    if (loading && items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null && items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error!, style: const TextStyle(color: Color(0xFFFF5555))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _load, child: const LText('重试')),
          ],
        ),
      );
    }

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: LText('暂无通知'),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return _buildNotificationCard(item);
      },
    );
  }

  Widget _buildNotificationCard(NotificationItem item) {
    final (icon, iconColor) = _resolveCategoryStyle(item.category);
    final hasDeepLink = item.route != null && item.route!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: item.isRead ? const Color(0x401E1E2E) : const Color(0x801E1E2E),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: item.isRead ? const Color(0xFF2F2F43) : const Color(0x6600C6FF),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _onNotificationTap(item),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                  ),
                  child: Icon(icon, color: iconColor, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              item.title,
                              style: TextStyle(
                                color: item.isRead ? const Color(0xFFB0B0C0) : Colors.white,
                                fontSize: 15,
                                fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!item.isRead)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 6),
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFF00C6FF),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.body,
                        style: const TextStyle(
                          color: Color(0xFFB0B0C0),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      if (hasDeepLink) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              _getDeepLinkActionText(item.route!),
                              style: const TextStyle(
                                color: Color(0xFF00C6FF),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const Icon(
                              Icons.arrow_forward_ios,
                              size: 10,
                              color: Color(0xFF00C6FF),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  (IconData, Color) _resolveCategoryStyle(String category) {
    switch (category) {
      case 'MARKET':
        return (Icons.trending_up, const Color(0xFF00C6FF));
      case 'SECURITY':
        return (Icons.shield_outlined, const Color(0xFFFF5555));
      case 'TRADE':
        return (Icons.candlestick_chart, const Color(0xFF00E08F));
      case 'RISK':
        return (Icons.warning_amber_rounded, const Color(0xFFFF5555));
      case 'WALLET':
        return (Icons.account_balance_wallet_outlined, const Color(0xFF7B4397));
      case 'C2C':
        return (Icons.swap_horiz, const Color(0xFFFFB300));
      default:
        return (Icons.notifications_none, const Color(0xFFB0B0C0));
    }
  }

  String _getDeepLinkActionText(String route) {
    if (route.startsWith('/trade')) return '前往交易查看';
    if (route.startsWith('/wallet')) return '前往钱包查看';
    if (route.startsWith('/c2c')) return '前往C2C交易';
    if (route.startsWith('/security')) return '前往安全中心';
    if (route.startsWith('/orders')) return '前往订单历史';
    return '点击查看详情';
  }
}
