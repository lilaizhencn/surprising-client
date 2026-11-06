import 'dart:convert';
import 'package:flutter/material.dart';
import 'app_scope.dart';
import 'app_state.dart';
import 'device_access_panel.dart';
import 'notifications_page.dart';
import 'notification_settings_page.dart';

/// 负责将系统推送通知携带的 route 与 routeParams 精准导航至目标页面
class NotificationRouter {
  static void navigate(BuildContext context, String? route, [dynamic rawParams, AppState? state]) {
    if (route == null || route.isEmpty) return;

    Map<String, dynamic> params = {};
    if (rawParams is Map<String, dynamic>) {
      params = rawParams;
    } else if (rawParams is String && rawParams.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawParams);
        if (decoded is Map<String, dynamic>) params = decoded;
      } catch (_) {}
    }

    final targetState = state ?? AppScope.of(context);
    final cleanRoute = route.trim().toLowerCase();

    if (cleanRoute.startsWith('/trade') || cleanRoute.contains('perpetual')) {
      final symbol = params['symbol'] as String?;
      if (symbol != null && symbol.isNotEmpty) {
        targetState.selectSymbol(symbol.toUpperCase());
      }
      // 通知 ClientShell 切换至交易 Tab
      _switchShellTab(context, 2, symbol);
    } else if (cleanRoute.startsWith('/security')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('设备与安全中心')),
            body: SafeArea(child: DeviceAccessPanel(state: targetState)),
          ),
        ),
      );
    } else if (cleanRoute.startsWith('/assets') || cleanRoute.startsWith('/wallet')) {
      _switchShellTab(context, 4);
    } else if (cleanRoute.startsWith('/c2c')) {
      _switchShellTab(context, 3);
    } else if (cleanRoute.startsWith('/markets')) {
      _switchShellTab(context, 1);
    } else if (cleanRoute.startsWith('/notifications/settings')) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationSettingsPage(state: targetState),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => NotificationsPage(state: targetState),
        ),
      );
    }
  }

  static void _switchShellTab(BuildContext context, int tabIndex, [String? symbol]) {
    // 递归向上查找 ClientShellController 或触发全局事件
    ShellTabNotification(tabIndex, symbol: symbol).dispatch(context);
  }
}

/// 用于在 Widget 树中分发切换 Tab 意图的通知
class ShellTabNotification extends Notification {
  const ShellTabNotification(this.tabIndex, {this.symbol});
  final int tabIndex;
  final String? symbol;
}
