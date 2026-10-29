import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'announcements/announcement_center.dart';
import 'app_scope.dart';
import 'affiliate/affiliate_page.dart';
import 'app_state.dart';
import 'auth/auth_sheet.dart';
import 'biometric_lock.dart';
import 'c2c_trading_page.dart';
import 'market/market_pages.dart';
import 'models.dart';
import 'telegram_login.dart';
import 'trading/trade_page.dart';
import 'ui/client_components.dart';
import 'ui/client_navigation.dart';
import 'ui/client_theme.dart';
import 'ui/adaptive_client_layout.dart';
import 'market/market_chart.dart';
import 'wallet/wallet_page.dart';

export 'account/kyc_webview.dart';
export 'account/profile_page.dart';
export 'account/security_sheet.dart';
export 'announcements/announcement_center.dart';
export 'app_scope.dart';
export 'auth/auth_sheet.dart';
export 'market/market_chart.dart';
export 'market/market_pages.dart';
export 'trading/advanced_orders.dart';
export 'trading/contract_settings.dart';
export 'trading/order_book.dart';
export 'trading/order_ticket.dart';
export 'trading/private_trading.dart';
export 'trading/trade_page.dart';
export 'trading/trading_details.dart';
export 'transfer_page.dart' show TransferPage;
export 'ui/client_components.dart';
export 'ui/client_navigation.dart';
export 'ui/crypto_avatar.dart';
export 'wallet/deposit_pages.dart';
export 'wallet/wallet_components.dart';
export 'wallet/wallet_page.dart';
export 'wallet/withdrawal_page.dart';

typedef C2cPage = C2cTradingPage;

class SurprisingClientApp extends StatefulWidget {
  const SurprisingClientApp({super.key, this.state, this.bootstrap = true});

  final AppState? state;
  final bool bootstrap;

  @override
  State<SurprisingClientApp> createState() => _SurprisingClientAppState();
}

class _SurprisingClientAppState extends State<SurprisingClientApp> {
  late final AppState state = widget.state ?? AppState();
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _secondaryRoute = ValueNotifier(false);
  late final _routeObserver = ClientRouteObserver(() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _secondaryRoute.value = _navigatorKey.currentState?.canPop() ?? false;
      }
    });
  });
  StreamSubscription<Uri>? _authLinks;
  String? _affiliateInviteOpen;

  @override
  void initState() {
    super.initState();
    state.presentation.value = (state.clientTheme, state.language);
    if (widget.bootstrap) {
      _authLinks = AppLinks().uriLinkStream.listen(
        (link) => unawaited(_returnFromTelegram(link)),
        onError: (Object _) {},
      );
      unawaited(state.bootstrap());
      unawaited(
        AppLinks()
            .getInitialLink()
            .then((link) async {
              if (link != null) await _returnFromTelegram(link);
            })
            .catchError((Object _) {}),
      );
    }
  }

  Future<void> _returnFromTelegram(Uri link) async {
    if (link.scheme == 'surprising' && link.host == 'affiliate') {
      final code = link.queryParameters['invite'];
      if (code == null || !RegExp(r'^[A-Za-z0-9]{32}$').hasMatch(code)) return;
      if (_affiliateInviteOpen == code) return;
      _affiliateInviteOpen = code;
      state.pendingInvitationCode = code.toUpperCase();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final navigation = _navigatorKey.currentState?.push(
          MaterialPageRoute<void>(
            builder: (_) => AffiliatePage(invitation: code),
          ),
        );
        if (navigation == null) {
          _affiliateInviteOpen = null;
        } else {
          unawaited(navigation.whenComplete(() => _affiliateInviteOpen = null));
        }
      });
      return;
    }
    if (!TelegramLoginFlow.isReturnLink(link)) return;
    try {
      final resumed = await state.resumeTelegramLogin(link);
      if (!mounted || !resumed || state.isLoggedIn) return;
      final context = _navigatorKey.currentState?.overlay?.context;
      if (context != null && context.mounted) showAuthSheet(context);
    } catch (_) {
      // No credentials or provider errors belong in a link-handler log.
      if (!mounted) return;
      final context = _navigatorKey.currentState?.overlay?.context;
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Telegram 登录未完成，请重新发起登录')));
      }
    }
  }

  @override
  void dispose() {
    unawaited(_authLinks?.cancel());
    _secondaryRoute.dispose();
    if (widget.state == null) state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      notifier: state,
      child: ValueListenableBuilder<(ClientTheme, ClientLanguage)>(
        valueListenable: state.presentation,
        builder: (context, preferences, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Surprising',
            navigatorKey: _navigatorKey,
            navigatorObservers: [_routeObserver],
            builder: (context, child) => BiometricLockGate(
              state: state,
              onUsePassword: () async {
                await state.logout();
                if (!mounted) return;
                _navigatorKey.currentState?.popUntil((route) => route.isFirst);
                final context = _navigatorKey.currentState?.overlay?.context;
                if (context != null && context.mounted) showAuthSheet(context);
              },
              child: ValueListenableBuilder<bool>(
                valueListenable: _secondaryRoute,
                child: child ?? const SizedBox.shrink(),
                builder: (context, secondary, navigator) => secondary
                    ? FoldAwareClientBody(primary: navigator!)
                    : navigator!,
              ),
            ),
            locale: Locale(preferences.$2.code),
            theme: buildClientTheme(preferences.$1),
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
  final contentKey = GlobalKey();
  String? seenNotice;
  String? seenError;
  bool announcementsOpen = false;
  bool checkedAnnouncementModal = false;
  String lastAnnouncementModalFingerprint = '';
  final Set<String> shownAnnouncementModals = {};

  void setTab(int next) {
    setState(() {
      index = next;
      announcementsOpen = false;
    });
  }

  void openAnnouncements() => setState(() => announcementsOpen = true);

  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    if (!state.requiresBiometricUnlock) {
      _showMessage(context, state);
      _maybeShowAnnouncementModal(state);
    }
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
            3 => const C2cPage(),
            _ => const WalletPage(),
          };
    void select(int next) => setTab(next);
    final content = KeyedSubtree(key: contentKey, child: page);
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceDim,
      child: FoldAwareClientBody(
        secondary: index == 2 && !announcementsOpen
            ? const MarketChartPage()
            : null,
        primary: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= 600 && constraints.maxHeight >= 360;
            return Scaffold(
              body: Row(
                children: [
                  if (wide)
                    ExchangeSideNav(
                      selectedIndex: index,
                      onSelected: select,
                      extended: constraints.maxWidth >= 1400,
                    ),
                  Expanded(
                    child: ClientNavigation(
                      openBuyCrypto: () => setTab(3),
                      openAnnouncements: openAnnouncements,
                      child: SafeArea(child: content),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: wide
                  ? null
                  : ExchangeBottomNav(selectedIndex: index, onSelected: select),
            );
          },
        ),
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
      if (!mounted || !state.isLoggedIn || state.requiresBiometricUnlock) {
        return;
      }
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
      if (!mounted || state.requiresBiometricUnlock) return;
      final media = MediaQuery.maybeOf(context);
      final size = media?.size;
      if (size == null || size.width <= 0 || size.height <= 0) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      if (state.lastError != null && state.lastError != seenError) {
        seenError = state.lastError;
        messenger.clearSnackBars();
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              state.lastError!,
              style: TextStyle(color: Theme.of(context).colorScheme.onError),
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
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
