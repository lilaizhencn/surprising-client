import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const key = 'surprising.client.settings.v1';
  test(
    'new settings are empty and valid recovery strings are preserved',
    () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureClientSettingsStore();
      expect(await store.read(), isEmpty);
      final values = {
        'theme': 'light',
        'pendingTransfers': '[{"opaque":"receipt"}]',
      };
      FlutterSecureStorage.setMockInitialValues({key: jsonEncode(values)});
      expect(await store.read(), values);
    },
  );

  for (final raw in ['{', '[]', '{"pendingTransfers":[]}', '{"theme":true}']) {
    test(
      'malformed secure settings are rejected without replacing recovery data: $raw',
      () async {
        FlutterSecureStorage.setMockInitialValues({key: raw});
        final store = SecureClientSettingsStore();
        await expectLater(store.read(), throwsFormatException);
        expect(await const FlutterSecureStorage().read(key: key), raw);
      },
    );
  }
}
