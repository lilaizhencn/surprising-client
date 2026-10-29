const kycStatuses = {
  'UNVERIFIED',
  'PENDING',
  'VERIFIED',
  'REJECTED',
  'EXPIRED',
};

bool kycExpired(Map<String, dynamic> profile, [DateTime? now]) {
  if (profile['status'] == 'EXPIRED') return true;
  final expiry = DateTime.tryParse('${profile['expiresAt'] ?? ''}');
  return profile['status'] == 'VERIFIED' &&
      expiry != null &&
      !expiry.isAfter(now ?? DateTime.now());
}

String kycStatusLabel(Map<String, dynamic> profile) {
  if (kycExpired(profile)) return '已过期，请重新认证';
  return const {
        'UNVERIFIED': '未认证',
        'PENDING': '审核中',
        'VERIFIED': '已通过',
        'REJECTED': '未通过，请补正材料',
        'EXPIRED': '已过期',
      }[profile['status']] ??
      (profile.isEmpty ? '未提交' : '状态暂不可用');
}
