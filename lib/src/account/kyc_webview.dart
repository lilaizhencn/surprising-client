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
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadHtmlString(
            '''<!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1"><script src="https://static.sumsub.com/idensic/static/sns-websdk-builder.js"></script></head><body><div id="sumsub-websdk-container"></div><script>window.__requestNewToken=()=>new Promise(resolve=>{window.__resolveNewToken=resolve;KycHost.postMessage("refresh")});window.__provideNewToken=token=>window.__resolveNewToken?.(token);snsWebSdk.init($tokenJson, window.__requestNewToken).withConf({lang:"${widget.language == ClientLanguage.en ? 'en' : 'zh'}"}).build().launch("#sumsub-websdk-container");</script></body></html>''',
            baseUrl: 'https://static.sumsub.com/',
          );
  }

  Future<void> _refreshToken() async {
    try {
      final token = await widget.refreshToken();
      await controller.runJavaScript(
        'window.__provideNewToken(${jsonEncode(token)});',
      );
    } catch (_) {
      await controller.runJavaScript('window.__provideNewToken("");');
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
                child: Text(
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
          Expanded(child: WebViewWidget(controller: controller)),
        ],
      ),
    ),
  );
}
