import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'c2c_models.dart';
import 'models.dart';

/// The original business request survives an unknown response; codes are never stored.
class C2cTradeRequest {
  C2cTradeRequest(this.owner, this.kind, this.key, this.hash, this.body);
  final int owner;
  final String kind, key, hash;
  final Map<String, dynamic> body;
  static const storage = FlutterSecureStorage();
  static String storageKey(int owner) => 'c2c.trade.$owner';
  static Future<C2cTradeRequest?> load(int owner) async {
    final raw = await storage.read(key: storageKey(owner));
    if (raw == null) return null;
    final value = asMap(jsonDecode(raw));
    if (value['owner'] != '$owner' ||
        !['ORDER_CREATE', 'AD_PUBLISH'].contains(value['kind'])) {
      throw const FormatException('原交易请求归属或类型不完整');
    }
    return C2cTradeRequest(
      owner,
      asString(value['kind']),
      asString(value['key']),
      asString(value['hash']),
      asMap(value['body']),
    );
  }

  static Future<C2cTradeRequest> prepare(
    int owner,
    String kind,
    Map<String, dynamic> input,
  ) async {
    if (await load(owner) != null) throw StateError('请先查询原交易请求');
    if (!['ORDER_CREATE', 'AD_PUBLISH'].contains(kind) ||
        input.containsKey('verification')) {
      throw const FormatException('交易请求无效');
    }
    final key = c2cUuid();
    final identity = kind == 'ORDER_CREATE'
        ? asString(input['quoteId'])
        : jsonEncode(input['payload']);
    final hash = sha256.convert(utf8.encode(identity)).toString();
    final body = <String, dynamic>{'requestKey': key, ...input};
    await storage.write(
      key: storageKey(owner),
      value: jsonEncode({
        'owner': '$owner',
        'kind': kind,
        'key': key,
        'hash': hash,
        'body': body,
      }),
    );
    return C2cTradeRequest(owner, kind, key, hash, body);
  }

  static Future<void> clear(int owner) =>
      storage.delete(key: storageKey(owner));
}
