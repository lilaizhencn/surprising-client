import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({required this.state, super.key});
  final AppState state;
  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<Map<String, dynamic>> rows = [];
  bool loading = false;
  String? error, owner;
  int generation = 0;

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
    rows = [];
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
      final result = await widget.state.api.notifications();
      if (mounted && request == generation && identity == owner) {
        setState(() => rows = result);
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() => error = '通知加载失败，请重试');
      }
    } finally {
      if (mounted && request == generation) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(_identityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('通知')),
    body: owner == null
        ? const Center(child: Text('请先登录'))
        : RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  ListTile(
                    title: Text(error!),
                    trailing: TextButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ),
                if (!loading && error == null && rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('暂无通知')),
                  ),
                for (final row in rows)
                  ListTile(
                    leading: Icon(
                      row['readAt'] == null
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_none,
                    ),
                    title: Text(asString(row['title'])),
                    subtitle: Text(asString(row['body'])),
                    onTap: () async {
                      final identity = owner;
                      try {
                        await widget.state.api.post(
                          '/api/v1/notifications/${row['notificationId']}/read',
                          const {},
                        );
                        if (!mounted || owner != identity) return;
                        setState(
                          () =>
                              row['readAt'] = DateTime.now().toIso8601String(),
                        );
                      } catch (_) {
                        if (mounted && owner == identity) {
                          setState(() => error = '操作未完成，请重试');
                        }
                      }
                    },
                  ),
              ],
            ),
          ),
  );
}
