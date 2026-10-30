// Manual/native automation entry point with normal Flutter bindings and real content APIs.
// Run against ContentQaServer; this entry point is excluded from production builds.
import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app_scope.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/announcements/announcement_center.dart';
import 'package:surprising_client/src/ui/client_theme.dart';

final mediaClock = ValueNotifier<String>('QA no article');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig(
    gatewayBaseUrl: 'http://127.0.0.1:19094',
    websocketUrl: '',
  );
  final state = AppState(config: config, apiClient: ApiClient(config));
  await state.refreshAnnouncements();
  runApp(_ContentPreview(state: state));
  // Observe the actual HTML media clock after native taps; a pause icon alone is not playback evidence.
  Timer.periodic(const Duration(seconds: 3), (_) {
    var found = false;
    void inspect(Element element) {
      final widget = element.widget;
      if (widget is WebViewWidget) {
        found = true;
        unawaited(
          widget.platform.params.controller
              .runJavaScriptReturningResult(
                "JSON.stringify(Array.from(document.querySelectorAll('audio,video')).map(e=>({tag:e.tagName,time:e.currentTime,ready:e.readyState,paused:e.paused,error:e.error?.code})))",
              )
              .then((value) {
                debugPrint('QA media clock: $value');
                Object? decoded = value is String ? jsonDecode(value) : value;
                if (decoded is String) decoded = jsonDecode(decoded);
                final records = decoded;
                if (records is! List) return;
                double time(String tag) => records
                    .whereType<Map>()
                    .where((item) => item['tag'] == tag)
                    .fold<double>(
                      0,
                      (current, item) =>
                          (item['time'] as num).toDouble() > current
                          ? (item['time'] as num).toDouble()
                          : current,
                    );
                mediaClock.value =
                    'QA video ${time('VIDEO').toStringAsFixed(1)} s; audio ${time('AUDIO').toStringAsFixed(1)} s';
              })
              .catchError((Object _) {}),
        );
      }
      element.visitChildren(inspect);
    }

    WidgetsBinding.instance.rootElement?.visitChildren(inspect);
    if (!found) mediaClock.value = 'QA no article';
  });
}

class _ContentPreview extends StatefulWidget {
  const _ContentPreview({required this.state});
  final AppState state;
  @override
  State<_ContentPreview> createState() => _ContentPreviewState();
}

class _ContentPreviewState extends State<_ContentPreview> {
  ClientTheme theme = ClientTheme.light;
  @override
  Widget build(BuildContext context) => AppScope(
    notifier: widget.state,
    child: MaterialApp(
      theme: buildClientTheme(theme),
      builder: (context, child) => Stack(
        children: [
          child!,
          Positioned(
            bottom: 24,
            left: 8,
            child: IgnorePointer(
              child: ValueListenableBuilder<String>(
                valueListenable: mediaClock,
                builder: (context, value, _) => Material(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: Text(
                      value,
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('公告验证'),
          actions: [
            TextButton(
              onPressed: () => setState(() => theme = ClientTheme.light),
              child: const Text('浅色'),
            ),
            TextButton(
              onPressed: () => setState(() => theme = ClientTheme.dark),
              child: const Text('深色'),
            ),
          ],
        ),
        body: AnnouncementCenterPage(onClose: () {}),
      ),
    ),
  );
}
