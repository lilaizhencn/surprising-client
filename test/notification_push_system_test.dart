import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/notification_router.dart';

void main() {
  group('Notification System Client Models & Routing', () {
    test('NotificationItem parsing and json roundtrip', () {
      final json = {
        'notificationId': 1001,
        'title': 'BTC 剧烈波动预警',
        'body': 'BTC-USDT-PERPETUAL 在短时间内上涨超过 6.50%',
        'category': 'MARKET',
        'route': '/trade/usd-perpetual',
        'routeParams': '{"symbol":"BTC-USDT-PERPETUAL"}',
        'readAt': null,
        'createdAt': '2026-11-06T12:00:00.000Z',
      };

      final item = NotificationItem.fromJson(json);
      expect(item.notificationId, 1001);
      expect(item.title, 'BTC 剧烈波动预警');
      expect(item.category, 'MARKET');
      expect(item.route, '/trade/usd-perpetual');
      expect(item.routeParams, '{"symbol":"BTC-USDT-PERPETUAL"}');
      expect(item.isRead, isFalse);

      final now = DateTime.now();
      final updated = item.copyWith(readAt: now);
      expect(updated.isRead, isTrue);

      final encoded = updated.toJson();
      expect(encoded['notificationId'], 1001);
      expect(encoded['category'], 'MARKET');
      expect(encoded['readAt'], now.toIso8601String());
    });

    test('NotificationPreferences defaults and json mapping', () {
      final prefs = NotificationPreferences.defaults();
      expect(prefs.marketVolatilityPush, isTrue);
      expect(prefs.marketVolatilityThresholdPct, 5.0);
      expect(prefs.securityLoginPush, isTrue);
      expect(prefs.tradingFillPush, isTrue);
      expect(prefs.liquidationRiskPush, isTrue);

      final json = prefs.toJson();
      expect(json['marketVolatilityPush'], isTrue);
      expect(json['marketVolatilityThresholdPct'], 5.0);
      expect(json['securityLoginPush'], isTrue);

      final modified = prefs.copyWith(
        marketVolatilityThresholdPct: 8.5,
        securityLoginEmail: false,
      );
      final modifiedJson = modified.toJson();
      final restored = NotificationPreferences.fromJson(modifiedJson);

      expect(restored.marketVolatilityThresholdPct, 8.5);
      expect(restored.securityLoginEmail, isFalse);
      expect(restored.marketVolatilityPush, isTrue);
    });

    test('ShellTabNotification correctly instantiates target tabs', () {
      const homeTab = ShellTabNotification(0);
      expect(homeTab.tabIndex, 0);

      const tradeTab = ShellTabNotification(2, symbol: 'ETH-USDT-PERPETUAL');
      expect(tradeTab.tabIndex, 2);
      expect(tradeTab.symbol, 'ETH-USDT-PERPETUAL');

      const walletTab = ShellTabNotification(4);
      expect(walletTab.tabIndex, 4);
    });
  });
}
