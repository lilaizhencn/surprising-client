import '../i18n/client_messages.dart';
import '../api.dart';
import 'package:flutter/material.dart';
import '../announcements/article_reader.dart';
import '../app_scope.dart';
import '../app_state.dart';
import '../ui/client_components.dart';
import 'legal_models.dart';

void openLegalDocument(BuildContext context, LegalDocument document) {
  final state = AppScope.of(context);
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ArticleReaderPage(
        title: document.title,
        html: document.bodyHtml,
        gatewayBaseUrl: state.config.gatewayBaseUrl,
        language: state.language,
        locale: document.locale,
      ),
    ),
  );
}

class LegalCenterPage extends StatefulWidget {
  const LegalCenterPage({super.key});
  @override
  State<LegalCenterPage> createState() => _LegalCenterPageState();
}

class _LegalCenterPageState extends State<LegalCenterPage> {
  List<LegalDocument> documents = [];
  String? error, locale;
  bool loading = true;
  int requestVersion = 0;
  ApiRequestCancellation? request;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = AppScope.of(context).language.contentLocale;
    if (locale != next) {
      locale = next;
      load();
    }
  }

  Future<void> load() async {
    final version = ++requestVersion;
    request?.cancel();
    final cancellation = ApiRequestCancellation();
    request = cancellation;
    final state = AppScope.of(context);
    setState(() {
      loading = true;
      error = null;
      documents = [];
    });
    try {
      final next = await state.api.legalDocuments(
        locale!,
        cancellation: cancellation,
      );
      if (mounted && version == requestVersion) {
        setState(() => documents = next);
      }
    } catch (failure) {
      if (mounted && version == requestVersion && !cancellation.isCancelled) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted && version == requestVersion) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    request?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = AppScope.of(context).language;
    return Scaffold(
      appBar: AppBar(
        title: LText(clientText(language, '协议与隐私', 'Legal and privacy')),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              LText(
                clientText(
                  language,
                  '阅读适用的协议、隐私说明及产品风险披露。',
                  'Read the applicable agreements, privacy information and product risk disclosures.',
                ),
              ),
              const SizedBox(height: 16),
              if (loading) const LinearProgressIndicator(),
              if (error != null) ...[
                LText(error!, key: const ValueKey('legal-error')),
                TextButton(
                  onPressed: load,
                  child: LText(clientText(language, '重试', 'Retry')),
                ),
              ],
              if (!loading && error == null && documents.isEmpty)
                LText(
                  clientText(
                    language,
                    '暂无已发布协议',
                    'No legal documents have been published yet.',
                  ),
                ),
              for (final document in documents)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(document.title),
                  subtitle: Text(document.revisionLabel),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLegalDocument(context, document),
                ),
              const SizedBox(height: 24),
              const SelectableText('河南朔望科技有限公司\nsupport@surprising.top'),
            ],
          ),
        ),
      ),
    );
  }
}

/// Keeps the exact revision and language attached to an explicit, initially unchecked choice.
class LegalReview extends StatefulWidget {
  const LegalReview({required this.onReady, required this.disabled, super.key});
  final ValueChanged<bool> onReady;
  final bool disabled;
  @override
  State<LegalReview> createState() => _LegalReviewState();
}

class _LegalReviewState extends State<LegalReview> {
  AppState? state;
  List<LegalDocument> documents = [];
  String? error, locale;
  bool checked = false, loading = true;
  int requestVersion = 0;
  ApiRequestCancellation? request;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    state = AppScope.of(context);
    final next = state!.language.contentLocale;
    if (locale != next) {
      locale = next;
      load();
    }
  }

  Future<void> load() async {
    final version = ++requestVersion;
    request?.cancel();
    final cancellation = ApiRequestCancellation();
    request = cancellation;
    final owner = state!;
    owner.api.clearLegalAcceptance();
    setState(() {
      checked = false;
      loading = true;
      error = null;
      documents = [];
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && version == requestVersion) widget.onReady(false);
    });
    try {
      final next = (await owner.api.legalDocuments(
        locale!,
        cancellation: cancellation,
      )).where((item) => item.registrationRequired).toList();
      if (next.length != 2 ||
          !next.any((item) => item.type == 'USER_AGREEMENT') ||
          !next.any((item) => item.type == 'PRIVACY_POLICY')) {
        throw const FormatException('必要协议暂不可用，请重试');
      }
      if (mounted && version == requestVersion) {
        setState(() => documents = next);
      }
    } catch (failure) {
      if (mounted && version == requestVersion && !cancellation.isCancelled) {
        setState(() => error = failure.toString());
      }
    } finally {
      if (mounted && version == requestVersion) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    request?.cancel();
    state?.api.clearLegalAcceptance();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final language = state!.language;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (loading) const LinearProgressIndicator(),
        for (final document in documents)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton(
              onPressed: widget.disabled
                  ? null
                  : () => openLegalDocument(context, document),
              child: Text('${document.title} · ${document.revisionLabel}'),
            ),
          ),
        if (error != null) ...[
          LText(error!),
          TextButton(
            onPressed: widget.disabled ? null : load,
            child: LText(clientText(language, '重试', 'Retry')),
          ),
        ],
        if (!loading && error == null)
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: LText(
              clientText(
                language,
                '我已阅读并同意用户协议，且已了解隐私政策。',
                'I have read and agree to the User Agreement and acknowledge the Privacy Policy.',
              ),
            ),
            value: checked,
            onChanged: widget.disabled
                ? null
                : (value) {
                    setState(() => checked = value == true);
                    state!.api.setLegalAcceptance(checked ? documents : []);
                    widget.onReady(checked);
                  },
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton(
            onPressed: widget.disabled
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LegalCenterPage(),
                    ),
                  ),
            child: LText(
              clientText(
                language,
                '全部协议与风险披露',
                'All agreements and risk disclosures',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class LegalUpdateSheet extends StatefulWidget {
  const LegalUpdateSheet({super.key});
  @override
  State<LegalUpdateSheet> createState() => _LegalUpdateSheetState();
}

class _LegalUpdateSheetState extends State<LegalUpdateSheet> {
  bool ready = false, busy = false;
  String? error;
  @override
  Widget build(BuildContext context) {
    final state = AppScope.of(context), language = state.language;
    return PopScope(
      canPop: !busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LText(
                clientText(
                  language,
                  '请确认更新后的协议',
                  'Please review the updated agreements',
                ),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              LText(
                clientText(
                  language,
                  '协议版本已更新，请阅读并确认后继续当前会话。',
                  'The legal documents have changed. Review the current versions before continuing your session.',
                ),
              ),
              LegalReview(
                disabled: busy,
                onReady: (value) {
                  if (mounted) setState(() => ready = value);
                },
              ),
              if (error != null) LText(error!),
              FilledButton(
                onPressed: !ready || busy
                    ? null
                    : () async {
                        setState(() {
                          busy = true;
                          error = null;
                        });
                        try {
                          await state.resumeLegalReview();
                          if (context.mounted) Navigator.pop(context);
                        } catch (failure) {
                          if (mounted) {
                            setState(() => error = failure.toString());
                          }
                        } finally {
                          if (mounted) setState(() => busy = false);
                        }
                      },
                child: LText(
                  clientText(language, '同意并继续', 'Agree and continue'),
                ),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        state.dismissLegalReview();
                        Navigator.pop(context);
                      },
                child: LText(clientText(language, '暂不确认', 'Not now')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
