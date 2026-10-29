import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/account_records.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/funding_records_page.dart';
import 'package:surprising_client/src/kyc_application_page.dart';
import 'package:surprising_client/src/kyc_documents_page.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/realtime_state.dart';

import 'auth_state_test.dart' show DelayedSessionStore;
import 'linear_delivery_trading_test.dart' show actor;
import 'trading_scale_widgets_test.dart' show contract;

void main() {
  void portrait(WidgetTester tester) {
    tester.view.physicalSize = const Size(392, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  for (final invalid in [null, 'NaN', '1.5', true, '9223372036854775808']) {
    testWidgets('invalid KYC document ID $invalid cannot be saved or removed', (
      tester,
    ) async {
      portrait(tester);
      final api = BadDisplayApi(documentId: invalid);
      final state = AppState(
        initialSession: actor,
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(home: KycDocumentsPage(state: state)),
      );
      await tester.pumpAndSettle();
      expect(find.text('材料暂不可用，请刷新后重试'), findsOneWidget);
      for (final label in ['保存原件', '删除未提交材料']) {
        final button = tester.widget<TextButton>(
          find.widgetWithText(TextButton, label),
        );
        expect(button.onPressed, isNull);
      }
      expect(api.documentActions, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'missing upload IDs yield validation feedback rather than a build error',
    (tester) async {
      portrait(tester);
      final state = AppState(
        initialSession: actor,
        offline: true,
        apiClient: BadDisplayApi(),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        MaterialApp(home: KycApplicationPage(state: state)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('测试国家').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('提交认证申请'));
      await tester.pumpAndSettle();
      expect(find.text('请上传所有必需材料'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('malformed announcement identifiers stay unavailable', (
    tester,
  ) async {
    portrait(tester);
    final state = AppState(offline: true)
      ..announcements = [
        {'announcementId': 'NaN', 'title': '不可用公告'},
        {'announcementId': '3', 'title': '有效公告', 'readAt': 'read'},
      ];
    addTearDown(state.dispose);
    await tester.pumpWidget(
      AppScope(
        notifier: state,
        child: MaterialApp(
          home: Scaffold(body: AnnouncementCenterPage(onClose: () {})),
        ),
      ),
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '不可用公告')).onTap,
      isNull,
    );
    expect(find.text('公告暂不可用，请刷新'), findsOneWidget);
    expect(find.text('有效公告'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('bad ledger quantities and prices remain unknown', (
    tester,
  ) async {
    portrait(tester);
    final instrument = contract(ProductMode.linear);
    final state = AppState(
      initialSession: actor,
      offline: true,
      apiClient: BadDisplayApi(),
    )..instruments = [instrument];
    addTearDown(state.dispose);
    await tester.pumpWidget(
      MaterialApp(home: FundingRecordsPage(state: state)),
    );
    await tester.pumpAndSettle();
    expect(find.text('数量：—'), findsOneWidget);
    expect(find.text('价格：—'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'malformed leverage and trigger prices do not interrupt a position card',
    (tester) async {
      portrait(tester);
      final instrument = contract(ProductMode.linear);
      final state = AppState(initialSession: actor, offline: true)
        ..instruments = [instrument];
      state.privateViews[ProductMode.linear] = MalformedPositionView(
        instrument,
      );
      addTearDown(state.dispose);
      final position = Position.fromJson({
        'instrumentId': instrument.instrumentId,
        'symbol': instrument.symbol,
        'signedQuantitySteps': 1,
        'entryPriceTicks': 101,
        'positionSide': 'NET',
        'marginMode': 'CROSS',
        'marginAsset': 'USDT',
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PositionRow(position: position, state: state),
          ),
        ),
      );
      final details = tester.widget<TradingDetails>(
        find.byType(TradingDetails),
      );
      expect(details.values['杠杆'], '--');
      expect(details.values['止盈止损'], contains('--'));
      expect(tester.takeException(), isNull);
    },
  );

  for (final invalid in [
    null,
    'NaN',
    '1500000.5',
    true,
    '9223372036854775808',
  ]) {
    testWidgets(
      'invalid leverage limit $invalid leaves the editor unavailable',
      (tester) async {
        portrait(tester);
        final instrument = contract(ProductMode.linear);
        final api = BadDisplayApi(leverageLimit: invalid);
        final state = AppState(
          initialSession: actor,
          offline: true,
          apiClient: api,
        );
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: TradingLeverageSheet(
                state: state,
                instrument: instrument,
                marginMode: 'CROSS',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('杠杆配置尚未就绪'), findsOneWidget);
        expect(find.text('保存杠杆'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'profile handles logout storage failure without an uncaught future',
    (tester) async {
      portrait(tester);
      final store = DelayedSessionStore()
        ..clearFailure = StateError('keychain unavailable');
      final state = AppState(
        initialSession: actor,
        offline: true,
        sessionStore: store,
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: const MaterialApp(home: Scaffold(body: ProfilePage())),
        ),
      );
      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();
      expect(state.session, isNull);
      expect(state.lastError, contains('无法清除'));
      expect(tester.takeException(), isNull);
    },
  );
}

class BadDisplayApi extends ApiClient {
  BadDisplayApi({this.documentId, this.leverageLimit})
    : super(const AppConfig());
  final Object? documentId;
  final Object? leverageLimit;
  int documentActions = 0;

  @override
  Future<List<Map<String, dynamic>>> kycDocuments() async => [
    {
      'documentId': documentId,
      'originalFilename': 'document.pdf',
      'status': 'UPLOADED',
    },
  ];

  @override
  Future<void> deleteKycDocument(int id) async => documentActions++;

  @override
  Future<Uint8List> downloadKycDocument(int id) async {
    documentActions++;
    return Uint8List(0);
  }

  @override
  Future<Map<String, dynamic>> leverageSetting(
    int userId,
    Instrument instrument,
    String marginMode,
  ) async => {'leveragePpm': 1000000, 'maxLeveragePpm': leverageLimit};

  @override
  Future<List<Map<String, dynamic>>> kycCountries() async => [
    {
      'code': 'CN',
      'names': {'zh': '测试国家'},
    },
  ];

  @override
  Future<Map<String, dynamic>> kycProvider() async => {
    'provider': 'SELF',
    'verificationOptions': [
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'BASIC'},
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'STANDARD'},
      {'applicantType': 'INDIVIDUAL', 'kycLevel': 'ENHANCED'},
      {'applicantType': 'BUSINESS', 'kycLevel': 'BASIC'},
    ],
  };

  @override
  Future<Map<String, String>> assetScales() async => {
    'BTC': '1000000',
    'USDT': '1000000',
  };

  @override
  Future<AccountRecordPage> accountRecords({
    required String category,
    required int userId,
    required ProductMode product,
    String asset = '',
    String referenceType = '',
    String instrumentId = '',
    String status = '',
    DateTime? from,
    DateTime? to,
    String? cursor,
  }) async => const AccountRecordPage(
    [
      {
        'instrumentId': '73',
        'asset': 'USDT',
        'amountUnits': 1,
        'quantitySteps': 'NaN',
        'priceTicks': '1.5',
      },
    ],
    null,
    false,
  );
}

class MalformedPositionView extends PrivateView {
  MalformedPositionView(this.instrument);
  final Instrument instrument;

  @override
  bool get ready => true;

  @override
  List<Map<String, dynamic>> rows(String kind) => switch (kind) {
    'leverage' => [
      {
        'instrumentId': instrument.instrumentId,
        'marginMode': 'CROSS',
        'leveragePpm': 'NaN',
      },
    ],
    'trigger' => [
      {
        'symbol': instrument.symbol,
        'positionSide': 'NET',
        'triggerType': 'TAKE_PROFIT',
        'triggerPriceTicks': 'Infinity',
      },
    ],
    _ => [],
  };
}
