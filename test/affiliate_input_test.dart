import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/affiliate/affiliate_page.dart';

void main() {
  test(
    'commission display preserves large asset scales without floating point',
    () {
      expect(
        scaledAmount(
          BigInt.parse('123456789012345678901234567890123456'),
          '1000000000000000000000000000000000000',
        ),
        '0.123456789012345678901234567890123456',
      );
      expect(scaledAmount(BigInt.from(2000000), 1000000), '2');
    },
  );
  test(
    'shares preserve four decimal places and reject invalid percentages',
    () {
      expect(affiliatePercent('20'), 200000);
      expect(affiliatePercent('60.0001'), 600001);
      expect(affiliatePercent('100'), 1000000);
      for (final invalid in ['-1', '100.0001', '2e1', 'NaN', '20.00001']) {
        expect(() => affiliatePercent(invalid), throwsFormatException);
      }
    },
  );
  test('web and native links identify the same invitation code', () {
    const code = 'ABCDEF0123456789ABCDEF0123456789';
    expect(affiliateCode('https://ex.tokdou.com/affiliate?invite=$code'), code);
    expect(affiliateCode('surprising://affiliate?invite=$code'), code);
    expect(affiliateCode(code.toLowerCase()), code);
  });
}
