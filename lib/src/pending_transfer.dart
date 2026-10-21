import 'dart:convert';
import 'dart:math';

import 'models.dart';

/// The original command is immutable; recovery always uses the same identity.
class PendingAccountTransfer {
  PendingAccountTransfer({
    required this.userId,
    required this.key,
    required this.source,
    required this.target,
    required this.asset,
    required this.amountUnits,
    this.status = 'UNKNOWN',
  });

  factory PendingAccountTransfer.create({
    required int userId,
    required String source,
    required String target,
    required String asset,
    required int amountUnits,
  }) {
    final random = Random.secure();
    return PendingAccountTransfer(
      userId: userId,
      key:
          'app-transfer-$userId-${base64UrlEncode(List.generate(18, (_) => random.nextInt(256))).replaceAll('=', '')}',
      source: source,
      target: target,
      asset: asset,
      amountUnits: amountUnits,
    );
  }

  final int userId;
  final String key, source, target, asset;
  final int amountUnits;
  final String status;

  PendingAccountTransfer withStatus(String next) => PendingAccountTransfer(
    userId: userId,
    key: key,
    source: source,
    target: target,
    asset: asset,
    amountUnits: amountUnits,
    status: next,
  );

  Map<String, dynamic> toJson() => {
    'userId': userId,
    'key': key,
    'source': source,
    'target': target,
    'asset': asset,
    'amountUnits': '$amountUnits',
    'status': status,
  };

  factory PendingAccountTransfer.fromJson(Map<String, dynamic> value) {
    final userId = int.tryParse(asString(value['userId'])) ?? 0;
    final key = asString(value['key']);
    final source = asString(value['source']),
        target = asString(value['target']);
    final asset = asString(value['asset']);
    final amount = int.tryParse(asString(value['amountUnits']));
    final status = asString(value['status']);
    if (userId <= 0 ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(key) ||
        !productAccountTypes.contains(source) ||
        !productAccountTypes.contains(target) ||
        source == target ||
        !RegExp(r'^[A-Z0-9]{1,20}$').hasMatch(asset) ||
        amount == null ||
        amount <= 0 ||
        !const {
          'UNKNOWN',
          'PENDING',
          'SOURCE_DEBITED',
          'FAILED',
          'VERIFY',
        }.contains(status)) {
      throw const FormatException('无法读取原划转凭证');
    }
    return PendingAccountTransfer(
      userId: userId,
      key: key,
      source: source,
      target: target,
      asset: asset,
      amountUnits: amount,
      status: status,
    );
  }
}
