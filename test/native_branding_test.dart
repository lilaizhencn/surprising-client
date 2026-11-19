import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'Android launcher name is AETERN without changing application identity',
    () {
      expect(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android:label="AETERN"'),
      );
      expect(
        File('android/app/build.gradle.kts').readAsStringSync(),
        contains('applicationId = "com.surprising.surprising_client"'),
      );
    },
  );

  test('iOS launcher name is AETERN without changing bundle identity', () {
    expect(
      File('ios/Runner/Info.plist').readAsStringSync(),
      matches(
        RegExp(r'<key>CFBundleDisplayName</key>\s*<string>AETERN</string>'),
      ),
    );
    expect(
      File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync(),
      contains('PRODUCT_BUNDLE_IDENTIFIER = com.surprising.surprisingClient;'),
    );
  });
}
