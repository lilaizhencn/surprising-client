import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_scope.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/legal/legal_models.dart';
import 'package:surprising_client/src/legal/legal_pages.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/session_store.dart';

Map<String, dynamic> document(int id, String type, {String locale = 'zh-CN'}) =>
    {
      'revisionId': '$id',
      'type': type,
      'locale': locale,
      'title': type,
      'bodyHtml': '<p>Reviewed text</p>',
      'revisionLabel': '2026-10-31.1',
      'registrationRequired': true,
    };

void main() {
  // Construct before testWidgets installs its network-blocking HttpOverrides.
  final networkClient = HttpClient();
  test('legal boundary rejects invalid identifiers, language and content', () {
    final value = document(29, 'USER_AGREEMENT');
    expect(LegalDocument.fromJson(value).revisionId, 29);
    for (final patch in [
      {'revisionId': '9223372036854775808'},
      {'revisionId': 0},
      {'locale': 'xx-XX'},
      {'title': ''},
      {'bodyHtml': ''},
      {'registrationRequired': 'true'},
    ]) {
      expect(
        () => LegalDocument.fromJson({...value, ...patch}),
        throwsFormatException,
      );
    }
  });

  test(
    'only authentication carries the explicit reviewed versions and clearing removes them',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final headers = <String?>[];
      final subscription = server.listen((request) async {
        headers.add(request.headers.value('X-Legal-Acceptance'));
        await request.drain<void>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{}');
        await request.response.close();
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
        httpClient: networkClient,
      );
      addTearDown(() async {
        api.dispose();
        await subscription.cancel();
        await server.close(force: true);
      });
      api.setLegalAcceptance([
        LegalDocument.fromJson(document(29, 'USER_AGREEMENT', locale: 'ar-SA')),
        LegalDocument.fromJson(document(30, 'PRIVACY_POLICY', locale: 'ar-SA')),
      ]);
      await api.post('/api/v1/auth/login', {});
      await api.get('/api/v1/legal/current');
      api.clearLegalAcceptance();
      await api.post('/api/v1/auth/login', {});
      expect(headers, ['29:ar-SA,30:ar-SA', null, null]);
      final cancellation = ApiRequestCancellation();
      final pending = api.legalDocuments('en-US', cancellation: cancellation);
      cancellation.cancel();
      await expectLater(pending, throwsA(isA<ApiRequestCancelled>()));
    },
  );

  testWidgets(
    'review starts unchecked, clears on a language change and on disposal',
    (tester) async {
      final api = _LegalApi();
      final state = AppState(
        offline: true,
        apiClient: api,
        settingsStore: _Settings(),
      );
      addTearDown(state.dispose);
      final ready = <bool>[];
      await tester.pumpWidget(
        AppScope(
          notifier: state,
          child: MaterialApp(
            home: Scaffold(
              body: LegalReview(onReady: ready.add, disabled: false),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(ready.last, false);
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pumpAndSettle();
      expect(ready.last, true);
      expect(api.accepted.map((item) => item.revisionId), [29, 30]);
      state.selectLanguage(ClientLanguage.en);
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        false,
      );
      expect(api.accepted, isEmpty);
      expect(ready.last, false);
      await tester.pumpWidget(const SizedBox());
      expect(api.accepted, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

class _LegalApi extends ApiClient {
  _LegalApi() : super(const AppConfig(gatewayBaseUrl: 'http://127.0.0.1'));
  List<LegalDocument> accepted = [];
  @override
  Future<List<LegalDocument>> legalDocuments(
    String locale, {
    ApiRequestCancellation? cancellation,
  }) async => [
    LegalDocument.fromJson(document(29, 'USER_AGREEMENT', locale: locale)),
    LegalDocument.fromJson(document(30, 'PRIVACY_POLICY', locale: locale)),
  ];
  @override
  void setLegalAcceptance(List<LegalDocument> documents) {
    super.setLegalAcceptance(documents);
    accepted = documents;
  }

  @override
  void clearLegalAcceptance() {
    super.clearLegalAcceptance();
    accepted = [];
  }
}

class _Settings implements ClientSettingsStore {
  Map<String, String> values = {};
  @override
  Future<Map<String, String>> read() async => values;
  @override
  Future<void> write(Map<String, String> next) async {
    values = next;
  }
}
