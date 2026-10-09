import 'models.dart';

class AccountRecordPage {
  const AccountRecordPage(this.rows, this.nextCursor, this.hasMore);
  final List<Map<String, dynamic>> rows;
  final String? nextCursor;
  final bool hasMore;
  factory AccountRecordPage.fromJson(Object? json, String key) {
    final map = asMap(json);
    final cursor = asString(map['nextCursor']);
    return AccountRecordPage(
      asList(
        json is List ? json : map[key] ?? map['items'],
      ).map(asMap).toList(),
      cursor.isEmpty ? null : cursor,
      map['hasMore'] == true && cursor.isNotEmpty,
    );
  }
}

/// Parse money without a floating point intermediate or silent rounding.
int exactAmountUnits(String amount, String scale) {
  final value = amount.trim();
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(value)) {
    throw const FormatException('请输入正确的划转数量');
  }
  final multiplier = BigInt.tryParse(scale);
  if (multiplier == null || multiplier <= BigInt.zero) {
    throw const FormatException('币种精度尚未同步，请刷新后重试');
  }
  final parts = value.split('.');
  final fractional = parts.length == 2 ? parts[1] : '';
  final divisor = BigInt.from(10).pow(fractional.length);
  final scaled = BigInt.parse(parts.join()) * multiplier;
  if (scaled.remainder(divisor) != BigInt.zero) {
    throw const FormatException('数量超过该币种允许的精度');
  }
  final units = scaled ~/ divisor;
  if (units <= BigInt.zero || units > BigInt.parse('9223372036854775807')) {
    throw const FormatException('划转数量必须大于零且不超过允许范围');
  }
  return units.toInt();
}

String formatAccountUnits(Object? units, String? scale) {
  final integer = BigInt.tryParse('$units');
  final multiplier = BigInt.tryParse(scale ?? '');
  if (integer == null || multiplier == null || multiplier <= BigInt.zero) {
    return '—';
  }
  final digits = multiplier.toString();
  if (!RegExp(r'^10*$').hasMatch(digits)) return '—';
  final decimals = digits.length - 1;
  if (decimals == 0) return '$integer';
  final value = integer.abs().toString().padLeft(decimals + 1, '0');
  final whole = value.substring(0, value.length - decimals);
  final fraction = value
      .substring(value.length - decimals)
      .replaceFirst(RegExp(r'0+$'), '');
  return '${integer.isNegative ? '-' : ''}$whole${fraction.isEmpty ? '' : '.$fraction'}';
}
