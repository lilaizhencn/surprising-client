import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';

import 'linear_delivery_trading_test.dart' show actor;
import 'support/authentication.dart';

class _AnnouncementApi extends TestApiClient {
  final listCalls = <String>[];
  final detailCalls = <int>[];
  final readCalls = <int>[];
  int allReadCalls = 0;
  Map<int, Map<String, dynamic>> details = {};
  List<Map<String, dynamic>> rows = [];
  int unread = 0;
  bool failDetail = false;

  @override
  Future<Map<String, dynamic>> announcements({
    required String locale,
    required String productLine,
    required String platform,
    required String placement,
    int offset = 0,
    int limit = 50,
  }) async {
    listCalls.add(placement);
    return {
      'announcements': placement == 'CENTER' ? rows : <Map<String, dynamic>>[],
      'offset': offset,
      'hasMore': false,
      'unreadCount': unread,
    };
  }

  @override
  Future<Map<String, dynamic>> announcementDetail({
    required int announcementId,
    required String locale,
    required String productLine,
    required String platform,
    required String placement,
  }) async {
    detailCalls.add(announcementId);
    if (failDetail) {
      throw ApiException(503, 'detail failed');
    }
    return details[announcementId] ??
        (throw ApiException(404, 'missing'));
  }

  @override
  Future<Map<String, dynamic>> markAnnouncementRead({
    required int announcementId,
    required String productLine,
    required String platform,
    required String placement,
  }) async {
    readCalls.add(announcementId);
    unread = unread > 0 ? unread - 1 : 0;
    for (final row in rows) {
      if (row['announcementId'] == announcementId) {
        row['readAt'] = '2026-11-19T10:00:00Z';
      }
    }
    final detail = Map<String, dynamic>.from(
      details[announcementId] ?? {'announcementId': announcementId},
    );
    detail['readAt'] = '2026-11-19T10:00:00Z';
    details[announcementId] = detail;
    return detail;
  }

  @override
  Future<Map<String, dynamic>> markAllAnnouncementsRead({
    required String productLine,
    required String platform,
    String placement = 'CENTER',
  }) async {
    allReadCalls++;
    unread = 0;
    for (final row in rows) {
      row['readAt'] = '2026-11-19T10:00:00Z';
    }
    return {'updated': rows.length};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> row(int id, {String? readAt, String title = '标题'}) => {
    'announcementId': id,
    'title': title,
    'summary': '摘要 $id',
    'category': 'PRODUCT',
    'readAt': readAt,
  };

  testWidgets('list does not fetch details and a tap opens fetched detail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _AnnouncementApi()
      ..rows = [row(7)]
      ..unread = 1
      ..details[7] = {
        'announcementId': 7,
        'title': '详情标题',
        'category': 'PRODUCT',
        'body': '完整正文',
        'locale': 'zh-CN',
      };
    final state = AppState(
      initialSession: actor,
      apiClient: api,
      offline: false,
    )..unreadAnnouncementCount = 1;
    state.announcements = api.rows;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          home: Scaffold(body: AnnouncementCenterPage(onClose: () {})),
        ),
      ),
    );
    expect(find.text('全部已读'), findsOneWidget);
    expect(find.byTooltip('刷新'), findsNothing);
    expect(find.byIcon(Icons.refresh), findsNothing);
    expect(find.text('阅读完整公告'), findsNothing);
    expect(api.detailCalls, isEmpty);
    expect(api.readCalls, isEmpty);

    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    expect(api.detailCalls, [7]);
    expect(find.text('详情标题'), findsWidgets);
    expect(find.text('完整正文'), findsOneWidget);
    expect(api.readCalls, [7]);
  });

  testWidgets('cached body can be shown after a later failure without marking read', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(392, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _AnnouncementApi()
      ..rows = [row(4)]
      ..unread = 1
      ..details[4] = {
        'announcementId': 4,
        'title': '缓存详情',
        'body': '缓存正文',
        'category': 'GENERAL',
      };
    final state = AppState(
      initialSession: actor,
      apiClient: api,
      offline: false,
    )..unreadAnnouncementCount = 1;
    state.announcements = api.rows;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          home: Scaffold(body: AnnouncementCenterPage(onClose: () {})),
        ),
      ),
    );
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    expect(find.text('缓存正文'), findsOneWidget);
    expect(api.readCalls, [4]);
    Navigator.of(tester.element(find.text('缓存正文'))).pop();
    await tester.pumpAndSettle();

    api.failDetail = true;
    api.readCalls.clear();
    api.rows = [row(4)]; // still unread on the list until a successful mark
    api.unread = 1;
    state.announcements = [row(4)];
    state.unreadAnnouncementCount = 1;
    state.notifyListeners();
    await tester.pump();
    await tester.tap(find.text('标题'));
    await tester.pumpAndSettle();
    // Cached body may still open, but a failed fetch must not by itself mark it read.
    expect(find.text('缓存正文'), findsOneWidget);
    expect(api.readCalls, isEmpty);
    expect(state.unreadAnnouncementCount, 1);
    expect(state.announcements.single['readAt'], isNull);
  });

  testWidgets('mark all read lives in the header', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final api = _AnnouncementApi()
      ..rows = [row(1), row(2)]
      ..unread = 2;
    final state = AppState(
      initialSession: actor,
      apiClient: api,
      offline: false,
    )..unreadAnnouncementCount = 2;
    state.announcements = api.rows;
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          home: Scaffold(body: AnnouncementCenterPage(onClose: () {})),
        ),
      ),
    );
    final header = tester.getRect(find.text('公告中心'));
    final action = tester.getRect(find.byKey(const ValueKey('mark-all-announcements-read')));
    expect(action.center.dy, closeTo(header.center.dy, 24));
    expect(action.left, greaterThan(header.left));
    await tester.tap(find.byKey(const ValueKey('mark-all-announcements-read')));
    await tester.pumpAndSettle();
    expect(api.allReadCalls, 1);
    expect(api.detailCalls, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
