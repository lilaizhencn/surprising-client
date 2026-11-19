import '../i18n/client_messages.dart';
import 'package:material_ui/material_ui.dart';
import '../app_scope.dart';
import '../app_state.dart';
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
  int? _openingAnnouncementId;

  Future<void> _openAnnouncement(
    AppState state,
    Map<String, dynamic> row,
  ) async {
    final id = _announcementId(row);
    if (id == null || _openingAnnouncementId != null) return;
    setState(() => _openingAnnouncementId = id);
    try {
      final fresh = await state.loadAnnouncementDetail(id);
      if (!mounted) return;
      final detail = fresh ?? state.announcementDetails[id];
      if (detail == null) return;
      final listRow = state.announcements
          .where((item) => _announcementId(item) == id)
          .firstOrNull;
      final alreadyRead = listRow?['readAt'] != null;
      // Read status follows the latest list / mark-read response, never the cached body.
      if (fresh != null && state.isLoggedIn && !alreadyRead) {
        await state.markAnnouncementRead(id);
      }
      if (!mounted) return;
      final title = '${detail['title'] ?? row['title'] ?? ''}';
      final html = detail['bodyHtml'] is String
          ? detail['bodyHtml'] as String
          : '';
      final language = state.language;
      if (html.isNotEmpty) {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => ArticleReaderPage(
              title: title,
              html: html,
              gatewayBaseUrl: state.api.config.gatewayBaseUrl,
              language: language,
              locale:
                  '${detail['locale'] ?? (language == ClientLanguage.en ? 'en-US' : 'zh-CN')}',
            ),
          ),
        );
      } else {
        await Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => _AnnouncementDetailPage(
              title: title,
              category: _announcementCategory(detail['category'], language),
              body: '${detail['body'] ?? ''}',
              publishedAt: '${detail['startsAt'] ?? ''}',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingAnnouncementId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final language = state.language;
    final rows = state.announcements;
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
              TextButton(
                key: const ValueKey('mark-all-announcements-read'),
                onPressed:
                    !state.isLoggedIn ||
                        state.unreadAnnouncementCount == 0 ||
                        state.announcementsLoading
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
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
                        child: LText(
                          clientText(
                            language,
                            '未读 ${state.unreadAnnouncementCount} 条',
                            '${state.unreadAnnouncementCount} unread',
                          ),
                        ),
                      ),
                      for (final row in rows)
                        Card(
                          child: ListTile(
                            leading: _openingAnnouncementId == _announcementId(row)
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
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
                                : () => _openAnnouncement(state, row),
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

class _AnnouncementDetailPage extends StatelessWidget {
  const _AnnouncementDetailPage({
    required this.title,
    required this.category,
    required this.body,
    required this.publishedAt,
  });

  final String title;
  final String category;
  final String body;
  final String publishedAt;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: LText(category)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          if (publishedAt.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(publishedAt, style: Theme.of(context).textTheme.labelMedium),
          ],
          const SizedBox(height: 16),
          SelectableText(body),
        ],
      ),
    );
  }
}
