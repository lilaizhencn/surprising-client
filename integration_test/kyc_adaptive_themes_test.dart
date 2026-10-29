import 'dart:convert';
import 'dart:io';
import 'dart:ui' show DisplayFeatureState;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import '../test/support/authentication.dart';
import '../test/transfer_page_test.dart' show MemorySettings;

/// Only the OS file selector is substituted. Uploads and KYC writes use real HTTP.
class SyntheticDocumentPicker extends FilePicker {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = false,
    int compressionQuality = 0,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jB9kAAAAASUVORK5CYII=',
    );
    return FilePickerResult([
      PlatformFile(
        name: 'synthetic-identity.png',
        size: bytes.length,
        bytes: bytes,
      ),
    ]);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const qaUrl = String.fromEnvironment('KYC_QA_URL');
  Future<void> handshake(String event, String name) async {
    final ack = File('${Directory.systemTemp.path}/kyc-adaptive-$name.ack');
    if (await ack.exists()) await ack.delete();
    debugPrint('$event:$name:${ack.path}');
    final deadline = DateTime.now().add(const Duration(seconds: 50));
    while (!await ack.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Host screenshot missing: $name');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    await ack.delete();
  }

  Future<void> capture(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 250)),
    );
    await handshake('NATIVE_CAPTURE_READY', name);
  }

  testWidgets(
    'native navigation and six distinct themes, large text and repeated transitions',
    (tester) async {
      final state = AppState(offline: true, settingsStore: MemorySettings());
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(
          key: ObjectKey(state),
          state: state,
          bootstrap: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人设置'));
      await tester.pumpAndSettle();
      for (final theme in ClientTheme.values) {
        await tester.tap(find.text('主题'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text(theme.label).last);
        await tester.tap(find.text(theme.label).last);
        await tester.pumpAndSettle();
        expect(state.clientTheme, theme);
        await capture(tester, 'theme-${theme.code}');
        expect(tester.takeException(), isNull);
      }
      tester.platformDispatcher.textScaleFactorTestValue = 1.4;
      await tester.pumpAndSettle();
      await tester.tap(find.text('主题'));
      await tester.pumpAndSettle();
      await capture(tester, 'large-text-picker');
      await tester.tap(find.text('深海蓝').last);
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await capture(tester, 'home-glass-navigation');
      await tester.tap(find.text('交易').last);
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(TradePage),
        matching: find.byType(TextField),
      );
      if (Platform.isIOS) {
        await tester.showKeyboard(fields.first);
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 700)),
        );
        await tester.pumpAndSettle();
      }
      await tester.enterText(fields.first, '12345.6');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(fields.first).controller!.text,
        '12345.6',
      );
      await capture(tester, 'trade-keyboard');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await capture(tester, 'trade-layout');
      if (Platform.isAndroid) {
        final controller = tester.widget<TextField>(fields.first).controller!;
        for (final posture in [
          'folded',
          'unfolded',
          'half-opened',
          'unfolded',
        ]) {
          await handshake('NATIVE_POSTURE_READY', posture);
          await tester.pumpAndSettle();
          bool ready() {
            final current = MediaQuery.of(
              tester.element(find.byType(ClientShell)),
            );
            if (posture == 'folded') return current.size.width < 600;
            if (current.size.width < 600) return false;
            return current.displayFeatures.any(
              (feature) =>
                  feature.state ==
                  (posture == 'half-opened'
                      ? DisplayFeatureState.postureHalfOpened
                      : DisplayFeatureState.postureFlat),
            );
          }

          for (var attempt = 0; !ready() && attempt < 60; attempt++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 250)),
            );
            await tester.pumpAndSettle();
          }
          expect(
            tester.widget<TextField>(fields.first).controller,
            same(controller),
          );
          expect(controller.text, '12345.6');
          final media = MediaQuery.of(tester.element(find.byType(ClientShell)));
          debugPrint(
            'NATIVE_WINDOW:$posture:${media.size}:${media.displayFeatures}',
          );
          if (posture == 'folded') {
            expect(media.size.width, lessThan(600));
          } else {
            expect(media.size.width, greaterThanOrEqualTo(600));
          }
          if (posture == 'half-opened') {
            expect(
              media.displayFeatures.any(
                (feature) =>
                    feature.state == DisplayFeatureState.postureHalfOpened,
              ),
              isTrue,
            );
          }
          await capture(tester, 'trade-$posture');
          expect(tester.takeException(), isNull);
        }
      }
      expect(tester.takeException(), isNull);
      for (var i = 0; i < 12; i++) {
        await tester.tap(find.text(i.isEven ? '首页' : '行情').last);
        await tester.pumpAndSettle();
        await Future<void>.delayed(const Duration(milliseconds: 600));
      }
      await capture(tester, 'after-navigation-cycles');
      expect(tester.takeException(), isNull);
    },
    skip: const bool.fromEnvironment('QA_ONLY_KYC'),
  );

  testWidgets(
    'real HTTP KYC upload, rejection, correction, approval and expiry renewal',
    (tester) async {
      final http = HttpClient();
      addTearDown(() => http.close(force: true));
      Future<void> admin(String path, [Map<String, dynamic>? body]) async {
        final request = await http.postUrl(Uri.parse('$qaUrl$path'));
        request.headers.set('Authorization', 'Bearer kyc-qa-admin');
        request.headers.contentType = ContentType.json;
        if (body != null) request.write(jsonEncode(body));
        final response = await request.close();
        final text = await utf8.decoder.bind(response).join();
        expect(response.statusCode, inInclusiveRange(200, 299), reason: text);
      }

      await tester.runAsync(() async {
        final deadline = DateTime.now().add(const Duration(minutes: 3));
        while (true) {
          try {
            await admin('/__qa/reset');
            break;
          } on SocketException {
            if (DateTime.now().isAfter(deadline)) rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 1));
        }
      });
      final originalPicker = FilePicker.platform;
      FilePicker.platform = SyntheticDocumentPicker();
      addTearDown(() => FilePicker.platform = originalPicker);
      final state = AppState(
        apiClient: ApiClient(const AppConfig(gatewayBaseUrl: qaUrl)),
        initialSession: const AuthSession(
          user: AuthUser(
            userId: 42,
            username: 'kycqa',
            email: 'kycqa@example.test',
            status: 'NORMAL',
          ),
          accessToken: 'kyc-qa-user',
          refreshToken: 'kyc-qa-refresh',
        ),
        sessionStore: MemorySessionStore(),
        settingsStore: MemorySettings(),
      );
      addTearDown(state.dispose);
      await tester.pumpWidget(
        SurprisingClientApp(
          key: ObjectKey(state),
          state: state,
          bootstrap: false,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('个人设置'));
      await tester.pumpAndSettle();
      debugPrint(
        'KYC_IDENTITY:${state.isLoggedIn}:${state.userId}:${state.language}',
      );
      await tester.scrollUntilVisible(
        find.text('身份认证'),
        200,
        scrollable: find
            .descendant(
              of: find.byType(ProfilePage),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await capture(tester, 'kyc-profile-entry');
      await tester.tap(find.text('身份认证'));
      Future<void> settle() async {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 700)),
        );
        await tester.pumpAndSettle();
      }

      await settle();
      Future<void> submit(String entry) async {
        final button = find.text(entry);
        await tester.ensureVisible(button);
        await tester.tap(button);
        await settle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('新加坡').last);
        await tester.pumpAndSettle();
        await tester.tap(find.byType(DropdownButtonFormField<String>).last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('护照').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('证件到期日期'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK').last);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.byIcon(Icons.upload_file).first);
        await tester.tap(find.byIcon(Icons.upload_file).first);
        await settle();
        await tester.ensureVisible(find.text('提交认证申请'));
        await tester.tap(find.text('提交认证申请'));
        await settle();
        expect(find.textContaining('身份认证 KYC · 审核中'), findsOneWidget);
      }

      await capture(tester, 'kyc-entry');
      await submit('填写认证资料');
      await capture(tester, 'kyc-pending');
      Map<String, dynamic> decision(String status) => {
        'kycLevel': 'BASIC',
        'status': status,
        'country': 'SG',
        'documentType': 'PASSPORT',
        'provider': 'SELF',
        'rejectionReason': status == 'REJECTED' ? '请重新上传清晰完整的证件照片' : null,
        'expiresAt': status == 'VERIFIED'
            ? DateTime.now()
                  .toUtc()
                  .add(const Duration(minutes: 10))
                  .toIso8601String()
            : null,
      };
      await tester.runAsync(
        () => admin(
          '/api/v1/admin/compliance/users/42/kyc',
          decision('REJECTED'),
        ),
      );
      await tester.ensureVisible(find.text('刷新认证状态'));
      await tester.tap(find.text('刷新认证状态'));
      await settle();
      expect(find.textContaining('请重新上传清晰完整的证件照片'), findsOneWidget);
      await capture(tester, 'kyc-rejected');
      await submit('补正并重新提交');
      await tester.runAsync(
        () => admin(
          '/api/v1/admin/compliance/users/42/kyc',
          decision('VERIFIED'),
        ),
      );
      await tester.ensureVisible(find.text('刷新认证状态'));
      await tester.tap(find.text('刷新认证状态'));
      await settle();
      expect(find.textContaining('身份认证 KYC · 已通过'), findsOneWidget);
      await capture(tester, 'kyc-verified');
      await tester.runAsync(() => admin('/__qa/expire'));
      await tester.tap(find.text('刷新认证状态'));
      await settle();
      expect(find.text('重新认证'), findsOneWidget);
      await capture(tester, 'kyc-expired');
      await submit('重新认证');
      await capture(tester, 'kyc-renewed');
      for (var sample = 0; sample < 20; sample++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(seconds: 3)),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('身份认证 KYC · 审核中'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await capture(tester, 'kyc-polling-after60s');
      expect(tester.takeException(), isNull);
    },
    skip: qaUrl.isEmpty,
  );
}
