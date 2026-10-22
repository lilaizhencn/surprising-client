import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'app_state.dart';
import 'models.dart';

class KycDocumentsPage extends StatefulWidget {
  const KycDocumentsPage({required this.state, super.key});
  final AppState state;
  @override
  State<KycDocumentsPage> createState() => _KycDocumentsPageState();
}

class _KycDocumentsPageState extends State<KycDocumentsPage> {
  String? identity, error;
  List<Map<String, dynamic>> records = [];
  int generation = 0;
  bool loading = false, busy = false;
  int? _documentId(Map<String, dynamic> row) {
    final id = parseInt64(row['documentId']);
    return id != null && id > 0 ? id : null;
  }

  bool get current =>
      mounted &&
      identity != null &&
      identity == widget.state.session?.accessToken;
  @override
  void initState() {
    super.initState();
    identity = widget.state.session?.accessToken;
    widget.state.addListener(_checkIdentity);
    _load();
  }

  void _checkIdentity() {
    if (identity == widget.state.session?.accessToken || identity == null) {
      return;
    }
    identity = null;
    generation++;
    setState(() {
      records = [];
      error = '登录状态已变更，请返回后重新打开';
      loading = false;
    });
  }

  Future<void> _load() async {
    if (!current) return;
    final version = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final rows = await widget.state.api.kycDocuments();
      if (current && version == generation) setState(() => records = rows);
    } catch (_) {
      if (current && version == generation) {
        setState(() => error = '认证材料暂不可用，请重试');
      }
    } finally {
      if (current && version == generation) setState(() => loading = false);
    }
  }

  Future<void> _change(Map<String, dynamic> row, bool remove) async {
    if (!current || busy) return;
    final id = _documentId(row);
    if (id == null) {
      setState(() => error = '材料暂不可用，请刷新后重试');
      return;
    }
    if (remove) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('删除未提交材料？'),
          content: const Text('如需使用该材料认证，需要重新上传。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true || !current) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (remove) {
        await widget.state.api.deleteKycDocument(id);
        if (current) await _load();
      } else {
        final bytes = await widget.state.api.downloadKycDocument(id);
        if (!current) return;
        final name = asString(
          row['originalFilename'],
          fallback: 'document-$id.pdf',
        ).replaceAll(RegExp(r'[/\\]'), '_');
        await FilePicker.platform.saveFile(
          dialogTitle: '保存认证材料',
          fileName: name,
          bytes: bytes,
        );
      }
    } catch (_) {
      if (current) {
        setState(() => error = remove ? '材料删除未完成，请刷新后重试' : '材料无法保存，请重试');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.state.removeListener(_checkIdentity);
    generation++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('认证材料')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (loading) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        TextButton(
          onPressed: current && !loading && !busy ? _load : null,
          child: const Text('刷新材料'),
        ),
        if (!loading && error == null && records.isEmpty) const Text('暂无已上传材料'),
        for (final row in records)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(asString(row['originalFilename'], fallback: '认证材料')),
                  if (_documentId(row) == null) const Text('材料暂不可用，请刷新后重试'),
                  Text(
                    '${row['documentType'] ?? ''} · ${row['status'] == 'SUBMITTED' ? '已提交' : '未提交'} · ${row['createdAt'] ?? ''}',
                  ),
                  Wrap(
                    children: [
                      TextButton(
                        onPressed: current && !busy && _documentId(row) != null
                            ? () => _change(row, false)
                            : null,
                        child: const Text('保存原件'),
                      ),
                      if (row['status'] == 'UPLOADED')
                        TextButton(
                          onPressed:
                              current && !busy && _documentId(row) != null
                              ? () => _change(row, true)
                              : null,
                          child: const Text('删除未提交材料'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}
