import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kline_chart/kline_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_state.dart';
import 'asset_overview.dart';
import 'api.dart';
import 'device_access_panel.dart';
import 'funding_records_page.dart';
import 'kyc_application_page.dart';
import 'kyc_documents_page.dart';
import 'deposit_page.dart';
import 'models.dart';
import 'spot_order.dart';
import 'spot_amend_order_sheet.dart';

const _ink = Color(0xFFF2F0F3);
const _muted = Color(0xFFC6CAD6);
const _paper = Color(0xFF111318);
const _panel = Color(0xFF191C23);
const _panelSoft = Color(0xFF222630);
const _line = Color(0xFF3B4252);
const _pink = Color(0xFF7C9AFF);
const _violet = Color(0xFF5D82FF);
const _mint = Color(0xFF55DF9A);
const _red = Color(0xFFFF7D86);
const _amber = Color(0xFFF1B85C);
const _lime = Color(0xFFF1B85C);

String clientText(ClientLanguage language, String zh, String en) {
  return language == ClientLanguage.en ? en : zh;
}

String _announcementCategory(Object? value, ClientLanguage language) {
  return switch ('$value') {
    'PRODUCT' => clientText(language, '产品更新', 'Product update'),
    'MAINTENANCE' => clientText(language, '维护通知', 'Maintenance'),
    'SECURITY' => clientText(language, '安全通知', 'Security'),
    'RISK' => clientText(language, '风险提示', 'Risk notice'),
    _ => clientText(language, '平台公告', 'General'),
  };
}

String tradingRecoveryLabel(PendingTradingOrder? pending) {
  if (pending?.cancelPlan != null) return '确认并继续撤单';
  if (pending?.amendRequestId != null) return '查询改单结果';
  if (pending?.cancelOrderId != null) return '查询撤单结果';
  return '查询委托结果';
}

String tradingPendingMessage(PendingTradingOrder? pending) {
  final plan = pending?.cancelPlan;
  if (plan != null) {
    return '现货批量撤单：已确认 ${plan.completed + plan.failed}/${plan.requested} 笔，请确认后继续';
  }
  if (pending?.amendRequestId != null) return '改单结果待确认，请勿重复提交';
  if (pending?.cancelOrderId != null) return '撤单结果待确认，请勿重复提交';
  return '委托结果待确认，请勿重复提交';
}

Future<void> confirmSpotCancellation(
  BuildContext context,
  AppState state,
) async {
  final user = state.userId,
      onlyCurrent = state.onlyCurrentTradingPair,
      symbol = state.selectedSymbol;
  final accepted = await showDialog<bool>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(onlyCurrent ? '撤销 $symbol 当前委托？' : '撤销全部现货委托？'),
      content: const Text('只处理本次读取到的委托。部分成交或已结束的订单可能无法撤销，请查看逐项结果。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog, false),
          child: const Text('返回'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog, true),
          child: const Text('确认撤单'),
        ),
      ],
    ),
  );
  if (accepted == true &&
      context.mounted &&
      state.userId == user &&
      state.mode == ProductMode.spot &&
      (!onlyCurrent || state.selectedSymbol == symbol)) {
    await state.cancelOpenSpotOrders(onlyCurrentPair: onlyCurrent);
  }
}

class AppScope extends InheritedNotifier<AppState> {
  const AppScope({
    required AppState super.notifier,
    required super.child,
    super.key,
  });

  static AppState of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}

class SurprisingClientApp extends StatefulWidget {
  const SurprisingClientApp({super.key, this.state, this.bootstrap = true});

  final AppState? state;
  final bool bootstrap;

  @override
  State<SurprisingClientApp> createState() => _SurprisingClientAppState();
}

class _SurprisingClientAppState extends State<SurprisingClientApp> {
  late final AppState state = widget.state ?? AppState();

  @override
  void initState() {
    super.initState();
    if (widget.bootstrap) {
      unawaited(state.bootstrap());
    }
  }

  @override
  void dispose() {
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: AnimatedBuilder(
        animation: state,
        builder: (context, _) {
          final isLight = state.clientTheme == ClientTheme.light;
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Surprising',
            locale: Locale(state.language.code),
            theme: ThemeData(
              brightness: isLight ? Brightness.light : Brightness.dark,
              useMaterial3: true,
              scaffoldBackgroundColor: isLight
                  ? const Color(0xFFFBF9FB)
                  : _paper,
              colorScheme: isLight
                  ? ColorScheme.light(
                      primary: const Color(0xFF003EC7),
                      onSurface: const Color(0xFF1B1C1E),
                      onSurfaceVariant: const Color(0xFF434656),
                      outlineVariant: const Color(0xFFE9E7EA),
                      secondary: _violet,
                      tertiary: const Color(0xFF006D3F),
                      surface: Colors.white,
                      surfaceContainerHighest: const Color(0xFFF5F3F6),
                      error: const Color(0xFF9E0D22),
                    )
                  : const ColorScheme.dark(
                      primary: _pink,
                      onPrimary: Color(0xFF111318),
                      onSurface: _ink,
                      onSurfaceVariant: _muted,
                      outlineVariant: _line,
                      secondary: _violet,
                      tertiary: _mint,
                      surface: _panel,
                      surfaceContainerHighest: _panelSoft,
                      error: _red,
                    ),
              canvasColor: isLight ? const Color(0xFFFBF9FB) : _paper,
              dividerColor: isLight ? const Color(0xFFD9DEE5) : _line,
              textTheme: TextTheme(
                titleLarge: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: isLight ? const Color(0xFF1B1C1E) : _ink,
                ),
                titleMedium: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: isLight ? const Color(0xFF1B1C1E) : _ink,
                ),
                bodyMedium: TextStyle(
                  fontSize: 12,
                  color: isLight ? const Color(0xFF1B1C1E) : _ink,
                ),
                labelMedium: TextStyle(
                  fontSize: 11,
                  color: isLight ? const Color(0xFF5F7482) : _muted,
                ),
              ),
              snackBarTheme: SnackBarThemeData(
                backgroundColor: _panel,
                contentTextStyle: TextStyle(color: _ink, fontSize: 13),
              ),
              bottomSheetTheme: BottomSheetThemeData(
                backgroundColor: isLight ? Colors.white : _panel,
                surfaceTintColor: Colors.transparent,
                dragHandleColor: _line,
              ),
              navigationBarTheme: NavigationBarThemeData(
                backgroundColor: _panel,
                indicatorColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                labelTextStyle: WidgetStateProperty.resolveWith(
                  (states) => TextStyle(
                    color: states.contains(WidgetState.selected)
                        ? _ink
                        : _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                iconTheme: WidgetStateProperty.resolveWith(
                  (states) => IconThemeData(
                    color: states.contains(WidgetState.selected)
                        ? _amber
                        : _muted,
                  ),
                ),
              ),
              chipTheme: ChipThemeData(
                backgroundColor: isLight ? const Color(0xFFF5F3F6) : _panelSoft,
                selectedColor: _pink.withValues(alpha: .20),
                side: BorderSide(
                  color: isLight ? const Color(0xFFC3C5D9) : _line,
                ),
                labelStyle: TextStyle(
                  color: isLight ? const Color(0xFF1B1C1E) : _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                secondaryLabelStyle: TextStyle(
                  color: isLight ? const Color(0xFF1B1C1E) : _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              iconButtonTheme: IconButtonThemeData(
                style: IconButton.styleFrom(
                  backgroundColor: isLight
                      ? const Color(0xFFF5F3F6)
                      : _panelSoft,
                  foregroundColor: isLight ? const Color(0xFF1B1C1E) : _ink,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isLight ? const Color(0xFFC3C5D9) : _line,
                    ),
                  ),
                ),
              ),
              filledButtonTheme: FilledButtonThemeData(
                style: FilledButton.styleFrom(
                  backgroundColor: isLight ? const Color(0xFF003EC7) : _pink,
                  foregroundColor: isLight ? Colors.white : _paper,
                  disabledBackgroundColor: _panelSoft,
                  disabledForegroundColor: _muted,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              outlinedButtonTheme: OutlinedButtonThemeData(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isLight ? const Color(0xFF1B1C1E) : _ink,
                  side: BorderSide(
                    color: isLight ? const Color(0xFFC3C5D9) : _line,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            home: const ClientShell(),
          );
        },
      ),
    );
  }
}

class ClientShell extends StatefulWidget {
  const ClientShell({super.key});

  @override
  State<ClientShell> createState() => _ClientShellState();
}

class _ClientShellState extends State<ClientShell> {
  int index = 0;
  String? seenNotice;
  String? seenError;
  bool announcementsOpen = false;
  bool checkedAnnouncementModal = false;
  String lastAnnouncementModalFingerprint = '';
  final Set<String> shownAnnouncementModals = {};

  void openInstrument(Instrument instrument) {
    setState(() => index = instrument.isSpot ? 2 : 3);
  }

  void setTab(int next) {
    final state = AppScope.of(context);
    if (next == 2) unawaited(state.selectMode(ProductMode.spot));
    if (next == 3 && state.mode.isSpot) {
      unawaited(state.selectMode(ProductMode.linear));
    }
    setState(() {
      index = next;
      announcementsOpen = false;
    });
  }

  void openAnnouncements() => setState(() => announcementsOpen = true);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    _showMessage(context, state);
    _maybeShowAnnouncementModal(state);
    final page = announcementsOpen
        ? AnnouncementCenterPage(
            onClose: () => setState(() => announcementsOpen = false),
          )
        : switch (index) {
            0 => const HomePage(),
            1 => const MarketsPage(),
            2 => TradePage(
              key: ValueKey('trade-${state.mode.name}-${state.selectedSymbol}'),
            ),
            3 => TradePage(
              key: ValueKey(
                'contract-${state.mode.name}-${state.selectedSymbol}',
              ),
            ),
            _ => const WalletPage(),
          };
    return Scaffold(
      body: SafeArea(child: page),
      bottomNavigationBar: ExchangeBottomNav(
        selectedIndex: index,
        onSelected: (next) {
          if (next == 2) {
            unawaited(state.selectMode(ProductMode.spot));
          } else if (next == 3 && state.mode.isSpot) {
            unawaited(state.selectMode(ProductMode.linear));
          }
          setState(() {
            index = next;
            announcementsOpen = false;
          });
        },
      ),
    );
  }

  void _maybeShowAnnouncementModal(AppState state) {
    if (!state.isLoggedIn || state.announcementsLoading) return;
    if (state.announcementError != null) return;
    final fingerprint = state.announcementModals
        .map((row) => '${row['announcementId']}:${row['readAt'] ?? ''}')
        .join('|');
    if (fingerprint != lastAnnouncementModalFingerprint) {
      lastAnnouncementModalFingerprint = fingerprint;
      checkedAnnouncementModal = false;
    }
    if (checkedAnnouncementModal) return;
    final next = state.announcementModals.where((row) {
      final id = '${row['announcementId'] ?? ''}';
      return id.isNotEmpty &&
          row['readAt'] == null &&
          !shownAnnouncementModals.contains(id);
    }).firstOrNull;
    if (next == null) {
      checkedAnnouncementModal = true;
      return;
    }
    final id = '${next['announcementId']}';
    shownAnnouncementModals.add(id);
    checkedAnnouncementModal = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !state.isLoggedIn) return;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (dialogContext) {
          final language = state.language;
          return AlertDialog(
            icon: const Icon(Icons.campaign_outlined),
            title: Text(
              '${next['title'] ?? clientText(language, '公告', 'Announcement')}',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if ('${next['summary'] ?? ''}'.isNotEmpty)
                    Text('${next['summary']}'),
                  const SizedBox(height: 12),
                  Text('${next['body'] ?? ''}'),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  openAnnouncements();
                },
                child: Text(
                  clientText(language, '公告中心', 'Announcement center'),
                ),
              ),
              FilledButton(
                onPressed: () async {
                  final navigator = Navigator.of(dialogContext);
                  final success = await state.markAnnouncementRead(
                    int.tryParse(id) ?? 0,
                    placement: 'MODAL',
                  );
                  if (success && navigator.mounted) navigator.pop();
                },
                child: Text(clientText(language, '已阅读', 'Read')),
              ),
            ],
          );
        },
      );
    });
  }

  void _showMessage(BuildContext context, AppState state) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final media = MediaQuery.maybeOf(context);
      final size = media?.size;
      if (size == null || size.width <= 0 || size.height <= 0) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      if (state.lastError != null && state.lastError != seenError) {
        seenError = state.lastError;
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(content: Text(state.lastError!), backgroundColor: _red),
        );
        return;
      }
      if (state.lastNotice != null && state.lastNotice != seenNotice) {
        seenNotice = state.lastNotice;
        messenger.clearSnackBars();
        messenger.showSnackBar(SnackBar(content: Text(state.lastNotice!)));
      }
    });
  }
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
    final selected =
        rows
            .where(
              (row) => asInt(row['announcementId']) == selectedAnnouncementId,
            )
            .firstOrNull ??
        rows.where((row) => row['readAt'] == null).firstOrNull ??
        rows.firstOrNull;
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
                child: Text(
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
            child: Text(
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
                        child: Text(
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
                            child: Text(
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
                            child: Text(
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
                              asInt(row['announcementId']) ==
                                  asInt(selected?['announcementId'])
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
                              '${row['summary'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () async {
                              final id = asInt(row['announcementId']);
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
                            child: Text(
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

class ExchangeBottomNav extends StatelessWidget {
  const ExchangeBottomNav({
    required this.selectedIndex,
    required this.onSelected,
    super.key,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final language = AppScope.of(context).language;
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final exchangeItems = [
      _ExchangeNavItem(
        Icons.grid_view_outlined,
        Icons.grid_view,
        clientText(language, '首页', 'Home'),
      ),
      _ExchangeNavItem(
        Icons.show_chart,
        Icons.show_chart,
        clientText(language, '行情', 'Markets'),
      ),
      _ExchangeNavItem(
        Icons.sync_alt,
        Icons.sync_alt,
        clientText(language, '交易', 'Trade'),
      ),
      _ExchangeNavItem(
        Icons.receipt_long_outlined,
        Icons.receipt_long,
        clientText(language, '合约', 'Contracts'),
      ),
      _ExchangeNavItem(
        Icons.account_balance_wallet_outlined,
        Icons.account_balance_wallet,
        clientText(language, '资产', 'Assets'),
      ),
    ];
    return Container(
      height: 56 + bottomInset,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
            width: .7,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < exchangeItems.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onSelected(i),
                child: _ExchangeNavButton(
                  item: exchangeItems[i],
                  selected: selectedIndex == i,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExchangeNavItem {
  const _ExchangeNavItem(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _ExchangeNavButton extends StatelessWidget {
  const _ExchangeNavButton({required this.item, required this.selected});

  final _ExchangeNavItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final selectedColor = Theme.of(context).colorScheme.primary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          selected ? item.selectedIcon : item.icon,
          color: selected
              ? selectedColor
              : Theme.of(context).colorScheme.onSurfaceVariant,
          size: 24,
        ),
        const SizedBox(height: 2),
        Text(
          item.label,
          style: TextStyle(
            color: selected
                ? selectedColor
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Container(
          width: selected ? 14 : 0,
          height: 2,
          decoration: BoxDecoration(
            color: selectedColor,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ],
    );
  }
}

class ExchangeNavGlyph extends StatelessWidget {
  const ExchangeNavGlyph({
    required this.label,
    required this.color,
    required this.selected,
    super.key,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(24),
      painter: _ExchangeNavGlyphPainter(
        label: label,
        color: color,
        selected: selected,
      ),
    );
  }
}

class _ExchangeNavGlyphPainter extends CustomPainter {
  const _ExchangeNavGlyphPainter({
    required this.label,
    required this.color,
    required this.selected,
  });

  final String label;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = selected ? 2.4 : 2.1
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    switch (label) {
      case '首页':
        _drawHome(canvas, size, fill);
      case '行情':
        _drawMarket(canvas, size, stroke);
      case '探索':
        _drawExplore(canvas, size, fill);
      case '交易':
        _drawTrade(canvas, size, stroke);
      case '合约':
        _drawContract(canvas, size, stroke, fill);
      case '资产':
        _drawWallet(canvas, size, stroke, fill);
      default:
        canvas.drawCircle(size.center(Offset.zero), size.width * .34, stroke);
    }
  }

  void _drawExplore(Canvas canvas, Size size, Paint fill) {
    final center = size.center(Offset.zero);
    final path = Path()
      ..moveTo(center.dx, size.height * .16)
      ..lineTo(size.width * .72, size.height * .72)
      ..lineTo(center.dx, size.height * .60)
      ..lineTo(size.width * .28, size.height * .72)
      ..close();
    canvas.drawPath(path, fill);
  }

  void _drawHome(Canvas canvas, Size size, Paint fill) {
    final unit = size.width / 5.6;
    final gap = unit * .54;
    final start = Offset(size.width * .18, size.height * .18);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        final rect = Rect.fromLTWH(
          start.dx + col * (unit + gap),
          start.dy + row * (unit + gap),
          unit,
          unit,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(unit * .14)),
          fill,
        );
      }
    }
  }

  void _drawMarket(Canvas canvas, Size size, Paint stroke) {
    final path = Path()
      ..moveTo(size.width * .14, size.height * .70)
      ..lineTo(size.width * .34, size.height * .52)
      ..lineTo(size.width * .48, size.height * .62)
      ..lineTo(size.width * .75, size.height * .34);
    canvas.drawPath(path, stroke);
    canvas.drawLine(
      Offset(size.width * .75, size.height * .34),
      Offset(size.width * .75, size.height * .52),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .75, size.height * .34),
      Offset(size.width * .57, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .18, size.height * .82),
      Offset(size.width * .68, size.height * .82),
      stroke,
    );
  }

  void _drawTrade(Canvas canvas, Size size, Paint stroke) {
    canvas.drawLine(
      Offset(size.width * .22, size.height * .34),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .66, size.height * .22),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .66, size.height * .46),
      Offset(size.width * .78, size.height * .34),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .78, size.height * .66),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .54),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .34, size.height * .78),
      Offset(size.width * .22, size.height * .66),
      stroke,
    );
  }

  void _drawContract(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final rect = Rect.fromLTWH(
      size.width * .24,
      size.height * .14,
      size.width * .50,
      size.height * .68,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * .06)),
      stroke,
    );
    for (final y in [.32, .48, .64]) {
      canvas.drawLine(
        Offset(size.width * .34, size.height * y),
        Offset(size.width * .64, size.height * y),
        stroke,
      );
    }
    final diamond = Path()
      ..moveTo(size.width * .76, size.height * .70)
      ..lineTo(size.width * .84, size.height * .78)
      ..lineTo(size.width * .76, size.height * .86)
      ..lineTo(size.width * .68, size.height * .78)
      ..close();
    canvas.drawPath(diamond, fill);
  }

  void _drawWallet(Canvas canvas, Size size, Paint stroke, Paint fill) {
    final rect = Rect.fromLTWH(
      size.width * .17,
      size.height * .25,
      size.width * .66,
      size.height * .50,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.width * .08)),
      stroke,
    );
    canvas.drawLine(
      Offset(size.width * .27, size.height * .25),
      Offset(size.width * .43, size.height * .12),
      stroke,
    );
    final pocket = Rect.fromLTWH(
      size.width * .54,
      size.height * .41,
      size.width * .29,
      size.height * .22,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(pocket, Radius.circular(size.width * .05)),
      stroke,
    );
    canvas.drawCircle(Offset(size.width * .65, size.height * .52), 1.5, fill);
  }

  @override
  bool shouldRepaint(covariant _ExchangeNavGlyphPainter oldDelegate) {
    return oldDelegate.label != label ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          state.refreshInstruments(),
          state.refreshAnnouncements(),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Surprising',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Stack(
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    tooltip: clientText(
                      state.language,
                      '公告中心',
                      'Announcements',
                    ),
                    onPressed: () => context
                        .findAncestorStateOfType<_ClientShellState>()
                        ?.openAnnouncements(),
                    icon: const Icon(Icons.campaign_outlined),
                  ),
                  if (state.unreadAnnouncementCount > 0)
                    Positioned(
                      right: 5,
                      top: 4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE5484D),
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                        child: Center(
                          child: Text(
                            state.unreadAnnouncementCount > 99
                                ? '99+'
                                : '${state.unreadAnnouncementCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                tooltip: '账户',
                onPressed: () {
                  if (state.isLoggedIn) {
                    context
                        .findAncestorStateOfType<_ClientShellState>()
                        ?.setTab(4);
                  } else {
                    showAuthSheet(context);
                  }
                },
                icon: const Icon(Icons.account_circle_outlined),
              ),
            ],
          ),
          for (final announcement in state.announcementBanners.take(1))
            Card(
              child: ListTile(
                leading: const Icon(Icons.campaign_outlined),
                title: Text(
                  '${announcement['title'] ?? clientText(state.language, '平台公告', 'Exchange announcement')}',
                ),
                subtitle: Text(
                  '${announcement['summary'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context
                    .findAncestorStateOfType<_ClientShellState>()
                    ?.openAnnouncements(),
              ),
            ),
          const SizedBox(height: 24),
          Text(
            '交易，从这里开始',
            style: Theme.of(
              context,
            ).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          const Text('现货 · 永续 · 交割 · 期权'),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () =>
                context.findAncestorStateOfType<_ClientShellState>()?.setTab(3),
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('开始永续交易'),
            ),
          ),
          if (!state.isLoggedIn)
            OutlinedButton(
              onPressed: () => showAuthSheet(context),
              child: const Text('登录 / 创建账户'),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(state.session!.user.username),
              subtitle: Text(state.session!.user.email),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context
                  .findAncestorStateOfType<_ClientShellState>()
                  ?.setTab(4),
            ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  '市场概览',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () => context
                    .findAncestorStateOfType<_ClientShellState>()
                    ?.setTab(1),
                child: const Text('全部行情'),
              ),
            ],
          ),
          if (state.instruments
              .where((i) => i.mode == ProductMode.linear)
              .isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('暂无行情，下拉刷新'),
            ),
          for (final instrument
              in state.instruments
                  .where((i) => i.mode == ProductMode.linear)
                  .take(8))
            PublicMarketRow(instrument: instrument),
        ],
      ),
    );
  }
}

class MarketsPage extends StatefulWidget {
  const MarketsPage({super.key});
  @override
  State<MarketsPage> createState() => _MarketsPageState();
}

class _MarketsPageState extends State<MarketsPage> {
  String query = '';
  ProductMode product = ProductMode.linear;
  bool sortByChange = false;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final items = state.instruments
        .where(
          (i) =>
              i.mode == product &&
              i.symbol.toLowerCase().contains(query.toLowerCase()),
        )
        .toList();
    if (sortByChange) {
      items.sort(
        (a, b) => (b.change24h ?? double.negativeInfinity).compareTo(
          a.change24h ?? double.negativeInfinity,
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: state.refreshInstruments,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('行情', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('market-search'),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索交易对',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => query = v),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final mode in ProductMode.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(mode.label),
                      selected: product == mode,
                      onSelected: (_) => setState(() => product = mode),
                    ),
                  ),
              ],
            ),
          ),
          Row(
            children: [
              const Expanded(child: Text('交易对 / 最新价')),
              TextButton(
                onPressed: () => setState(() => sortByChange = !sortByChange),
                child: Text(sortByChange ? '24h 涨跌幅 ↓' : '24h 涨跌幅'),
              ),
            ],
          ),
          if (items.isEmpty)
            const Padding(padding: EdgeInsets.all(24), child: Text('暂无匹配的交易对')),
          for (final instrument in items)
            PublicMarketRow(instrument: instrument),
        ],
      ),
    );
  }
}

class PublicMarketRow extends StatelessWidget {
  const PublicMarketRow({required this.instrument, super.key});
  final Instrument instrument;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final price = state.latestPriceFor(instrument) ?? instrument.lastPrice;
    final change = instrument.change24h;
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () async {
        final shell = context.findAncestorStateOfType<_ClientShellState>();
        unawaited(state.selectInstrument(instrument));
        shell?.openInstrument(instrument);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instrument.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    instrument.mode.label,
                    style: TextStyle(
                      color: colors.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Text(
                price == null
                    ? '--'
                    : money(price, digits: instrument.pricePrecision),
                textAlign: TextAlign.end,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 76,
              child: Text(
                change == null
                    ? '--'
                    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                textAlign: TextAlign.end,
                style: TextStyle(
                  color: change == null
                      ? colors.onSurfaceVariant
                      : change >= 0
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TradePage extends StatefulWidget {
  const TradePage({super.key});

  @override
  State<TradePage> createState() => _TradePageState();
}

class _TradePageState extends State<TradePage> {
  final priceController = TextEditingController();
  final quantityController = TextEditingController();
  String side = 'BUY';
  String orderType = 'LIMIT';
  String timeInForce = 'GTC';
  String marginMode = 'CROSS';
  String positionSide = 'NET';
  bool reduceOnly = false;
  bool postOnly = false;
  bool bboEnabled = false;
  String bboPriceMode = 'OPPONENT_1';
  bool priceInitialized = false;

  @override
  void dispose() {
    priceController.dispose();
    quantityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final instrument = state.selectedInstrument;
    if (instrument.symbol.isEmpty) {
      return Column(
        children: [
          ProductLineTabs(
            value: state.mode,
            onChanged: (mode) => unawaited(state.selectMode(mode)),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                await state.refreshInstruments();
                await state.selectMode(state.mode);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  ProductPageSelector(
                    value: state.mode,
                    title: '交易产品页',
                    compact: true,
                    onChanged: (mode) => unawaited(state.selectMode(mode)),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    '${state.mode.label}暂无可交易合约',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text('可切换其他产品，或下拉刷新合约列表。', textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ],
      );
    }
    final latestPrice = state.latestPriceFor(instrument);
    if (state.orderBook.bids.isNotEmpty && !priceInitialized) {
      priceInitialized = true;
      priceController.text = instrument.isSpot
          ? scaledAmount(
              BigInt.from(state.orderBook.bids.first.priceTicks) *
                  BigInt.from(instrument.priceTickUnits),
              instrument.quoteScaleUnits,
            )
          : money(
              instrument.priceFromTicks(state.orderBook.bids.first.priceTicks),
              digits: instrument.pricePrecision,
            );
    }
    return Column(
      children: [
        ProductLineTabs(
          value: state.mode,
          onChanged: (mode) => unawaited(state.selectMode(mode)),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await state.refreshPublicData();
              await state.refreshPrivateData();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 20),
              children: [
                ProductPageSelector(
                  value: state.mode,
                  title: '交易产品页',
                  compact: true,
                  onChanged: (mode) => unawaited(state.selectMode(mode)),
                ),
                Divider(
                  height: 10,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                TradeSymbolHeader(
                  instrument: instrument,
                  latestPrice: latestPrice,
                  onRefresh: state.refreshPublicData,
                ),
                if (instrument.isDelivery || instrument.isOption) ...[
                  const SizedBox(height: 6),
                  ProductLifecyclePanel(
                    state: state,
                    instrument: instrument,
                    latestPrice: latestPrice,
                  ),
                ],
                if (instrument.isDerivative) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        Text(
                          '最新价 ${latestPrice == null ? '--' : money(latestPrice, digits: instrument.pricePrecision)}',
                        ),
                        Text(
                          '标记价 ${state.markPrices['${state.mode.productLine}:${instrument.symbol}'] == null ? '--' : money(instrument.priceFromTicks(state.markPrices['${state.mode.productLine}:${instrument.symbol}']!), digits: instrument.pricePrecision)}',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  ContractQuickSettings(
                    marginMode: marginMode,
                    leverage:
                        '${(instrument.maxLeveragePpm / 1000000).round()}x',
                    positionMode: state.positionMode,
                    onMarginMode: (value) => setState(() => marginMode = value),
                    onPositionMode: (mode) =>
                        unawaited(state.changePositionMode(mode)),
                  ),
                ],
                const SizedBox(height: 6),
                SymbolStrip(
                  instruments: state.visibleInstruments,
                  selected: state.selectedSymbol,
                  onSelected: (symbol) => unawaited(state.selectSymbol(symbol)),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 376,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        flex: 12,
                        child: OrderTicket(
                          side: side,
                          orderType: orderType,
                          timeInForce: timeInForce,
                          marginMode: marginMode,
                          positionMode: state.positionMode,
                          positionSide: positionSide,
                          reduceOnly: reduceOnly,
                          postOnly: postOnly,
                          bboEnabled: bboEnabled,
                          bboPriceMode: bboPriceMode,
                          onBboEnabled: (value) =>
                              setState(() => bboEnabled = value),
                          onBboPriceMode: (value) =>
                              setState(() => bboPriceMode = value),
                          priceController: priceController,
                          quantityController: quantityController,
                          instrument: instrument,
                          loggedIn: state.isLoggedIn,
                          onSide: (value) => setState(() => side = value),
                          onOrderType: (value) => setState(() {
                            orderType = value;
                            postOnly = false;
                            bboEnabled = false;
                            timeInForce = value == 'MARKET' ? 'IOC' : 'GTC';
                          }),
                          onTimeInForce: (value) => setState(() {
                            timeInForce = value;
                            postOnly = value == 'GTX';
                          }),
                          onMarginMode: (value) =>
                              setState(() => marginMode = value),
                          onPositionSide: (value) =>
                              setState(() => positionSide = value),
                          onReduceOnly: (value) =>
                              setState(() => reduceOnly = value),
                          onPostOnly: (value) => setState(() {
                            postOnly = value;
                            timeInForce = value ? 'GTX' : 'GTC';
                          }),
                          onSubmit: () {
                            if (state.submittingOrder) return;
                            if (!state.isLoggedIn) {
                              showAuthSheet(context);
                              return;
                            }
                            if (orderType != 'MARKET' &&
                                !bboEnabled &&
                                decimalIncrement(
                                      priceController.text,
                                      instrument.priceTickUnits,
                                      scaleUnits: instrument.isSpot
                                          ? instrument.quoteScaleUnits ?? 0
                                          : 100000000,
                                    ) ==
                                    null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('价格必须符合最小价格变动')),
                              );
                              return;
                            }
                            unawaited(
                              state.placeOrder(
                                side: side,
                                orderType: orderType,
                                timeInForce: timeInForce,
                                price:
                                    double.tryParse(priceController.text) ?? 0,
                                priceText: priceController.text,
                                quantitySteps: instrument.isSpot
                                    ? decimalIncrement(
                                            quantityController.text,
                                            instrument.quantityStepUnits,
                                            scaleUnits:
                                                instrument.baseScaleUnits ?? 0,
                                          ) ??
                                          0
                                    : int.tryParse(quantityController.text) ??
                                          0,
                                marginMode: instrument.isSpot
                                    ? 'CROSS'
                                    : marginMode,
                                positionSide:
                                    instrument.isSpot ||
                                        state.positionMode == 'ONE_WAY'
                                    ? 'NET'
                                    : positionSide == 'NET'
                                    ? (side == 'SELL' ? 'SHORT' : 'LONG')
                                    : positionSide,
                                reduceOnly: instrument.isSpot
                                    ? false
                                    : reduceOnly,
                                postOnly: postOnly,
                                bboPriceMode: orderType == 'LIMIT' && bboEnabled
                                    ? bboPriceMode
                                    : null,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 9,
                        child: OrderBookPanel(
                          instrument: instrument,
                          orderBook: state.orderBook,
                          latestPrice: latestPrice,
                          onPrice: (price) {
                            setState(() {
                              bboEnabled = false;
                              orderType = 'LIMIT';
                              timeInForce = 'GTC';
                              postOnly = false;
                              priceController.text = price;
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (state.submittingOrder) const LinearProgressIndicator(),
                RecentTradesPanel(state: state),
                const SizedBox(height: 12),
                PrivateTradingPanel(state: state),
                if (instrument.isDerivative) ...[
                  Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                      childrenPadding: EdgeInsets.zero,
                      collapsedIconColor: Theme.of(
                        context,
                      ).colorScheme.onSurfaceVariant,
                      iconColor: Theme.of(context).colorScheme.onSurface,
                      title: const Text(
                        '高级委托',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      children: [
                        AlgoOrderPanel(state: state, marginMode: marginMode),
                        const SizedBox(height: 6),
                        TriggerOrderPanel(
                          key: ValueKey(
                            '${state.mode}-${state.selectedSymbol}-$marginMode-${state.positionMode}',
                          ),
                          state: state,
                          marginMode: marginMode,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                ],
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 2),
                    collapsedIconColor: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant,
                    iconColor: Theme.of(context).colorScheme.onSurface,
                    title: Text(
                      '${instrument.displayName.replaceAll('-', '')} ${instrument.contractLabel} K线图表',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    children: [
                      KlinePanel(
                        candles: state.candles,
                        period: state.period,
                        onPeriod: (period) =>
                            unawaited(state.selectPeriod(period)),
                      ),
                    ],
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

class WalletPage extends StatefulWidget {
  const WalletPage({super.key});

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  final toolsController = ExpansibleController();
  final toolsKey = GlobalKey();

  void _openTools(AppState state) {
    if (!state.isLoggedIn) {
      showAuthSheet(context);
      return;
    }
    toolsController.expand();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = toolsKey.currentContext;
      if (mounted && target != null) Scrollable.ensureVisible(target);
    });
  }

  final amountController = TextEditingController(text: '10');
  final transferEmailCodeController = TextEditingController();
  final transferTotpCodeController = TextEditingController();
  String source = 'FUNDING';
  String target = 'SPOT';
  String asset = 'USDT';
  String walletSymbol = 'USDT';

  @override
  void dispose() {
    toolsController.dispose();
    amountController.dispose();
    transferEmailCodeController.dispose();
    transferTotpCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: RefreshIndicator(
        onRefresh: () async {
          await Future.wait([
            state.refreshPrivateData(),
            state.refreshValuation(),
          ]);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            AssetOverview(
              state: state,
              onDeposit: () => _openRechargeFlow(context, state),
              onWithdraw: () => _openWithdrawalFlow(context, state),
              onTools: () => _openTools(state),
            ),
            if (!state.isLoggedIn)
              PrimaryAction(
                label: '登录 / 注册',
                icon: Icons.login,
                onPressed: () => showAuthSheet(context),
              )
            else
              Theme(
                data: Theme.of(context).copyWith(
                  dividerColor: Colors.transparent,
                  splashColor: Colors.transparent,
                  highlightColor: Colors.transparent,
                ),
                child: ExpansionTile(
                  key: toolsKey,
                  controller: toolsController,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: EdgeInsets.zero,
                  collapsedIconColor: Theme.of(context).colorScheme.onSurface,
                  iconColor: Theme.of(context).colorScheme.onSurface,
                  title: const Text(
                    '钱包工具',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                  children: [
                    Panel(
                      child: PrimaryAction(
                        label: '充值地址与网络',
                        icon: Icons.qr_code,
                        onPressed: () => _openRechargeFlow(context, state),
                      ),
                    ),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionTitle(title: '提币'),
                          Text(
                            '通过独立安全表单核对网络、地址、数量和验证信息。',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 10),
                          PrimaryAction(
                            label: '打开提币表单',
                            icon: Icons.call_made,
                            onPressed: () =>
                                _openWithdrawalFlow(context, state),
                          ),
                        ],
                      ),
                    ),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SectionTitle(title: '账户划转'),
                          Row(
                            children: [
                              Expanded(
                                child: SmallDropdown(
                                  value: source,
                                  values: productAccountTypes,
                                  labelBuilder: productAccountLabel,
                                  enabled: !state.transferOutcomeLocked,
                                  onChanged: (value) =>
                                      setState(() => source = value),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.symmetric(horizontal: 6),
                                child: Icon(Icons.arrow_forward, size: 18),
                              ),
                              Expanded(
                                child: SmallDropdown(
                                  value: target,
                                  values: productAccountTypes,
                                  labelBuilder: productAccountLabel,
                                  enabled: !state.transferOutcomeLocked,
                                  onChanged: (value) =>
                                      setState(() => target = value),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: AppTextField(
                                  controller: amountController,
                                  label: '数量',
                                  enabled: !state.transferOutcomeLocked,
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 86,
                                child: AppTextField(
                                  initialValue: asset,
                                  label: '资产',
                                  enabled: !state.transferOutcomeLocked,
                                  onChanged: (value) =>
                                      asset = value.toUpperCase(),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '小额划转无需额外验证；大额划转按 USDT 估值验证，绑定 2FA 后还需动态验证码。',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                          if (state.transferVerificationRequired) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: AppTextField(
                                    controller: transferEmailCodeController,
                                    label: '邮箱验证码',
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: AppTextField(
                                    controller: transferTotpCodeController,
                                    label: '2FA 验证码（未绑定可留空）',
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 10),
                          PrimaryAction(
                            label: state.transferSubmitting
                                ? '提交中…'
                                : state.transferOutcomeLocked
                                ? '等待结果确认'
                                : '确认划转',
                            icon: Icons.swap_horiz,
                            onPressed:
                                state.transferSubmitting ||
                                    state.transferOutcomeLocked
                                ? null
                                : () => unawaited(
                                    state.transfer(
                                      sourceAccountType: source,
                                      targetAccountType: target,
                                      asset: asset,
                                      amount:
                                          double.tryParse(
                                            amountController.text,
                                          ) ??
                                          0,
                                      amountText: amountController.text,
                                      emailCode:
                                          transferEmailCodeController.text,
                                      totpCode: transferTotpCodeController.text,
                                    ),
                                  ),
                          ),
                          if (state.transferOutcomeLocked)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                state.transferOutcomeTerminalFailure
                                    ? '本次划转已失败，可以重新填写后再试。'
                                    : '划转结果待确认，请勿重复提交。',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          if (state.transferOutcomeTerminalFailure)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: state.resetTransferIntent,
                                child: const Text('重新填写'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    SectionTitle(
                      title: '链上资产',
                      action: IconButton.filledTonal(
                        onPressed: () => unawaited(state.refreshWallet()),
                        icon: const Icon(Icons.refresh),
                      ),
                    ),

                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => FundingRecordsPage(state: state),
                        ),
                      ),
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('查看分类资金与交易记录'),
                    ),
                    const SectionTitle(title: '资金记录'),
                    if (state.walletError != null ||
                        state.walletOrdersError != null)
                      Text(state.walletError ?? state.walletOrdersError!),
                    ...state.walletOrders.map(
                      (record) => WalletOrderRecordRow(record: record),
                    ),
                    if (state.walletReady &&
                        state.walletOrdersError == null &&
                        state.walletOrders.isEmpty)
                      const EmptyState(text: '暂无资金记录'),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openRechargeFlow(BuildContext context, AppState state) {
    if (!state.isLoggedIn) {
      showAuthSheet(context);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => MobileDepositPage(state: state)),
    );
  }

  void _openWithdrawalFlow(BuildContext context, AppState state) {
    if (!state.isLoggedIn) {
      showAuthSheet(context);
      return;
    }
    unawaited(() async {
      await state.refreshWithdrawalRules();
      if (!context.mounted) return;
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => const WithdrawalPage()));
    }());
  }
}

class WithdrawalPage extends StatefulWidget {
  const WithdrawalPage({super.key});

  @override
  State<WithdrawalPage> createState() => _WithdrawalPageState();
}

class _WithdrawalPageState extends State<WithdrawalPage> {
  final addressController = TextEditingController();
  final amountController = TextEditingController();
  final emailCodeController = TextEditingController();
  final totpCodeController = TextEditingController();
  String? selectedSymbol;
  String? selectedChain;
  String? localError;

  @override
  void dispose() {
    addressController.dispose();
    amountController.dispose();
    emailCodeController.dispose();
    totpCodeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.withdrawalRulesReady) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              const RechargeHeader(title: '提币'),
              const SizedBox(height: 40),
              const EmptyState(text: '提币规则暂不可用，请刷新后重试'),
              const SizedBox(height: 16),
              PrimaryAction(
                label: state.withdrawalRulesLoading ? '刷新中…' : '刷新提币规则',
                icon: Icons.refresh,
                onPressed: state.withdrawalRulesLoading
                    ? null
                    : () => unawaited(state.refreshWithdrawalRules()),
              ),
            ],
          ),
        ),
      );
    }
    final assets = state.walletPortfolio.assets
        .where((item) => item.symbol.trim().isNotEmpty)
        .toList();
    if (assets.isEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
            children: [
              const RechargeHeader(title: '提币'),
              const SizedBox(height: 40),
              const EmptyState(text: '暂无可提币资产，请先刷新资金账户'),
              const SizedBox(height: 16),
              PrimaryAction(
                label: state.loadingPrivate ? '刷新中…' : '刷新资产',
                icon: Icons.refresh,
                onPressed: state.loadingPrivate
                    ? null
                    : () => unawaited(state.refreshWallet()),
              ),
            ],
          ),
        ),
      );
    }

    final symbolValues = assets.map((item) => item.symbol).toList();
    final symbol = symbolValues.contains(selectedSymbol)
        ? selectedSymbol!
        : symbolValues.first;
    final asset = assets.firstWhere((item) => item.symbol == symbol);
    final chainAssets = asset.chains.where((item) {
      final rule = state.withdrawalRuleFor(item.chain, symbol);
      return rule != null && rule.withdrawalEnabled;
    }).toList();
    final chainValues = chainAssets.map((item) => item.chain).toList();
    final chain = chainValues.contains(selectedChain)
        ? selectedChain!
        : chainValues.isEmpty
        ? ''
        : chainValues.first;
    final chainAsset = chainAssets.cast<WalletChainAsset?>().firstWhere(
      (item) => item?.chain == chain,
      orElse: () => null,
    );
    final rule = state.withdrawalRuleFor(chain, symbol);
    final locked = state.withdrawalSubmitting || state.withdrawalOutcomeLocked;
    final minimum = rule?.minimumAmount;
    final previewReceived = rule?.receivedAmount(amountController.text.trim());

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 32),
          children: [
            RechargeHeader(
              title: '提币',
              trailing: IconButton(
                tooltip: '刷新提币规则',
                onPressed: state.withdrawalRulesLoading
                    ? null
                    : () => unawaited(state.refreshWithdrawalRules()),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                ),
                icon: state.withdrawalRulesLoading
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh, size: 26),
              ),
            ),
            const SizedBox(height: 18),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(title: '资产与网络'),
                  Row(
                    children: [
                      Expanded(
                        child: SmallDropdown(
                          value: symbol,
                          values: symbolValues,
                          enabled: !locked,
                          onChanged: (next) => setState(() {
                            selectedSymbol = next;
                            selectedChain = null;
                            localError = null;
                          }),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: chainValues.isEmpty
                            ? Text(
                                '无可用网络',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              )
                            : SmallDropdown(
                                value: chain,
                                values: chainValues,
                                enabled: !locked,
                                labelBuilder: (value) {
                                  final selected = chainAssets.firstWhere(
                                    (item) => item.chain == value,
                                  );
                                  return selected.network.isEmpty
                                      ? value
                                      : '$value · ${selected.network}';
                                },
                                onChanged: (next) => setState(() {
                                  selectedChain = next;
                                  localError = null;
                                }),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  InfoLine(
                    label: '可用余额',
                    value: chainAsset == null
                        ? '--'
                        : '${_plainAssetAmount(chainAsset.availableBalance)} $symbol',
                  ),
                  if (minimum != null)
                    InfoLine(
                      label: rule?.configuredMinimum == null
                          ? '最小单位'
                          : '最低提币数量',
                      value: '$minimum $symbol',
                    ),
                  if (rule?.decimals != null)
                    InfoLine(label: '数量精度', value: '${rule!.decimals} 位小数'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionTitle(title: '接收信息'),
                  TextField(
                    controller: addressController,
                    enabled: !locked,
                    autocorrect: false,
                    enableSuggestions: false,
                    keyboardType: TextInputType.text,
                    onChanged: (_) => setState(() => localError = null),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: InputDecoration(
                      labelText: '提币地址',
                      hintText: '请粘贴并逐字核对接收地址',
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: AppTextField(
                          controller: amountController,
                          label: '提币数量',
                          enabled: !locked,
                          onChanged: (_) => setState(() => localError = null),
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: locked || chainAsset == null
                            ? null
                            : () => setState(() {
                                amountController.text = _plainAssetAmount(
                                  chainAsset.availableBalance,
                                );
                                localError = null;
                              }),
                        child: const Text('全部'),
                      ),
                    ],
                  ),
                  if (rule?.fee != null)
                    InfoLine(label: '手续费', value: '${rule!.fee} $symbol'),
                  if (previewReceived != null &&
                      !previewReceived.startsWith('-'))
                    InfoLine(label: '预计到账', value: '$previewReceived $symbol'),
                  const SizedBox(height: 8),
                  Text(
                    '客户端校验用于提前发现输入问题，最终以钱包和风控服务校验为准。网络选错或地址错误可能导致资产无法找回。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            if (state.withdrawalVerificationRequired) ...[
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SectionTitle(title: '安全验证'),
                    AppTextField(
                      controller: emailCodeController,
                      label: '邮箱验证码',
                      enabled: !locked,
                    ),
                    if (state.withdrawalTotpRequired) ...[
                      const SizedBox(height: 8),
                      AppTextField(
                        controller: totpCodeController,
                        label: '验证器动态码',
                        enabled: !locked,
                      ),
                    ],
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: state.withdrawalSubmitting
                            ? null
                            : () =>
                                  unawaited(state.requestWithdrawalChallenge()),
                        child: const Text('重新发送邮箱验证码'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (localError != null) ...[
              const SizedBox(height: 10),
              Text(
                localError!,
                key: const ValueKey('withdrawal-local-error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ],
            if (state.withdrawalConfirmation != null) ...[
              const SizedBox(height: 12),
              WithdrawalConfirmationPanel(
                confirmation: state.withdrawalConfirmation!,
              ),
            ],
            const SizedBox(height: 14),
            PrimaryAction(
              label: state.withdrawalSubmitting
                  ? '提交中…'
                  : state.withdrawalOutcomeUnknown
                  ? '结果待核对'
                  : state.withdrawalOutcomeLocked
                  ? '提币已受理'
                  : '核对并确认提币',
              icon: Icons.verified_user_outlined,
              onPressed: locked || chain.isEmpty
                  ? null
                  : () =>
                        unawaited(_reviewAndSubmit(state, symbol, chain, rule)),
            ),
            if (state.withdrawalOutcomeUnknown) ...[
              const SizedBox(height: 10),
              const Text(
                '本次请求可能已到达钱包服务。为避免重复扣款，当前提币意图已锁定，请先核对提币记录。',
                style: TextStyle(color: _amber, fontSize: 11, height: 1.45),
              ),
            ] else if (state.withdrawalOutcomeLocked) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => unawaited(_startAnotherWithdrawal(state)),
                  child: const Text('发起另一笔提币'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _reviewAndSubmit(
    AppState state,
    String symbol,
    String chain,
    WithdrawalAssetRule? rule,
  ) async {
    final error = state.validateWithdrawal(
      chain: chain,
      symbol: symbol,
      toAddress: addressController.text,
      amount: amountController.text,
    );
    if (error != null) {
      setState(() => localError = error);
      return;
    }
    if (state.withdrawalVerificationRequired &&
        emailCodeController.text.trim().length != 6) {
      setState(() => localError = '请输入 6 位邮箱验证码');
      return;
    }
    if (state.withdrawalTotpRequired &&
        totpCodeController.text.trim().length != 6) {
      setState(() => localError = '请输入 6 位验证器动态码');
      return;
    }
    final amount = amountController.text.trim();
    final fee = rule?.fee;
    final received = rule?.receivedAmount(amount);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('确认提币信息'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InfoLine(
              label: '网络',
              value: rule?.network.isNotEmpty == true
                  ? '$chain · ${rule!.network}'
                  : chain,
            ),
            InfoLine(label: '地址', value: addressController.text.trim()),
            InfoLine(label: '数量', value: '$amount $symbol'),
            if (fee != null) InfoLine(label: '手续费', value: '$fee $symbol'),
            if (received != null)
              InfoLine(label: '预计到账', value: '$received $symbol'),
            const SizedBox(height: 10),
            const Text(
              '请确认网络与接收地址完全一致。提交后不可撤销。',
              style: TextStyle(color: _muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('返回修改'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认提交'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await state.withdrawWallet(
      chain: chain,
      symbol: symbol,
      toAddress: addressController.text,
      amount: amount,
      emailCode: emailCodeController.text,
      totpCode: totpCodeController.text,
    );
  }

  Future<void> _startAnotherWithdrawal(AppState state) async {
    await state.resetWithdrawalIntent();
    if (!mounted) return;
    setState(() {
      addressController.clear();
      amountController.clear();
      emailCodeController.clear();
      totpCodeController.clear();
      localError = null;
    });
  }
}

class WithdrawalConfirmationPanel extends StatelessWidget {
  const WithdrawalConfirmationPanel({required this.confirmation, super.key});

  final WithdrawalConfirmation confirmation;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '提币确认摘要'),
          InfoLine(
            label: '网络',
            value: confirmation.network.isEmpty
                ? confirmation.chain
                : '${confirmation.chain} · ${confirmation.network}',
          ),
          InfoLine(label: '地址', value: confirmation.toAddress),
          InfoLine(
            label: '数量',
            value: '${confirmation.amount} ${confirmation.symbol}',
          ),
          if (confirmation.fee != null)
            InfoLine(
              label: '手续费',
              value: '${confirmation.fee} ${confirmation.symbol}',
            ),
          if (confirmation.receivedAmount != null)
            InfoLine(
              label: '到账数量',
              value: '${confirmation.receivedAmount} ${confirmation.symbol}',
            ),
          InfoLine(label: '状态', value: confirmation.status),
          if (confirmation.reference.isNotEmpty)
            InfoLine(label: '提币编号', value: confirmation.reference),
        ],
      ),
    );
  }
}

String _plainAssetAmount(double value) {
  final fixed = value.toStringAsFixed(18);
  return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
}

class RechargeCoinPage extends StatefulWidget {
  const RechargeCoinPage({super.key});

  @override
  State<RechargeCoinPage> createState() => _RechargeCoinPageState();
}

class _RechargeCoinPageState extends State<RechargeCoinPage> {
  final queryController = TextEditingController();

  @override
  void dispose() {
    queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final query = queryController.text.trim().toUpperCase();
    final symbols = rechargeSymbols(
      state,
    ).where((symbol) => query.isEmpty || symbol.contains(query)).toList();
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            RechargeHeader(
              title: '选择资产',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: '帮助',
                    onPressed: () {},
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: BorderSide.none,
                    ),
                    icon: const Icon(Icons.help_outline, size: 30),
                  ),
                  IconButton(
                    tooltip: '记录',
                    onPressed: () => unawaited(state.refreshWallet()),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      side: BorderSide.none,
                    ),
                    icon: const Icon(Icons.receipt_long_outlined, size: 30),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            RechargeSearchField(
              controller: queryController,
              hint: '搜索数字货币',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 26),
            const Text(
              '数字货币',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 24),
            for (final symbol in symbols)
              RechargeCoinRow(
                symbol: symbol,
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RechargeNetworkPage(symbol: symbol),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class RechargeNetworkPage extends StatelessWidget {
  const RechargeNetworkPage({required this.symbol, super.key});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final chains = rechargeChains(state, symbol);
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
          children: [
            const RechargeHeader(title: '选择网络'),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF111111),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF333333)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info,
                    color: Theme.of(context).colorScheme.onSurface,
                    size: 24,
                  ),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '不清楚如何选择网络？',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 12),
                        Text(
                          '请确保您选择的网络，与汇出平台或钱包的网络保持一致。',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontSize: 17,
                            height: 1.45,
                          ),
                        ),
                        SizedBox(height: 18),
                        Text(
                          '了解更多  →',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 34),
            Row(
              children: [
                Text(
                  '网络',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 17,
                  ),
                ),
                Spacer(),
                Text(
                  '到账时间/最小充币金额',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            const Text(
              '可用',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 24),
            for (final chain in chains)
              RechargeNetworkRow(
                symbol: symbol,
                chain: chain,
                onTap: () async {
                  await state.loadDepositAddress(chain: chain, symbol: symbol);
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RechargeAddressPage(symbol: symbol, chain: chain),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class RechargeAddressPage extends StatefulWidget {
  const RechargeAddressPage({
    required this.symbol,
    required this.chain,
    super.key,
  });

  final String symbol;
  final String chain;

  @override
  State<RechargeAddressPage> createState() => _RechargeAddressPageState();
}

class _RechargeAddressPageState extends State<RechargeAddressPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = AppScope.of(context);
      final address = state.walletDepositAddress;
      if (address == null ||
          address.symbol != widget.symbol ||
          address.chain != widget.chain) {
        unawaited(
          state.loadDepositAddress(chain: widget.chain, symbol: widget.symbol),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final address = state.walletDepositAddress;
    final matches =
        address != null &&
        address.symbol == widget.symbol &&
        address.chain == widget.chain;
    final addressText = matches ? address.address : '地址生成中...';
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 30),
          children: [
            RechargeHeader(
              title: '',
              trailing: IconButton(
                tooltip: '更多',
                onPressed: () {},
                style: IconButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  side: BorderSide.none,
                ),
                icon: const Icon(Icons.more_horiz, size: 30),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                '充值 ${widget.symbol}',
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF202020),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    _QrImage(
                      dataUrl: matches ? address.qrCodeDataUrl : '',
                      size: 244,
                    ),
                    Container(
                      width: 50,
                      height: 50,
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: CryptoAvatar(symbol: widget.symbol, size: 42),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 34),
            Text(
              '地址 〉',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    addressText,
                    style: const TextStyle(
                      fontSize: 24,
                      height: 1.15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                InkWell(
                  onTap: matches
                      ? () => Clipboard.setData(
                          ClipboardData(text: address.address),
                        )
                      : null,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: const BoxDecoration(
                      color: Color(0xFF1F1F1F),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.copy, size: 28),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              '切换至 0x 地址  ⇄',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 28),
            const Divider(color: Color(0xFF262626)),
            RechargeInfoLine(
              label: '网络',
              value: networkDisplayName(widget.chain, widget.symbol),
              leading: CryptoAvatar(
                symbol: chainSymbol(widget.chain),
                size: 18,
              ),
            ),
            const RechargeInfoLine(label: '充值账户', value: '资金账户'),
            RechargeInfoLine(
              label: '最小充币金额',
              value: '0.01 ${widget.symbol}',
              showChevron: false,
              showInfo: true,
            ),
            RechargeInfoLine(
              label: '到账时间',
              value: networkEta(widget.chain),
              showChevron: false,
              showInfo: true,
            ),
            RechargeInfoLine(
              label: '可提币时间',
              value: networkEta(widget.chain),
              showChevron: false,
              showInfo: true,
            ),
            const RechargeInfoLine(label: '合约地址', value: '查看详情'),
            if (!matches) ...[
              const SizedBox(height: 18),
              PrimaryAction(
                label: state.loadingPrivate ? '加载中' : '重新获取地址',
                icon: Icons.refresh,
                onPressed: () => unawaited(
                  state.loadDepositAddress(
                    chain: widget.chain,
                    symbol: widget.symbol,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class RechargeHeader extends StatelessWidget {
  const RechargeHeader({required this.title, this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              tooltip: '返回',
              onPressed: () => Navigator.pop(context),
              style: IconButton.styleFrom(
                backgroundColor: Colors.transparent,
                side: BorderSide.none,
              ),
              icon: const Icon(Icons.arrow_back_ios_new, size: 27),
            ),
          ),
          if (title.isNotEmpty)
            Text(
              title,
              style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w900),
            ),
          if (trailing != null)
            Align(alignment: Alignment.centerRight, child: trailing!),
        ],
      ),
    );
  }
}

class RechargeSearchField extends StatelessWidget {
  const RechargeSearchField({
    required this.controller,
    required this.hint,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        prefixIcon: Icon(
          Icons.search,
          color: Theme.of(context).colorScheme.onSurface,
          size: 30,
        ),
        filled: true,
        fillColor: const Color(0xFF1F1F1F),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class RechargeCoinRow extends StatelessWidget {
  const RechargeCoinRow({required this.symbol, required this.onTap, super.key});

  final String symbol;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          children: [
            CryptoAvatar(symbol: symbol, size: 56),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        symbol,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (symbol == 'USDG') ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.tertiary.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text(
                            '3.5% 年化收益',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.tertiary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Text(
                    assetDisplayName(symbol),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RechargeNetworkRow extends StatelessWidget {
  const RechargeNetworkRow({
    required this.symbol,
    required this.chain,
    required this.onTap,
    super.key,
  });

  final String symbol;
  final String chain;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Row(
          children: [
            CryptoAvatar(symbol: chainSymbol(chain), size: 52),
            const SizedBox(width: 18),
            Expanded(
              child: Text(
                networkDisplayName(chain, symbol),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 23,
                  height: 1.18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  networkEta(chain),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '0.01 $symbol',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class RechargeInfoLine extends StatelessWidget {
  const RechargeInfoLine({
    required this.label,
    required this.value,
    this.leading,
    this.showChevron = true,
    this.showInfo = false,
    super.key,
  });

  final String label;
  final String value;
  final Widget? leading;
  final bool showChevron;
  final bool showInfo;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (showInfo) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.info_outline,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 18,
                ),
              ],
            ],
          ),
          const Spacer(),
          if (leading != null) ...[leading!, const SizedBox(width: 8)],
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 21,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (showChevron) ...[
            const SizedBox(width: 3),
            Icon(
              Icons.keyboard_arrow_down,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
    );
  }
}

List<String> rechargeSymbols(AppState state) {
  final symbols =
      state.walletPortfolio.assets
          .map((asset) => asset.symbol.toUpperCase())
          .where((symbol) => symbol.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
  if (symbols.isNotEmpty) return symbols;
  return const [
    'USDT',
    'USDG',
    'USDC',
    'BTC',
    'ETH',
    'XAUT',
    'SOL',
    'TRX',
    '1INCH',
  ];
}

List<String> rechargeChains(AppState state, String symbol) {
  for (final asset in state.walletPortfolio.assets) {
    if (asset.symbol.toUpperCase() != symbol.toUpperCase()) continue;
    final chains = asset.chains
        .map((chain) => chain.chain)
        .where((chain) => chain.isNotEmpty)
        .toSet()
        .toList();
    if (chains.isNotEmpty) return chains;
  }
  if (symbol == 'BTC') return const ['BTC'];
  if (symbol == 'ETH') return const ['ETH', 'ARB', 'AVAX'];
  return const [
    'Surprising Chain',
    'TRON',
    'ETH',
    'APTOS',
    'ARB',
    'AVAX',
    'BERA',
  ];
}

String chainSymbol(String chain) {
  final upper = chain.toUpperCase();
  if (upper.contains('TRON') || upper == 'TRX') return 'TRX';
  if (upper.contains('ETH')) return 'ETH';
  if (upper.contains('BTC')) return 'BTC';
  if (upper.contains('SOL')) return 'SOL';
  if (upper.contains('SURPRISING')) return 'SPEX';
  if (upper.contains('APTOS')) return 'APTOS';
  if (upper.contains('ARB')) return 'ARB';
  if (upper.contains('AVAX') || upper.contains('AVALANCHE')) return 'AVAX';
  if (upper.contains('BERA')) return 'BERA';
  return upper.isEmpty ? '?' : upper.substring(0, 1);
}

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        PageHeader(
          title: '我的',
          subtitle: state.isLoggedIn ? state.session!.user.email : '未登录',
        ),
        Panel(
          child: Row(
            children: [
              const SparkleMark(size: 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      state.isLoggedIn ? state.session!.user.email : '游客',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    Text(
                      state.isLoggedIn
                          ? 'UID ${state.userId} · ${state.session!.user.status}'
                          : '登录后同步订单、持仓和资产',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (state.isLoggedIn)
                IconButton.filledTonal(
                  onPressed: state.logout,
                  icon: const Icon(Icons.logout),
                )
              else
                FilledButton(
                  onPressed: () => showAuthSheet(context),
                  child: const Text('登录'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet_outlined),
              title: const Text('资产概览'),
              subtitle: const Text('资金账户与各交易账户'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('资产')),
                    body: const WalletPage(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Panel(
          child: Column(
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('主题'),
                subtitle: const Text('切换交易终端的明暗外观'),
                trailing: DropdownButton<ClientTheme>(
                  value: state.clientTheme,
                  underline: const SizedBox.shrink(),
                  items: ClientTheme.values
                      .map(
                        (theme) => DropdownMenuItem(
                          value: theme,
                          child: Text(theme.label),
                        ),
                      )
                      .toList(),
                  onChanged: (next) {
                    if (next != null) state.selectTheme(next);
                  },
                ),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('语言 / Language'),
                subtitle: const Text('应用界面语言'),
                trailing: DropdownButton<ClientLanguage>(
                  value: state.language,
                  underline: const SizedBox.shrink(),
                  items: ClientLanguage.values
                      .map(
                        (language) => DropdownMenuItem(
                          value: language,
                          child: Text(language.label),
                        ),
                      )
                      .toList(),
                  onChanged: (next) {
                    if (next != null) state.selectLanguage(next);
                  },
                ),
              ),
            ],
          ),
        ),
        if (state.isLoggedIn) ...[
          const SizedBox(height: 12),
          Panel(
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.security,
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                title: const Text('安全中心'),
                subtitle: const Text('2FA、敏感场景和 API Key'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showSecuritySheet(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Material(
              color: Colors.transparent,
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.badge_outlined),
                title: Text(
                  clientText(state.language, '身份认证', 'Identity verification'),
                ),
                subtitle: Text(
                  clientText(
                    state.language,
                    '提交认证资料与查看审核结果',
                    'Submit documents and review verification status',
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showSecuritySheet(context, kycOnly: true),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fingerprint, color: _amber),
              title: Text(
                state.biometricLoginEnabled ? '生物识别登录已启用' : '启用生物识别登录',
              ),
              subtitle: Text(
                state.biometricLoginEnabled
                    ? '下次打开 App 使用面容或指纹解锁'
                    : state.biometricLoginAvailable
                    ? '只保存加密 refresh token，不保存 access token'
                    : '设备未检测到可用的生物识别能力',
              ),
              trailing: state.biometricLoginEnabled
                  ? OutlinedButton(
                      onPressed: state.biometricLoginUpdating
                          ? null
                          : () => unawaited(
                              _confirmDisableBiometric(context, state),
                            ),
                      child: Text(state.biometricLoginUpdating ? '处理中…' : '关闭'),
                    )
                  : FilledButton.tonal(
                      onPressed:
                          state.biometricLoginAvailable &&
                              !state.biometricLoginUpdating
                          ? () => unawaited(state.enableBiometricLogin())
                          : null,
                      child: Text(state.biometricLoginUpdating ? '处理中…' : '启用'),
                    ),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _confirmDisableBiometric(
    BuildContext context,
    AppState state,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('关闭生物识别登录？'),
        content: const Text('关闭后，下次打开 App 将直接使用已保存的登录会话，不再要求面容或指纹解锁。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认关闭'),
          ),
        ],
      ),
    );
    if (confirmed == true) await state.disableBiometricLogin();
  }
}

class KycSumsubWebView extends StatefulWidget {
  const KycSumsubWebView({
    required this.token,
    required this.refreshToken,
    required this.language,
    super.key,
  });
  final String token;
  final Future<String> Function() refreshToken;
  final ClientLanguage language;

  @override
  State<KycSumsubWebView> createState() => _KycSumsubWebViewState();
}

class _KycSumsubWebViewState extends State<KycSumsubWebView> {
  late final WebViewController controller;

  @override
  void initState() {
    super.initState();
    final tokenJson = jsonEncode(widget.token);
    controller =
        WebViewController(
            onPermissionRequest: (request) {
              if (request.types.every(
                (type) =>
                    type == WebViewPermissionResourceType.camera ||
                    type == WebViewPermissionResourceType.microphone,
              )) {
                request.grant();
              } else {
                request.deny();
              }
            },
          )
          ..addJavaScriptChannel(
            'KycHost',
            onMessageReceived: (_) => unawaited(_refreshToken()),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(
            '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><script src="https://static.sumsub.com/idensic/static/sns-websdk-builder.js"></script></head><body><div id="sumsub-websdk-container"></div><script>window.__requestNewToken=()=>new Promise(resolve=>{window.__resolveNewToken=resolve;KycHost.postMessage("refresh")});window.__provideNewToken=token=>window.__resolveNewToken?.(token);snsWebSdk.init($tokenJson, window.__requestNewToken).withConf({lang:"${widget.language == ClientLanguage.en ? 'en' : 'zh'}"}).build().launch("#sumsub-websdk-container");</script></body></html>''',
            baseUrl: 'https://static.sumsub.com/',
          );
  }

  Future<void> _refreshToken() async {
    try {
      final token = await widget.refreshToken();
      await controller.runJavaScript(
        'window.__provideNewToken(${jsonEncode(token)});',
      );
    } catch (_) {
      await controller.runJavaScript('window.__provideNewToken("");');
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  clientText(
                    widget.language,
                    'Sumsub 身份与人脸核验',
                    'Sumsub identity and face verification',
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    ),
  );
}

class SecuritySheet extends StatefulWidget {
  const SecuritySheet({this.kycOnly = false, super.key});

  final bool kycOnly;

  @override
  State<SecuritySheet> createState() => _SecuritySheetState();
}

class _SecuritySheetState extends State<SecuritySheet> {
  Timer? _kycStatusPoll;
  bool _pollingSecurity = false;
  bool _operationCancelled = false;
  Map<String, dynamic> mfa = const {};
  Map<String, dynamic> mfaRecovery = const {};
  Map<String, dynamic> mfaRecoveryChallenge = const {};
  Map<String, dynamic> enrollment = const {};
  List<Map<String, dynamic>> scenes = const [];
  List<Map<String, dynamic>> keys = const [];
  Map<String, dynamic> kyc = const {};
  Map<String, dynamic> kycProviderInfo = const {};
  Map<String, dynamic> kycVerificationSession = const {};
  final totp = TextEditingController();
  final emailCode = TextEditingController();
  final securityEmailCode = TextEditingController();
  final apiTotp = TextEditingController();
  final apiLabel = TextEditingController();
  final apiAllowlist = TextEditingController();
  bool apiTradeEnabled = false;
  bool apiWithdrawEnabled = false;
  String? apiSecret;
  final currentPassword = TextEditingController();
  final mfaPassword = TextEditingController();
  final mfaEmailCode = TextEditingController();
  final mfaPhoneCode = TextEditingController();
  final loginMethodDestination = TextEditingController();
  final mfaRecoveryCode = TextEditingController();
  final mfaRecoveryReason = TextEditingController();
  final newPassword = TextEditingController();
  final changePasswordEmailCode = TextEditingController();
  final changePasswordTotpCode = TextEditingController();
  List<Map<String, dynamic>> kycDocumentRecords = const [];
  String kycProvider = 'SUMSUB';
  bool get kycSimulationEnabled => kycProviderInfo['simulationEnabled'] == true;
  bool busy = false;
  String? error;
  String? notice;

  String? loadedToken;
  String? operationToken;
  bool get operationCurrent =>
      mounted &&
      operationToken == loadedToken &&
      AppScope.of(context).session?.accessToken == operationToken;
  bool loading = true;
  bool mfaLoaded = false;
  bool kycLoaded = false;
  int loadVersion = 0;
  final Map<String, String> loadErrors = {};
  List<Map<String, dynamic>> methods = const [];
  Map<String, dynamic> sessionsPage = const {};
  Map<String, dynamic> historyPage = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _kycStatusPoll ??= Timer.periodic(const Duration(seconds: 12), (_) {
      if (!mounted ||
          _pollingSecurity ||
          loading ||
          busy ||
          loadedToken == null) {
        return;
      }
      final state = AppScope.of(context);
      if (state.session?.accessToken != loadedToken) return;
      final version = loadVersion, token = loadedToken;
      _pollingSecurity = true;
      unawaited(() async {
        try {
          if (kyc['status'] == 'PENDING') {
            final value = await state.api.kycStatus();
            if (mounted &&
                version == loadVersion &&
                state.session?.accessToken == token) {
              setState(() => kyc = value);
            }
          }
          if (mfaRecovery['status'] == 'PENDING' &&
              version == loadVersion &&
              state.session?.accessToken == token) {
            final value = await state.api.mfaRecoveryStatus();
            if (mounted &&
                version == loadVersion &&
                state.session?.accessToken == token) {
              setState(() => mfaRecovery = value);
            }
          }
        } catch (_) {
          // The next poll retries; a transient read must not overwrite the form.
        } finally {
          _pollingSecurity = false;
        }
      }());
    });
    final token = AppScope.of(context).session?.accessToken;
    if (token == loadedToken) return;
    loadedToken = token;
    ++loadVersion;
    mfa = {};
    mfaRecovery = {};
    mfaRecoveryChallenge = {};
    enrollment = {};
    scenes = [];
    keys = [];
    kyc = {};
    kycProviderInfo = {};
    kycVerificationSession = {};
    methods = [];
    sessionsPage = {};
    historyPage = {};
    kycDocumentRecords = [];
    mfaLoaded = false;
    kycLoaded = false;
    loading = true;
    error = null;
    notice = null;
    loadErrors.clear();
    totp.clear();
    emailCode.clear();
    securityEmailCode.clear();
    apiTotp.clear();
    currentPassword.clear();
    newPassword.clear();
    changePasswordEmailCode.clear();
    changePasswordTotpCode.clear();
    apiLabel.clear();
    apiAllowlist.clear();
    apiSecret = null;
    apiTradeEnabled = false;
    apiWithdrawEnabled = false;
    mfaPassword.clear();
    mfaEmailCode.clear();
    mfaPhoneCode.clear();
    mfaRecoveryCode.clear();
    mfaRecoveryReason.clear();
    loginMethodDestination.clear();
    if (token != null) unawaited(_load());
  }

  @override
  void dispose() {
    _kycStatusPoll?.cancel();
    totp.dispose();
    emailCode.dispose();
    securityEmailCode.dispose();
    apiTotp.dispose();
    apiLabel.dispose();
    apiAllowlist.dispose();
    currentPassword.dispose();
    mfaPassword.dispose();
    mfaEmailCode.dispose();
    mfaPhoneCode.dispose();
    loginMethodDestination.dispose();
    mfaRecoveryCode.dispose();
    mfaRecoveryReason.dispose();
    newPassword.dispose();
    changePasswordEmailCode.dispose();
    changePasswordTotpCode.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final state = AppScope.of(context);
    if (!state.isLoggedIn) return;
    final token = state.session!.accessToken;
    final version = ++loadVersion;
    loading = true;
    mfaLoaded = false;
    kycLoaded = false;
    methods = [];
    sessionsPage = {};
    historyPage = {};
    mfa = {};
    kyc = {};
    kycProviderInfo = {};
    scenes = [];
    keys = [];
    kycDocumentRecords = [];
    loadErrors.clear();
    bool current() =>
        mounted &&
        version == loadVersion &&
        state.session?.accessToken == token;
    Future<void> read<T>(
      String label,
      Future<T> Function() request,
      void Function(T) apply,
    ) async {
      try {
        final value = await request();
        if (current()) setState(() => apply(value));
      } catch (_) {
        if (current()) setState(() => loadErrors[label] = '$label加载失败，请重试');
      }
    }

    await Future.wait([
      if (!widget.kycOnly) ...[
        read('2FA', state.api.mfaStatus, (value) {
          mfa = value;
          mfaLoaded = true;
        }),
        read(
          '2FA 恢复',
          state.api.mfaRecoveryStatus,
          (value) => mfaRecovery = value,
        ),
        read('敏感场景', state.api.securityScenes, (value) => scenes = value),
        read('API 密钥', state.api.apiKeys, (value) => keys = value),
      ],
      read('身份认证', state.api.kycStatus, (value) {
        kyc = value;
        kycLoaded = true;
        _applyKyc(kyc);
      }),
      read('KYC 服务', state.api.kycProvider, (value) {
        kycProviderInfo = value;
        kycProvider = asString(value['provider'], fallback: 'SUMSUB');
      }),
      read(
        '认证材料',
        state.api.kycDocuments,
        (value) => kycDocumentRecords = value,
      ),
      if (!widget.kycOnly) ...[
        read(
          '登录验证方式',
          state.api.loginVerificationMethods,
          (value) => methods = value,
        ),
        read('活跃会话', state.api.userSessions, (value) => sessionsPage = value),
        read('登录历史', state.api.loginHistory, (value) => historyPage = value),
      ],
    ]);
    if (current()) setState(() => loading = false);
  }

  Future<void> _loadMoreSecurity(bool history) async {
    final state = AppScope.of(context);
    final token = state.session?.accessToken;
    final page = history ? historyPage : sessionsPage;
    final cursor = nullableString(page['nextCursor']);
    if (cursor == null) return;
    final next = history
        ? await state.api.loginHistory(cursor: cursor)
        : await state.api.userSessions(cursor: cursor);
    if (!mounted || state.session?.accessToken != token) return;
    final field = history ? 'logs' : 'sessions';
    setState(() {
      final merged = {
        ...next,
        field: [...asList(page[field]), ...asList(next[field])],
      };
      if (history) {
        historyPage = merged;
      } else {
        sessionsPage = merged;
      }
    });
  }

  void _applyKyc(Map<String, dynamic> profile) {
    if (profile['provider'] != null) {
      kycProvider = asString(profile['provider']);
    }
  }

  Future<void> _completeKycSimulation(AppState state, String decision) async {
    final next = await state.api.completeKycSimulation(decision);
    if (!operationCurrent) return;
    setState(() {
      kyc = next;
      kycVerificationSession = {};
    });
  }

  Future<void> _launchKycProvider(AppState state) async {
    final session = kycVerificationSession;
    final token = asString(session['launchToken']);
    final redirect = asString(session['redirectUrl']);
    if (kycProvider == 'SUMSUB' && token.isNotEmpty) {
      if (Platform.isAndroid) {
        final permissions = await const MethodChannel(
          'surprising/kyc-permissions',
        ).invokeMethod<bool>('requestCameraAndMicrophone');
        if (permissions != true) {
          throw const FormatException('身份核验需要相机和麦克风权限');
        }
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => KycSumsubWebView(
          token: token,
          language: state.language,
          refreshToken: () async {
            final refreshed = await state.api.refreshKycSession();
            final nextToken = asString(refreshed['launchToken']);
            if (nextToken.isEmpty) throw const FormatException('无法刷新核验令牌');
            return nextToken;
          },
        ),
      );
      if (mounted) {
        await state.api.kycStatus().then((value) {
          if (mounted) setState(() => kyc = value);
        });
      }
      return;
    }
    if (kycProvider == 'VERIFF' && redirect.isNotEmpty) {
      final uri = Uri.tryParse(redirect);
      if (uri == null || !uri.hasScheme || uri.scheme != 'https') {
        throw const FormatException('服务商核验链接无效');
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    throw const FormatException('当前核验会话暂不可启动');
  }

  Future<void> _changePassword(AppState state) async {
    if (currentPassword.text.isEmpty || newPassword.text.length < 8) {
      throw const FormatException('请输入当前密码和至少 8 位新密码');
    }
    await state.api.changePassword(
      currentPassword: currentPassword.text,
      newPassword: newPassword.text,
      emailCode: changePasswordEmailCode.text,
      totpCode: changePasswordTotpCode.text,
    );
    if (!operationCurrent) return;
    setState(() {
      currentPassword.clear();
      newPassword.clear();
      changePasswordEmailCode.clear();
      changePasswordTotpCode.clear();
    });
  }

  Future<void> _updateSecurityScene(
    AppState state,
    String code,
    bool enabled,
  ) async {
    try {
      final saved = await state.api.updateSecurityScene(
        code,
        enabled,
        emailCode: securityEmailCode.text.trim(),
        totpCode: totp.text.trim(),
      );
      if (operationCurrent) {
        setState(
          () => scenes = scenes
              .map((item) => asString(item['sceneCode']) == code ? saved : item)
              .toList(),
        );
        securityEmailCode.clear();
      }
    } on ApiException catch (cause) {
      if (cause.statusCode != 428) rethrow;
      final challenge = await state.api.issueSecurityChallenge(
        'SECURITY_SETTINGS',
      );
      if (operationCurrent) {
        setState(
          () =>
              notice = '安全设置需要验证，验证码已发送至 ${asString(challenge['destination'])}',
        );
      }
    }
  }

  Future<void> _run(Future<void> Function() action, String message) async {
    if (busy) return;
    operationToken = loadedToken;
    _operationCancelled = false;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await action();
      if (operationCurrent && notice == null && !_operationCancelled) {
        setState(() => notice = message);
      }
    } catch (cause) {
      if (operationCurrent) {
        setState(
          () => error = cause is FormatException
              ? cause.message
              : cause is ApiException
              ? '$cause'
              : '操作未完成，请稍后重试',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<String> _apiAllowlist() => apiAllowlist.text
      .split(RegExp(r'[\s,]+'))
      .where((v) => v.isNotEmpty)
      .toSet()
      .toList();

  Future<bool> _confirmSecurity(String title, String message) async {
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialog, true),
                child: const Text('确认'),
              ),
            ],
          ),
        ) ==
        true;
    if (!confirmed) _operationCancelled = true;
    return confirmed;
  }

  Future<void> _beginLoginMethodChange(
    AppState state,
    String method,
    bool enabled, {
    bool changeBinding = false,
  }) async {
    mfaPassword.clear();
    loginMethodDestination.clear();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(changeBinding ? '更换绑定' : '安全验证方式设置'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('绑定或变更邮箱、手机、谷歌验证码后，24 小时内不能提现。'),
            TextField(
              controller: mfaPassword,
              obscureText: true,
              decoration: const InputDecoration(labelText: '登录密码'),
            ),
            if (changeBinding)
              TextField(
                controller: loginMethodDestination,
                keyboardType: method == 'EMAIL'
                    ? TextInputType.emailAddress
                    : TextInputType.phone,
                decoration: InputDecoration(
                  labelText: method == 'EMAIL' ? '新邮箱' : '新手机号（国际区号）',
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('发送验证码'),
          ),
        ],
      ),
    );
    if (accepted != true || mfaPassword.text.isEmpty) return;
    await _run(() async {
      final next = await state.api.beginLoginMethod(
        method: method,
        currentPassword: mfaPassword.text,
        enabled: enabled,
        destination: changeBinding ? loginMethodDestination.text : null,
      );
      if (operationCurrent) {
        setState(() => enrollment = {...next, 'loginMethod': method});
      }
    }, '验证码已发送，请完成安全验证');
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.isLoggedIn) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('登录已失效，请重新登录'),
      );
    }
    final mfaEnabled = mfa['enabled'] == true || mfa['enrolled'] == true;
    final actionsBlocked = busy || loading || !mfaLoaded;
    final kycActionsBlocked =
        busy || loading || !kycLoaded || kycProviderInfo.isEmpty;
    final enrollmentSecret = asString(enrollment['secret']);
    final mfaChallenge = asMap(enrollment['challenge']);
    final challengeMethods = asList(
      mfaChallenge['methods'],
    ).map(asMap).toList();
    final challengeToken = asString(mfaChallenge['challengeToken']);
    final disablingMfa = enrollment['disabling'] == true;
    final needsEmailCode = challengeMethods.any(
      (method) => method['type'] == 'EMAIL',
    );
    final needsPhoneCode = challengeMethods.any(
      (method) => method['type'] == 'PHONE',
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  widget.kycOnly
                      ? clientText(
                          state.language,
                          '身份认证',
                          'Identity verification',
                        )
                      : '安全中心',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (notice != null)
              Text(
                notice!,
                style: TextStyle(color: Theme.of(context).colorScheme.tertiary),
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (loading) const LinearProgressIndicator(),
            for (final message in loadErrors.values) Text(message),
            TextButton.icon(
              onPressed: loading || busy
                  ? null
                  : () {
                      setState(() => loading = true);
                      unawaited(_load());
                    },
              icon: const Icon(Icons.refresh),
              label: const Text('刷新安全状态'),
            ),
            if (!widget.kycOnly) ...[
              const SectionTitle(title: '登录验证方式'),
              for (final method in methods)
                if (method['type'] == 'TOTP')
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: InfoLine(
                        label: '谷歌验证器',
                        value:
                            '${method['bound'] == true ? asString(method['destination'], fallback: '已绑定') : '未绑定'} · ${method['enabled'] == true ? '已启用' : '未启用'}',
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          InfoLine(
                            label: switch (method['type']) {
                              'EMAIL' => '邮箱',
                              'PHONE' => '手机',
                              _ => '谷歌验证器',
                            },
                            value:
                                '${method['bound'] == true ? asString(method['destination'], fallback: '已绑定') : '未绑定'} · ${method['enabled'] == true ? '已启用' : '未启用'}',
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: actionsBlocked
                                    ? null
                                    : () => _beginLoginMethodChange(
                                        state,
                                        asString(method['type']),
                                        method['enabled'] != true,
                                      ),
                                child: Text(
                                  method['enabled'] == true ? '停用' : '启用/绑定',
                                ),
                              ),
                              if (method['type'] == 'EMAIL' ||
                                  method['type'] == 'PHONE')
                                TextButton(
                                  onPressed: actionsBlocked
                                      ? null
                                      : () => _beginLoginMethodChange(
                                          state,
                                          asString(method['type']),
                                          true,
                                          changeBinding: true,
                                        ),
                                  child: const Text('更换绑定'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              TextButton.icon(
                icon: const Icon(Icons.devices_outlined),
                label: const Text('下线其他设备'),
                onPressed: busy
                    ? null
                    : () => _run(() async {
                        final confirmed = await _confirmSecurity(
                          '下线其他设备？',
                          '当前手机会保持登录，其他设备需要重新登录。',
                        );
                        if (!confirmed || !operationCurrent) return;
                        await state.api.revokeOtherSessions(
                          state.session!.refreshToken,
                        );
                        if (operationCurrent) await _load();
                      }, '其他设备已下线'),
              ),
              DeviceAccessPanel(state: state),
              ExpansionTile(
                title: const Text('活跃会话'),
                children: [
                  for (final item in asList(sessionsPage['sessions']))
                    ListTile(
                      title: Text(
                        asString(asMap(item)['userAgent'], fallback: '未知设备'),
                      ),
                      subtitle: Text(
                        '${asMap(item)['ipAddress'] ?? '—'}\n登录 ${asMap(item)['createdAt'] ?? '—'}\n到期 ${asMap(item)['expiresAt'] ?? '—'}',
                      ),
                      trailing: TextButton(
                        onPressed: busy
                            ? null
                            : () => _run(() async {
                                final id = asString(asMap(item)['sessionId']);
                                if (id.isEmpty) {
                                  throw const FormatException('会话信息暂不可用，请刷新');
                                }
                                if (!await _confirmSecurity(
                                      '下线这个会话？',
                                      '该设备需要重新登录后才能继续使用。',
                                    ) ||
                                    !operationCurrent) {
                                  return;
                                }
                                await state.api.revokeUserSession(id);
                                if (operationCurrent) await _load();
                              }, '会话已下线'),
                        child: const Text('下线'),
                      ),
                    ),
                  if (!loading &&
                      !loadErrors.containsKey('活跃会话') &&
                      asList(sessionsPage['sessions']).isEmpty)
                    const Text('暂无活跃会话'),
                  if (sessionsPage['hasMore'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () =>
                                _run(() => _loadMoreSecurity(false), '已加载更多会话'),
                      child: const Text('加载更多会话'),
                    ),
                ],
              ),
              ExpansionTile(
                title: const Text('登录历史'),
                children: [
                  for (final item in asList(historyPage['logs']))
                    ListTile(
                      title: Text(
                        '${asMap(item)['result'] ?? '—'} · ${asMap(item)['ipAddress'] ?? '—'}',
                      ),
                      subtitle: Text(
                        '${asMap(item)['createdAt'] ?? '—'}\n${asMap(item)['userAgent'] ?? '—'}\n${asMap(item)['reason'] ?? ''}',
                      ),
                    ),
                  if (!loading &&
                      !loadErrors.containsKey('登录历史') &&
                      asList(historyPage['logs']).isEmpty)
                    const Text('暂无登录记录'),
                  if (historyPage['hasMore'] == true)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => _run(
                              () => _loadMoreSecurity(true),
                              '已加载更多登录记录',
                            ),
                      child: const Text('加载更多登录记录'),
                    ),
                ],
              ),
              SectionTitle(
                title: !mfaLoaded
                    ? '2FA 状态未获取'
                    : mfaEnabled
                    ? '2FA 已启用'
                    : '绑定 2FA',
              ),
              if (mfa['withdrawalsRestrictedUntil'] != null &&
                  DateTime.tryParse(
                        '${mfa['withdrawalsRestrictedUntil']}',
                      )?.isAfter(DateTime.now()) ==
                      true)
                Text(
                  '安全信息变更后提现暂不可用，可恢复时间：${mfa['withdrawalsRestrictedUntil']}',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (!mfaEnabled && enrollment.isEmpty) ...[
                const Text('绑定或变更邮箱、手机、谷歌验证码后，24 小时内不能提现。'),
                AppTextField(controller: mfaPassword, label: '登录密码'),
                PrimaryAction(
                  label: '生成绑定信息',
                  icon: Icons.qr_code_2,
                  onPressed: actionsBlocked
                      ? null
                      : () => _run(() async {
                          final next = await state.api.enrollMfa(
                            mfaPassword.text,
                          );
                          if (operationCurrent) {
                            setState(() => enrollment = next);
                          }
                        }, '验证码已发送，请完成双重验证'),
                ),
              ],
              if (mfaEnabled && enrollment.isEmpty) ...[
                const Text('关闭谷歌验证码后将重新生成新密钥；安全信息变更后 24 小时内不能提现。'),
                AppTextField(controller: mfaPassword, label: '登录密码'),
                TextButton(
                  onPressed: actionsBlocked
                      ? null
                      : () => _run(() async {
                          final next = await state.api.beginMfaDisable(
                            mfaPassword.text,
                          );
                          if (operationCurrent) {
                            setState(
                              () => enrollment = {...next, 'disabling': true},
                            );
                          }
                        }, '验证码已发送，请完成双重验证'),
                  child: const Text('关闭 2FA'),
                ),
              ],
              if (enrollment.isNotEmpty) ...[
                if (enrollmentSecret.isNotEmpty) ...[
                  if (asString(
                    enrollment['qrCodeDataUrl'],
                  ).startsWith('data:image/png;base64,'))
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        color: Colors.white,
                        child: Image.memory(
                          base64Decode(
                            asString(
                              enrollment['qrCodeDataUrl'],
                            ).split(',').last,
                          ),
                          width: 184,
                          height: 184,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                  const Text('请使用身份验证器扫描二维码，或手动输入密钥。密钥只显示这一次，请勿截图或转发。'),
                  InfoLine(label: '密钥', value: enrollmentSecret),
                ],
                for (final method in challengeMethods)
                  if (method['type'] == 'EMAIL')
                    AppTextField(controller: mfaEmailCode, label: '邮箱验证码'),
                for (final method in challengeMethods)
                  if (method['type'] == 'PHONE')
                    AppTextField(controller: mfaPhoneCode, label: '手机验证码'),
                if (challengeMethods.any((method) => method['type'] == 'TOTP'))
                  AppTextField(
                    controller: totp,
                    label: disablingMfa ? '当前谷歌验证码' : '谷歌验证码',
                  ),
                Text('安全信息变更后，提现将在 24 小时后恢复。'),
                PrimaryAction(
                  label: disablingMfa ? '确认关闭' : '确认绑定',
                  icon: Icons.verified_user,
                  onPressed: actionsBlocked || challengeToken.isEmpty
                      ? null
                      : () => _run(() async {
                          final args = {
                            'challengeToken': challengeToken,
                            'currentPassword': mfaPassword.text,
                            'emailCode': needsEmailCode
                                ? mfaEmailCode.text.trim()
                                : null,
                            'phoneCode': needsPhoneCode
                                ? mfaPhoneCode.text.trim()
                                : null,
                            'totpCode': totp.text.trim(),
                          };
                          final loginMethod = asString(
                            enrollment['loginMethod'],
                          );
                          final next = loginMethod.isNotEmpty
                              ? await state.api
                                    .confirmLoginMethod(
                                      method: loginMethod,
                                      currentPassword: args['currentPassword']!,
                                      challengeToken: args['challengeToken']!,
                                      emailCode: args['emailCode'],
                                      phoneCode: args['phoneCode'],
                                      totpCode: args['totpCode'],
                                    )
                                    .then((_) => state.api.mfaStatus())
                              : disablingMfa
                              ? await state.api.confirmMfaDisable(
                                  challengeToken: args['challengeToken']!,
                                  currentPassword: args['currentPassword']!,
                                  emailCode: args['emailCode'],
                                  phoneCode: args['phoneCode'],
                                  totpCode: args['totpCode']!,
                                )
                              : await state.api.confirmMfa(
                                  challengeToken: args['challengeToken']!,
                                  currentPassword: args['currentPassword']!,
                                  emailCode: args['emailCode'],
                                  phoneCode: args['phoneCode'],
                                  totpCode: args['totpCode']!,
                                );
                          if (operationCurrent) {
                            setState(() {
                              mfa = next;
                              enrollment = const {};
                              totp.clear();
                              mfaPassword.clear();
                              mfaEmailCode.clear();
                              mfaPhoneCode.clear();
                            });
                            if (loginMethod.isNotEmpty) unawaited(_load());
                          }
                        }, disablingMfa ? '2FA 已关闭' : '2FA 已启用'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => enrollment = const {}),
                  child: const Text('取消'),
                ),
              ],
              const SectionTitle(title: '丢失谷歌验证码'),
              Text(
                '恢复需要已通过的 KYC、登录密码、邮箱或手机验证码，并由运营人员人工审核。审核通过后会移除旧验证器，提现冻结 24 小时。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (mfaRecovery['status'] == 'PENDING')
                InfoLine(
                  label: '恢复申请',
                  value: '审核中 · ${mfaRecovery['submittedAt'] ?? ''}',
                )
              else if (mfaRecovery['status'] == 'APPROVED')
                const InfoLine(label: '恢复申请', value: '已通过，可以重新绑定新的验证器密钥')
              else ...[
                if (mfaRecovery['status'] == 'REJECTED')
                  Text('上次申请未通过：${mfaRecovery['decisionReason'] ?? ''}'),
                if (mfaRecoveryChallenge.isEmpty) ...[
                  AppTextField(controller: mfaPassword, label: '登录密码'),
                  PrimaryAction(
                    label: '发送恢复验证码',
                    icon: Icons.mark_email_read_outlined,
                    onPressed: actionsBlocked || !mfaEnabled
                        ? null
                        : () => _run(
                            () async {
                              final challenge = await state.api
                                  .issueMfaRecoveryChallenge(mfaPassword.text);
                              if (operationCurrent) {
                                setState(
                                  () => mfaRecoveryChallenge = challenge,
                                );
                              }
                            },
                            '验证码已发送到 ${mfaRecoveryChallenge['destination'] ?? '已绑定联系方式'}',
                          ),
                  ),
                ] else ...[
                  Text('验证码发送至 ${mfaRecoveryChallenge['destination'] ?? ''}'),
                  AppTextField(controller: mfaRecoveryCode, label: '恢复验证码'),
                  AppTextField(
                    controller: mfaRecoveryReason,
                    label: '丢失原因（至少 8 个字符）',
                  ),
                  PrimaryAction(
                    label: '提交人工审核',
                    icon: Icons.support_agent,
                    onPressed: actionsBlocked
                        ? null
                        : () => _run(() async {
                            final id = int.tryParse(
                              '${mfaRecoveryChallenge['challengeId']}',
                            );
                            if (id == null) throw StateError('恢复验证码已失效，请重新申请');
                            final request = await state.api.submitMfaRecovery(
                              challengeId: id,
                              currentPassword: mfaPassword.text,
                              code: mfaRecoveryCode.text.trim(),
                              reason: mfaRecoveryReason.text.trim(),
                            );
                            if (operationCurrent) {
                              setState(() {
                                mfaRecovery = request;
                                mfaRecoveryChallenge = const {};
                                mfaRecoveryCode.clear();
                                mfaRecoveryReason.clear();
                              });
                            }
                          }, '已提交，请等待人工审核'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() => mfaRecoveryChallenge = const {}),
                    child: const Text('取消'),
                  ),
                ],
              ],
              const SectionTitle(title: '敏感场景'),
              ...scenes.map((scene) {
                final enabled = scene['enabled'] == true;
                final code = asString(scene['sceneCode']);
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(asString(scene['label'], fallback: code)),
                  subtitle: Text(code),
                  value: enabled,
                  onChanged: actionsBlocked
                      ? null
                      : (next) => _run(() async {
                          await _updateSecurityScene(state, code, next);
                        }, '安全场景已更新'),
                );
              }),
              const SectionTitle(title: '安全设置验证'),
              Text(
                '修改敏感场景前需要邮箱验证码，绑定 2FA 后还需动态验证码。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              AppTextField(controller: securityEmailCode, label: '安全设置邮箱验证码'),
              const SectionTitle(title: '修改密码'),
              Text(
                '修改密码后，其他设备的登录会话会失效。若开启修改密码场景，请先发送邮箱验证码。',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 8),
              AppTextField(
                controller: currentPassword,
                label: '当前密码',
                obscure: true,
              ),
              AppTextField(
                controller: newPassword,
                label: '新密码（至少 8 位）',
                obscure: true,
              ),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      controller: changePasswordEmailCode,
                      label: '邮箱验证码',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: AppTextField(
                      controller: changePasswordTotpCode,
                      label: '2FA 验证码',
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  Expanded(
                    child: TextButton.icon(
                      onPressed: actionsBlocked
                          ? null
                          : () => _run(
                              () => state.api.issueSecurityChallenge(
                                'CHANGE_PASSWORD',
                              ),
                              '验证码已发送到邮箱',
                            ),
                      icon: const Icon(Icons.email_outlined),
                      label: const Text('发送验证码'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PrimaryAction(
                      label: '确认修改',
                      icon: Icons.password,
                      onPressed: actionsBlocked
                          ? null
                          : () => _run(
                              () => _changePassword(state),
                              '密码已修改，请重新登录其他设备',
                            ),
                    ),
                  ),
                ],
              ),
            ],
            SectionTitle(
              title:
                  '身份认证 KYC · ${kycLoaded ? asString(kyc['status'], fallback: '未提交') : '状态未获取'}',
            ),
            Text(
              '提币前请完成身份认证。请提供清晰、真实且在有效期内的材料。',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
            TextButton.icon(
              onPressed: busy || loading
                  ? null
                  : () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => KycDocumentsPage(state: state),
                      ),
                    ),
              icon: const Icon(Icons.folder_outlined),
              label: const Text('查看认证材料'),
            ),
            if (kyc['country'] != null)
              InfoLine(label: '国家 / 地区', value: asString(kyc['country'])),
            if (kyc['kycLevel'] != null)
              InfoLine(label: '认证等级', value: asString(kyc['kycLevel'])),
            if (kyc['reviewReason'] != null)
              Text(asString(kyc['reviewReason'])),
            if (!['PENDING', 'VERIFIED'].contains(kyc['status']))
              PrimaryAction(
                label: '填写认证资料',
                icon: Icons.badge_outlined,
                onPressed:
                    busy || loading || !kycLoaded || kycProviderInfo.isEmpty
                    ? null
                    : () => _run(
                        () async {
                          final next = await Navigator.of(context)
                              .push<Map<String, dynamic>>(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      KycApplicationPage(state: state),
                                ),
                              );
                          if (next == null || !operationCurrent) {
                            if (operationCurrent) {
                              setState(() => notice = '已返回认证页面');
                            }
                            return;
                          }
                          final profile = asMap(next['profile']);
                          setState(() {
                            kyc = profile;
                            kycVerificationSession = asMap(
                              next['verificationSession'],
                            );
                            _applyKyc(profile);
                          });
                        },
                        kycSimulationEnabled
                            ? '已提交模拟认证，请选择核验结果'
                            : '认证已提交，请继续核验',
                      ),
              ),
            if (kyc['status'] == 'PENDING' &&
                kycProvider != 'SELF' &&
                kycVerificationSession.isEmpty)
              PrimaryAction(
                label: clientText(
                  state.language,
                  '继续认证',
                  'Continue verification',
                ),
                icon: Icons.play_arrow,
                onPressed: kycActionsBlocked
                    ? null
                    : () => _run(() async {
                        final next = kycSimulationEnabled
                            ? <String, dynamic>{'simulation': true}
                            : await state.api.refreshKycSession();
                        if (!operationCurrent) return;
                        setState(() => kycVerificationSession = next);
                        if (!kycSimulationEnabled) {
                          await _launchKycProvider(state);
                        }
                      }, '认证会话已恢复'),
              ),
            if (kycSimulationEnabled && kycVerificationSession.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                clientText(
                  state.language,
                  '模拟模式：未调用第三方服务，可选择结果验证完整状态流转。',
                  'Simulation mode: no provider is called. Choose an outcome to test the complete status flow.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: kycActionsBlocked
                        ? null
                        : () => _run(
                            () => _completeKycSimulation(state, 'APPROVED'),
                            '模拟核验通过',
                          ),
                    child: Text(
                      clientText(state.language, '模拟自动通过', 'Simulate approval'),
                    ),
                  ),
                  TextButton(
                    onPressed: kycActionsBlocked
                        ? null
                        : () => _run(
                            () =>
                                _completeKycSimulation(state, 'MANUAL_REVIEW'),
                            '已转人工复核',
                          ),
                    child: Text(
                      clientText(
                        state.language,
                        '模拟人工复核',
                        'Simulate manual review',
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: kycActionsBlocked
                        ? null
                        : () => _run(
                            () => _completeKycSimulation(state, 'REJECTED'),
                            '模拟核验拒绝',
                          ),
                    child: Text(
                      clientText(state.language, '模拟拒绝', 'Simulate rejection'),
                    ),
                  ),
                ],
              ),
            ],
            if (!kycSimulationEnabled && kycVerificationSession.isNotEmpty) ...[
              const SizedBox(height: 8),
              PrimaryAction(
                label: kycProvider == 'SUMSUB'
                    ? clientText(
                        state.language,
                        '打开 Sumsub 证件与人脸核验',
                        'Open Sumsub identity and face verification',
                      )
                    : clientText(
                        state.language,
                        '打开 Veriff 证件与人脸核验',
                        'Open Veriff identity and face verification',
                      ),
                icon: Icons.open_in_new,
                onPressed: kycActionsBlocked
                    ? null
                    : () => _run(() => _launchKycProvider(state), '已返回核验服务'),
              ),
            ],
            if (!widget.kycOnly) ...[
              const SectionTitle(title: 'API Key'),
              if (apiSecret != null)
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Secret 仅显示这一次，请妥善保存'),
                      SelectableText(
                        apiSecret!,
                        key: const ValueKey('api-secret'),
                      ),
                      TextButton(
                        onPressed: () => setState(() => apiSecret = null),
                        child: const Text('我已保存'),
                      ),
                    ],
                  ),
                ),
              AppTextField(controller: apiLabel, label: '名称'),
              AppTextField(
                controller: apiAllowlist,
                label: 'IP 白名单（多个地址以逗号分隔）',
              ),
              const Text('默认只有读取权限。按需要开启交易或提现权限。'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许交易'),
                value: apiTradeEnabled,
                onChanged: actionsBlocked
                    ? null
                    : (v) => setState(() => apiTradeEnabled = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('允许提币'),
                subtitle: const Text('仅在确有自动化提币需求时开启，并妥善保管 Secret'),
                value: apiWithdrawEnabled,
                onChanged: actionsBlocked
                    ? null
                    : (enabled) => setState(() => apiWithdrawEnabled = enabled),
              ),
              AppTextField(controller: emailCode, label: '邮箱验证码'),
              AppTextField(controller: apiTotp, label: '2FA 验证码'),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: actionsBlocked
                          ? null
                          : () => _run(() async {
                              await state.api.issueSecurityChallenge(
                                'SECURITY_SETTINGS',
                              );
                            }, '验证码已发送'),
                      child: const Text('发送邮箱验证码'),
                    ),
                  ),
                  Expanded(
                    child: PrimaryAction(
                      label: '创建 API Key',
                      icon: Icons.key,
                      onPressed: actionsBlocked
                          ? null
                          : () => _run(() async {
                              final created = await state.api.createApiKey(
                                label: apiLabel.text.trim(),
                                permissions: [
                                  'READ',
                                  if (apiTradeEnabled) 'TRADE',
                                  if (apiWithdrawEnabled) 'WITHDRAW',
                                ],
                                ipAllowlist: _apiAllowlist(),
                                emailCode: emailCode.text.trim(),
                                totpCode: apiTotp.text.trim(),
                              );
                              if (operationCurrent) {
                                setState(() {
                                  keys = [...keys, asMap(created['apiKey'])];
                                  apiSecret = asString(created['secret']);
                                  apiTradeEnabled = false;
                                  apiAllowlist.clear();
                                  apiLabel.clear();
                                  emailCode.clear();
                                  apiTotp.clear();
                                  apiWithdrawEnabled = false;
                                });
                              }
                            }, 'API Key 已创建，请保存 Secret'),
                    ),
                  ),
                ],
              ),
              ...keys.map(
                (apiKey) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(asString(apiKey['label'], fallback: 'API Key')),
                  subtitle: Text(
                    '${asString(apiKey['apiKey'])} · ${asString(apiKey['permissions'])}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (action) => _run(() async {
                      final key = asString(apiKey['apiKey']);
                      if (key.isEmpty) {
                        throw const FormatException('密钥信息暂不可用，请刷新');
                      }
                      if (action == 'allowlist') {
                        apiAllowlist.text = asList(
                          apiKey['ipAllowlist'],
                        ).join(', ');
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialog) => AlertDialog(
                            title: const Text('修改 IP 白名单'),
                            content: AppTextField(
                              controller: apiAllowlist,
                              label: 'IP 地址或 CIDR，以逗号分隔',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(dialog, false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(dialog, true),
                                child: const Text('保存'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed != true || !operationCurrent) {
                          _operationCancelled = true;
                          return;
                        }
                        await state.api.updateApiKeyAllowlist(
                          apiKey: key,
                          ipAllowlist: _apiAllowlist(),
                          emailCode: emailCode.text.trim(),
                          totpCode: apiTotp.text.trim(),
                        );
                      } else {
                        if (!await _confirmSecurity(
                              '撤销 API 密钥？',
                              '使用该密钥的应用将无法继续访问。',
                            ) ||
                            !operationCurrent) {
                          return;
                        }
                        await state.api.revokeApiKey(
                          apiKey: key,
                          emailCode: emailCode.text.trim(),
                          totpCode: apiTotp.text.trim(),
                        );
                      }
                      if (operationCurrent) await _load();
                    }, action == 'allowlist' ? 'IP 白名单已更新' : 'API Key 已撤销'),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'allowlist', child: Text('IP 白名单')),
                      PopupMenuItem(value: 'revoke', child: Text('撤销')),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

void showSecuritySheet(BuildContext context, {bool kycOnly = false}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => AppScope(
      notifier: AppScope.of(context),
      child: SecuritySheet(kycOnly: kycOnly),
    ),
  );
}

class KlinePanel extends StatefulWidget {
  const KlinePanel({
    required this.candles,
    required this.period,
    required this.onPeriod,
    super.key,
  });

  final List<Candle> candles;
  final String period;
  final ValueChanged<String> onPeriod;

  @override
  State<KlinePanel> createState() => _KlinePanelState();
}

class _KlinePanelState extends State<KlinePanel> {
  late final KLineController controller;

  @override
  void initState() {
    super.initState();
    controller = KLineController()
      ..itemCount = 38
      ..minCount = 12
      ..maxCount = 90
      ..showTimeAxis = true
      ..showMainIndicators = [IndicatorType.ma]
      ..showSubIndicators = [IndicatorType.vol, IndicatorType.macd]
      ..chartStyle = const KLineChartStyle(
        backgroundColor: Colors.transparent,
        gridLineColor: _line,
        gridLineWidth: 0.6,
        rulerTextStyle: TextStyle(color: _muted, fontSize: 10),
      )
      ..candleStyle = const KLineCandleStyle(
        riseColor: _mint,
        fallColor: _red,
        riseWickColor: _mint,
        fallWickColor: _red,
      )
      ..volumeStyle = const KLineVolumeStyle(riseColor: _mint, fallColor: _red)
      ..indicatorColors = const [_amber, _violet, _pink];
    controller.priceFormatter = (value) =>
        value.toStringAsFixed(value > 1000 ? 1 : 4);
    controller.volumeFormatter = (value) => compactInt(value.round());
    _setData();
  }

  @override
  void didUpdateWidget(covariant KlinePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.candles != widget.candles) _setData();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void _setData() {
    controller.setData(
      widget.candles.map((candle) {
        return KLineData(
          open: candle.open,
          high: candle.high,
          low: candle.low,
          close: candle.close,
          volume: candle.volume,
          time: candle.timeMillis,
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Panel(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
      child: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('K线', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                for (final period in const ['1m', '5m', '15m', '1h', '4h'])
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: ChoiceChip(
                      label: Text(period),
                      selected: widget.period == period,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => widget.onPeriod(period),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(height: 252, child: KLineView(controller: controller)),
        ],
      ),
    );
  }
}

class OrderTicket extends StatelessWidget {
  const OrderTicket({
    required this.side,
    required this.orderType,
    required this.timeInForce,
    required this.marginMode,
    required this.positionMode,
    required this.positionSide,
    required this.reduceOnly,
    required this.postOnly,
    required this.bboEnabled,
    required this.bboPriceMode,
    required this.onBboEnabled,
    required this.onBboPriceMode,
    required this.priceController,
    required this.quantityController,
    required this.instrument,
    required this.loggedIn,
    required this.onSide,
    required this.onOrderType,
    required this.onTimeInForce,
    required this.onMarginMode,
    required this.onPositionSide,
    required this.onReduceOnly,
    required this.onPostOnly,
    required this.onSubmit,
    super.key,
  });

  final String side;
  final String orderType;
  final String timeInForce;
  final String marginMode;
  final String positionMode;
  final String positionSide;
  final bool reduceOnly;
  final bool postOnly;
  final bool bboEnabled;
  final String bboPriceMode;
  final ValueChanged<bool> onBboEnabled;
  final ValueChanged<String> onBboPriceMode;
  final TextEditingController priceController;
  final TextEditingController quantityController;
  final Instrument instrument;
  final bool loggedIn;
  final ValueChanged<String> onSide;
  final ValueChanged<String> onOrderType;
  final ValueChanged<String> onTimeInForce;
  final ValueChanged<String> onMarginMode;
  final ValueChanged<String> onPositionSide;
  final ValueChanged<bool> onReduceOnly;
  final ValueChanged<bool> onPostOnly;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final buy = side == 'BUY';
    final hedgeMode = instrument.isDerivative && positionMode == 'HEDGE';
    final effectiveReduceOnly = instrument.effectiveReduceOnly(
      reduceOnly: reduceOnly,
      side: side,
      positionMode: positionMode,
      positionSide: positionSide,
    );
    void stepPrice(int direction) {
      if (orderType == 'MARKET') return;
      if (instrument.isSpot) {
        final scale = instrument.quoteScaleUnits;
        if (scale == null || instrument.priceTickUnits <= 0) return;
        final current =
            decimalIncrement(
              priceController.text,
              instrument.priceTickUnits,
              scaleUnits: scale,
            ) ??
            0;
        priceController.text = scaledAmount(
          BigInt.from(math.max(0, current + direction)) *
              BigInt.from(instrument.priceTickUnits),
          scale,
        );
        return;
      }
      final current = double.tryParse(priceController.text) ?? 0;
      final tick = instrument.priceFromTicks(1).abs();
      final next = math.max(0.0, current + tick * direction);
      priceController.text = money(next, digits: instrument.pricePrecision);
    }

    void stepQuantity(int direction) {
      final current = instrument.isSpot
          ? decimalIncrement(
                  quantityController.text,
                  instrument.quantityStepUnits,
                  scaleUnits: instrument.baseScaleUnits ?? 0,
                ) ??
                0
          : int.tryParse(quantityController.text) ?? 0;
      final next = math.max(0, current + direction);
      quantityController.text = instrument.isSpot
          ? scaledAmount(
              BigInt.from(next) * BigInt.from(instrument.quantityStepUnits),
              instrument.baseScaleUnits,
            )
          : next.toString();
    }

    return Panel(
      padding: const EdgeInsets.all(6),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            BuySellSwitch(value: side, onChanged: onSide),
            const SizedBox(height: 5),
            Row(
              children: [
                Expanded(
                  child: SmallDropdown(
                    value: orderType,
                    values: const ['LIMIT', 'MARKET'],
                    labelBuilder: orderTypeLabel,
                    onChanged: onOrderType,
                  ),
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: SmallDropdown(
                    value: timeInForce,
                    values: orderType == 'MARKET'
                        ? const ['IOC', 'FOK']
                        : const ['GTC', 'IOC', 'FOK', 'GTX'],
                    labelBuilder: timeInForceLabel,
                    onChanged: onTimeInForce,
                  ),
                ),
              ],
            ),
            if (instrument.isDerivative) ...[
              const SizedBox(height: 5),
              Row(
                children: [
                  Expanded(
                    child: SmallDropdown(
                      value: marginMode,
                      values: const ['CROSS', 'ISOLATED'],
                      labelBuilder: marginModeLabel,
                      onChanged: onMarginMode,
                    ),
                  ),
                  if (hedgeMode) ...[
                    const SizedBox(width: 5),
                    Expanded(
                      child: SmallDropdown(
                        value: positionSide == 'NET'
                            ? (instrument.mode == ProductMode.linearDelivery &&
                                      side == 'SELL'
                                  ? 'SHORT'
                                  : 'LONG')
                            : positionSide,
                        values: const ['LONG', 'SHORT'],
                        labelBuilder: positionSideLabel,
                        onChanged: onPositionSide,
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 5),
            if (orderType == 'LIMIT') ...[
              ToggleLine(
                label: 'BBO 最优价',
                value: bboEnabled,
                onChanged: onBboEnabled,
              ),
              if (bboEnabled) ...[
                SmallDropdown(
                  key: const ValueKey('bbo-price-mode'),
                  value: bboPriceMode,
                  values: bboPriceModes,
                  labelBuilder: bboPriceModeLabel,
                  onChanged: onBboPriceMode,
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    '提交时按所选盘口档位确定限价，不随行情自动改价。',
                    style: TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ],
            if (!bboEnabled || orderType == 'MARKET')
              Row(
                children: [
                  Expanded(
                    child: TradeNumericField(
                      controller: priceController,
                      label: '价格 (${instrument.quoteAsset})',
                      enabled: orderType != 'MARKET',
                      onMinus: () => stepPrice(-1),
                      onPlus: () => stepPrice(1),
                    ),
                  ),
                  const SizedBox(width: 5),
                  BestPriceButton(
                    enabled: orderType != 'MARKET',
                    onTap: () {
                      final book = AppScope.of(context).orderBook;
                      final levels = buy ? book.asks : book.bids;
                      if (levels.isEmpty) return;
                      priceController.text = instrument.isSpot
                          ? scaledAmount(
                              BigInt.from(levels.first.priceTicks) *
                                  BigInt.from(instrument.priceTickUnits),
                              instrument.quoteScaleUnits,
                            )
                          : money(
                              instrument.priceFromTicks(
                                levels.first.priceTicks,
                              ),
                              digits: instrument.pricePrecision,
                            );
                    },
                  ),
                ],
              ),
            const SizedBox(height: 5),
            TradeNumericField(
              controller: quantityController,
              label: '数量',
              suffixLabel: instrument.isSpot ? instrument.baseAsset : '张',
              onMinus: () => stepQuantity(-1),
              onPlus: () => stepQuantity(1),
            ),
            if (instrument.isSpot)
              SpotOrderSizing(
                instrument: instrument,
                side: side,
                orderType: orderType,
                bboMode: bboEnabled && orderType == 'LIMIT'
                    ? bboPriceMode
                    : null,
                price: priceController,
                quantity: quantityController,
                loggedIn: loggedIn,
              ),
            const SizedBox(height: 6),
            Text(
              '最小价格变动 ${instrument.isSpot ? scaledAmount(BigInt.from(instrument.priceTickUnits), instrument.quoteScaleUnits) : instrument.priceFromTicks(1)} ${instrument.quoteAsset}',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
            ),
            const SizedBox(height: 3),
            Row(
              children: [
                if (instrument.isDerivative)
                  Expanded(
                    child: ToggleLine(
                      label: '只减仓',
                      value: effectiveReduceOnly,
                      enabled:
                          instrument.isDerivative &&
                          !(effectiveReduceOnly && !reduceOnly),
                      onChanged: onReduceOnly,
                    ),
                  ),
                Expanded(
                  child: ToggleLine(
                    label: 'Post',
                    value: postOnly,
                    enabled: orderType == 'LIMIT',
                    onChanged: onPostOnly,
                  ),
                ),
              ],
            ),
            if (instrument.status != 'TRADING')
              Text(
                instrument.mode == ProductMode.linearDelivery &&
                        instrument.status == 'SETTLING'
                    ? '合约结算中，仅允许减仓；撤单与持仓仍可查看'
                    : instrument.status == 'PRE_TRADING'
                    ? '该交易对尚未开放交易'
                    : '该交易对已暂停交易',
                style: const TextStyle(fontSize: 11),
              ),
            const SizedBox(height: 6),
            if (AppScope.of(context).tradingCommandPending) ...[
              Text(
                tradingPendingMessage(
                  AppScope.of(context).pendingTradingCommand,
                ),
                style: const TextStyle(fontSize: 11),
              ),
              TextButton(
                onPressed: AppScope.of(context).submittingOrder
                    ? null
                    : () => unawaited(
                        AppScope.of(context).checkPendingTradingCommand(),
                      ),
                child: Text(
                  tradingRecoveryLabel(
                    AppScope.of(context).pendingTradingCommand,
                  ),
                ),
              ),
            ],
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: loggedIn
                    ? (buy
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.error)
                    : Theme.of(context).colorScheme.secondary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size.fromHeight(34),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed:
                  AppScope.of(context).submittingOrder ||
                      AppScope.of(context).tradingCommandPending ||
                      (loggedIn &&
                          !instrument.canPlaceOrder(
                            reduceOnly: effectiveReduceOnly,
                          ))
                  ? null
                  : onSubmit,
              icon: Icon(loggedIn ? Icons.flash_on : Icons.login, size: 16),
              label: Text(
                loggedIn
                    ? instrument.mode == ProductMode.linearDelivery &&
                              effectiveReduceOnly
                          ? (buy ? '买入平空' : '卖出平多')
                          : instrument.isSpot
                          ? (buy ? '买入' : '卖出')
                          : hedgeMode
                          ? (buy ? '买入' : '卖出')
                          : (buy ? '买入 / 开多' : '卖出 / 开空')
                    : '登录',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SpotOrderSizing extends StatelessWidget {
  const SpotOrderSizing({
    required this.instrument,
    required this.side,
    required this.orderType,
    required this.bboMode,
    required this.price,
    required this.quantity,
    required this.loggedIn,
    super.key,
  });
  final Instrument instrument;
  final String side, orderType;
  final String? bboMode;
  final TextEditingController price, quantity;
  final bool loggedIn;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: price,
    builder: (context, _) {
      final state = AppScope.of(context);
      final asset = side == 'BUY'
          ? instrument.quoteAsset
          : instrument.baseAsset;
      final balance = state.balances
          .where(
            (row) =>
                row.accountType == 'SPOT' &&
                row.asset.toUpperCase() == asset.toUpperCase(),
          )
          .firstOrNull;
      final terms = state.spotOrderTerms;
      String? size(int percent) => spotOrderQuantity(
        instrument: instrument,
        balance: balance,
        book: state.orderBook,
        side: side,
        orderType: orderType,
        price: price.text,
        bboMode: bboMode,
        takerFeeRatePpm: terms?.takerFeeRatePpm,
        marketMaxSlippagePpm: terms?.marketMaxSlippagePpm,
        percentage: percent,
      );
      final ready = loggedIn && size(100) != null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 4),
          Text(
            '可用 ${scaledAmount(balance == null ? null : BigInt.from(balance.availableUnits), side == 'BUY' ? instrument.quoteScaleUnits : instrument.baseScaleUnits)} $asset',
            style: const TextStyle(fontSize: 10),
          ),
          Row(
            children: [
              for (final percent in [25, 50, 75, 100])
                Expanded(
                  child: TextButton(
                    key: ValueKey('spot-percent-$percent'),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 32),
                    ),
                    onPressed: ready
                        ? () {
                            final value = size(percent);
                            if (value != null) {
                              quantity.text = value == '0' ? '' : value;
                            }
                          }
                        : null,
                    child: Text('$percent%'),
                  ),
                ),
            ],
          ),
          if (loggedIn && !ready)
            TextButton(
              onPressed: () => unawaited(() async {
                await state.refreshInstruments(silent: true);
                await state.refreshSpotOrderTerms();
              }()),
              child: const Text('刷新下单资料'),
            ),
        ],
      );
    },
  );
}

class AlgoOrderPanel extends StatefulWidget {
  const AlgoOrderPanel({
    required this.state,
    required this.marginMode,
    super.key,
  });

  final AppState state;
  final String marginMode;

  @override
  State<AlgoOrderPanel> createState() => _AlgoOrderPanelState();
}

class _AlgoOrderPanelState extends State<AlgoOrderPanel> {
  String algoType = 'TWAP';
  String side = 'BUY';
  String positionSide = 'LONG';
  bool reduceOnly = false;
  bool postOnly = false;
  bool submitting = false;
  late final TextEditingController priceTicksController;
  final quantityController = TextEditingController(text: '2');
  final childQuantityController = TextEditingController(text: '1');
  final intervalController = TextEditingController(text: '5');
  final durationController = TextEditingController(text: '20');

  @override
  void initState() {
    super.initState();
    priceTicksController = TextEditingController(
      text: _defaultPriceTicks().toString(),
    );
  }

  @override
  void dispose() {
    priceTicksController.dispose();
    quantityController.dispose();
    childQuantityController.dispose();
    intervalController.dispose();
    durationController.dispose();
    super.dispose();
  }

  int _defaultPriceTicks() {
    final instrument = widget.state.selectedInstrument;
    final latestPrice = widget.state.latestPriceFor(instrument);
    if (latestPrice != null && latestPrice > 0) {
      return instrument.ticksFromPrice(latestPrice);
    }
    final book = widget.state.orderBook;
    if (book.symbol == instrument.symbol) {
      if (side == 'BUY' && book.asks.isNotEmpty) {
        return book.asks.first.priceTicks;
      }
      if (side == 'SELL' && book.bids.isNotEmpty) {
        return book.bids.first.priceTicks;
      }
    }
    return 0;
  }

  bool get _valid {
    final priceTicks = int.tryParse(priceTicksController.text) ?? 0;
    final quantity = int.tryParse(quantityController.text) ?? 0;
    final childQuantity = int.tryParse(childQuantityController.text) ?? 0;
    final interval = int.tryParse(intervalController.text) ?? 0;
    final duration = int.tryParse(durationController.text) ?? 0;
    if (quantity <= 0 || childQuantity <= 0 || childQuantity > quantity) {
      return false;
    }
    if (interval <= 0 || duration <= 0) return false;
    return algoType == 'TWAP' || priceTicks > 0;
  }

  Future<void> submit() async {
    if (!_valid || submitting) return;
    setState(() => submitting = true);
    final hedgeMode = widget.state.positionMode == 'HEDGE';
    final effectivePositionSide = hedgeMode ? positionSide : 'NET';
    await widget.state.placeAlgoOrder(
      AlgoOrderDraft(
        algoType: algoType,
        side: side,
        priceTicks: int.tryParse(priceTicksController.text) ?? 0,
        quantitySteps: int.tryParse(quantityController.text) ?? 0,
        childQuantitySteps: int.tryParse(childQuantityController.text) ?? 0,
        intervalSeconds: int.tryParse(intervalController.text) ?? 0,
        durationSeconds: int.tryParse(durationController.text) ?? 0,
        marginMode: widget.marginMode,
        positionSide: effectivePositionSide,
        reduceOnly: reduceOnly,
        postOnly: algoType == 'ICEBERG' && postOnly,
      ),
    );
    if (mounted) setState(() => submitting = false);
  }

  @override
  Widget build(BuildContext context) {
    final hedgeMode = widget.state.positionMode == 'HEDGE';
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('算法单', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SmallDropdown(
                  value: algoType,
                  values: const ['TWAP', 'ICEBERG'],
                  labelBuilder: algoTypeLabel,
                  onChanged: (value) => setState(() {
                    algoType = value;
                    if (value == 'TWAP') postOnly = false;
                  }),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: SmallDropdown(
                  value: side,
                  values: const ['BUY', 'SELL'],
                  onChanged: (value) => setState(() => side = value),
                ),
              ),
              if (hedgeMode) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: SmallDropdown(
                    value: positionSide,
                    values: const ['LONG', 'SHORT'],
                    labelBuilder: positionSideLabel,
                    onChanged: (value) => setState(() => positionSide = value),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: priceTicksController,
                  label: '价格 ticks',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: quantityController,
                  label: '总量 steps',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: childQuantityController,
                  label: '切片 steps',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: AppTextField(
                  controller: intervalController,
                  label: '间隔秒',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: AppTextField(
                  controller: durationController,
                  label: '时长秒',
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ToggleLine(
                  label: '只减仓',
                  value: reduceOnly,
                  onChanged: (value) => setState(() => reduceOnly = value),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: ToggleLine(
                  label: 'Post',
                  value: postOnly,
                  enabled: algoType == 'ICEBERG',
                  onChanged: (value) => setState(() => postOnly = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.secondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              minimumSize: const Size.fromHeight(38),
            ),
            onPressed: _valid && !submitting ? submit : null,
            icon: Icon(submitting ? Icons.hourglass_top : Icons.schedule),
            label: Text(submitting ? '提交中' : '提交 ${algoTypeLabel(algoType)}'),
          ),
        ],
      ),
    );
  }
}

class TriggerOrderPanel extends StatefulWidget {
  const TriggerOrderPanel({
    required this.state,
    required this.marginMode,
    super.key,
  });

  final AppState state;
  final String marginMode;

  @override
  State<TriggerOrderPanel> createState() => _TriggerOrderPanelState();
}

class _TriggerOrderPanelState extends State<TriggerOrderPanel> {
  final List<_TriggerLevelInput> levels = [];
  bool submitting = false;

  void addLevel(String triggerType) {
    if (submitting) return;
    final defaultPrice = _defaultTriggerPrice();
    setState(() {
      levels.add(
        _TriggerLevelInput(
          id: '${DateTime.now().microsecondsSinceEpoch}-${levels.length}',
          triggerType: triggerType,
          closeTarget: 'LONG',
          triggerPriceTicks: triggerType == 'TRAILING_STOP'
              ? '0'
              : defaultPrice,
          activationPriceTicks: triggerType == 'TRAILING_STOP'
              ? defaultPrice
              : '',
          callbackRatePpm: triggerType == 'TRAILING_STOP' ? '0.1' : '',
          quantitySteps: '1',
        ),
      );
    });
  }

  String _defaultTriggerPrice() {
    final instrument = widget.state.selectedInstrument;
    final price = widget.state.latestPriceFor(instrument);
    return price == null
        ? ''
        : price.toStringAsFixed(instrument.pricePrecision);
  }

  List<TriggerOrderDraft> _drafts() {
    final hedgeMode = widget.state.positionMode == 'HEDGE';
    return levels
        .where(
          (level) =>
              level.triggerType != 'TRAILING_STOP' ||
              level.activationPriceTicks.trim().isEmpty ||
              decimalIncrement(
                    level.activationPriceTicks,
                    widget.state.selectedInstrument.priceTickUnits,
                  ) !=
                  null,
        )
        .map((level) {
          final triggerPriceTicks =
              decimalIncrement(
                level.triggerPriceTicks,
                widget.state.selectedInstrument.priceTickUnits,
              ) ??
              0;
          final activationPriceTicks = decimalIncrement(
            level.activationPriceTicks,
            widget.state.selectedInstrument.priceTickUnits,
          );
          final callbackRatePpm = decimalIncrement(
            level.callbackRatePpm,
            10000,
          );
          final quantitySteps = int.tryParse(level.quantitySteps) ?? 0;
          return TriggerOrderDraft(
            side: level.closeTarget == 'LONG' ? 'SELL' : 'BUY',
            triggerType: level.triggerType,
            triggerPriceTicks: triggerPriceTicks,
            activationPriceTicks: level.triggerType == 'TRAILING_STOP'
                ? activationPriceTicks
                : null,
            callbackRatePpm: level.triggerType == 'TRAILING_STOP'
                ? callbackRatePpm
                : null,
            quantitySteps: quantitySteps,
            marginMode: widget.marginMode,
            positionSide: hedgeMode ? level.closeTarget : 'NET',
          );
        })
        .where(_validDraft)
        .toList();
  }

  bool _validDraft(TriggerOrderDraft draft) {
    if (draft.quantitySteps <= 0) return false;
    if (draft.triggerType == 'TRAILING_STOP') {
      final callbackRate = draft.callbackRatePpm;
      return draft.triggerPriceTicks >= 0 &&
          (draft.activationPriceTicks == null ||
              draft.activationPriceTicks! >= 0) &&
          callbackRate != null &&
          callbackRate >= 1000 &&
          callbackRate <= 100000;
    }
    return draft.triggerPriceTicks > 0;
  }

  Future<void> submit() async {
    final drafts = _drafts();
    if (drafts.isEmpty || drafts.length != levels.length || submitting) return;
    final submittedIds = levels.map((level) => level.id).toList();
    setState(() => submitting = true);
    final submitted = await widget.state.placeTriggerOrders(drafts);
    if (mounted) {
      setState(() {
        levels.removeWhere(
          (level) => submittedIds.take(submitted).contains(level.id),
        );
        submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final validCount = _drafts().length;
    return Panel(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  '条件单',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton.filledTonal(
                tooltip: '新增止盈',
                onPressed: () => addLevel('TAKE_PROFIT'),
                icon: const Icon(Icons.add_chart, size: 18),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: '新增止损',
                onPressed: () => addLevel('STOP_LOSS'),
                icon: const Icon(Icons.add_alert, size: 18),
              ),
              const SizedBox(width: 6),
              IconButton.filledTonal(
                tooltip: '新增追踪止损',
                onPressed: () => addLevel('TRAILING_STOP'),
                icon: const Icon(Icons.timeline, size: 18),
              ),
            ],
          ),
          if (levels.isEmpty)
            Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                '暂无待提交档位',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            for (final level in levels) _levelRow(level),
            const SizedBox(height: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: _amber,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                minimumSize: const Size.fromHeight(38),
              ),
              onPressed:
                  validCount == 0 || validCount != levels.length || submitting
                  ? null
                  : submit,
              icon: Icon(
                submitting ? Icons.hourglass_top : Icons.notifications,
              ),
              label: Text(submitting ? '提交中' : '提交 $validCount 档'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _levelRow(_TriggerLevelInput level) {
    return AbsorbPointer(
      absorbing: submitting,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _line),
          color: _panelSoft,
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: SmallDropdown(
                    value: level.triggerType,
                    values: const ['TAKE_PROFIT', 'STOP_LOSS', 'TRAILING_STOP'],
                    labelBuilder: triggerTypeLabel,
                    onChanged: (value) => setState(() {
                      level.triggerType = value;
                      if (value == 'TRAILING_STOP') {
                        level.triggerPriceTicks = '0';
                        if (level.activationPriceTicks.isEmpty) {
                          level.activationPriceTicks = _defaultTriggerPrice();
                        }
                        if (level.callbackRatePpm.isEmpty) {
                          level.callbackRatePpm = '0.1';
                        }
                      } else {
                        if (level.triggerPriceTicks == '0') {
                          level.triggerPriceTicks = _defaultTriggerPrice();
                        }
                        level.activationPriceTicks = '';
                        level.callbackRatePpm = '';
                      }
                    }),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SmallDropdown(
                    value: level.closeTarget,
                    values: const ['LONG', 'SHORT'],
                    labelBuilder: (value) => value == 'LONG' ? '平多' : '平空',
                    onChanged: (value) =>
                        setState(() => level.closeTarget = value),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  tooltip: '删除',
                  onPressed: () => setState(() => levels.remove(level)),
                  icon: const Icon(Icons.delete_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              level.triggerType == 'TRAILING_STOP'
                  ? '激活后按回调比例触发平仓'
                  : '标记价格 ${(level.triggerType == 'TAKE_PROFIT') == (level.closeTarget == 'LONG') ? '≥' : '≤'} 触发价时市价平仓',
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: AppTextField(
                    key: ValueKey('${level.id}-price'),
                    initialValue: level.triggerPriceTicks,
                    label:
                        '触发价 (${widget.state.selectedInstrument.quoteAsset})',
                    onChanged: (value) =>
                        setState(() => level.triggerPriceTicks = value),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: AppTextField(
                    key: ValueKey('${level.id}-quantity'),
                    initialValue: level.quantitySteps,
                    label: '平仓数量（张）',
                    onChanged: (value) =>
                        setState(() => level.quantitySteps = value),
                  ),
                ),
              ],
            ),
            if (level.triggerType == 'TRAILING_STOP') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                      key: ValueKey('${level.id}-activation'),
                      initialValue: level.activationPriceTicks,
                      label: '激活价格',
                      onChanged: (value) =>
                          setState(() => level.activationPriceTicks = value),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: AppTextField(
                      key: ValueKey('${level.id}-callback'),
                      initialValue: level.callbackRatePpm,
                      label: '回调比例 (%)',
                      onChanged: (value) =>
                          setState(() => level.callbackRatePpm = value),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TriggerLevelInput {
  _TriggerLevelInput({
    required this.id,
    required this.triggerType,
    required this.closeTarget,
    required this.triggerPriceTicks,
    required this.activationPriceTicks,
    required this.callbackRatePpm,
    required this.quantitySteps,
  });

  final String id;
  String triggerType;
  String closeTarget;
  String triggerPriceTicks;
  String activationPriceTicks;
  String callbackRatePpm;
  String quantitySteps;
}

class OrderBookPanel extends StatelessWidget {
  const OrderBookPanel({
    required this.instrument,
    required this.orderBook,
    required this.latestPrice,
    required this.onPrice,
    super.key,
  });

  final Instrument instrument;
  final OrderBook orderBook;
  final double? latestPrice;
  final ValueChanged<String> onPrice;

  @override
  Widget build(BuildContext context) {
    final maxQuantity = [
      ...orderBook.asks.take(5),
      ...orderBook.bids.take(5),
    ].fold<int>(0, (value, level) => math.max(value, level.quantitySteps));
    final asks = orderBook.asks.take(5).toList().reversed.toList();
    final bids = orderBook.bids.take(5).toList();
    final askTotal = asks.fold<int>(
      0,
      (sum, level) => sum + level.quantitySteps.abs(),
    );
    final bidTotal = bids.fold<int>(
      0,
      (sum, level) => sum + level.quantitySteps.abs(),
    );
    final buyRatio = bidTotal + askTotal == 0
        ? .5
        : bidTotal / (bidTotal + askTotal);
    final fallbackPriceTicks = bids.isNotEmpty
        ? bids.first.priceTicks
        : (asks.isNotEmpty ? asks.last.priceTicks : 0);
    final displayPrice =
        latestPrice ??
        (fallbackPriceTicks == 0
            ? null
            : instrument.priceFromTicks(fallbackPriceTicks));
    return Panel(
      padding: const EdgeInsets.all(6),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '价格',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
              Text(
                instrument.isSpot ? '数量 (${instrument.baseAsset})' : '数量（张）',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          for (final level in asks)
            BookLine(
              level: level,
              maxQuantity: maxQuantity,
              instrument: instrument,
              color: Theme.of(context).colorScheme.error,
              onTap: onPrice,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              displayPrice == null
                  ? '--'
                  : money(displayPrice, digits: instrument.pricePrecision),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.tertiary,
              ),
            ),
          ),
          for (final level in bids)
            BookLine(
              level: level,
              maxQuantity: maxQuantity,
              instrument: instrument,
              color: Theme.of(context).colorScheme.tertiary,
              onTap: onPrice,
            ),
          const Spacer(),
          OrderBookRatioBar(buyRatio: buyRatio),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => AppScope(
                notifier: AppScope.of(context),
                child: FullOrderBookSheet(onPrice: onPrice),
              ),
            ),
            child: const Text('查看20档', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }
}

class OrderBookRatioBar extends StatelessWidget {
  const OrderBookRatioBar({required this.buyRatio, super.key});

  final double buyRatio;

  @override
  Widget build(BuildContext context) {
    final buy = buyRatio.clamp(0.0, 1.0);
    final sell = 1 - buy;
    return Row(
      children: [
        Text(
          '${(buy * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Theme.of(context).colorScheme.tertiary,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: SizedBox(
            height: 4,
            child: Row(
              children: [
                Expanded(
                  flex: math.max(1, (buy * 1000).round()),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.tertiary,
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(999),
                      ),
                    ),
                  ),
                ),
                Container(
                  width: 1,
                  color: Theme.of(context).colorScheme.surface,
                ),
                Expanded(
                  flex: math.max(1, (sell * 1000).round()),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.horizontal(
                        right: Radius.circular(999),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '${(sell * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            color: Theme.of(context).colorScheme.error,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class OrderBookLayoutIcon extends StatelessWidget {
  const OrderBookLayoutIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size.square(28),
      painter: _BookGridPainter(),
    );
  }
}

class _BookGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final colors = [_red, _muted, _mint, _muted];
    final rects = [
      Rect.fromLTWH(size.width * .08, size.height * .10, 7, 7),
      Rect.fromLTWH(size.width * .08, size.height * .42, 7, 7),
      Rect.fromLTWH(size.width * .08, size.height * .74, 7, 7),
      Rect.fromLTWH(size.width * .48, size.height * .10, 7, 7),
      Rect.fromLTWH(size.width * .48, size.height * .42, 7, 7),
      Rect.fromLTWH(size.width * .48, size.height * .74, 7, 7),
    ];
    for (var i = 0; i < rects.length; i++) {
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;
      canvas.drawRRect(
        RRect.fromRectAndRadius(rects[i], const Radius.circular(1.4)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class PrivateTradingPanel extends StatefulWidget {
  const PrivateTradingPanel({required this.state, super.key});

  final AppState state;

  @override
  State<PrivateTradingPanel> createState() => _PrivateTradingPanelState();
}

class _PrivateTradingPanelState extends State<PrivateTradingPanel> {
  int tab = 0;
  AppState get state => widget.state;
  @override
  Widget build(BuildContext context) {
    final botCount =
        state.openAlgoOrders.length + state.openTriggerOrders.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (state.pendingTradingCommand?.cancelOrderId != null ||
            state.pendingTradingCommand?.amendRequestId != null ||
            state.pendingTradingCommand?.cancelPlan != null) ...[
          Text(tradingPendingMessage(state.pendingTradingCommand)),
          TextButton(
            onPressed: state.submittingOrder
                ? null
                : state.checkPendingTradingCommand,
            child: Text(tradingRecoveryLabel(state.pendingTradingCommand)),
          ),
        ],
        if (state.isLoggedIn &&
            !(state.privateViews[state.mode]?.ready ?? false))
          const Text('账户同步中 / Syncing account'),
        if (state.isLoggedIn && state.accountRisk != null)
          Panel(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '权益',
                    value: money(
                      unitsToDecimal(state.accountRisk!.equityUnits),
                      digits: 4,
                    ),
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                Expanded(
                  child: MetricPill(
                    label: '维持保证金',
                    value: money(
                      unitsToDecimal(state.accountRisk!.maintenanceMarginUnits),
                      digits: 4,
                    ),
                    color: _amber,
                  ),
                ),
                Expanded(
                  child: MetricPill(
                    label: '保证金率',
                    value: percentageFromPpm(state.accountRisk!.marginRatioPpm),
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
            ),
          ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final entry in [
                '持仓 (${state.positions.length})',
                '当前委托 (${state.openOrders.length})',
                '止盈止损 / 策略 ($botCount)',
                '最近订单更新',
              ].asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: tab == entry.key,
                    onSelected: (_) {
                      setState(() => tab = entry.key);
                      if (entry.key == 0) {
                        unawaited(state.refreshPositionRiskDetails());
                      }
                    },
                  ),
                ),
            ],
          ),
        ),
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('仅当前交易对'),
          value: state.onlyCurrentTradingPair,
          onChanged: (value) => state.setTradingPairFilter(value ?? true),
        ),
        if (tab == 3) ...[
          const Text('本次连接收到的最近 100 条订单更新'),
          if (state.recentOrderUpdates.isEmpty)
            const TradingEmptyState(text: '暂无订单更新'),
          for (final order in state.recentOrderUpdates)
            OrderRow(
              order: order,
              instrument:
                  state.instruments
                      .where(
                        (i) => i.mode == state.mode && i.symbol == order.symbol,
                      )
                      .firstOrNull ??
                  Instrument.empty(state.mode),
              onAmend:
                  !state.mode.isSpot ||
                      state.submittingOrder ||
                      state.tradingCommandPending
                  ? null
                  : () {
                      final instrument = state.instruments
                          .where(
                            (i) =>
                                i.mode == state.mode &&
                                i.symbol == order.symbol,
                          )
                          .firstOrNull;
                      if (instrument != null) {
                        showSpotAmendOrderSheet(
                          context,
                          state,
                          order,
                          instrument,
                        );
                      }
                    },
              onCancel: state.submittingOrder || state.tradingCommandPending
                  ? null
                  : () => state.cancelOrder(order),
            ),
        ],
        if (!state.isLoggedIn)
          TextButton(
            onPressed: () => showAuthSheet(context),
            child: const Text('登录查看持仓与委托'),
          ),
        if (tab == 0) ...[
          if (state.positions.isEmpty)
            const TradingEmptyState(text: '暂无仓位')
          else
            ...state.positions.map(
              (position) => PositionRow(position: position, state: state),
            ),
        ],
        if (tab == 1 && state.mode == ProductMode.spot && state.isLoggedIn) ...[
          OutlinedButton(
            onPressed: state.submittingOrder || state.tradingCommandPending
                ? null
                : () => confirmSpotCancellation(context, state),
            child: Text(
              state.onlyCurrentTradingPair ? '撤销当前交易对委托' : '撤销全部现货委托',
            ),
          ),
          if (state.lastCancellationResult?.userId == state.userId) ...[
            Text(
              '已处理 ${state.lastCancellationResult!.requested} 笔，成功 ${state.lastCancellationResult!.completed} 笔，失败 ${state.lastCancellationResult!.failed} 笔',
            ),
            if (state.lastCancellationResult!.failed > 0)
              TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => AnimatedBuilder(
                    animation: state,
                    builder: (context, _) {
                      final result = state.lastCancellationResult;
                      if (result == null || result.userId != state.userId) {
                        return const SafeArea(child: Text('账户已变化，请关闭此窗口'));
                      }
                      return SafeArea(
                        child: ListView.builder(
                          itemCount: result.failures.length,
                          itemBuilder: (context, i) {
                            final failure = result.failures[i];
                            return ListTile(
                              title: Text('订单 #${failure.orderId}'),
                              subtitle: Text(
                                failure.code == 'ORDER_NOT_FOUND'
                                    ? '订单不存在或已结束'
                                    : failure.code == 'ORDER_OWNER_MISMATCH'
                                    ? '批次包含其他账户订单，未执行该批'
                                    : '撤单未被接受，请查看最新订单状态',
                              ),
                            );
                          },
                        ),
                      );
                    },
                  ),
                ),
                child: const Text('查看失败订单'),
              ),
          ],
        ],
        if (tab == 1 && state.openOrders.isEmpty)
          const TradingEmptyState(text: '暂无委托'),
        if (tab == 1 && state.openOrders.isNotEmpty) ...[
          const SectionTitle(title: '当前委托'),
          ...state.openOrders.map(
            (order) => OrderRow(
              order: order,
              instrument:
                  state.instruments
                      .where(
                        (i) => i.mode == state.mode && i.symbol == order.symbol,
                      )
                      .firstOrNull ??
                  Instrument.empty(state.mode),
              onAmend:
                  !state.mode.isSpot ||
                      state.submittingOrder ||
                      state.tradingCommandPending
                  ? null
                  : () {
                      final instrument = state.instruments
                          .where(
                            (i) =>
                                i.mode == state.mode &&
                                i.symbol == order.symbol,
                          )
                          .firstOrNull;
                      if (instrument != null) {
                        showSpotAmendOrderSheet(
                          context,
                          state,
                          order,
                          instrument,
                        );
                      }
                    },
              onCancel: state.submittingOrder || state.tradingCommandPending
                  ? null
                  : () => state.cancelOrder(order),
            ),
          ),
          if (state.openOrdersHasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton.icon(
                onPressed: state.loadingMoreOpenOrders
                    ? null
                    : state.loadMoreOpenOrders,
                icon: const Icon(Icons.expand_more),
                label: Text(state.loadingMoreOpenOrders ? '加载中...' : '加载更多委托'),
              ),
            ),
        ],
        if (tab == 2 && botCount == 0)
          const TradingEmptyState(text: '暂无止盈止损或策略委托'),
        if (tab == 2 && state.openAlgoOrders.isNotEmpty) ...[
          const SectionTitle(title: '交易机器人'),
          ...state.openAlgoOrders.map(
            (order) => AlgoOrderRow(
              order: order,
              state: state,
              onCancel: () => state.cancelAlgoOrder(order),
            ),
          ),
        ],
        if (tab == 2 && state.openTriggerOrders.isNotEmpty) ...[
          const SectionTitle(title: '止盈止损'),
          ...state.openTriggerOrders.map(
            (order) => TriggerOrderRow(
              order: order,
              state: state,
              onCancel: () => state.cancelTriggerOrder(order),
            ),
          ),
        ],
        if (tab == 0 && state.liquidationOrders.isNotEmpty) ...[
          const SectionTitle(title: '爆仓记录'),
          ...state.liquidationOrders.map(
            (order) => Panel(
              child: InfoLine(
                label: '#${order.orderId} ${order.symbol}',
                value: '${order.status} · ${order.quantitySteps}',
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class TradingPanelTabs extends StatelessWidget {
  const TradingPanelTabs({
    required this.positionCount,
    required this.orderCount,
    required this.botCount,
    super.key,
  });

  final int positionCount;
  final int orderCount;
  final int botCount;

  @override
  Widget build(BuildContext context) {
    final tabs = [
      '持有仓位 ($positionCount)',
      '当前委托 ($orderCount)',
      '交易机器人${botCount > 0 ? ' ($botCount)' : ''}',
    ];
    return Container(
      margin: const EdgeInsets.only(top: 2, bottom: 6),
      padding: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tabs[index],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: index == 0
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: index == 0 ? 24 : 0,
                    height: 2,
                    decoration: BoxDecoration(
                      color: _amber,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ],
              ),
            ),
            if (index != tabs.length - 1) const SizedBox(width: 10),
          ],
          IconButton(
            tooltip: '订单筛选',
            onPressed: () {},
            style: IconButton.styleFrom(
              backgroundColor: Colors.transparent,
              side: BorderSide.none,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
            ),
            constraints: const BoxConstraints.tightFor(width: 32, height: 32),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.document_scanner_outlined, size: 19),
          ),
        ],
      ),
    );
  }
}

class TradingEmptyState extends StatelessWidget {
  const TradingEmptyState({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 112,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.content_paste_search_outlined,
            size: 38,
            color: Theme.of(
              context,
            ).colorScheme.onSurfaceVariant.withValues(alpha: .62),
          ),
          const SizedBox(height: 8),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthSheet extends StatefulWidget {
  const AuthSheet({super.key});
  @override
  State<AuthSheet> createState() => _AuthSheetState();
}

class _AuthSheetState extends State<AuthSheet> {
  final identifier = TextEditingController();
  final password = TextEditingController();
  final code = TextEditingController();
  final codes = <String, String>{};
  String mode = 'login';
  bool phone = false;
  bool busy = false;
  bool showPassword = false;
  String? message;

  @override
  void dispose() {
    identifier.dispose();
    password.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit(AppState state) async {
    if (busy) return;
    final challenge = state.pendingLoginChallenge;
    final needsPassword =
        ['login', 'register', 'reset'].contains(mode) && challenge == null;
    if (challenge == null &&
            mode != 'verify' &&
            identifier.text.trim().isEmpty ||
        needsPassword && password.text.isEmpty ||
        ['verify', 'reset'].contains(mode) && code.text.trim().isEmpty) {
      setState(() => message = '请填写所有必填信息');
      return;
    }
    if (challenge != null &&
        (challenge.expired ||
            challenge.methods.any(
              (m) => !RegExp(
                r'^\d{6}$',
              ).hasMatch(codes[asString(m['type'])] ?? ''),
            ))) {
      setState(
        () => message = challenge.expired ? '验证已过期，请返回登录' : '请输入全部六位验证码',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    var close = false;
    var clearCredentials = false;
    var next = mode;
    if (challenge != null) {
      await state.verifyLogin({
        for (final entry in codes.entries)
          switch (entry.key) {
            'EMAIL' => 'emailCode',
            'PHONE' => 'phoneCode',
            _ => 'totpCode',
          }: entry.value,
      });
      if (state.pendingVerificationSession != null) next = 'verify';
      close = state.isLoggedIn;
    } else if (mode == 'forgot') {
      if (await state.requestPasswordReset(identifier.text)) next = 'reset';
    } else if (mode == 'reset') {
      if (await state.resetPassword(
        identifier: identifier.text,
        code: code.text,
        newPassword: password.text,
      )) {
        next = 'login';
        clearCredentials = true;
      }
    } else if (mode == 'verify') {
      close = await state.verifyPendingEmail(code.text);
    } else {
      if (mode == 'register') {
        await state.register(identifier.text, password.text, phone: phone);
      } else {
        await state.login(identifier.text, password.text);
      }
      if (state.pendingVerificationSession != null) next = 'verify';
      if (state.pendingLoginChallenge != null) clearCredentials = true;
      close = state.isLoggedIn;
    }
    if (!mounted) return;
    if (clearCredentials) {
      password.clear();
      code.clear();
    }
    setState(() {
      busy = false;
      mode = next;
      message = state.lastError ?? state.lastNotice;
    });
    if (close) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final challenge = state.pendingLoginChallenge;
    final title = challenge != null
        ? '安全验证'
        : switch (mode) {
            'register' => '注册账户',
            'forgot' => '找回密码',
            'reset' => '设置新密码',
            'verify' => '验证邮箱',
            _ => '登录账户',
          };
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        8,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Surprising',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 20),
            if (challenge != null) ...[
              const Text('输入所有要求的验证码以完成登录'),
              for (final method in challenge.methods)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    enabled: !busy,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (v) => codes[asString(method['type'])] = v,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      labelText: switch (method['type']) {
                        'EMAIL' => '邮箱验证码',
                        'PHONE' => '短信验证码',
                        _ => '身份验证器验证码',
                      },
                      helperText: nullableString(method['destination']),
                    ),
                  ),
                ),
            ] else ...[
              if (mode == 'register') ...[
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('邮箱')),
                    ButtonSegment(value: true, label: Text('手机号')),
                  ],
                  selected: {phone},
                  onSelectionChanged: busy
                      ? null
                      : (v) => setState(() => phone = v.first),
                ),
                const SizedBox(height: 16),
              ],
              if (mode != 'verify')
                TextField(
                  controller: identifier,
                  enabled: !busy,
                  keyboardType: mode == 'register' && phone
                      ? TextInputType.phone
                      : TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: mode == 'login'
                        ? '邮箱或手机号'
                        : phone && mode == 'register'
                        ? '国际手机号'
                        : '邮箱',
                  ),
                ),
              if (['login', 'register', 'reset'].contains(mode)) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: !showPassword,
                  autofillHints: [
                    mode == 'login'
                        ? AutofillHints.password
                        : AutofillHints.newPassword,
                  ],
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: mode == 'reset' ? '新密码' : '密码',
                    suffixIcon: IconButton(
                      tooltip: showPassword ? '隐藏密码' : '显示密码',
                      onPressed: () =>
                          setState(() => showPassword = !showPassword),
                      icon: Icon(
                        showPassword ? Icons.visibility_off : Icons.visibility,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => submit(state),
                ),
              ],
              if (['verify', 'reset'].contains(mode)) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: code,
                  enabled: !busy,
                  keyboardType: TextInputType.number,
                  autofillHints: const [AutofillHints.oneTimeCode],
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: '邮箱验证码',
                  ),
                ),
              ],
            ],
            if (message != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(message!, key: const ValueKey('auth-message')),
              ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : () => submit(state),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  busy
                      ? '处理中…'
                      : challenge != null
                      ? '确认验证'
                      : switch (mode) {
                          'forgot' => '发送验证码',
                          'reset' => '更新密码',
                          'verify' => '完成邮箱验证',
                          'register' => '创建账户',
                          _ => '登录',
                        },
                ),
              ),
            ),
            if (mode == 'verify')
              TextButton(
                onPressed: busy
                    ? null
                    : () async {
                        setState(() => busy = true);
                        await state.resendPendingEmail();
                        if (mounted) {
                          setState(() {
                            busy = false;
                            message = state.lastError ?? state.lastNotice;
                          });
                        }
                      },
                child: const Text('重新发送验证码'),
              ),
            if (mode == 'login' && challenge == null) ...[
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        mode = 'forgot';
                        message = null;
                        password.clear();
                      }),
                child: const Text('忘记密码？'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        mode = 'register';
                        message = null;
                      }),
                child: const Text('没有账户，去注册'),
              ),
              if (state.pendingBiometricSession != null)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          setState(() => busy = true);
                          final ok = await state.unlockBiometricSession();
                          if (!context.mounted) return;
                          setState(() {
                            busy = false;
                            message = state.lastError;
                          });
                          if (ok) Navigator.pop(context);
                        },
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('使用生物识别登录'),
                ),
            ] else
              TextButton(
                onPressed: busy
                    ? null
                    : () => setState(() {
                        state.pendingLoginChallenge = null;
                        mode = 'login';
                        codes.clear();
                        code.clear();
                        password.clear();
                        message = null;
                      }),
                child: const Text('返回登录'),
              ),
          ],
        ),
      ),
    );
  }
}

void showAuthSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        AppScope(notifier: AppScope.of(context), child: const AuthSheet()),
  );
}

class PageHeader extends StatelessWidget {
  const PageHeader({
    required this.title,
    required this.subtitle,
    this.action,
    this.dense = false,
    super.key,
  });

  final String title;
  final String subtitle;
  final Widget? action;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(0, dense ? 0 : 8, 0, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          ...action == null ? const <Widget>[] : [action!],
        ],
      ),
    );
  }
}

class ExchangeSearchBox extends StatelessWidget {
  const ExchangeSearchBox({required this.hint, super.key});

  final String hint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.search,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 18,
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MarketPrimaryTabs extends StatelessWidget {
  const MarketPrimaryTabs({required this.selectedIndex, super.key});

  final int selectedIndex;

  @override
  Widget build(BuildContext context) {
    const tabs = ['自选', '加密货币', '传统金融', 'Alpha', '金融增长'];
    return SizedBox(
      height: 36,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 18),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                tabs[index],
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Container(
                width: selected ? 20 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: _amber,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class ProductPageSelector extends StatelessWidget {
  const ProductPageSelector({
    required this.value,
    required this.title,
    required this.onChanged,
    this.compact = false,
    super.key,
  });

  final ProductMode value;
  final String title;
  final ValueChanged<ProductMode> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openProductPagePicker(context),
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 42 : 50),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.primary.withValues(alpha: .16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.open_in_new,
                  color: Theme.of(context).colorScheme.primary,
                  size: 17,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      value.label,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProductPagePicker(BuildContext context) async {
    final selected = await showModalBottomSheet<ProductMode>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return ProductPagePickerSheet(current: value);
      },
    );
    if (selected != null && selected != value) {
      onChanged(selected);
    }
  }
}

class ProductPagePickerSheet extends StatelessWidget {
  const ProductPagePickerSheet({required this.current, super.key});

  final ProductMode current;

  @override
  Widget build(BuildContext context) {
    final items = [
      (label: 'U本位永续', detail: 'USDT 保证金永续合约', mode: ProductMode.linear),
      (label: '币本位永续', detail: '币本位保证金永续合约', mode: ProductMode.inverse),
      (label: 'U本位交割', detail: '到期现金交割合约', mode: ProductMode.linearDelivery),
      (label: '币本位交割', detail: '币本位到期交割合约', mode: ProductMode.inverseDelivery),
      (label: '期权', detail: '欧式现金行权期权', mode: ProductMode.option),
      (label: '现货', detail: '资产和资产直接兑换', mode: ProductMode.spot),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '打开产品页',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  side: BorderSide(
                    color: item.mode == current
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outlineVariant,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                tileColor: item.mode == current
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: .14)
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                title: Text(
                  item.label,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                subtitle: Text(
                  item.detail,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                trailing: item.mode == current
                    ? Icon(
                        Icons.check_circle,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : Icon(
                        Icons.chevron_right,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                onTap: () => Navigator.of(context).pop(item.mode),
              ),
            ),
        ],
      ),
    );
  }
}

class CategoryStrip extends StatelessWidget {
  const CategoryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    const values = ['全部', '新币', 'DeFi', '元宇宙', '支付', 'PoW'];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: values.length + 1,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == values.length) {
            return Center(
              child: Icon(
                Icons.format_list_bulleted,
                color: Theme.of(context).colorScheme.onSurface,
                size: 20,
              ),
            );
          }
          final selected = index == 0;
          return Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                values[index],
                style: TextStyle(
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class MarketSortHeader extends StatelessWidget {
  const MarketSortHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(10, 7, 10, 5),
      child: Row(
        children: [
          Expanded(
            flex: 7,
            child: Text(
              '名称↕ / 成交额↕',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              '最新价格↕',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
          SizedBox(width: 7),
          SizedBox(
            width: 78,
            child: Text(
              '24 小时涨跌↕',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class MarketTickerRow extends StatelessWidget {
  const MarketTickerRow({
    required this.instrument,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final Instrument instrument;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final latestPrice = state.latestPriceFor(instrument);
    final change = instrument.change24h;
    final quote = instrument.quoteAsset.isEmpty
        ? instrument.settleAsset
        : instrument.quoteAsset;
    final priceText = latestPrice == null
        ? '--'
        : money(latestPrice, digits: instrument.pricePrecision);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 7, 10, 8),
        color: selected
            ? Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: .28)
            : Colors.transparent,
        child: Row(
          children: [
            Expanded(
              flex: 7,
              child: Row(
                children: [
                  CryptoAvatar(symbol: instrument.baseAsset, size: 28),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                instrument.displayName.replaceAll('-', ''),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (instrument.isDerivative) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outlineVariant,
                                  ),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  instrument.contractLabel,
                                  style: TextStyle(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurface,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${assetDisplayName(instrument.baseAsset)} | ${volumeText(instrument)} $quote',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    priceText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    latestPrice == null
                        ? '--'
                        : '${instrument.quoteAsset} ${money(latestPrice, digits: 2)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Container(
              width: 78,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: change == null
                    ? Theme.of(context).colorScheme.onSurfaceVariant
                    : change >= 0
                    ? Theme.of(context).colorScheme.tertiary
                    : Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(
                change == null
                    ? '--'
                    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TradeSymbolHeader extends StatelessWidget {
  const TradeSymbolHeader({
    required this.instrument,
    required this.latestPrice,
    required this.onRefresh,
    super.key,
  });

  final Instrument instrument;
  final double? latestPrice;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final change = instrument.change24h;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      instrument.displayName.replaceAll('-', ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 5),
                  if (instrument.isDerivative)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        instrument.contractLabel,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                change == null
                    ? '--'
                    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(2)}%',
                style: TextStyle(
                  color: change == null
                      ? Theme.of(context).colorScheme.onSurfaceVariant
                      : change >= 0
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: 'K线',
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.candlestick_chart_outlined, size: 20),
        ),
        IconButton(
          tooltip: '更多',
          onPressed: onRefresh,
          style: IconButton.styleFrom(
            backgroundColor: Colors.transparent,
            side: BorderSide.none,
            foregroundColor: Theme.of(context).colorScheme.onSurface,
          ),
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          padding: EdgeInsets.zero,
          icon: const Icon(Icons.more_horiz, size: 21),
        ),
      ],
    );
  }
}

class ProductLifecyclePanel extends StatelessWidget {
  const ProductLifecyclePanel({
    required this.state,
    required this.instrument,
    required this.latestPrice,
    super.key,
  });

  final AppState state;
  final Instrument instrument;
  final double? latestPrice;

  @override
  Widget build(BuildContext context) {
    final isOption = instrument.isOption;
    final underlying = _underlyingInstrument();
    final underlyingPrice = underlying == null
        ? null
        : state.latestPriceFor(underlying);
    final strike = instrument.strikePrice;
    final intrinsic = _intrinsicValue(instrument, underlyingPrice, strike);
    final chain = _optionChainRows(instrument, state.instruments);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isOption ? Icons.auto_graph : Icons.event_available_outlined,
                size: 18,
                color: _amber,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isOption ? '期权链路' : '交割合约生命周期',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                instrument.mode.productLine,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              LifecycleChip(label: '状态', value: instrument.status),
              LifecycleChip(
                label: '到期',
                value: shortDateTime(instrument.expiryTime),
              ),
              LifecycleChip(
                label: isOption ? '行权' : '交割',
                value: shortDateTime(instrument.deliveryTime),
              ),
              LifecycleChip(
                label: instrument.mode == ProductMode.linearDelivery
                    ? '距到期'
                    : '剩余',
                value: timeLeft(
                  instrument.mode == ProductMode.linearDelivery
                      ? instrument.expiryTime
                      : instrument.deliveryTime ?? instrument.expiryTime,
                ),
              ),
              LifecycleChip(
                label: '结算',
                value: instrument.settlementMethod ?? '--',
              ),
              LifecycleChip(label: '账户', value: instrument.mode.accountType),
            ],
          ),
          if (isOption) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                MetricPill(
                  label: '底层',
                  value: underlyingPrice == null
                      ? instrument.underlyingSymbol ?? '--'
                      : money(
                          underlyingPrice,
                          digits: underlying?.pricePrecision ?? 2,
                        ),
                  color: Theme.of(context).colorScheme.secondary,
                ),
                MetricPill(
                  label: '行权价',
                  value: strike == null
                      ? '--'
                      : money(strike, digits: instrument.pricePrecision),
                  color: _amber,
                ),
                MetricPill(
                  label: '权利金',
                  value: latestPrice == null
                      ? '--'
                      : money(latestPrice!, digits: instrument.pricePrecision),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
                MetricPill(
                  label: '内在价值',
                  value: intrinsic == null
                      ? '--'
                      : money(intrinsic, digits: instrument.pricePrecision),
                  color: intrinsic != null && intrinsic > 0
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                MetricPill(
                  label: 'Delta估算',
                  value: estimatedDelta(instrument, underlyingPrice, strike),
                  color: Theme.of(context).colorScheme.secondary,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (chain.isEmpty)
              Text(
                '暂无同到期期权链',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              )
            else
              Column(
                children: [
                  const InfoLine(label: '期权链', value: '到期 / 行权价 / CALL / PUT'),
                  ...chain
                      .take(6)
                      .map(
                        (row) => InfoLine(
                          label:
                              '${row.expiry} ${money(row.strike, digits: instrument.pricePrecision)}',
                          value: '${row.call ?? '-'} / ${row.put ?? '-'}',
                        ),
                      ),
                ],
              ),
          ] else ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: MetricPill(
                    label: '方向',
                    value: instrument.mode == ProductMode.inverseDelivery
                        ? '币本位反向'
                        : 'U本位正向',
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MetricPill(
                    label: '结算资产',
                    value: instrument.settleAsset,
                    color: _amber,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: MetricPill(
                    label: '最大杠杆',
                    value: '${(instrument.maxLeveragePpm / 1000000).round()}x',
                    color: Theme.of(context).colorScheme.tertiary,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Instrument? _underlyingInstrument() {
    final target = instrument.underlyingSymbol;
    if (target == null || target.isEmpty) return null;
    for (final item in state.instruments) {
      if (item.symbol == target) return item;
    }
    return null;
  }
}

class LifecycleChip extends StatelessWidget {
  const LifecycleChip({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 96, maxWidth: 168),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 9,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class ContractQuickSettings extends StatelessWidget {
  const ContractQuickSettings({
    required this.marginMode,
    required this.leverage,
    required this.positionMode,
    required this.onMarginMode,
    required this.onPositionMode,
    super.key,
  });

  final String marginMode;
  final String leverage;
  final String positionMode;
  final ValueChanged<String> onMarginMode;
  final ValueChanged<String> onPositionMode;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TradeSettingButton(
            label: marginMode == 'ISOLATED' ? '逐仓' : '全仓',
            onTap: () =>
                onMarginMode(marginMode == 'ISOLATED' ? 'CROSS' : 'ISOLATED'),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: TradeSettingButton(
            label: '杠杆',
            onTap: () {
              final state = AppScope.of(context);
              if (!state.isLoggedIn) {
                showAuthSheet(context);
                return;
              }
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                builder: (_) => TradingLeverageSheet(
                  state: state,
                  instrument: state.selectedInstrument,
                  marginMode: marginMode,
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: TradeSettingButton(
            label: positionMode == 'HEDGE' ? '双' : '单',
            onTap: () =>
                onPositionMode(positionMode == 'HEDGE' ? 'ONE_WAY' : 'HEDGE'),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          flex: 4,
          child: Text(
            _fundingLabel(AppScope.of(context)),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 9.5,
              height: 1.12,
            ),
          ),
        ),
      ],
    );
  }
}

class TradeSettingButton extends StatelessWidget {
  const TradeSettingButton({
    required this.label,
    required this.onTap,
    super.key,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class AssetPortfolioCard extends StatelessWidget {
  const AssetPortfolioCard({
    required this.icon,
    required this.title,
    required this.amount,
    super.key,
  });

  final IconData icon;
  final String title;
  final String amount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF171717),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: const BoxDecoration(
              color: Color(0xFF2A2A2A),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.onSurface,
              size: 16,
            ),
          ),
          const Spacer(),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            amount,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class AssetSparkline extends StatelessWidget {
  const AssetSparkline({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _AssetSparklinePainter());
  }
}

class _AssetSparklinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final points = <Offset>[
      Offset(0, size.height * .62),
      Offset(size.width * .10, size.height * .48),
      Offset(size.width * .20, size.height * .54),
      Offset(size.width * .32, size.height * .40),
      Offset(size.width * .45, size.height * .45),
      Offset(size.width * .57, size.height * .30),
      Offset(size.width * .70, size.height * .50),
      Offset(size.width * .82, size.height * .42),
      Offset(size.width, size.height * .78),
    ];
    final line = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      line.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(line)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [_red.withValues(alpha: .35), _red.withValues(alpha: 0)],
      ).createShader(Offset.zero & size);
    canvas.drawPath(fill, fillPaint);

    final dotPaint = Paint()
      ..color = _red.withValues(alpha: .45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = .9;
    for (var x = 4.0; x < size.width; x += 8) {
      for (var y = size.height * .42; y < size.height; y += 8) {
        canvas.drawCircle(Offset(x, y), 1, dotPaint);
      }
    }

    final linePaint = Paint()
      ..color = _red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(line, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

String formatValuation(double? value, ValuationCurrency currency) {
  if (value == null || !value.isFinite) return '—';
  return '${currency.symbol}${money(value, digits: 2)}';
}

class WalletTokenRow extends StatelessWidget {
  const WalletTokenRow({
    required this.asset,
    required this.priceUsdt,
    required this.currency,
    required this.valuationRate,
    super.key,
  });

  final WalletAssetSummary asset;
  final double? priceUsdt;
  final ValuationCurrency currency;
  final double? valuationRate;

  @override
  Widget build(BuildContext context) {
    final value = priceUsdt == null || valuationRate == null
        ? null
        : asset.totalBalance * priceUsdt! * valuationRate!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          CryptoAvatar(symbol: asset.symbol, size: 36),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        asset.symbol,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  money(asset.totalBalance, digits: 8),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                formatValuation(value, currency),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value == null ? '暂无实时估值' : '现货账户余额',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class Panel extends StatelessWidget {
  const Panel({
    required this.child,
    this.padding = const EdgeInsets.all(10),
    super.key,
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: padding,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.dividerColor.withValues(alpha: .82)),
      ),
      child: child,
    );
  }
}

class GradientPanel extends StatelessWidget {
  const GradientPanel({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final surfaceVariant = theme.colorScheme.surfaceContainerHighest;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: LinearGradient(
          colors: [
            surface,
            surfaceVariant,
            theme.colorScheme.secondary.withValues(alpha: .22),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: theme.dividerColor),
      ),
      child: child,
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({required this.title, this.action, super.key});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 6),
      child: Row(
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const Spacer(),
          ...action == null ? const <Widget>[] : [action!],
        ],
      ),
    );
  }
}

class ModeSelector extends StatelessWidget {
  const ModeSelector({required this.value, required this.onChanged, super.key});

  final ProductMode value;
  final ValueChanged<ProductMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ProductMode>(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.primary.withValues(alpha: .20)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
        ),
      ),
      segments: ProductMode.values
          .map((mode) => ButtonSegment(value: mode, label: Text(mode.label)))
          .toList(),
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class PositionModeSelector extends StatelessWidget {
  const PositionModeSelector({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.secondary.withValues(alpha: .18)
              : Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Theme.of(context).colorScheme.onSurface
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? Theme.of(context).colorScheme.secondary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        textStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      ),
      segments: const [
        ButtonSegment(value: 'ONE_WAY', label: Text('净仓')),
        ButtonSegment(value: 'HEDGE', label: Text('双向持仓')),
      ],
      selected: {value == 'HEDGE' ? 'HEDGE' : 'ONE_WAY'},
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}

class SymbolStrip extends StatelessWidget {
  const SymbolStrip({
    required this.instruments,
    required this.selected,
    required this.onSelected,
    super.key,
  });

  final List<Instrument> instruments;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: instruments.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final item = instruments[index];
          return ChoiceChip(
            selected: item.symbol == selected,
            selectedColor: Theme.of(
              context,
            ).colorScheme.primary.withValues(alpha: .20),
            backgroundColor: Theme.of(
              context,
            ).colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: item.symbol == selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            labelStyle: TextStyle(
              color: item.symbol == selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
            label: Text(item.displayName),
            onSelected: (_) => onSelected(item.symbol),
          );
        },
      ),
    );
  }
}

class BuySellSwitch extends StatelessWidget {
  const BuySellSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(36),
              backgroundColor: value == 'BUY'
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .86),
              foregroundColor: value == 'BUY'
                  ? Colors.white
                  : Theme.of(context).colorScheme.tertiary,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(left: Radius.circular(8)),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => onChanged('BUY'),
            child: const Text('买入'),
          ),
        ),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(36),
              backgroundColor: value == 'SELL'
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: .86),
              foregroundColor: value == 'SELL'
                  ? Colors.white
                  : Theme.of(context).colorScheme.error,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.horizontal(
                  right: Radius.circular(8),
                ),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: () => onChanged('SELL'),
            child: const Text('卖出'),
          ),
        ),
      ],
    );
  }
}

class TradeNumericField extends StatelessWidget {
  const TradeNumericField({
    required this.controller,
    required this.label,
    required this.onMinus,
    required this.onPlus,
    this.suffixLabel,
    this.enabled = true,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final String? suffixLabel;
  final bool enabled;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: TextField(
        controller: controller,
        enabled: enabled,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 4,
            vertical: 6,
          ),
          prefixIcon: IconButton(
            tooltip: '减少',
            onPressed: enabled ? onMinus : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 28, height: 28),
            icon: const Icon(Icons.remove, size: 16),
          ),
          suffixIcon: SizedBox(
            width: suffixLabel == null ? 28 : 58,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (suffixLabel != null)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 2),
                      child: Text(
                        suffixLabel!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                IconButton(
                  tooltip: '增加',
                  onPressed: enabled ? onPlus : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 24,
                    height: 28,
                  ),
                  icon: const Icon(Icons.add, size: 16),
                ),
              ],
            ),
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: .55),
            ),
          ),
        ),
      ),
    );
  }
}

class BestPriceButton extends StatelessWidget {
  const BestPriceButton({
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 58,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled
              ? Theme.of(context).colorScheme.surfaceContainerHighest
              : Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Text(
          enabled ? '最优价' : '市价',
          style: TextStyle(
            color: enabled
                ? Theme.of(context).colorScheme.onSurface
                : Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class OrderMetaRow extends StatelessWidget {
  const OrderMetaRow({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class OrderAmountSlider extends StatelessWidget {
  const OrderAmountSlider({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 8,
            right: 8,
            child: Container(
              height: 3,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(5, (index) {
              return Transform.rotate(
                angle: math.pi / 4,
                child: Container(
                  width: index == 0 ? 14 : 10,
                  height: index == 0 ? 14 : 10,
                  decoration: BoxDecoration(
                    color: index == 0
                        ? Theme.of(context).colorScheme.surface
                        : Theme.of(context).colorScheme.surface,
                    border: Border.all(
                      color: index == 0
                          ? Theme.of(context).colorScheme.onSurface
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: 1.5,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class SmallDropdown extends StatelessWidget {
  const SmallDropdown({
    required this.value,
    required this.values,
    required this.onChanged,
    this.labelBuilder,
    this.enabled = true,
    super.key,
  });

  final String value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final String Function(String value)? labelBuilder;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: Theme.of(context).colorScheme.surface,
          iconEnabledColor: Theme.of(context).colorScheme.onSurfaceVariant,
          style: TextStyle(
            fontSize: 10.5,
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w500,
          ),
          items: values
              .map(
                (item) => DropdownMenuItem(
                  value: item,
                  child: Text(
                    labelBuilder == null ? item : labelBuilder!(item),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: enabled
              ? (next) {
                  if (next != null) onChanged(next);
                }
              : null,
        ),
      ),
    );
  }
}

class AppTextField extends StatelessWidget {
  const AppTextField({
    this.controller,
    this.initialValue,
    required this.label,
    this.enabled = true,
    this.obscure = false,
    this.readOnly = false,
    this.onChanged,
    super.key,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String label;
  final bool enabled;
  final bool obscure;
  final bool readOnly;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      initialValue: controller == null ? initialValue : null,
      enabled: enabled,
      obscureText: obscure,
      readOnly: readOnly,
      onChanged: onChanged,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurface,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 11,
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        filled: true,
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .55),
          ),
        ),
      ),
      keyboardType: obscure
          ? TextInputType.text
          : const TextInputType.numberWithOptions(decimal: true),
    );
  }
}

class ToggleLine extends StatelessWidget {
  const ToggleLine({
    required this.label,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    super.key,
  });

  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? () => onChanged(!value) : null,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          Checkbox(
            value: value,
            onChanged: enabled ? (next) => onChanged(next ?? false) : null,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                color: enabled
                    ? Theme.of(context).colorScheme.onSurface
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BookLine extends StatelessWidget {
  const BookLine({
    required this.level,
    required this.maxQuantity,
    required this.instrument,
    required this.color,
    required this.onTap,
    super.key,
  });

  final OrderBookLevel level;
  final int maxQuantity;
  final Instrument instrument;
  final Color color;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final price = instrument.isSpot
        ? scaledAmount(
            BigInt.from(level.priceTicks) *
                BigInt.from(instrument.priceTickUnits),
            instrument.quoteScaleUnits,
          )
        : money(
            instrument.priceFromTicks(level.priceTicks),
            digits: instrument.pricePrecision,
          );
    final depth = maxQuantity <= 0
        ? 0.0
        : (level.quantitySteps / maxQuantity).clamp(0.0, 1.0);
    return InkWell(
      onTap: price == '--' ? null : () => onTap(price),
      child: SizedBox(
        height: 20,
        child: Stack(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: depth,
                child: Container(color: color.withValues(alpha: .14)),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    price,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                    ),
                  ),
                ),
                Text(
                  instrument.isSpot
                      ? scaledAmount(
                          BigInt.from(level.quantitySteps) *
                              BigInt.from(instrument.quantityStepUnits),
                          instrument.baseScaleUnits,
                        )
                      : compactInt(level.quantitySteps),
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class InstrumentRow extends StatelessWidget {
  const InstrumentRow({
    required this.instrument,
    this.selected = false,
    this.onTap,
    super.key,
  });

  final Instrument instrument;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final latestPrice = AppScope.of(context).latestPriceFor(instrument);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(
                instrument.baseAsset.isEmpty
                    ? '?'
                    : instrument.baseAsset.substring(0, 1),
                style: TextStyle(
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    instrument.displayName,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${instrument.mode.label} · ${instrument.status} · ${(instrument.maxLeveragePpm / 1000000).round()}X',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            MetricPill(
              label: '最新',
              value: latestPrice == null
                  ? '--'
                  : money(latestPrice, digits: instrument.pricePrecision),
              color: Theme.of(context).colorScheme.tertiary,
            ),
          ],
        ),
      ),
    );
  }
}

class BalanceRow extends StatelessWidget {
  const BalanceRow({required this.balance, super.key});

  final ProductBalance balance;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        children: [
          InfoLine(
            label: '${balance.accountType} · ${balance.asset}',
            value: money(balance.equity, digits: 4),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '可用',
                  value: money(balance.available, digits: 4),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '冻结',
                  value: money(balance.locked, digits: 4),
                  color: _amber,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class DepositAddressCard extends StatelessWidget {
  const DepositAddressCard({required this.address, super.key});

  final WalletDepositAddress address;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _QrImage(dataUrl: address.qrCodeDataUrl),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${address.chain} · ${address.symbol}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      address.address,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (address.memo.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      InfoLine(label: 'Memo', value: address.memo),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (address.warnings.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (final warning in address.warnings.take(3))
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  warning,
                  style: const TextStyle(color: _amber, fontSize: 11),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _QrImage extends StatelessWidget {
  const _QrImage({required this.dataUrl, this.size = 96});

  final String dataUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (!dataUrl.startsWith('data:image') || !dataUrl.contains(',')) {
      return _placeholder();
    }
    try {
      final bytes = base64Decode(dataUrl.split(',').last);
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    } catch (_) {
      return _placeholder();
    }
  }

  Widget _placeholder() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: CustomPaint(
        size: Size.square(size),
        painter: _QrPlaceholderPainter(),
      ),
    );
  }
}

class _QrPlaceholderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final background = Paint()..color = Colors.white;
    canvas.drawRect(Offset.zero & size, background);

    final module = size.width / 29;
    final black = Paint()..color = Colors.black;
    final quiet = module * 1.2;

    void drawModule(int x, int y) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            quiet + x * module,
            quiet + y * module,
            module * .72,
            module * .72,
          ),
          Radius.circular(module * .36),
        ),
        black,
      );
    }

    void finder(int x, int y) {
      final left = quiet + x * module;
      final top = quiet + y * module;
      canvas.drawCircle(
        Offset(left + module * 3, top + module * 3),
        module * 3,
        black,
      );
      canvas.drawCircle(
        Offset(left + module * 3, top + module * 3),
        module * 2,
        background,
      );
      canvas.drawCircle(
        Offset(left + module * 3, top + module * 3),
        module * 1.2,
        black,
      );
    }

    finder(1, 1);
    finder(21, 1);
    finder(1, 21);

    for (var y = 0; y < 27; y++) {
      for (var x = 0; x < 27; x++) {
        final inTopLeft = x < 8 && y < 8;
        final inTopRight = x > 18 && y < 8;
        final inBottomLeft = x < 8 && y > 18;
        if (inTopLeft || inTopRight || inBottomLeft) continue;
        final seed = (x * 17 + y * 31 + x * y * 7) % 11;
        if (seed == 0 || seed == 3 || seed == 7) drawModule(x, y);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class WalletAssetRow extends StatelessWidget {
  const WalletAssetRow({required this.asset, super.key});

  final WalletAssetSummary asset;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                asset.symbol,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Text(
                money(asset.totalBalance, digits: 8),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: MetricPill(
                  label: '可用',
                  value: money(asset.availableBalance, digits: 8),
                  color: Theme.of(context).colorScheme.tertiary,
                ),
              ),
              Expanded(
                child: MetricPill(
                  label: '冻结',
                  value: money(asset.lockedBalance, digits: 8),
                  color: _amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final chain in asset.chains)
                Chip(
                  label: Text(
                    '${chain.chain} ${money(chain.totalBalance, digits: 6)}',
                  ),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class WalletOrderRecordRow extends StatelessWidget {
  const WalletOrderRecordRow({required this.record, super.key});

  final WalletOrderRecord record;

  @override
  Widget build(BuildContext context) {
    final isOut =
        record.type.contains('WITHDRAW') || record.type.contains('OUT');
    return Panel(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: isOut
                ? Theme.of(context).colorScheme.error.withValues(alpha: 0.12)
                : Theme.of(
                    context,
                  ).colorScheme.tertiary.withValues(alpha: 0.12),
            child: Icon(
              isOut ? Icons.call_made : Icons.call_received,
              color: isOut
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.tertiary,
              size: 18,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${record.type} · ${record.chain}/${record.symbol}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '${record.status} · ${record.refNo}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (record.errorMessage.isNotEmpty)
                  Text(
                    record.errorMessage,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isOut ? '-' : '+'}${money(record.amount, digits: 8)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isOut
                      ? Theme.of(context).colorScheme.error
                      : Theme.of(context).colorScheme.tertiary,
                ),
              ),
              if (record.fee > 0)
                Text(
                  'fee ${money(record.fee, digits: 8)}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

String tradingQuantity(Instrument instrument, int steps) => instrument.isSpot
    ? '${scaledAmount(BigInt.from(steps) * BigInt.from(instrument.quantityStepUnits), instrument.baseScaleUnits)} ${instrument.baseAsset}'
    : '$steps 张';

String tradingAmount(Object? units, Instrument instrument, [String? asset]) {
  final amount = units == null ? null : BigInt.tryParse('$units');
  final text = scaledAmount(
    amount,
    instrument.isSpot
        ? instrument.quoteScaleUnits
        : instrument.settleScaleUnits ?? 100000000,
  );
  return text == '--'
      ? text
      : '$text ${asset == null || asset.isEmpty ? instrument.settleAsset : asset}';
}

String tradingTime(DateTime? time) => time == null
    ? '--'
    : time.toLocal().toIso8601String().substring(0, 19).replaceFirst('T', ' ');
String tradingStatus(OrderModel order) {
  final status = order.status == 'OPEN'
      ? (order.executedQuantitySteps > 0 ? 'PARTIALLY_FILLED' : 'NEW')
      : order.status;
  return const {
        'NEW': '未成交',
        'ACCEPTED': '未成交',
        'PARTIALLY_FILLED': '部分成交',
        'FILLED': '已成交',
        'CANCELED': '已撤销',
        'CANCELLED': '已撤销',
        'REJECTED': '已拒绝',
        'CANCEL_REQUESTED': '撤销中',
        'PENDING_RESERVE': '处理中',
      }[status] ??
      status;
}

class TradingDetails extends StatelessWidget {
  const TradingDetails({required this.values, super.key});
  final Map<String, String> values;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      spacing: 12,
      runSpacing: 10,
      children: [
        for (final entry in values.entries)
          SizedBox(
            width: (constraints.maxWidth - 12) / 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  entry.value,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class OrderRow extends StatelessWidget {
  const OrderRow({
    required this.order,
    required this.instrument,
    required this.onCancel,
    this.onAmend,
    super.key,
  });
  final OrderModel order;
  final Instrument instrument;
  final VoidCallback? onCancel;
  final VoidCallback? onAmend;
  @override
  Widget build(BuildContext context) {
    final average = double.tryParse(order.averagePriceTicks ?? '');
    final priceScale = instrument.isSpot
        ? instrument.quoteScaleUnits
        : 100000000;
    final multiplier = instrument.notionalMultiplierUnits;
    final linear =
        instrument.mode == ProductMode.linear ||
        instrument.mode == ProductMode.linearDelivery;
    final executed = BigInt.tryParse(order.executedValueTicks ?? '');
    final canCancel = [
      'OPEN',
      'NEW',
      'ACCEPTED',
      'PARTIALLY_FILLED',
      'PENDING_RESERVE',
    ].contains(order.status);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${order.side == 'BUY' ? '买入' : '卖出'} ${order.symbol}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: order.side == 'BUY'
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
              if (canCancel &&
                  order.orderType == 'LIMIT' &&
                  order.status != 'PENDING_RESERVE' &&
                  onAmend != null)
                TextButton(onPressed: onAmend, child: const Text('改单')),
              if (canCancel && onCancel != null)
                TextButton(onPressed: onCancel, child: const Text('撤单')),
            ],
          ),
          Text(
            '${order.orderType} · ${order.marginMode == 'ISOLATED' ? '逐仓' : '全仓'} · ${positionSideLabel(order.positionSide)} · ${tradingStatus(order)}',
          ),
          const SizedBox(height: 10),
          TradingDetails(
            values: {
              '委托价格': order.orderType == 'MARKET'
                  ? '市价'
                  : money(
                      instrument.priceFromTicks(order.priceTicks),
                      digits: instrument.pricePrecision,
                    ),
              '成交均价':
                  average == null ||
                      !average.isFinite ||
                      priceScale == null ||
                      priceScale <= 0
                  ? '--'
                  : money(
                      average * instrument.priceTickUnits / priceScale,
                      digits: instrument.pricePrecision,
                    ),
              '委托数量': tradingQuantity(instrument, order.quantitySteps),
              '已成交数量': tradingQuantity(instrument, order.executedQuantitySteps),
              '剩余数量': tradingQuantity(instrument, order.remainingQuantitySteps),
              '成交进度': order.fillProgress,
              '委托价值':
                  !linear || multiplier == null || order.orderType == 'MARKET'
                  ? '--'
                  : tradingAmount(
                      BigInt.from(order.priceTicks) *
                          BigInt.from(order.quantitySteps) *
                          BigInt.from(multiplier),
                      instrument,
                    ),
              '成交价值': !linear || multiplier == null || executed == null
                  ? '--'
                  : tradingAmount(
                      executed * BigInt.from(multiplier),
                      instrument,
                    ),
              '累计手续费': tradingAmount(order.cumulativeFeeUnits, instrument),
              '结算币种': instrument.settleAsset,
              '只减仓 / 只做 Maker':
                  '${order.reduceOnly ? '是' : '否'} / ${order.postOnly ? '是' : '否'}',
              '有效方式': order.timeInForce,
              '委托时间': tradingTime(order.createdAt),
              '更新时间': tradingTime(order.updatedAt),
              '订单编号': '${order.orderId}',
            },
          ),
        ],
      ),
    );
  }
}

class AlgoOrderRow extends StatelessWidget {
  const AlgoOrderRow({
    required this.order,
    required this.state,
    required this.onCancel,
    super.key,
  });

  final AlgoOrderModel order;
  final AppState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final instrument = state.instruments.firstWhere(
      (item) => item.mode == state.mode && item.symbol == order.symbol,
      orElse: () => state.selectedInstrument,
    );
    final priceText = order.priceTicks > 0
        ? money(
            instrument.priceFromTicks(order.priceTicks),
            digits: instrument.pricePrecision,
          )
        : 'MARKET';
    final progress = order.executedQuantitySteps + order.activeQuantitySteps;
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${algoTypeLabel(order.algoType)} ${order.side} ${order.symbol}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: order.side == 'BUY'
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                Text(
                  '${order.marginMode} ${positionSideLabel(order.positionSide)} · ${order.timeInForce} · ${order.status}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '价 $priceText · 进度 $progress/${order.quantitySteps} · 切片 ${order.childQuantitySteps}/${order.intervalSeconds}s',
                  style: const TextStyle(fontSize: 12),
                ),
                if (order.rejectReason != null &&
                    order.rejectReason!.isNotEmpty)
                  Text(
                    order.rejectReason!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class TriggerOrderRow extends StatelessWidget {
  const TriggerOrderRow({
    required this.order,
    required this.state,
    required this.onCancel,
    super.key,
  });

  final TriggerOrderModel order;
  final AppState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final instrument = state.instruments.firstWhere(
      (item) => item.mode == state.mode && item.symbol == order.symbol,
      orElse: () => state.selectedInstrument,
    );
    final isTakeProfit = order.triggerType == 'TAKE_PROFIT';
    final triggerText = order.triggerType == 'TRAILING_STOP'
        ? '激活 ${order.activationPriceTicks == null ? '立即' : money(instrument.priceFromTicks(order.activationPriceTicks!), digits: instrument.pricePrecision)} / 回调 ${((order.callbackRatePpm ?? 0) / 10000).toStringAsFixed(2)}%'
        : '触发 ${money(instrument.priceFromTicks(order.triggerPriceTicks), digits: instrument.pricePrecision)}';
    return Panel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${triggerTypeLabel(order.triggerType)} ${order.symbol}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isTakeProfit
                        ? Theme.of(context).colorScheme.tertiary
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                Text(
                  '${triggerCloseLabel(order.side, order.positionSide)} · ${order.marginMode} ${positionSideLabel(order.positionSide)} · ${order.status}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                Text(
                  '$triggerText · 量 ${order.quantitySteps}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onCancel,
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }
}

class PositionRow extends StatelessWidget {
  const PositionRow({required this.position, required this.state, super.key});
  final Position position;
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final instrument =
        state.instruments
            .where((i) => i.mode == state.mode && i.symbol == position.symbol)
            .firstOrNull ??
        Instrument.empty(state.mode);
    final view = state.privateViews[state.mode];
    final risk = view?.ready == true
        ? state.positionRisks
              .where(
                (r) =>
                    r.symbol == position.symbol &&
                    r.positionSide == position.positionSide,
              )
              .firstOrNull
        : null;
    final queriedRisk = state.queriedPositionRisks
        .where(
          (r) =>
              r.symbol == position.symbol &&
              r.positionSide == position.positionSide,
        )
        .firstOrNull;
    final leverage = view
        ?.rows('leverage')
        .where(
          (r) =>
              (r['instrumentId'] == instrument.instrumentId ||
                  r['symbol'] == instrument.symbol) &&
              r['marginMode'] == position.marginMode,
        )
        .firstOrNull;
    final mark = state.markTicksFor(instrument);
    final pnl = state.unrealizedPnlFor(position) ?? risk?.unrealizedPnlUnits;
    final triggers =
        view
            ?.rows('trigger')
            .where(
              (r) =>
                  r['symbol'] == position.symbol &&
                  r['positionSide'] == position.positionSide,
            )
            .toList() ??
        [];
    String price(int? ticks) =>
        ticks == null || ticks <= 0 || instrument.symbol.isEmpty
        ? '--'
        : money(
            instrument.priceFromTicks(ticks),
            digits: instrument.pricePrecision,
          );
    final asset = position.marginAsset.isEmpty
        ? instrument.settleAsset
        : position.marginAsset;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '${position.symbol} ${position.isLong ? '多' : '空'}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: position.isLong
                      ? Theme.of(context).colorScheme.tertiary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
              Chip(
                label: Text(
                  '${position.marginMode == 'ISOLATED' ? '逐仓' : '全仓'} · ${positionSideLabel(position.positionSide)}',
                ),
                visualDensity: VisualDensity.compact,
              ),
              TextButton.icon(
                onPressed: () => unawaited(state.closePosition(position)),
                icon: const Icon(Icons.logout, size: 16),
                label: const Text('平仓'),
              ),
            ],
          ),
          TradingDetails(
            values: {
              '持仓数量': tradingQuantity(
                instrument,
                position.signedQuantitySteps.abs(),
              ),
              '杠杆': leverage == null
                  ? '--'
                  : '${asInt(leverage['leveragePpm']) / 1000000}×',
              '开仓均价': price(position.entryPriceTicks),
              '标记价格': price(mark),
              '未实现盈亏': tradingAmount(pnl, instrument, asset),
              '已实现盈亏': tradingAmount(
                position.realizedPnlUnits,
                instrument,
                asset,
              ),
              '持仓保证金': tradingAmount(
                position.positionMarginUnits,
                instrument,
                asset,
              ),
              '维持保证金': tradingAmount(
                risk?.maintenanceMarginUnits,
                instrument,
                asset,
              ),
              '保证金率': risk?.marginRatioPpm == null
                  ? '--'
                  : percentageFromPpm(risk!.marginRatioPpm!),
              '强平价格（快照）': price(queriedRisk?.liquidationPriceTicks),
              '风险状态': risk?.status ?? '风险数据同步中',
              '止盈止损': view?.ready != true
                  ? '同步中'
                  : triggers.isEmpty
                  ? '未设置'
                  : triggers
                        .map(
                          (r) =>
                              '${triggerTypeLabel(asString(r['triggerType']))} ${price(asNullableInt(r['triggerPriceTicks']))}',
                        )
                        .join(' / '),
            },
          ),
        ],
      ),
    );
  }
}

class CryptoAvatar extends StatelessWidget {
  const CryptoAvatar({required this.symbol, required this.size, super.key});

  final String symbol;
  final double size;

  @override
  Widget build(BuildContext context) {
    final upper = symbol.toUpperCase();
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _CryptoAvatarPainter(upper)),
    );
  }
}

class _CryptoAvatarPainter extends CustomPainter {
  const _CryptoAvatarPainter(this.symbol);

  final String symbol;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final background = Paint()..color = assetColor(symbol);
    canvas.drawCircle(center, size.width / 2, background);

    switch (symbol) {
      case 'BTC':
        _drawText(canvas, size, 'B', Colors.white, .58, FontWeight.w900);
        _drawStroke(canvas, size, Colors.white.withValues(alpha: .9));
      case 'ETH':
        _drawEth(canvas, size);
      case 'USDT':
        _drawStable(canvas, size, 'T');
      case 'USDC':
        _drawStable(canvas, size, r'$');
      case 'USDG':
        _drawText(canvas, size, 'G', Colors.white, .58, FontWeight.w900);
      case 'SPEX':
      case 'SURPRISING CHAIN':
        _drawPlatformTokenMark(canvas, size);
      case 'SOL':
        _drawSol(canvas, size);
      case 'TRX':
        _drawTriangleMark(canvas, size, Colors.white);
      case 'XAU':
      case 'XAUT':
        _drawGold(canvas, size);
      case 'APT':
      case 'APTOS':
        _drawAptos(canvas, size);
      case 'ARB':
      case 'ARBITRUM':
        _drawHex(canvas, size);
      case 'AVAX':
      case 'AVALANCHE':
        _drawAvax(canvas, size);
      case 'BERA':
      case 'BERACHAIN':
        _drawText(
          canvas,
          size,
          'B',
          const Color(0xFF111111),
          .54,
          FontWeight.w900,
        );
      default:
        final label = symbol.isEmpty ? '?' : symbol.substring(0, 1);
        _drawText(canvas, size, label, _ink, .52, FontWeight.w800);
    }
  }

  void _drawText(
    Canvas canvas,
    Size size,
    String text,
    Color color,
    double scale,
    FontWeight weight,
  ) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: size.width * scale,
          fontWeight: weight,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        (size.width - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  void _drawStroke(Canvas canvas, Size size, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * .035
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(size.width * .38, size.height * .24),
      Offset(size.width * .38, size.height * .76),
      paint,
    );
    canvas.drawLine(
      Offset(size.width * .58, size.height * .24),
      Offset(size.width * .58, size.height * .76),
      paint,
    );
  }

  void _drawEth(Canvas canvas, Size size) {
    final white = Paint()..color = Colors.white;
    final faint = Paint()..color = Colors.white.withValues(alpha: .65);
    final top = Path()
      ..moveTo(size.width * .50, size.height * .16)
      ..lineTo(size.width * .28, size.height * .52)
      ..lineTo(size.width * .50, size.height * .43)
      ..lineTo(size.width * .72, size.height * .52)
      ..close();
    final bottom = Path()
      ..moveTo(size.width * .50, size.height * .48)
      ..lineTo(size.width * .28, size.height * .57)
      ..lineTo(size.width * .50, size.height * .84)
      ..lineTo(size.width * .72, size.height * .57)
      ..close();
    canvas.drawPath(top, white);
    canvas.drawPath(bottom, faint);
  }

  void _drawStable(Canvas canvas, Size size, String label) {
    final white = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * .06;
    canvas.drawCircle(size.center(Offset.zero), size.width * .30, white);
    _drawText(canvas, size, label, Colors.white, .46, FontWeight.w900);
  }

  void _drawPlatformTokenMark(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final unit = size.width * .18;
    final start = Offset(size.width * .22, size.height * .22);
    for (var row = 0; row < 2; row++) {
      for (var col = 0; col < 2; col++) {
        canvas.drawRect(
          Rect.fromLTWH(
            start.dx + col * unit,
            start.dy + row * unit,
            unit * .82,
            unit * .82,
          ),
          paint,
        );
      }
    }
    canvas.drawRect(
      Rect.fromLTWH(
        size.width * .56,
        size.height * .56,
        unit * .82,
        unit * .82,
      ),
      paint,
    );
  }

  void _drawSol(Canvas canvas, Size size) {
    final colors = [
      const Color(0xFF14F195),
      const Color(0xFF80ECFF),
      const Color(0xFFDC1FFF),
    ];
    for (var i = 0; i < 3; i++) {
      final paint = Paint()..color = colors[i];
      final top = size.height * (.28 + i * .18);
      final path = Path()
        ..moveTo(size.width * .24, top)
        ..lineTo(size.width * .76, top)
        ..lineTo(size.width * .66, top + size.height * .10)
        ..lineTo(size.width * .14, top + size.height * .10)
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  void _drawTriangleMark(Canvas canvas, Size size, Color color) {
    final stroke = Paint()
      ..color = color
      ..strokeWidth = size.width * .06
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * .28, size.height * .20)
      ..lineTo(size.width * .76, size.height * .38)
      ..lineTo(size.width * .42, size.height * .78)
      ..close();
    canvas.drawPath(path, stroke);
  }

  void _drawGold(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * .055
      ..style = PaintingStyle.stroke;
    for (final center in [
      Offset(size.width * .36, size.height * .40),
      Offset(size.width * .58, size.height * .40),
      Offset(size.width * .47, size.height * .62),
    ]) {
      canvas.drawCircle(center, size.width * .095, stroke);
    }
  }

  void _drawAptos(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = size.width * .07
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final y = size.height * (.32 + i * .12);
      canvas.drawLine(
        Offset(size.width * .22, y),
        Offset(size.width * .78, y),
        paint,
      );
    }
  }

  void _drawHex(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF8CC8FF)
      ..strokeWidth = size.width * .07
      ..style = PaintingStyle.stroke;
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final angle = -math.pi / 2 + i * math.pi / 3;
      final point =
          size.center(Offset.zero) +
          Offset(math.cos(angle), math.sin(angle)) * size.width * .32;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, stroke);
  }

  void _drawAvax(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white;
    final path = Path()
      ..moveTo(size.width * .50, size.height * .22)
      ..lineTo(size.width * .75, size.height * .72)
      ..lineTo(size.width * .25, size.height * .72)
      ..close();
    canvas.drawPath(path, paint);
    canvas.drawCircle(
      Offset(size.width * .62, size.height * .66),
      1.8,
      Paint()..color = const Color(0xFFE84142),
    );
  }

  @override
  bool shouldRepaint(covariant _CryptoAvatarPainter oldDelegate) {
    return oldDelegate.symbol != symbol;
  }
}

Color assetColor(String symbol) {
  return switch (symbol.toUpperCase()) {
    'BTC' => const Color(0xFFF7931A),
    'ETH' => const Color(0xFF627EEA),
    'SPEX' || 'SURPRISING CHAIN' => const Color(0xFF050505),
    'USDT' => const Color(0xFF26A17B),
    'USDC' => const Color(0xFF2775CA),
    'USDG' => const Color(0xFF8DC63F),
    'SOL' => const Color(0xFF111827),
    'TRX' => const Color(0xFFFF0013),
    'APT' || 'APTOS' => const Color(0xFF111111),
    'ARB' || 'ARBITRUM' => const Color(0xFF2D374B),
    'AVAX' || 'AVALANCHE' => const Color(0xFFE84142),
    'BERA' || 'BERACHAIN' => const Color(0xFFFFFFFF),
    'XAU' || 'XAUT' => const Color(0xFFB79525),
    _ => const Color(0xFF2B3139),
  };
}

String assetDisplayName(String symbol) {
  return switch (symbol.toUpperCase()) {
    'BTC' => 'Bitcoin',
    'ETH' => 'Ethereum',
    'SPEX' => 'Surprising EX',
    'SOL' => 'Solana',
    'USDT' => 'Tether',
    'USDC' => 'USD Coin',
    'TRX' => 'TRON',
    'XAU' || 'XAUT' => 'Tether Gold',
    _ => symbol,
  };
}

String volumeText(Instrument instrument) => instrument.volume24h == null
    ? '--'
    : money(instrument.volume24h!, digits: 2);

String shortDateTime(DateTime? value) {
  if (value == null) return '--';
  final local = value.toLocal();
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.year}-$month-$day $hour:$minute';
}

String timeLeft(DateTime? value) {
  if (value == null) return '--';
  final seconds = value.difference(DateTime.now()).inSeconds;
  if (seconds <= 0) return '已到期';
  final days = seconds ~/ 86400;
  final hours = (seconds % 86400) ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (days > 0) return '$days天$hours小时';
  return '$hours小时$minutes分';
}

double? _intrinsicValue(
  Instrument instrument,
  double? underlyingPrice,
  double? strike,
) {
  if (underlyingPrice == null || strike == null) return null;
  if (instrument.optionType == 'PUT') {
    return math.max(0, strike - underlyingPrice);
  }
  return math.max(0, underlyingPrice - strike);
}

String estimatedDelta(
  Instrument instrument,
  double? underlyingPrice,
  double? strike,
) {
  if (underlyingPrice == null || strike == null || strike <= 0) return '--';
  final ratio = underlyingPrice / strike;
  final call = instrument.optionType != 'PUT';
  if (call) {
    if (ratio >= 1.03) return '0.7500';
    if (ratio <= 0.97) return '0.2500';
    return '0.5000';
  }
  if (ratio <= 0.97) return '-0.7500';
  if (ratio >= 1.03) return '-0.2500';
  return '-0.5000';
}

List<OptionChainRow> _optionChainRows(
  Instrument selected,
  List<Instrument> instruments,
) {
  final targetExpiry = _dateKey(selected.expiryTime ?? selected.deliveryTime);
  final targetUnderlying = selected.underlyingSymbol ?? selected.baseAsset;
  final rows = <String, OptionChainRow>{};
  for (final item in instruments) {
    if (!item.isOption) continue;
    if ((item.underlyingSymbol ?? item.baseAsset) != targetUnderlying) continue;
    final expiry = _dateKey(item.expiryTime ?? item.deliveryTime);
    if (targetExpiry.isNotEmpty && expiry != targetExpiry) continue;
    final strike = item.strikePrice;
    if (strike == null) continue;
    final key = '$expiry:$strike';
    final current = rows[key] ?? OptionChainRow(expiry: expiry, strike: strike);
    rows[key] = item.optionType == 'PUT'
        ? current.copyWith(put: item.symbol)
        : current.copyWith(call: item.symbol);
  }
  final sorted = rows.values.toList()
    ..sort((left, right) => left.strike.compareTo(right.strike));
  return sorted;
}

String _dateKey(DateTime? value) {
  if (value == null) return '';
  final utc = value.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

class OptionChainRow {
  const OptionChainRow({
    required this.expiry,
    required this.strike,
    this.call,
    this.put,
  });

  final String expiry;
  final double strike;
  final String? call;
  final String? put;

  OptionChainRow copyWith({String? call, String? put}) {
    return OptionChainRow(
      expiry: expiry,
      strike: strike,
      call: call ?? this.call,
      put: put ?? this.put,
    );
  }
}

String networkDisplayName(String chain, String symbol) {
  final upper = chain.toUpperCase();
  return switch (upper) {
    'TRON' || 'TRX' => 'Tron (TRC20)',
    'ETH' || 'ETHEREUM' => 'Ethereum (ERC20)',
    'BTC' => 'Bitcoin',
    'SURPRISING CHAIN' => 'Surprising Chain ($symbol)',
    'ARB' || 'ARBITRUM' => 'Arbitrum One ($symbol)',
    'AVAX' || 'AVALANCHE' => 'Avalanche C-Chain',
    'APT' || 'APTOS' => 'Aptos',
    'BERA' || 'BERACHAIN' => 'Berachain (${symbol}0)',
    _ => chain,
  };
}

String networkEta(String chain) {
  final upper = chain.toUpperCase();
  if (upper.contains('ETH')) return '约 7 分钟';
  if (upper.contains('ARB')) return '约 18 分钟';
  return '约 1 分钟';
}

class WalletAction extends StatelessWidget {
  const WalletAction({
    required this.icon,
    required this.label,
    required this.onTap,
    super.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 64,
        child: Column(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: const BoxDecoration(
                color: _lime,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: Colors.black, size: 25),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class MetricPill extends StatelessWidget {
  const MetricPill({
    required this.label,
    required this.value,
    required this.color,
    super.key,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: .18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class QuickTile extends StatelessWidget {
  const QuickTile({
    required this.icon,
    required this.title,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.secondary),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(40),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class InfoLine extends StatelessWidget {
  const InfoLine({required this.label, required this.value, super.key});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Panel(
      child: Row(
        children: [
          Icon(
            Icons.inbox_outlined,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SparkleMark extends StatelessWidget {
  const SparkleMark({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(size: Size.square(size), painter: _SparklePainter());
  }
}

class _SparklePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = const LinearGradient(
        colors: [_pink, _violet, _amber],
      ).createShader(rect);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.deflate(2),
        Radius.circular(size.width * .22),
      ),
      paint,
    );
    final star = Path();
    final center = Offset(size.width * .50, size.height * .46);
    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? size.width * .24 : size.width * .10;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point =
          center + Offset(math.cos(angle) * radius, math.sin(angle) * radius);
      if (i == 0) {
        star.moveTo(point.dx, point.dy);
      } else {
        star.lineTo(point.dx, point.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Colors.white);
    canvas.drawCircle(
      Offset(size.width * .72, size.height * .22),
      size.width * .05,
      Paint()..color = Colors.white.withValues(alpha: .85),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class RecentTradesPanel extends StatelessWidget {
  const RecentTradesPanel({required this.state, super.key});
  final AppState state;
  @override
  Widget build(BuildContext context) {
    final instrument = state.selectedInstrument;
    return ExpansionTile(
      title: const Text('最新成交'),
      children: [
        if (state.recentTrades.isEmpty)
          const Padding(padding: EdgeInsets.all(16), child: Text('暂无成交')),
        for (final trade in state.recentTrades.take(50))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    asNullableDateTime(
                          trade['eventTime'],
                        )?.toLocal().toIso8601String().substring(11, 19) ??
                        '--',
                  ),
                ),
                Expanded(
                  child: Text(
                    trade['priceTicks'] == null
                        ? asString(trade['price'], fallback: '--')
                        : money(
                            instrument.priceFromTicks(
                              asInt(trade['priceTicks']),
                            ),
                            digits: instrument.pricePrecision,
                          ),
                    style: TextStyle(
                      color: trade['side'] == 'BUY'
                          ? Theme.of(context).colorScheme.tertiary
                          : Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    asString(
                      trade['quantity'],
                      fallback: tradingQuantity(
                        instrument,
                        asInt(trade['quantitySteps']),
                      ),
                    ),
                    textAlign: TextAlign.end,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

String _fundingLabel(AppState state) {
  if (!state.mode.isPerpetual) return '';
  final metrics =
      state.marketMetrics['${state.mode.productLine}:${state.selectedSymbol}'];
  final rate = metrics?['fundingRatePpm'];
  return '资金费率\n${rate == null ? '--' : '${(asInt(rate) / 10000).toStringAsFixed(4)}%'}';
}

class FullOrderBookSheet extends StatefulWidget {
  const FullOrderBookSheet({this.onPrice, super.key});
  final ValueChanged<String>? onPrice;
  @override
  State<FullOrderBookSheet> createState() => _FullOrderBookSheetState();
}

class _FullOrderBookSheetState extends State<FullOrderBookSheet> {
  int multiple = 1;
  int depth = 20;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context), instrument = state.selectedInstrument;
    final bids = aggregateBookLevels(
      state.orderBook.bids,
      multiple,
      bids: true,
    ).take(depth).toList();
    final asks = aggregateBookLevels(
      state.orderBook.asks,
      multiple,
      bids: false,
    ).take(depth).toList();
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(
        children: [
          ListTile(
            title: Text('${instrument.displayName} · 盘口'),
            subtitle: const Text('实时完整快照，最多 20 档'),
            trailing: IconButton(
              tooltip: '关闭',
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text('价格档位'),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<int>(
                    key: const ValueKey('book-precision'),
                    isExpanded: true,
                    value: multiple,
                    items: [
                      for (final value in [
                        1,
                        10,
                        100,
                        500,
                        1000,
                        10000,
                        100000,
                      ])
                        DropdownMenuItem(
                          value: value,
                          child: Text(
                            money(
                              instrument.priceFromTicks(value),
                              digits: instrument.pricePrecision,
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => multiple = value ?? 1),
                  ),
                ),
                const SizedBox(width: 16),
                const Text('档数'),
                const SizedBox(width: 8),
                DropdownButton<int>(
                  key: const ValueKey('book-depth'),
                  value: depth,
                  items: [
                    for (final value in [10, 20])
                      DropdownMenuItem(value: value, child: Text('$value')),
                  ],
                  onChanged: (value) => setState(() => depth = value ?? 20),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (bids.isEmpty && asks.isEmpty) const Text('暂无盘口'),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _side(
                        instrument,
                        bids,
                        '买盘',
                        Theme.of(context).colorScheme.tertiary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _side(
                        instrument,
                        asks,
                        '卖盘',
                        Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _side(
    Instrument instrument,
    List<OrderBookLevel> levels,
    String title,
    Color color,
  ) {
    var total = 0;
    final rows = <({OrderBookLevel level, int total})>[];
    for (final level in levels) {
      total += level.quantitySteps;
      rows.add((level: level, total: total));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 32),
                    alignment: Alignment.centerLeft,
                  ),
                  onPressed: widget.onPrice == null
                      ? null
                      : () {
                          widget.onPrice!(
                            money(
                              instrument.priceFromTicks(row.level.priceTicks),
                              digits: instrument.pricePrecision,
                            ),
                          );
                          Navigator.pop(context);
                        },
                  child: Text(
                    money(
                      instrument.priceFromTicks(row.level.priceTicks),
                      digits: instrument.pricePrecision,
                    ),
                    style: TextStyle(color: color),
                  ),
                ),
                Text(
                  '数量 ${tradingQuantity(instrument, row.level.quantitySteps)}',
                  style: const TextStyle(fontSize: 11),
                ),
                Text(
                  '累计 ${tradingQuantity(instrument, row.total)}',
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Product selection remains visible while a trading page scrolls. Each tab
/// selects a complete product context, rather than sharing a symbol-only view.
class ProductLineTabs extends StatefulWidget {
  const ProductLineTabs({
    required this.value,
    required this.onChanged,
    super.key,
  });
  final ProductMode value;
  final ValueChanged<ProductMode> onChanged;
  @override
  State<ProductLineTabs> createState() => _ProductLineTabsState();
}

class _ProductLineTabsState extends State<ProductLineTabs> {
  final anchors = {for (final mode in ProductMode.values) mode: GlobalKey()};
  @override
  void initState() {
    super.initState();
    _revealSelected();
  }

  @override
  void didUpdateWidget(covariant ProductLineTabs oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _revealSelected();
  }

  void _revealSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = anchors[widget.value]?.currentContext;
      if (target != null) Scrollable.ensureVisible(target, alignment: .5);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        key: const ValueKey('product-line-tabs'),
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            for (final mode in ProductMode.values)
              Padding(
                key: anchors[mode],
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: ValueKey('product-tab-${mode.name}'),
                  label: Text(mode.label),
                  selected: widget.value == mode,
                  onSelected: (_) {
                    if (mode != widget.value) widget.onChanged(mode);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class TradingLeverageSheet extends StatefulWidget {
  const TradingLeverageSheet({
    required this.state,
    required this.instrument,
    required this.marginMode,
    super.key,
  });
  final AppState state;
  final Instrument instrument;
  final String marginMode;
  @override
  State<TradingLeverageSheet> createState() => _TradingLeverageSheetState();
}

class _TradingLeverageSheetState extends State<TradingLeverageSheet> {
  final controller = TextEditingController();
  late final int? userId;
  late final String? token;
  Map<String, dynamic>? setting;
  bool loading = true, saving = false;
  String? error;
  @override
  void initState() {
    super.initState();
    userId = widget.state.userId;
    token = widget.state.session?.accessToken;
    unawaited(load());
  }

  bool get sameSession =>
      userId != null &&
      widget.state.userId == userId &&
      widget.state.session?.accessToken == token;
  Future<void> load() async {
    try {
      if (!sameSession) throw StateError('请先登录');
      final row = await widget.state.api.leverageSetting(
        userId!,
        widget.instrument,
        widget.marginMode,
      );
      if (!mounted) return;
      if (!sameSession) throw StateError('登录状态已变化，请重新打开');
      if (asInt(row['maxLeveragePpm']) < 1000000 ||
          asInt(row['leveragePpm']) < 1000000) {
        throw StateError('杠杆配置尚未就绪');
      }
      setState(() {
        setting = row;
        controller.text = '${asInt(row['leveragePpm']) / 1000000}';
        loading = false;
      });
    } catch (cause) {
      if (mounted) {
        setState(() {
          error = '加载杠杆失败：$cause';
          loading = false;
        });
      }
    }
  }

  Future<void> save() async {
    if (saving || setting == null) return;
    final ppm = decimalIncrement(
      controller.text,
      100,
    ); // leverage × 1,000,000, no rounding.
    if (!sameSession ||
        ppm == null ||
        ppm < 1000000 ||
        ppm > asInt(setting!['maxLeveragePpm'])) {
      setState(() => error = sameSession ? '请输入有效范围内的杠杆倍数' : '登录状态已变化，请重新打开');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.state.api.updateLeverage(
        userId!,
        widget.instrument,
        widget.marginMode,
        ppm,
      );
      if (!mounted) return;
      if (!sameSession) {
        setState(() => error = '登录状态已变化，请核对设置');
        return;
      }
      widget.state.leverageUpdated();
      Navigator.pop(context);
    } catch (cause) {
      if (mounted) setState(() => error = '修改杠杆失败：$cause');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      16,
      16,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${widget.instrument.symbol} · ${widget.marginMode == 'ISOLATED' ? '逐仓' : '全仓'}杠杆',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 12),
          if (loading) const LinearProgressIndicator(),
          if (setting != null) ...[
            Text('允许范围 1–${asInt(setting!['maxLeveragePpm']) / 1000000}×'),
            TextField(
              controller: controller,
              enabled: !saving,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '杠杆倍数'),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: saving ? null : save,
              child: Text(saving ? '保存中…' : '保存杠杆'),
            ),
          ],
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    ),
  );
}
