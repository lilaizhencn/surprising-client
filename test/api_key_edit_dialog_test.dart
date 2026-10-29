import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/account/api_key_edit_dialog.dart';
import 'package:surprising_client/src/api.dart';

void main() {
  final key = <String, dynamic>{
    'apiKey': 'sx_sample',
    'label': 'read key',
    'permissions': 'READ',
    'ipAllowlist': <String>[],
  };

  Future<void> open(
    WidgetTester tester,
    Future<void> Function(ApiKeySettings) save,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => showDialog<bool>(
                context: context,
                builder: (_) => ApiKeyEditDialog(
                  apiKey: key,
                  mfaRequired: false,
                  onSendCode: () async {},
                  onSave: save,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder input(String label) => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.decoration?.labelText == label,
  );

  testWidgets('write permission requires IP before sending credentials', (
    tester,
  ) async {
    int requests = 0;
    await open(tester, (_) async {
      requests++;
    });
    await tester.enterText(input('邮箱验证码'), '123456');
    await tester.ensureVisible(find.text('允许交易'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许交易'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pump();
    expect(requests, 0);
    expect(find.textContaining('必须设置 IP 白名单'), findsOneWidget);
  });

  testWidgets(
    'editing sends name permissions and deduplicated IPs exactly once',
    (tester) async {
      final pending = Completer<void>();
      final sent = <ApiKeySettings>[];
      await open(tester, (settings) {
        sent.add(settings);
        return pending.future;
      });
      await tester.enterText(input('名称'), 'maker');
      await tester.enterText(input('IP 白名单'), '203.0.113.7, 203.0.113.7');
      await tester.enterText(input('邮箱验证码'), '123456');
      await tester.ensureVisible(find.text('允许交易'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('允许交易'));
      await tester.pump();
      await tester.tap(find.text('保存'));
      await tester.pump();
      expect(sent, hasLength(1));
      expect(sent.single.label, 'maker');
      expect(sent.single.permissions, ['READ', 'TRADE']);
      expect(sent.single.ipAllowlist, ['203.0.113.7']);
      expect(find.text('处理中…'), findsOneWidget);
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('编辑 API 密钥'), findsNothing);
    },
  );

  testWidgets(
    'a definitive rejection permits correction while an unknown result requires refresh',
    (tester) async {
      bool uncertain = false;
      await open(tester, (_) async {
        if (uncertain) throw StateError('network');
        throw ApiException(400, 'invalid IP');
      });
      await tester.enterText(input('邮箱验证码'), '123456');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.text('编辑 API 密钥'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNotNull,
      );
      uncertain = true;
      await tester.enterText(input('邮箱验证码'), '123456');
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(find.textContaining('操作结果尚未确认'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '保存'))
            .onPressed,
        isNull,
      );
    },
  );
}
