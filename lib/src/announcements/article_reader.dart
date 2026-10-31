import '../i18n/client_messages.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import '../models.dart';
import '../ui/client_components.dart';

/// Displays server-sanitized articles with scripts, frames and arbitrary media blocked.
class ArticleReaderPage extends StatefulWidget {
  const ArticleReaderPage({
    required this.title,
    required this.html,
    required this.gatewayBaseUrl,
    required this.language,
    required this.locale,
    super.key,
  });
  final String title;
  final String html;
  final String gatewayBaseUrl;
  final ClientLanguage language;
  final String locale;
  @override
  State<ArticleReaderPage> createState() => _ArticleReaderPageState();
}

class _ArticleReaderPageState extends State<ArticleReaderPage>
    with WidgetsBindingObserver {
  late final WebViewController controller;
  String? error;
  String? mediaError;
  String? document;
  bool loading = true;
  bool suspended = false;
  bool loadingDocument = false;
  int documentVersion = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final params = WebViewPlatform.instance is WebKitWebViewPlatform
        ? WebKitWebViewControllerCreationParams(allowsInlineMediaPlayback: true)
        : const PlatformWebViewControllerCreationParams();
    controller = WebViewController.fromPlatformCreationParams(params)
      // Native WKWebView media controls require JavaScript. Article scripts remain blocked by CSP.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'SurprisingArticleMedia',
        onMessageReceived: (message) {
          if (message.message == '$documentVersion:failed') {
            _setMediaFailure(true);
          } else if (message.message == '$documentVersion:ready') {
            _setMediaFailure(false);
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            loadingDocument = false;
            if (mounted) setState(() => loading = false);
            if (!suspended) unawaited(_observeMedia());
          },
          onWebResourceError: (failure) {
            // Subresource callbacks also report successful media preloads as ERR_FAILED.
            // Report media failures from the HTML elements instead.
            if (mounted && failure.isForMainFrame == true) {
              setState(() {
                loading = false;
                error = clientText(
                  widget.language,
                  '文章加载失败，请重试',
                  'Could not load the article. Please try again.',
                );
              });
            }
          },
          onNavigationRequest: (request) {
            if (request.url == 'about:blank') {
              return NavigationDecision.navigate;
            }
            final uri = Uri.tryParse(request.url);
            final base = Uri.parse(widget.gatewayBaseUrl);
            if (loadingDocument &&
                request.isMainFrame &&
                uri != null &&
                uri.scheme == base.scheme &&
                uri.authority == base.authority &&
                (uri.path.isEmpty || uri.path == '/') &&
                !uri.hasQuery &&
                !uri.hasFragment) {
              return NavigationDecision.navigate;
            }
            if (request.isMainFrame &&
                uri != null &&
                (uri.scheme == 'https' || uri.scheme == 'mailto')) {
              unawaited(_openLink(uri));
            }
            return NavigationDecision.prevent;
          },
        ),
      );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final colors = Theme.of(context).colorScheme;
    String hex(Color color) =>
        '#${(color.toARGB32() & 0xffffff).toRadixString(16).padLeft(6, '0')}';
    const escape = HtmlEscape(HtmlEscapeMode.attribute);
    final direction = widget.locale.startsWith('ar') ? 'rtl' : 'ltr';
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final body = widget.html;
    final next =
        '''<!doctype html><html lang="${escape.convert(widget.locale)}" dir="$direction"><head>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; script-src 'none'; frame-src 'none'; connect-src 'none'; img-src https://ex-cdn.tokdou.com/public/exchange/content/; media-src https://ex-cdn.tokdou.com/public/exchange/content/; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'">
<style>html{color-scheme:${Theme.of(context).brightness == Brightness.dark ? 'dark' : 'light'}}body{margin:0;padding:20px;background:${hex(colors.surface)};color:${hex(colors.onSurface)};font:${16 * scale}px/1.8 -apple-system,BlinkMacSystemFont,Arial,sans-serif;overflow-wrap:anywhere}a{color:${hex(colors.primary)}}img,video{display:block;max-width:100%;max-height:65vh;height:auto;margin:16px auto;border-radius:10px;object-fit:contain}audio{display:block;width:100%;margin:16px 0}p{margin:0 0 1em}h2,h3{line-height:1.4}pre{white-space:pre-wrap;padding:12px;background:${hex(colors.surfaceContainerHighest)};border-radius:8px}blockquote{margin-inline:0;padding-inline:14px;border-inline-start:3px solid ${hex(colors.outlineVariant)}}ul,ol{padding-inline-start:1.6em}</style></head><body>$body</body></html>''';
    if (document != next) {
      document = next;
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    if (document == null || suspended) return;
    documentVersion++;
    setState(() {
      loading = true;
      error = null;
      mediaError = null;
    });
    try {
      loadingDocument = true;
      await controller.loadHtmlString(
        document!,
        baseUrl: widget.gatewayBaseUrl,
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = clientText(
            widget.language,
            '文章加载失败，请重试',
            'Could not load the article. Please try again.',
          );
        });
      }
    }
  }

  void _setMediaFailure(bool failed) {
    if (!mounted || suspended) return;
    final next = failed
        ? clientText(
            widget.language,
            '部分媒体加载失败，可刷新后重试。',
            'Some media could not load. Refresh to try again.',
          )
        : null;
    if (next != mediaError) setState(() => mediaError = next);
  }

  Future<void> _observeMedia() async {
    final version = documentVersion;
    try {
      // Trusted native observer; article scripts remain blocked by CSP.
      await controller.runJavaScript('''
(() => {
  const version = $version;
  if (window.surprisingArticleMediaVersion === version) return;
  window.surprisingArticleMediaVersion = version;
  const media = Array.from(document.querySelectorAll('img,audio,video'));
  const report = () => {
    const failed = media.some(item => item.tagName === 'IMG'
      ? item.complete && item.naturalWidth === 0
      : item.error !== null && item.error.code !== 1);
    SurprisingArticleMedia.postMessage(version + (failed ? ':failed' : ':ready'));
  };
  for (const event of ['error', 'load', 'loadedmetadata']) {
    document.addEventListener(event, report, true);
  }
  report();
})();
''');
    } catch (_) {
      if (version == documentVersion) _setMediaFailure(true);
    }
  }

  Future<void> _openLink(Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* The user can retry; never navigate the embedded reader to an external site. */
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: LText(
            clientText(
              widget.language,
              '链接暂时无法打开，请稍后重试',
              'Could not open the link. Please try again.',
            ),
          ),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      suspended = true;
      unawaited(controller.loadHtmlString('<html><body></body></html>'));
    } else if (state == AppLifecycleState.resumed && suspended) {
      suspended = false;
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Stop playback and release network-backed media before the native view is destroyed.
    unawaited(
      controller
          .loadHtmlString('<html><body></body></html>')
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: clientText(widget.language, '刷新', 'Refresh'),
          onPressed: loading ? null : _load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          if (loading) const LinearProgressIndicator(),
          if (mediaError != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(child: LText(mediaError!)),
                  TextButton(
                    onPressed: _load,
                    child: LText(clientText(widget.language, '重试', 'Retry')),
                  ),
                ],
              ),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LText(error!),
                  TextButton(
                    onPressed: _load,
                    child: LText(clientText(widget.language, '重试', 'Retry')),
                  ),
                ],
              ),
            ),
          Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    ),
  );
}
