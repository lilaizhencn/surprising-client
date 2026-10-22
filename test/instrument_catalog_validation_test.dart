import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

Map<String, Object> _instrument(ProductMode product, {String id = '42'}) => {
  'instrumentId': id,
  'symbol': '${product.productLine}-USDT',
  'contractType': product.contractType,
  'instrumentType': product.isSpot
      ? 'SPOT'
      : product.isPerpetual
      ? 'PERPETUAL'
      : product.isDelivery
      ? 'DELIVERY'
      : 'OPTION',
  'productLine': product.productLine,
  'status': 'TRADING',
  'baseAsset': 'BTC',
  'quoteAsset': 'USDT',
  'settleAsset': 'USDT',
};

Future<ApiClient> _catalog(Object Function(Uri) page) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    request.response.write(
      jsonEncode(
        request.uri.path.endsWith('/asset-scales')
            ? {'BTC': '100000000', 'USDT': '1000000'}
            : page(request.uri),
      ),
    );
    await request.response.close();
  });
  final api = ApiClient(
    AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
  );
  addTearDown(() async {
    api.dispose();
    await server.close(force: true);
  });
  return api;
}

void main() {
  test(
    'all six products retain identity and authoritative asset scales',
    () async {
      final api = await _catalog(
        (_) => {
          'instruments': [
            for (final mode in ProductMode.values) _instrument(mode),
          ],
          'hasMore': false,
        },
      );
      final instruments = await api.instruments();
      expect(instruments.map((i) => i.mode), ProductMode.values);
      expect(
        instruments.every(
          (i) => i.instrumentId == '42' && i.quoteScaleUnits == 1000000,
        ),
        isTrue,
      );
    },
  );

  for (final rows in <Object?>[
    null,
    {},
    [null],
    ['invalid'],
    [_instrument(ProductMode.linear)..remove('contractType')],
    [_instrument(ProductMode.linear)..['productLine'] = 'SPOT'],
    [_instrument(ProductMode.linear)..['instrumentId'] = ''],
  ]) {
    test('invalid catalog is rejected atomically: $rows', () async {
      final api = await _catalog(
        (_) => {'instruments': rows, 'hasMore': false},
      );
      await expectLater(api.instruments(), throwsFormatException);
    });
  }

  test(
    'duplicate permanent identity across pages rejects the whole catalog',
    () async {
      final api = await _catalog(
        (uri) => {
          'instruments': [_instrument(ProductMode.spot)],
          'hasMore': !uri.queryParameters.containsKey('cursor'),
          'nextCursor': 'next',
        },
      );
      await expectLater(api.instruments(), throwsFormatException);
    },
  );

  test(
    'requested expiring product cannot accept another valid product',
    () async {
      final api = await _catalog(
        (_) => {
          'instruments': [_instrument(ProductMode.inverseDelivery)],
          'hasMore': false,
        },
      );
      await expectLater(
        api.expiringInstruments(ProductMode.linearDelivery),
        throwsFormatException,
      );
    },
  );
}
