import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

void main() {
  test(
    'funding balances, records and address use the same authoritative APIs as Web',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>[];
      final subscription = server.listen((request) async {
        paths.add(request.uri.path);
        Object response;
        if (request.uri.path.endsWith('/asset-scales')) {
          response = {'USDT': '1000000'};
        } else if (request.uri.path.endsWith('/balances')) {
          response = {
            'balances': [
              {
                'asset': 'USDT',
                'availableUnits': '1234567',
                'lockedUnits': '1',
              },
            ],
          };
        } else if (request.uri.path.endsWith('/deposit-address')) {
          expect(request.method, 'POST');
          expect(jsonDecode(await utf8.decoder.bind(request).join()), {
            'asset': 'USDT',
            'network': 'ETH',
          });
          response = {
            'asset': 'USDT',
            'network': 'ETH',
            'address': '0x-real-address',
            'memo': '',
          };
        } else {
          response = [];
        }
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(response));
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
      );
      final portfolio = await api.walletPortfolio(1);
      expect(portfolio.assets.single.availableBalance, 1.234567);
      expect(portfolio.assets.single.totalBalance, 1.234568);
      await api.walletOrders(1);
      final address = await api.walletDepositAddress(
        1,
        chain: 'ETH',
        symbol: 'USDT',
      );
      expect(address.address, '0x-real-address');
      expect(address.chain, 'ETH');
      expect(paths.any((path) => path.contains('/wallet/app/')), false);
    },
  );

  test(
    'external transfers merge both histories and preserve direction and time order',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final subscription = server.listen((request) async {
        final withdrawal = request.uri.path.endsWith('/withdrawals');
        expect(request.uri.queryParameters['asset'], 'BTC');
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode([
            {
              'asset': 'BTC',
              'createdAt': withdrawal
                  ? '2026-10-09T10:00:00Z'
                  : '2026-10-09T09:00:00Z',
            },
          ]),
        );
        await request.response.close();
      });
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
      );
      final records = await api.accountRecords(
        category: 'external-transfer',
        userId: 1,
        product: ProductMode.spot,
        asset: 'btc',
      );
      expect(records.rows.map((row) => row['referenceType']).toList(), [
        'WITHDRAWAL',
        'DEPOSIT',
      ]);
      expect(records.hasMore, false);
    },
  );
  test(
    'all six product record queries send the correct product and account scope',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <HttpRequest>[];
      final subscription = server.listen((request) async {
        requests.add(request);
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({'entries': [], 'transfers': [], 'orders': []}),
        );
        await request.response.close();
      });
      final api = ApiClient(
        AppConfig(gatewayBaseUrl: 'http://127.0.0.1:${server.port}'),
      );
      addTearDown(() async {
        await subscription.cancel();
        await server.close(force: true);
      });
      for (final product in ProductMode.values) {
        await api.accountRecords(
          category: 'product-ledger',
          userId: 1,
          product: product,
          asset: 'usdt',
        );
        expect(
          requests.last.headers.value('X-Product-Line'),
          product.productLine,
        );
        expect(
          requests.last.uri.queryParameters['accountType'],
          product.accountType,
        );
        expect(requests.last.uri.queryParameters['asset'], 'USDT');
        await api.accountRecords(
          category: 'order',
          userId: 1,
          product: product,
          instrumentId: '604',
        );
        expect(requests.last.uri.queryParameters['instrumentId'], '604');
        expect(
          requests.last.headers.value('X-Product-Line'),
          product.productLine,
        );
      }
    },
  );
}
