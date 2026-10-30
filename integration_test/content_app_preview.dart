// Local device QA entry point. Uses the complete production shell and real content API.
import 'package:flutter/material.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const config = AppConfig(
    gatewayBaseUrl: 'http://127.0.0.1:19094',
    websocketUrl: '',
  );
  final state = AppState(config: config, apiClient: ApiClient(config));
  await state.restoreAuthentication();
  await state.refreshAnnouncements();
  runApp(SurprisingClientApp(state: state, bootstrap: false));
}
