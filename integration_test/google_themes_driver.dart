import 'dart:io';
import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() => integrationDriver(
  onScreenshot: (name, image, [args]) async {
    final directory = Directory(
      Platform.environment['GOOGLE_THEMES_QA_DIR'] ??
          '/tmp/surprising-google-themes-native',
    );
    await directory.create(recursive: true);
    await File('${directory.path}/$name.png').writeAsBytes(image);
    return true;
  },
);
