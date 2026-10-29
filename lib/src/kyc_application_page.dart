import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';
import 'ui/adaptive_client_layout.dart';

List<String> kycRequiredSlots(String type, String applicant, String level) => [
  if (type == 'ID_CARD') ...[
    'ID_CARD_FRONT',
    'ID_CARD_BACK',
    'ID_CARD_SELFIE',
  ] else if (type == 'PASSPORT')
    'PASSPORT'
  else ...[
    '${type}_FRONT',
    '${type}_BACK',
  ],
  if (level != 'BASIC') 'ADDRESS_PROOF',
  if (applicant == 'BUSINESS') 'BUSINESS_LICENSE',
  if (level == 'ENHANCED' && type != 'ID_CARD') 'FACE_IMAGE',
];

DateTime threeMonthsBefore(DateTime today) {
  final month = DateTime.utc(today.year, today.month - 3, 1);
  final last = DateTime.utc(month.year, month.month + 1, 0).day;
  return DateTime.utc(
    month.year,
    month.month,
    today.day > last ? last : today.day,
  );
}

class KycApplicationPage extends StatefulWidget {
  const KycApplicationPage({required this.state, super.key});
  final AppState state;
  @override
  State<KycApplicationPage> createState() => _KycApplicationPageState();
}

class _KycApplicationPageState extends State<KycApplicationPage> {
  static const labels = {
    'ID_CARD_FRONT': '身份证正面',
    'ID_CARD_BACK': '身份证反面',
    'ID_CARD_SELFIE': '手持身份证照片',
    'PASSPORT': '护照资料页',
    'DRIVING_LICENSE_FRONT': '驾驶证正面',
    'DRIVING_LICENSE_BACK': '驾驶证反面',
    'RESIDENCE_PERMIT_FRONT': '居留证正面',
    'RESIDENCE_PERMIT_BACK': '居留证反面',
    'ADDRESS_PROOF': '地址证明',
    'BUSINESS_LICENSE': '企业登记证书',
    'FACE_IMAGE': '人脸照片',
  };
  String? country, error;
  (int?, int)? identity;
  (int?, int)? get accountIdentity => widget.state.isLoggedIn
      ? (widget.state.userId, widget.state.auth.revision)
      : null;
  String provider = '',
      type = 'ID_CARD',
      applicant = 'INDIVIDUAL',
      level = 'BASIC';
  List<Map<String, dynamic>> countries = [];
  List<Map<String, dynamic>> verificationOptions = [];
  final documents = <String, Map<String, dynamic>>{};
  DateTime? expires, issued, addressIssued;
  bool loading = true, busy = false;
  String? uploading;
  int generation = 0;
  bool invalidated = false;
  bool get current =>
      mounted && identity != null && identity == accountIdentity;
  List<String> get slots => kycRequiredSlots(type, applicant, level);

  int? _documentId(String slot) {
    final id = parseInt64(documents[slot]?['documentId']);
    return id != null && id > 0 ? id : null;
  }

  @override
  void initState() {
    super.initState();
    identity = accountIdentity;
    widget.state.addListener(_checkIdentity);
    unawaited(_load());
  }

  void _checkIdentity() {
    if (identity == accountIdentity || invalidated) return;
    invalidated = true;
    generation++;
    setState(() {
      documents.clear();
      countries = [];
      error = '登录状态已变更，请返回后重新打开认证页面';
      loading = false;
      busy = false;
    });
  }

  Future<void> _load() async {
    final version = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await Future.wait([
        widget.state.api.kycCountries(),
        widget.state.api.kycProvider(),
      ]);
      if (!current || version != generation) return;
      setState(() {
        countries = result[0] as List<Map<String, dynamic>>;
        provider = asString(asMap(result[1])['provider']);
        verificationOptions = asList(asMap(result[1])['verificationOptions'])
            .map(asMap)
            .where(
              (option) =>
                  [
                    'INDIVIDUAL',
                    'BUSINESS',
                  ].contains(option['applicantType']) &&
                  [
                    'BASIC',
                    'STANDARD',
                    'ENHANCED',
                  ].contains(option['kycLevel']),
            )
            .toList();
        if (verificationOptions.isEmpty) throw const FormatException('认证流程未配置');
        applicant = asString(verificationOptions.first['applicantType']);
        level = asString(verificationOptions.first['kycLevel']);
      });
    } catch (_) {
      if (current && version == generation) {
        setState(() => error = '认证配置暂不可用，请重试');
      }
    } finally {
      if (current && version == generation) setState(() => loading = false);
    }
  }

  Future<void> _upload(String slot) async {
    if (busy || uploading != null || !current) return;
    final version = generation;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
    } catch (_) {
      if (current) setState(() => error = '无法打开文件选择器，请检查访问权限');
      return;
    }
    if (!current ||
        version != generation ||
        result == null ||
        result.files.isEmpty) {
      return;
    }
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      setState(() => error = '请选择不超过 10 MB 的 JPG、PNG 或 PDF 材料');
      return;
    }
    setState(() {
      uploading = slot;
      error = null;
    });
    try {
      final uploaded = await widget.state.api.uploadKycDocument(
        documentType: slot,
        fileName: file.name,
        bytes: bytes,
      );
      final documentId = parseInt64(uploaded['documentId']);
      if (documentId == null || documentId <= 0) {
        throw const FormatException('上传材料缺少有效标识');
      }
      if (current && version == generation) {
        setState(() => documents[slot] = {...uploaded, 'fileName': file.name});
      }
    } catch (_) {
      if (current && version == generation) {
        setState(() => error = '材料上传失败，请重试');
      }
    } finally {
      if (current && version == generation) setState(() => uploading = null);
    }
  }

  Future<void> _remove(String slot) async {
    if (!current || busy || uploading != null) return;
    final id = _documentId(slot);
    if (id == null) {
      setState(() => error = '材料暂不可用，请重新上传');
      return;
    }
    setState(() {
      uploading = slot;
      error = null;
    });
    try {
      await widget.state.api.deleteKycDocument(id);
      if (current) setState(() => documents.remove(slot));
    } catch (_) {
      if (current) setState(() => error = '材料暂时无法移除，请重试');
    } finally {
      if (current) setState(() => uploading = null);
    }
  }

  Future<void> _pickDate(String field) async {
    final now = DateTime.now().toUtc();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: today,
      firstDate: DateTime(1900),
      lastDate: field == 'expires' ? DateTime(2100) : today,
    );
    if (!current || picked == null) return;
    final date = DateTime.utc(picked.year, picked.month, picked.day);
    setState(() {
      if (field == 'expires') {
        expires = date;
      } else if (field == 'issued') {
        issued = date;
      } else {
        addressIssued = date;
      }
    });
  }

  Future<void> _submit() async {
    if (!current || busy || uploading != null || loading) return;
    final now = DateTime.now().toUtc(), today = DateTime.now().toUtc();
    final day = DateTime.utc(now.year, now.month, now.day);
    final documentIds = slots.map(_documentId).toList();
    String? invalid;
    if (!countries.any((c) => c['code'] == country)) {
      invalid = '请选择国家或地区';
    } else if (!['SELF', 'SUMSUB', 'VERIFF'].contains(provider) ||
        !verificationOptions.any(
          (option) =>
              option['applicantType'] == applicant &&
              option['kycLevel'] == level,
        )) {
      invalid = '身份核验服务暂不可用';
    } else if (provider == 'SELF') {
      if (documentIds.any((id) => id == null)) {
        invalid = '请上传所有必需材料';
      } else if (expires == null || expires!.isBefore(day)) {
        invalid = '证件有效期不能为空或早于今天';
      } else if (type == 'ID_CARD' &&
          (issued == null ||
              issued!.isAfter(day) ||
              issued!.isAfter(expires!))) {
        invalid = '身份证签发日期必须有效，且不晚于今天和有效期';
      } else if (level != 'BASIC' &&
          (addressIssued == null ||
              addressIssued!.isBefore(threeMonthsBefore(today)) ||
              addressIssued!.isAfter(day))) {
        invalid = '地址证明需在最近三个月内签发';
      }
    }
    if (invalid != null) {
      setState(() => error = invalid);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    String? date(DateTime? d) => d?.toIso8601String().split('T').first;
    try {
      final result = await widget.state.api.submitKyc(
        applicantType: applicant,
        kycLevel: level,
        country: country!,
        documentType: type,
        provider: provider,
        providerReference: '',
        faceVerificationStatus: level == 'ENHANCED'
            ? 'PENDING'
            : 'NOT_REQUIRED',
        documentIds: provider == 'SELF'
            ? documentIds.whereType<int>().toList()
            : [],
        documentExpiresOn: provider == 'SELF' ? date(expires) : null,
        documentIssuedOn: provider == 'SELF' && type == 'ID_CARD'
            ? date(issued)
            : null,
        addressIssuedOn: provider == 'SELF' && level != 'BASIC'
            ? date(addressIssued)
            : null,
      );
      if (mounted && current) Navigator.pop(context, result);
    } catch (cause) {
      if (current) setState(() => error = '认证提交未完成：$cause');
    } finally {
      if (current) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    generation++;
    widget.state.removeListener(_checkIdentity);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = !current || busy || loading || uploading != null;
    Widget choice(
      String label,
      String value,
      Map<String, String> values,
      ValueChanged<String> change,
    ) => DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: values.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: blocked
          ? null
          : (v) {
              if (v != null) setState(() => change(v));
            },
    );
    Widget dateButton(
      String label,
      String field,
      DateTime? value,
    ) => OutlinedButton(
      onPressed: blocked ? null : () => _pickDate(field),
      child: Text(
        '$label${value == null ? '' : '：${value.toIso8601String().split('T').first}'}',
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('填写身份认证资料')),
      body: FoldAwareClientBody(
        primary: SafeArea(
          child: ClientFormWidth(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (loading) const LinearProgressIndicator(),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if ((countries.isEmpty || verificationOptions.isEmpty) &&
                    !loading)
                  TextButton(
                    onPressed: current ? _load : null,
                    child: const Text('重新加载认证配置'),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: country,
                  isExpanded: true,
                  menuMaxHeight: 320,
                  decoration: const InputDecoration(labelText: '国家 / 地区'),
                  items: countries
                      .map(
                        (c) => DropdownMenuItem<String>(
                          value: asString(c['code']),
                          child: Text(
                            '${asMap(c['names'])['zh'] ?? c['code']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: blocked
                      ? null
                      : (v) => setState(() => country = v),
                ),
                if (verificationOptions.isNotEmpty) ...[
                  choice(
                    '申请主体',
                    applicant,
                    {
                      for (final option in verificationOptions)
                        asString(option['applicantType']):
                            option['applicantType'] == 'BUSINESS' ? '企业' : '个人',
                    },
                    (v) {
                      applicant = v;
                      level = asString(
                        verificationOptions.firstWhere(
                          (option) => option['applicantType'] == v,
                        )['kycLevel'],
                      );
                    },
                  ),
                  choice('认证等级', level, {
                    for (final option in verificationOptions.where(
                      (option) => option['applicantType'] == applicant,
                    ))
                      asString(option['kycLevel']): const {
                        'BASIC': '基础',
                        'STANDARD': '标准',
                        'ENHANCED': '增强',
                      }[option['kycLevel']]!,
                  }, (v) => level = v),
                ],
                choice('证件类型', type, {
                  'ID_CARD': '身份证',
                  'PASSPORT': '护照',
                  'DRIVING_LICENSE': '驾驶证',
                  'RESIDENCE_PERMIT': '居留证',
                }, (v) => type = v),
                if (provider == 'SELF') ...[
                  const SizedBox(height: 12),
                  dateButton('证件到期日期', 'expires', expires),
                  if (type == 'ID_CARD')
                    dateButton('身份证签发日期', 'issued', issued),
                  if (level != 'BASIC')
                    dateButton('地址证明签发日期', 'address', addressIssued),
                  const Text(
                    '材料需清晰完整，支持 JPG、PNG、PDF，每份不超过 10 MB。地址证明可使用账单、银行流水或政府居住证明。',
                  ),
                  for (final slot in slots)
                    Card(
                      child: ListTile(
                        title: Text(labels[slot] ?? slot),
                        subtitle: Text(
                          documents.containsKey(slot) &&
                                  _documentId(slot) == null
                              ? '材料暂不可用，请重新上传'
                              : asString(
                                  documents[slot]?['fileName'],
                                  fallback: '未上传',
                                ),
                        ),
                        trailing: uploading == slot
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Wrap(
                                children: [
                                  IconButton(
                                    tooltip: '上传材料',
                                    onPressed: blocked
                                        ? null
                                        : () => _upload(slot),
                                    icon: const Icon(Icons.upload_file),
                                  ),
                                  if (documents.containsKey(slot))
                                    IconButton(
                                      tooltip: '移除材料',
                                      onPressed:
                                          blocked || _documentId(slot) == null
                                          ? null
                                          : () => _remove(slot),
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                ],
                              ),
                      ),
                    ),
                ] else if (provider.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text('提交后继续 $provider 证件与人脸核验。认证材料由核验服务采集。'),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed:
                      blocked ||
                          countries.isEmpty ||
                          verificationOptions.isEmpty
                      ? null
                      : _submit,
                  child: Text(busy ? '提交中…' : '提交认证申请'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
