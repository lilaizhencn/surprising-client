import '../i18n/client_messages.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../app_scope.dart';
import '../api.dart' show clientErrorMessage;
import '../app_state.dart';
import '../auth/auth_sheet.dart';
import '../models.dart';
import '../ui/client_components.dart';
import 'affiliate_poster.dart';

const affiliateProducts = [
  'SPOT',
  'LINEAR_PERPETUAL',
  'INVERSE_PERPETUAL',
  'LINEAR_DELIVERY',
  'INVERSE_DELIVERY',
  'OPTION',
];
String affiliateCode(String text) {
  final uri = Uri.tryParse(text.trim());
  return (uri?.queryParameters['invite'] ?? text.trim()).toUpperCase();
}

int affiliatePercent(String text) {
  if (!RegExp(r'^\d{1,3}(\.\d{1,4})?$').hasMatch(text.trim())) {
    throw const FormatException('请输入 0–100%，最多四位小数');
  }
  final parts = text.trim().split('.');
  final value =
      int.parse(parts.first) * 10000 +
      int.parse((parts.length == 1 ? '' : parts[1]).padRight(4, '0'));
  if (value > 1000000) throw const FormatException('分配比例不能超过 100%');
  return value;
}

String _amount(Map<String, dynamic> row, String key) {
  final value = row[key];
  if (value is! String || !RegExp(r'^\d+$').hasMatch(value)) {
    throw FormatException('佣金字段 $key 不完整');
  }
  return value;
}

String _status(Object? value) => switch (value) {
  'PAID' => '已到账',
  'UNKNOWN' => '到账确认中',
  'PENDING' => '待发放',
  'REJECTED' => '发放被拒绝，待平台处理',
  _ => '待结算',
};

class AffiliatePage extends StatefulWidget {
  const AffiliatePage({super.key, this.invitation});
  final String? invitation;
  @override
  State<AffiliatePage> createState() => _AffiliatePageState();
}

class _AffiliatePageState extends State<AffiliatePage> {
  final code = TextEditingController();
  final target = TextEditingController();
  final share = TextEditingController(text: '50');
  AppState? app;
  int? owner;
  Map<String, dynamic>? data, preview, selected, created;
  Map<String, String> scales = {};
  List<Map<String, dynamic>> members = [], entries = [], payouts = [];
  String subject = '', line = '', memberCursor = '0', entryCursor = '0';
  String queryScope = '';
  String? memberNext, entryNext, error, notice;
  String copiedKey = '';
  bool loading = false, busy = false, initialized = false, kolEnabled = false;
  int generation = 0;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = AppScope.of(context);
    app = state;
    if (initialized && owner == state.loginUserId) return;
    initialized = true;
    owner = state.loginUserId;
    kolEnabled = false;
    subject = '';
    selected = null;
    created = null;
    target.clear();
    share.text = '50';
    data = null;
    members = [];
    entries = [];
    payouts = [];
    code.text = widget.invitation ?? state.pendingInvitationCode ?? '';
    unawaited(load());
    if (code.text.isNotEmpty) unawaited(checkInvitation());
  }

  @override
  void dispose() {
    generation++;
    code.dispose();
    target.dispose();
    share.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (owner == null) return;
    final current = ++generation;
    final state = app!;
    final user = owner;
    setState(() {
      loading = true;
      error = null;
      final scope = '$owner:$subject:$line';
      if (queryScope != scope) {
        data = null;
        queryScope = scope;
      }
    });
    try {
      final self = await state.api.get(
        '/api/v1/affiliate/me',
        query: {'productLine': line},
      );
      if (!mounted || current != generation || state.loginUserId != user) return;
      final ownProfile = asMap(self['profile']);
      if (ownProfile['userId'] != '$user' ||
          ownProfile['kolEnabled'] is! bool) {
        throw const FormatException('邀请资料与当前用户不匹配');
      }
      final enabled = ownProfile['kolEnabled'] == true;
      final branch = enabled && subject.isNotEmpty && subject != '$user'
          ? subject
          : '';
      final values = await Future.wait([
        branch.isEmpty
            ? Future.value(self)
            : state.api.get(
                '/api/v1/affiliate/members/$branch',
                query: {'productLine': line},
              ),
        state.api.get(
          '/api/v1/affiliate/members',
          query: {
            'cursor': !enabled && subject.isNotEmpty ? '0' : memberCursor,
            if (branch.isNotEmpty) 'parentId': branch,
          },
        ),
        state.api.get(
          '/api/v1/affiliate/entries',
          query: {'cursor': entryCursor, 'productLine': line},
        ),
        state.api.get('/api/v1/affiliate/payouts'),
        state.api.assetScales(),
      ]);
      if (!mounted || current != generation || state.loginUserId != user) return;
      final overview = values[0];
      final profile = asMap(overview['profile']);
      final counts = asMap(overview['counts']);
      if (profile['userId'] is! String ||
          profile['inviteCode'] is! String ||
          profile['kolEnabled'] is! bool ||
          overview['balances'] is! List ||
          overview['invitations'] is! List) {
        throw const FormatException('邀请资料响应不完整');
      }
      _amount(counts, 'directInviteCount');
      _amount(counts, 'teamInviteCount');
      for (final value in asList(overview['balances'])) {
        final row = asMap(value);
        for (final field in [
          'receivedUnits',
          'delegatedUnits',
          'retainedUnits',
          'pendingUnits',
          'paidUnits',
          'inFlightUnits',
          'teamFeeUnits',
          'directFeeUnits',
        ]) {
          _amount(row, field);
        }
      }
      if (values.skip(1).take(3).any((value) => value['items'] is! List)) {
        throw const FormatException('邀请列表响应不完整');
      }
      final assetScales = Map<String, String>.from(values[4]);
      for (final row in [
        ...asList(overview['balances']),
        ...asList(values[2]['items']),
        ...asList(values[3]['items']),
        ...asList(
          values[1]['items'],
        ).expand((value) => asList(asMap(value)['contributions'])),
      ].map(asMap)) {
        final asset = asString(row['asset']);
        if (!RegExp(r'^10*$').hasMatch(assetScales[asset] ?? '')) {
          throw FormatException('币种 $asset 精度尚未就绪，请刷新重试');
        }
      }
      for (final value in asList(values[2]['items'])) {
        _amount(asMap(value), 'retainedUnits');
      }
      for (final value in asList(values[3]['items'])) {
        _amount(asMap(value), 'amountUnits');
      }
      for (final member in asList(values[1]['items']).map(asMap)) {
        if (member['contributions'] is! List) {
          throw const FormatException('成员贡献响应不完整');
        }
        for (final row in asList(member['contributions']).map(asMap)) {
          for (final field in ['feeUnits', 'receivedUnits', 'retainedUnits']) {
            _amount(row, field);
          }
        }
      }
      setState(() {
        scales = assetScales;
        kolEnabled = enabled;
        if (!enabled) {
          if (subject.isNotEmpty) memberCursor = '0';
          subject = '';
          selected = null;
          created = null;
          target.clear();
          share.text = '50';
        }
        data = overview;
        members = asList(values[1]['items']).map(asMap).toList();
        memberNext = nullableString(values[1]['nextCursor']);
        entries = asList(values[2]['items']).map(asMap).toList();
        entryNext = nullableString(values[2]['nextCursor']);
        payouts = asList(values[3]['items']).map(asMap).toList();
      });
    } catch (failure) {
      if (mounted && current == generation) {
        setState(() {
          error = clientErrorMessage(failure);
          kolEnabled = false;
          data = null;
          members = [];
          selected = null;
          created = null;
          target.clear();
          share.text = '50';
        });
      }
    } finally {
      if (mounted && current == generation) setState(() => loading = false);
    }
  }

  Future<void> checkInvitation() async {
    final value = affiliateCode(code.text);
    if (value.isEmpty) {
      setState(() => preview = null);
      return;
    }
    setState(() {
      preview = null;
      error = null;
    });
    try {
      final response = await app!.api.get(
        '/api/v1/affiliate/preview',
        query: {'code': value},
      );
      if (mounted && affiliateCode(code.text) == value) {
        setState(() => preview = response);
        if (owner == null) {
          app!.pendingInvitationCode = response['cooperation'] == true
              ? null
              : value;
        }
      }
    } catch (failure) {
      if (mounted && affiliateCode(code.text) == value) {
        setState(() => error = clientErrorMessage(failure));
      }
    }
  }

  Future<void> act(Future<void> Function() operation, String message) async {
    if (busy) return;
    final user = owner;
    setState(() {
      busy = true;
      error = null;
      notice = null;
    });
    try {
      await operation();
      if (!mounted || app!.userId != user) return;
      setState(() => notice = message);
      showFeedback(message);
      await load();
    } catch (failure) {
      if (mounted && app!.userId == user) {
        final message = clientErrorMessage(failure);
        setState(() => error = message);
        showFeedback(message);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> copy(
    String value, {
    String label = '邀请链接已复制',
    String key = '',
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    setState(() {
      notice = label;
      if (key.isNotEmpty) copiedKey = key;
    });
    showFeedback(label);
    if (key.isNotEmpty) {
      Future<void>.delayed(const Duration(milliseconds: 1800), () {
        if (mounted && copiedKey == key) {
          setState(() => copiedKey = '');
        }
      });
    }
  }

  void showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: LText(message)));
  }

  Widget _buildHeroSection(
    AppState state,
    Map<String, dynamic> profile,
    Map<String, dynamic> counts,
    bool own,
  ) {
    final inviteCode = asString(profile['inviteCode']);
    final userId = asString(profile['userId']);
    final exclusiveLink = inviteCode.isEmpty
        ? ''
        : affiliateRegistrationLink(
            state.api.config.publicWebBaseUrl,
            inviteCode,
          );
    final rebateRatePercent =
        requireInt64(data!['rootRatePpm'], 'rootRatePpm') / 10000.0;
    final rateLabel = formatAffiliateRatePercent(rebateRatePercent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0x1CF5C451), Color(0x0A1E293B)],
          ),
          border: Border.all(color: const Color(0x3DF5C451)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0x24F5C451),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: const Color(0x59F5C451)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.auto_awesome,
                              size: 13,
                              color: Color(0xFFF5C451),
                            ),
                            const SizedBox(width: 5),
                            LText(
                              own
                                  ? (kolEnabled ? 'KOL 专属推广名片' : '我的专属邀请权益')
                                  : '成员 UID $userId',
                              style: const TextStyle(
                                color: Color(0xFFF5C451),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      LText(
                        own ? '邀请好友交易，共享返佣红利' : '成员 UID $userId 推广概览',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
                if (!own)
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        subject = '';
                        memberCursor = '0';
                        selected = null;
                      });
                      unawaited(load());
                    },
                    child: const LText('返回我的团队'),
                  ),
              ],
            ),
            if (own && inviteCode.isNotEmpty) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _copyPill(
                          label: '专属短邀请码',
                          value: inviteCode,
                          highlight: true,
                          copied: copiedKey == 'code',
                          onTap: () => copy(
                            inviteCode,
                            label: '邀请码已复制',
                            key: 'code',
                          ),
                        ),
                        const SizedBox(height: 10),
                        _copyPill(
                          label: '专属注册链接',
                          value: exclusiveLink,
                          highlight: false,
                          copied: copiedKey == 'link',
                          onTap: () => copy(
                            exclusiveLink,
                            label: '专属注册链接已复制',
                            key: 'link',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => showAffiliatePosterDialog(
                      context,
                      inviteCode: inviteCode,
                      inviteLink: exclusiveLink,
                      rebateRatePercent: rebateRatePercent,
                      userId: userId,
                      onCopy: (text, label) => copy(text, label: label),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: QrImageView(
                        data: exclusiveLink,
                        size: 92,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF0A0D1A),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF0A0D1A),
                        ),
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => showAffiliatePosterDialog(
                        context,
                        inviteCode: inviteCode,
                        inviteLink: exclusiveLink,
                        rebateRatePercent: rebateRatePercent,
                        userId: userId,
                        onCopy: (text, label) => copy(text, label: label),
                      ),
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const LText('专属邀请函与海报'),
                    ),
                  ),
                ],
              ),
              if (!kolEnabled && data!['teamActive'] == false) ...[
                const SizedBox(height: 8),
                const LText('当前邀请返佣已暂停，历史记录保留。'),
              ],
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _kpiTile(
                  kolEnabled ? '平台顶层比例' : '邀请返佣比例',
                  '$rateLabel%',
                ),
                _kpiTile('直接邀请', '${counts['directInviteCount']}'),
                if (kolEnabled)
                  _kpiTile('团队邀请', '${counts['teamInviteCount']}'),
                _kpiTile(
                  '结算状态',
                  profile['autoSettlement'] == true ? '自动结算' : '手动结算',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _copyPill({
    required String label,
    required String value,
    required bool highlight,
    required bool copied,
    required VoidCallback onTap,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LText(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          height: 38,
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: highlight ? 15 : 12,
                    fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
                    letterSpacing: highlight ? 1.2 : 0,
                    color: highlight ? const Color(0xFFF5C451) : null,
                  ),
                ),
              ),
              TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 28),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onTap,
                icon: Icon(copied ? Icons.check : Icons.copy, size: 14),
                label: LText(
                  copied ? '已复制' : '复制',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _kpiTile(String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 112),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAcceptInvitationSection(AppState state) => section('接受邀请', [
    field('邀请码或邀请链接', code),
    OutlinedButton(
      onPressed: busy ? null : checkInvitation,
      child: const LText('查看邀请'),
    ),
    if (preview != null) ...[
      const SizedBox(height: 8),
      LText('邀请人 UID ${preview!['inviterId']}'),
      LText(
        preview!['cooperation'] == true && !kolEnabled
            ? '该邀请暂不可用，请联系邀请人。'
            : preview!['cooperation'] == true
            ? '团队合作：你获得对应上级佣金的 ${requireInt64(preview!['sharePpm'], 'sharePpm') / 10000}%。加入后，本人交易不向团队上级返佣。'
            : '普通邀请：接受后，符合条件的交易手续费自动进入邀请核算。',
      ),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: busy || (preview!['cooperation'] == true && !kolEnabled)
            ? null
            : () => owner == null
                  ? showAuthSheet(context)
                  : act(() async {
                      await state.api.post('/api/v1/affiliate/accept', {
                        'code': affiliateCode(code.text),
                      });
                      state.pendingInvitationCode = null;
                      code.clear();
                      preview = null;
                    }, '邀请已接受'),
        child: LText(owner == null ? '登录或注册后接受' : '确认接受邀请'),
      ),
    ],
  ]);

  Widget section(String title, List<Widget> children) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Panel(
      padding: const EdgeInsets.all(16),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    ),
  );
  Widget field(
    String label,
    TextEditingController controller, {
    bool numeric = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      enabled: !busy,
      keyboardType: numeric
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context);
    final profile = asMap(data?['profile']);
    final counts = asMap(data?['counts']);
    final own = !kolEnabled || subject.isEmpty || subject == '$owner';
    return Scaffold(
      appBar: AppBar(
        title: LText(kolEnabled ? '邀请与合作' : '邀请返佣'),
        actions: [
          IconButton(
            tooltip: clientLabel(context, '刷新'),
            onPressed: loading ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(16),
            children: [
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LText(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              if (notice != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LText(notice!),
                ),
              if (owner == null) ...[
                _buildAcceptInvitationSection(state),
                const LText('每位注册用户都可邀请好友。登录后查看专属短邀请码、注册链接、邀请函及返佣明细。'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => showAuthSheet(context),
                  child: const LText('登录 / 注册'),
                ),
              ] else if (loading && data == null)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                )
              else if (data != null) ...[
                _buildHeroSection(state, profile, counts, own),
                _buildAcceptInvitationSection(state),
                if (kolEnabled)
                  section('当前合作分配', [
                    LText(
                      '平台顶层比例 ${requireInt64(data!['rootRatePpm'], 'rootRatePpm') / 10000}%。下级从所属分支的上级佣金中获得约定份额。',
                    ),
                    if (data!['teamActive'] == false)
                      const LText('顶层团队已暂停，新团队佣金暂不分配，历史记录保留。'),
                    if (asList(data!['teamPath']).isNotEmpty)
                      ExpansionTile(
                        title: LText(
                          '查看合作路径（${asList(data!['teamPath']).length} 层）',
                        ),
                        children: [
                          for (final value in asList(data!['teamPath']))
                            LText(
                              'UID ${asMap(value)['parentId']} → UID ${asMap(value)['childId']}：上级额度的 ${requireInt64(asMap(value)['sharePpm'], 'sharePpm') / 10000}%',
                            ),
                        ],
                      ),
                  ]),
                section(kolEnabled ? '贡献与佣金' : '我的返佣', [
                  DropdownButtonFormField<String>(
                    initialValue: line,
                    decoration: InputDecoration(
                      labelText: clientLabel(context, '产品线'),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: LText('全部产品，分别展示'),
                      ),
                      ...affiliateProducts.map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        line = value ?? '';
                        entryCursor = '0';
                      });
                      unawaited(load());
                    },
                  ),
                  LText(
                    kolEnabled
                        ? '收益按产品与币种分别展示。获得额度包含下级份额，可结算的是本人留存。'
                        : '返佣按产品与币种分别展示，包含历史记录；待结算和到账确认中的金额尚未到账。',
                  ),
                  if (asList(data!['balances']).isEmpty)
                    const LText('暂无已确认佣金，产生合格手续费后自动更新。'),
                  for (final value in asList(data!['balances'])) ...[
                    const Divider(),
                    Text(
                      '${asMap(value)['productLine']} / ${asMap(value)['asset']}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    for (final entry in {
                      if (kolEnabled) ...{
                        '团队费用贡献': 'teamFeeUnits',
                        '直接费用贡献': 'directFeeUnits',
                        '获得额度': 'receivedUnits',
                        '下级分配': 'delegatedUnits',
                        '本人留存': 'retainedUnits',
                      } else
                        '累计返佣': 'retainedUnits',
                      '待结算': 'pendingUnits',
                      '在途': 'inFlightUnits',
                      '已到账': 'paidUnits',
                    }.entries)
                      Text(
                        '${entry.key}：${scaledAmount(BigInt.parse(_amount(asMap(value), entry.value)), scales[asString(asMap(value)['asset'])])} ${asMap(value)['asset']}',
                      ),
                  ],
                ]),
                section(kolEnabled ? '邀请用户与团队成员' : '我邀请的好友', [
                  if (members.isEmpty)
                    LText(kolEnabled ? '该分支还没有邀请用户。' : '你还没有邀请好友。'),
                  for (final member in members)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText(
                            kolEnabled
                                ? 'UID ${member['userId']} · 直接邀请 ${member['directInviteCount']} 人'
                                : 'UID ${member['userId']}',
                          ),
                          LText('邀请时间：${member['acceptedAt']}'),
                          if (kolEnabled)
                            LText(
                              member['teamParentId'] == null
                                  ? '普通邀请用户'
                                  : '团队下级 · 分配 ${requireInt64(member['sharePpm'], 'sharePpm') / 10000}%',
                            ),
                          if (asList(member['contributions']).isEmpty)
                            LText(kolEnabled ? '暂无交易贡献' : '暂无已确认返佣'),
                          for (final value in asList(member['contributions']))
                            LText(
                              kolEnabled
                                  ? '${asMap(value)['productLine']} / ${asMap(value)['asset']}：手续费 ${scaledAmount(BigInt.parse(_amount(asMap(value), 'feeUnits')), scales[asString(asMap(value)['asset'])])} · 获得 ${scaledAmount(BigInt.parse(_amount(asMap(value), 'receivedUnits')), scales[asString(asMap(value)['asset'])])} · 留存 ${scaledAmount(BigInt.parse(_amount(asMap(value), 'retainedUnits')), scales[asString(asMap(value)['asset'])])}'
                                  : '${asMap(value)['productLine']} / ${asMap(value)['asset']} · 为我产生的返佣 ${scaledAmount(BigInt.parse(_amount(asMap(value), 'retainedUnits')), scales[asString(asMap(value)['asset'])])}',
                            ),
                          Wrap(
                            spacing: 8,
                            children: [
                              if (kolEnabled && member['teamParentId'] != null)
                                OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      subject = member['userId'].toString();
                                      memberCursor = '0';
                                      selected = null;
                                    });
                                    unawaited(load());
                                  },
                                  child: const LText('查看贡献'),
                                ),
                              if (own && kolEnabled)
                                OutlinedButton(
                                  onPressed: () => setState(() {
                                    selected = member;
                                    target.text = member['userId'].toString();
                                    share.text = member['sharePpm'] == null
                                        ? '50'
                                        : '${requireInt64(member['sharePpm'], 'sharePpm') / 10000}';
                                  }),
                                  child: LText(
                                    member['teamParentId'] == null
                                        ? '邀请成为下级'
                                        : '调整比例',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: memberCursor == '0'
                            ? null
                            : () {
                                setState(() => memberCursor = '0');
                                unawaited(load());
                              },
                        child: const LText('首页'),
                      ),
                      OutlinedButton(
                        onPressed: memberNext == null
                            ? null
                            : () {
                                setState(() => memberCursor = memberNext!);
                                unawaited(load());
                              },
                        child: const LText('下一页'),
                      ),
                    ],
                  ),
                ]),
                if (own && kolEnabled)
                  section('KOL 合作管理', [
                    field('合作用户 UID（留空生成链接）', target, numeric: true),
                    field('下级获得上级佣金的比例（%）', share, numeric: true),
                    FilledButton(
                      onPressed: busy
                          ? null
                          : () => act(() async {
                              final ppm = affiliatePercent(share.text);
                              if (selected?['teamParentId'] != null) {
                                await state.api.post(
                                  '/api/v1/affiliate/members/${selected!['userId']}/share',
                                  {'sharePpm': ppm},
                                );
                                selected = null;
                                target.clear();
                                created = null;
                              } else {
                                created = await state.api
                                    .post('/api/v1/affiliate/invitations', {
                                      'targetUserId': target.text.trim().isEmpty
                                          ? null
                                          : target.text.trim(),
                                      'sharePpm': ppm,
                                    });
                              }
                            }, '合作设置已保存，首次入队须对方接受'),
                      child: LText(
                        selected?['teamParentId'] != null
                            ? '保存未来分配比例'
                            : '生成合作邀请',
                      ),
                    ),
                    if (created != null)
                      OutlinedButton(
                        onPressed: () => copy(
                          '${state.api.config.publicWebBaseUrl}/affiliate?invite=${created!['code']}',
                        ),
                        child: const LText('复制合作邀请链接'),
                      ),
                  ]),
                if (own &&
                    kolEnabled &&
                    asList(data!['invitations']).isNotEmpty)
                  section('待接受的合作邀请', [
                    for (final value in asList(data!['invitations']))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: LText(
                          '邀请人 ${asMap(value)['inviterId']} · ${requireInt64(asMap(value)['sharePpm'], 'sharePpm') / 10000}%',
                        ),
                        subtitle: LText('有效至 ${asMap(value)['expiresAt']}'),
                        trailing: TextButton(
                          onPressed: () {
                            if (asMap(value)['inviterId'] == owner.toString()) {
                              unawaited(
                                copy(
                                  '${state.api.config.publicWebBaseUrl}/affiliate?invite=${asMap(value)['code']}',
                                ),
                              );
                            } else {
                              code.text = asMap(value)['code'].toString();
                              unawaited(checkInvitation());
                            }
                          },
                          child: LText(
                            asMap(value)['inviterId'] == owner.toString()
                                ? '复制链接'
                                : '查看',
                          ),
                        ),
                      ),
                  ]),
                if (own)
                  section('佣金明细', [
                    if (entries.isEmpty) const LText('暂无佣金明细。'),
                    for (final row in entries)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${row['productLine']} / ${row['asset']} · ${scaledAmount(BigInt.tryParse(asString(row['retainedUnits'])), scales[asString(row['asset'])])} ${row['asset']}',
                        ),
                        subtitle: LText(
                          '来源 UID ${row['sourceUserId']} · ${row['occurredAt']}\n${_status(row['status'])}',
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          onPressed: entryCursor == '0'
                              ? null
                              : () {
                                  setState(() => entryCursor = '0');
                                  unawaited(load());
                                },
                          child: const LText('明细首页'),
                        ),
                        OutlinedButton(
                          onPressed: entryNext == null
                              ? null
                              : () {
                                  setState(() => entryCursor = entryNext!);
                                  unawaited(load());
                                },
                          child: const LText('更多明细'),
                        ),
                      ],
                    ),
                  ]),
                if (own)
                  section('结算记录', [
                    if (payouts.isEmpty)
                      const LText('暂无结算记录。确认成熟的佣金由平台资金账户划转，资金不足时保留待处理。'),
                    for (final row in payouts)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          '${row['productLine']} / ${row['asset']} · ${scaledAmount(BigInt.tryParse(asString(row['amountUnits'])), scales[asString(row['asset'])])} ${row['asset']}',
                        ),
                        subtitle: Text(
                          '${_status(row['status'])}${row['error'] == null ? '' : '\n${row['error']}'}',
                        ),
                      ),
                  ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
