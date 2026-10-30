import '../i18n/client_messages.dart';
import 'package:flutter/material.dart';
import '../app_scope.dart';
import '../models.dart';
import '../ui/client_components.dart';
import 'article_reader.dart';

String _announcementCategory(Object? value, ClientLanguage language) {
  return switch ('$value') {
    'PRODUCT' => clientText(language, '产品更新', 'Product update'),
    'MAINTENANCE' => clientText(language, '维护通知', 'Maintenance'),
    'SECURITY' => clientText(language, '安全通知', 'Security'),
    'RISK' => clientText(language, '风险提示', 'Risk notice'),
    _ => clientText(language, '平台公告', 'General'),
  };
}

int? _announcementId(Map<String, dynamic>? row) {
  final id = parseInt64(row?['announcementId']);
  return id != null && id > 0 ? id : null;
}

class AnnouncementCenterPage extends StatefulWidget {
  const AnnouncementCenterPage({required this.onClose, super.key});

  final VoidCallback onClose;

  @override
  State<AnnouncementCenterPage> createState() => _AnnouncementCenterPageState();
}

class _AnnouncementCenterPageState extends State<AnnouncementCenterPage> {
  int? selectedAnnouncementId;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final language = state.language;
    final rows = state.announcements;
    final available = rows.where((row) => _announcementId(row) != null);
    final selected =
        available
            .where((row) => _announcementId(row) == selectedAnnouncementId)
            .firstOrNull ??
        available.where((row) => row['readAt'] == null).firstOrNull ??
        available.firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              IconButton(
                onPressed: widget.onClose,
                icon: const Icon(Icons.arrow_back),
              ),
              Expanded(
                child: LText(
                  clientText(language, '公告中心', 'Announcements'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              IconButton(
                tooltip: clientText(language, '刷新', 'Refresh'),
                onPressed: state.announcementsLoading
                    ? null
                    : state.refreshAnnouncements,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        if (state.announcementError != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: LText(
              state.announcementError!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: state.refreshAnnouncements,
            child: rows.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: 90),
                      Icon(
                        Icons.campaign_outlined,
                        size: 44,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: 14),
                      Center(
                        child: LText(
                          clientText(language, '暂无公告', 'No announcements yet'),
                        ),
                      ),
                    ],
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: LText(
                              clientText(
                                language,
                                '未读 ${state.unreadAnnouncementCount} 条',
                                '${state.unreadAnnouncementCount} unread',
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: state.unreadAnnouncementCount == 0
                                ? null
                                : () async {
                                    await state.markAllAnnouncementsRead();
                                    if (mounted) setState(() {});
                                  },
                            child: LText(
                              clientText(language, '全部已读', 'Mark all read'),
                            ),
                          ),
                        ],
                      ),
                      if (selected != null) ...[
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _announcementCategory(
                                    selected['category'],
                                    language,
                                  ),
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${selected['title'] ?? ''}',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                if ('${selected['summary'] ?? ''}'
                                    .isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text('${selected['summary']}'),
                                ],
                                const SizedBox(height: 14),
                                if (selected['bodyHtml'] is String &&
                                    (selected['bodyHtml'] as String).isNotEmpty)
                                  FilledButton.tonalIcon(
                                    icon: const Icon(Icons.article_outlined),
                                    label: LText(
                                      clientText(
                                        language,
                                        '阅读完整公告',
                                        'Read full announcement',
                                      ),
                                    ),
                                    onPressed: () =>
                                        Navigator.of(context).push<void>(
                                          MaterialPageRoute(
                                            builder: (_) => ArticleReaderPage(
                                              title:
                                                  '${selected['title'] ?? ''}',
                                              html:
                                                  selected['bodyHtml']
                                                      as String,
                                              gatewayBaseUrl: state
                                                  .api
                                                  .config
                                                  .gatewayBaseUrl,
                                              language: language,
                                              locale:
                                                  '${selected['locale'] ?? (language == ClientLanguage.en ? 'en-US' : 'zh-CN')}',
                                            ),
                                          ),
                                        ),
                                  )
                                else
                                  SelectableText('${selected['body'] ?? ''}'),
                                const SizedBox(height: 12),
                                Text(
                                  '${selected['startsAt'] ?? ''}',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.labelMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      for (final row in rows)
                        Card(
                          color:
                              _announcementId(row) != null &&
                                  _announcementId(row) ==
                                      _announcementId(selected)
                              ? Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHighest
                              : null,
                          child: ListTile(
                            leading: Icon(
                              row['readAt'] == null
                                  ? Icons.markunread_outlined
                                  : Icons.drafts_outlined,
                            ),
                            title: Text(
                              '${row['title'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(
                              _announcementId(row) == null
                                  ? clientText(
                                      language,
                                      '公告暂不可用，请刷新',
                                      'Announcement unavailable. Refresh to retry.',
                                    )
                                  : '${row['summary'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: _announcementId(row) == null
                                ? null
                                : () async {
                                    final id = _announcementId(row);
                                    if (id == null) return;
                                    setState(() => selectedAnnouncementId = id);
                                    if (row['readAt'] == null) {
                                      await state.markAnnouncementRead(id);
                                    }
                                  },
                          ),
                        ),
                      if (state.announcementsHasMore)
                        Center(
                          child: TextButton(
                            onPressed: state.announcementsLoading
                                ? null
                                : state.loadMoreAnnouncements,
                            child: LText(
                              clientText(language, '加载更多', 'Load more'),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}
