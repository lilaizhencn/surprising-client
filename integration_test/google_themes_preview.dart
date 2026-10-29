// A normal app binding lets native automation exercise the OS keyboard.
// All data and provider availability are local fixtures; no live account is used.
import 'package:flutter/material.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'google_themes_test.dart' show GoogleQaApi, MemoryThemeSettings;

void main() {
  runApp(
    SurprisingClientApp(
      state: AppState(
        offline: true,
        apiClient: GoogleQaApi(),
        settingsStore: MemoryThemeSettings(),
      ),
      bootstrap: false,
    ),
  );
}
