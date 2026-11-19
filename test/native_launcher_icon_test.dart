import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

void expectPng(String path, int size, int colorType) {
  final bytes = File(path).readAsBytesSync();
  expect(bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10], reason: path);
  final data = bytes.buffer.asByteData();
  expect(data.getUint32(16, Endian.big), size, reason: path);
  expect(data.getUint32(20, Endian.big), size, reason: path);
  expect(bytes[25], colorType, reason: path);
}

void main() {
  test(
    'every referenced iOS launcher is correctly sized RGB without alpha',
    () {
      const folder = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final entries =
          jsonDecode(File('$folder/Contents.json').readAsStringSync())['images']
              as List;
      for (final entry in entries) {
        final size =
            (double.parse((entry['size'] as String).split('x').first) *
                    double.parse(
                      (entry['scale'] as String).replaceAll('x', ''),
                    ))
                .toInt();
        expectPng('$folder/${entry['filename']}', size, 2);
      }
    },
  );

  test('Android launcher supports adaptive masks and all raster densities', () {
    const root = 'android/app/src/main/res';
    const dimensions = {
      'mdpi': [48, 108],
      'hdpi': [72, 162],
      'xhdpi': [96, 216],
      'xxhdpi': [144, 324],
      'xxxhdpi': [192, 432],
    };
    for (final entry in dimensions.entries) {
      final base = '$root/mipmap-${entry.key}';
      expectPng('$base/ic_launcher.png', entry.value[0], 2);
      expectPng('$base/ic_launcher_round.png', entry.value[0], 2);
      expectPng('$base/ic_launcher_foreground.png', entry.value[1], 6);
    }
    for (final file in ['ic_launcher.xml', 'ic_launcher_round.xml']) {
      final xml = File('$root/mipmap-anydpi-v26/$file').readAsStringSync();
      expect(xml, contains('<adaptive-icon'));
      expect(xml, contains('@color/aetern_launcher_background'));
      expect(xml, contains('@mipmap/ic_launcher_foreground'));
    }
    expect(
      File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      contains('android:roundIcon="@mipmap/ic_launcher_round"'),
    );
  });
}
