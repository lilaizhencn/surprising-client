import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/affiliate/affiliate_page.dart';
import 'package:surprising_client/src/affiliate/affiliate_poster.dart';

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
    expect(
      affiliateRegistrationLink('https://ex.tokdou.com/', 'ABCD2345'),
      'https://ex.tokdou.com/auth/register?invite=ABCD2345',
    );
    expect(formatAffiliateRatePercent(30.0), '30');
    expect(formatAffiliateRatePercent(30.5), '30.5');
  });

  testWidgets('invitation poster card renders brand, code, rate, and UID', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: AffiliateInvitationPosterCard(
                inviteCode: 'ABCD2345',
                inviteLink: 'https://ex.tokdou.com/auth/register?invite=ABCD2345',
                rebateRatePercent: 40.0,
                userId: '10086',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('AETERN'), findsOneWidget);
    expect(find.text('ABCD2345'), findsOneWidget);
    expect(find.textContaining('最高 40% 手续费回馈'), findsOneWidget);
    expect(find.textContaining('邀请人 UID 10086'), findsOneWidget);
  });
}
