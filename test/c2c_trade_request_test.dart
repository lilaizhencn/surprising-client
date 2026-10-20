import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/c2c_trade_request.dart';
import 'package:surprising_client/src/c2c_models.dart';

void main() {
  test('display keeps exact nonzero decimal digits and integer zeroes', () {
    expect(c2cDecimal('1000'), '1000');
    expect(c2cDecimal('6.650000000000000000'), '6.65');
    expect(c2cDecimal('92233720368.5477580700'), '92233720368.54775807');
    expect(c2cDecimal('0.0000000100'), '0.00000001');
  });
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test(
    'original order is stored before sending and survives a lost response',
    () async {
      final request = await C2cTradeRequest.prepare(12, 'ORDER_CREATE', {
        'quoteId': 'abc',
      });
      expect(
        request.hash,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      final restored = await C2cTradeRequest.load(12);
      expect(restored!.key, request.key);
      expect(restored.body, {'requestKey': request.key, 'quoteId': 'abc'});
      await expectLater(
        C2cTradeRequest.prepare(12, 'ORDER_CREATE', {'quoteId': 'other'}),
        throwsStateError,
      );
    },
  );
  test(
    'new account cannot load or clear the previous account request',
    () async {
      final original = await C2cTradeRequest.prepare(12, 'ORDER_CREATE', {
        'quoteId': 'original',
      });
      expect(await C2cTradeRequest.load(13), isNull);
      await C2cTradeRequest.clear(13);
      expect((await C2cTradeRequest.load(12))!.key, original.key);
    },
  );
  test('verification secrets cannot enter durable trade recovery', () async {
    await expectLater(
      C2cTradeRequest.prepare(12, 'ORDER_CREATE', {
        'quoteId': 'abc',
        'verification': {'emailCode': '123456'},
      }),
      throwsFormatException,
    );
    expect(await C2cTradeRequest.load(12), isNull);
  });
}
