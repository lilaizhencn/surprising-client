import '../i18n/client_messages.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../models.dart';
import '../ui/client_components.dart';

class KycSumsubWebView extends StatefulWidget {
  const KycSumsubWebView({
    required this.token,
    required this.refreshToken,
    required this.language,
    super.key,
  });
  final String token;
  final Future<String> Function() refreshToken;
  final ClientLanguage language;

  @override
  State<KycSumsubWebView> createState() => _KycSumsubWebViewState();
}

class _KycSumsubWebViewState extends State<KycSumsubWebView> {
  late final WebViewController controller;
  String? error;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    final tokenJson = jsonEncode(widget.token);
    controller =
        WebViewController(
            onPermissionRequest: (request) {
              if (request.types.every(
                (type) =>
                    type == WebViewPermissionResourceType.camera ||
                    type == WebViewPermissionResourceType.microphone,
              )) {
                request.grant();
              } else {
                request.deny();
              }
            },
          )
          ..addJavaScriptChannel(
            'KycHost',
            onMessageReceived: (_) => unawaited(_refreshToken()),
          )
          ..setNavigationDelegate(
            NavigationDelegate(
              onPageStarted: (_) {
                if (mounted) {
                  setState(() {
                    loading = true;
                    error = null;
                  });
                }
              },
              onPageFinished: (_) {
                if (mounted) setState(() => loading = false);
              },
              onWebResourceError: (failure) {
                if (mounted && failure.isForMainFrame == true) {
                  setState(() {
                    error = '核验页面加载失败，请检查网络后重试';
                    loading = false;
                  });
                }
              },
              onNavigationRequest: (request) {
                if (!request.isMainFrame) return NavigationDecision.navigate;
                final uri = Uri.tryParse(request.url);
                return uri != null &&
                        uri.scheme == 'https' &&
                        (uri.host == 'sumsub.com' ||
                            uri.host.endsWith('.sumsub.com'))
                    ? NavigationDecision.navigate
                    : NavigationDecision.prevent;
              },
            ),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(
            '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><script src="https://static.sumsub.com/idensic/static/sns-websdk-builder.js"></script></head><body><div id="sumsub-websdk-container"></div><script>window.__requestNewToken=()=>new Promise(resolve=>{window.__resolveNewToken=resolve;KycHost.postMessage("refresh")});window.__provideNewToken=token=>window.__resolveNewToken?.(token);snsWebSdk.init($tokenJson, window.__requestNewToken).withConf({lang:"${widget.language == ClientLanguage.en ? 'en' : 'zh'}"}).build().launch("#sumsub-websdk-container");</script></body></html>''',
            baseUrl: 'https://static.sumsub.com/',
          );
  }

  Future<void> _refreshToken() async {
    try {
      final token = await widget.refreshToken();
      if (!mounted) return;
      await controller.runJavaScript(
        'window.__provideNewToken(${jsonEncode(token)});',
      );
    } catch (_) {
      if (mounted) setState(() => error = '核验会话更新失败，请重试或关闭后继续认证');
    }
  }

  @override
  Widget build(BuildContext context) => Dialog.fullscreen(
    child: SafeArea(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: LText(
                  clientText(
                    widget.language,
                    'Sumsub 身份与人脸核验',
                    'Sumsub identity and face verification',
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  LText(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() => error = null);
                      await _refreshToken();
                      if (mounted && error == null) await controller.reload();
                    },
                    child: const LText('重试'),
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
