import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/i18n/client_messages.dart';
import 'package:surprising_client/src/i18n/messages.g.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  test(
    'every supported language has complete labels and matching placeholders',
    () {
      final parameters = RegExp(r'\{[A-Za-z_][A-Za-z0-9_]*\}');
      Set<String> tokens(String text) =>
          parameters.allMatches(text).map((item) => item[0]!).toSet();
      expect(
        clientMessageCatalogs.keys.toSet(),
        ClientLanguage.values.map((language) => language.code).toSet(),
      );
      for (final language in ClientLanguage.values) {
        final messages = clientMessageCatalogs[language.code]!;
        expect(messages.keys.toSet(), clientSourceMessages);
        for (final key in clientSourceMessages) {
          expect(
            messages[key]!.trim(),
            isNotEmpty,
            reason: '${language.code}/$key',
          );
          expect(
            tokens(messages[key]!),
            tokens(key),
            reason: '${language.code}/$key',
          );
        }
      }
    },
  );
  test('labels translate while arbitrary user data remains exact', () {
    expect(translateClientLabel('游客', 'en'), 'Guest');
    expect(translateClientLabel('用户自定义名字_ABC', 'ar'), '用户自定义名字_ABC');
    expect(translateClientLabel('价格', 'ja'), '価格');
    expect(
      translateClientLabel('请阅读并确认更新后的协议以继续登录', 'hi'),
      contains('समझौतों'),
    );
  });
}
