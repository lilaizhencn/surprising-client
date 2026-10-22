import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/deposit_page.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/user_scanner_page.dart';
import 'redesign_smoke_test.dart' show NativeQaApi;

// The host operates Android's actual DocumentsUI and Sharesheet. No accounts,
// payments or messages are sent to an external service.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> hostAction(WidgetTester tester, String action) async {
    final ack = File('${Directory.systemTemp.path}/native-export-$action.ack');
    if (await ack.exists()) await ack.delete();
    debugPrint('NATIVE_EXPORT_READY:$action:${ack.path}');
    await tester.runAsync(() async {
      final deadline = DateTime.now().add(const Duration(seconds: 45));
      while (!await ack.exists()) {
        if (DateTime.now().isAfter(deadline)) {
          throw StateError('Host did not complete $action');
        }
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      await ack.delete();
    });
  }

  testWidgets('native QR save, share dismissal and gallery selection', (
    tester,
  ) async {
    expect(
      Platform.isAndroid,
      isTrue,
      reason: 'Host automation covers Android only',
    );
    final api = ExportQaApi();
    final state = AppState(
      initialSession: const AuthSession(
        user: AuthUser(
          userId: 7,
          username: '',
          displayName: 'Synthetic user',
          email: '',
          status: 'NORMAL',
        ),
        accessToken: 'synthetic-only',
        refreshToken: 'synthetic-only',
      ),
      offline: true,
      apiClient: api,
    );
    addTearDown(state.dispose);
    await tester.pumpWidget(MaterialApp(home: MobileDepositPage(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deposit-asset-USDT')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('deposit-network-ETH')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存二维码'));
    await tester.pump(const Duration(milliseconds: 400));
    await hostAction(tester, 'save');
    await tester.pumpAndSettle();
    expect(find.text('二维码已保存'), findsOneWidget);
    final scanner = MobileScannerController(autoStart: false);
    try {
      final saved = await scanner.analyzeImage(
        '${Directory.systemTemp.path}/native-saved-deposit.png',
      );
      expect(
        saved?.barcodes.any(
          (code) =>
              code.rawValue == '0x1111111111111111111111111111111111111111',
        ),
        isTrue,
      );
    } finally {
      await scanner.dispose();
    }
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('分享'));
    await tester.pump(const Duration(milliseconds: 400));
    await hostAction(tester, 'share');
    await tester.pumpAndSettle();
    expect(find.text('分享失败，请重试或复制地址'), findsNothing);
    // A cancelled native picker must not show a new successful-save notice.
    await tester.tap(find.byTooltip('更多'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存二维码'));
    await tester.pump(const Duration(milliseconds: 400));
    await hostAction(tester, 'cancel-save');
    await tester.pumpAndSettle();
    expect(find.text('二维码已保存'), findsNothing);
    expect(find.text('二维码无法保存，请重试'), findsNothing);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawColor(Colors.white, BlendMode.src)
      ..translate(40, 40);
    QrPainter(
      data: userQrCode(8),
      version: QrVersions.auto,
    ).paint(canvas, const Size.square(400));
    final image = await recorder.endRecording().toImage(480, 480);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    await File(
      '${Directory.systemTemp.path}/native-synthetic-gallery.png',
    ).writeAsBytes(data!.buffer.asUint8List());
    await hostAction(tester, 'prepare-gallery');
    await tester.pumpWidget(MaterialApp(home: UserScannerPage(state: state)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('相册'));
    await tester.pump(const Duration(milliseconds: 400));
    await hostAction(tester, 'gallery');
    // A settled Flutter frame does not mean the native image decoder finished.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (find.text('UID 8').evaluate().isEmpty &&
        DateTime.now().isBefore(deadline)) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
    expect(api.scanned, [userQrCode(8)]);
    expect(find.text('Synthetic scanned user'), findsOneWidget);
    expect(find.text('UID 8'), findsOneWidget);
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    binding.reportData = {
      'nativeSave': 'saved PNG decoded to the displayed deposit address',
      'nativeShare':
          'actual Sharesheet opened and dismissed; no external messages sent',
      'cancelledSave': 'no success or failure message',
      'nativeGallery':
          'actual DocumentsUI image selected and decoded to the public user card',
    };
  });
}

class ExportQaApi extends NativeQaApi {
  final scanned = <String>[];
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = false,
  }) async {
    if (path != '/api/v1/users/scan') {
      throw StateError('Unexpected synthetic request');
    }
    scanned.add(body['qrCode'] as String);
    return {'userId': 8, 'displayName': 'Synthetic scanned user'};
  }
}
