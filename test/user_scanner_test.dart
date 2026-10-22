import 'dart:async';
import 'package:file_picker/file_picker.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/user_scanner_page.dart';
import 'account_display_test.dart' show session;
import 'support/authentication.dart';

const attributes = MobileScannerViewAttributes(
  cameraDirection: CameraFacing.back,
  currentTorchMode: TorchState.off,
  size: Size(320, 480),
);

void main() {
  late ScannerPlatform platform;
  late MobileScannerPlatform previous;
  late FilePicker previousPicker;
  setUp(() {
    try {
      previousPicker = FilePicker.platform;
    } on Error {
      previousPicker = FilePickerIO();
    }
    FilePicker.platform = previousPicker;
    previous = MobileScannerPlatform.instance;
    platform = ScannerPlatform();
    MobileScannerPlatform.instance = platform;
  });
  tearDown(() async {
    await platform.captures.close();
    MobileScannerPlatform.instance = previous;
    FilePicker.platform = previousPicker;
  });

  testWidgets(
    'gallery result arriving before resume is processed after resume',
    (tester) async {
      final picker = ScannerPhotoPicker();
      FilePicker.platform = picker;
      final api = ScannerApi();
      final state = _ScannerState(api: api);
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(home: UserScannerPage(state: state)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('相册'));
      await tester.pumpAndSettle();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      picker.result.complete(
        FilePickerResult([
          PlatformFile(name: 'synthetic.png', path: '/synthetic.png', size: 10),
        ]),
      );
      await tester.pumpAndSettle();
      expect(api.requests, isEmpty);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(api.requests, [userQrCode(9)]);
      api.response.complete({'userId': 9, 'displayName': '相册用户'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('相册用户'), findsOneWidget);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'swiping away during permission request stops the late camera start',
    (tester) async {
      platform.startResult = Completer<MobileScannerViewAttributes>();
      final state = _ScannerState();
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(home: UserScannerPage(state: state)));
      await tester.pump();
      expect(platform.starts, 1);
      await tester.drag(find.byType(TabBarView), const Offset(-600, 0));
      await tester.pump(const Duration(milliseconds: 500));
      platform.startResult!.complete(attributes);
      await tester.pumpAndSettle();
      expect(platform.running, isFalse);
      expect(platform.stops, 1);
      expect(find.text('UID 1'), findsOneWidget);
      await tester.drag(find.byType(TabBarView), const Offset(600, 0));
      await tester.pumpAndSettle();
      expect(platform.running, isTrue);
      expect(platform.starts, 2);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(platform.running, isFalse);
      expect(platform.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  for (final closePage in [false, true]) {
    testWidgets(
      'pending gallery resume cancels on ${closePage ? "disposal" : "logout"}',
      (tester) async {
        final previousPicker = FilePicker.platform;
        final picker = ScannerPhotoPicker();
        FilePicker.platform = picker;
        addTearDown(() => FilePicker.platform = previousPicker);
        final api = ScannerApi();
        final state = _ScannerState(api: api);
        addTearDown(state.dispose);
        await tester.pumpWidget(
          MaterialApp(home: UserScannerPage(state: state)),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('相册'));
        await tester.pumpAndSettle();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        picker.result.complete(
          FilePickerResult([
            PlatformFile(
              name: 'synthetic.png',
              path: '/synthetic.png',
              size: 10,
            ),
          ]),
        );
        await tester.pumpAndSettle();
        if (closePage) {
          await tester.pumpWidget(const SizedBox());
        } else {
          await state.logout();
        }
        await tester.pump();
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(api.requests, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'closing while permission is pending releases the eventual camera session',
    (tester) async {
      platform.startResult = Completer<MobileScannerViewAttributes>();
      final state = _ScannerState();
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(home: UserScannerPage(state: state)));
      await tester.pump();
      expect(platform.starts, 1);
      await tester.pumpWidget(const SizedBox());
      platform.startResult!.complete(attributes);
      await tester.pumpAndSettle();
      expect(platform.running, isFalse);
      expect(platform.stops, 1);
      expect(platform.disposals, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'scan results are public cards, reject external QR and discard late account results',
    (tester) async {
      final api = ScannerApi();
      final state = _ScannerState(api: api);
      addTearDown(state.dispose);
      await tester.pumpWidget(MaterialApp(home: UserScannerPage(state: state)));
      await tester.pumpAndSettle();
      void scan(String value) => platform.captures.add(
        BarcodeCapture(barcodes: [Barcode(rawValue: value)]),
      );
      scan('https://external.example/');
      await tester.pumpAndSettle();
      expect(api.requests, isEmpty);
      expect(find.text('请扫描 Surprising 用户二维码'), findsOneWidget);
      scan(userQrCode(9));
      await tester.pump();
      expect(api.requests, [userQrCode(9)]);
      await state.logout();
      await tester.pump();
      api.response.complete({'userId': 9, 'displayName': '迟到的资料'});
      await tester.pumpAndSettle();
      expect(find.text('迟到的资料'), findsNothing);
      expect(find.text('请先登录'), findsOneWidget);
      await signInAs(state, session);
      api.response = Completer<Map<String, dynamic>>();
      await tester.pumpAndSettle();
      scan(userQrCode(9));
      await tester.pump();
      api.response.complete({'userId': 9, 'displayName': '合成用户'});
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('合成用户'), findsOneWidget);
      expect(find.text('UID 9'), findsOneWidget);
      expect(platform.running, isFalse);
      await tester.tap(find.text('完成'));
      await tester.pumpAndSettle();
      expect(platform.running, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}

class _ScannerState extends AppState {
  _ScannerState({ScannerApi? api})
    : super(
        initialSession: session,
        apiClient: api ?? ScannerApi(),
        sessionStore: MemorySessionStore(),
        config: const AppConfig(websocketUrl: ''),
      );

  @override
  Future<void> refreshPrivateData() async {}
}

class ScannerApi extends TestApiClient {
  final requests = <String>[];
  Completer<Map<String, dynamic>> response = Completer();
  @override
  Future<Map<String, dynamic>> post(
    String path,
    Map<String, dynamic> body, {
    int? userId,
    String? productLine,
    Map<String, String>? headers,
    bool unwrapResponseResult = false,
  }) {
    expect(path, '/api/v1/users/scan');
    requests.add(body['qrCode'] as String);
    return response.future;
  }
}

class ScannerPlatform extends MobileScannerPlatform {
  final captures = StreamController<BarcodeCapture?>.broadcast();
  Completer<MobileScannerViewAttributes>? startResult;
  int starts = 0, stops = 0, disposals = 0;
  bool running = false;
  @override
  Future<BarcodeCapture?> analyzeImage(
    String path, {
    List<BarcodeFormat> formats = const [],
  }) async => BarcodeCapture(barcodes: [Barcode(rawValue: userQrCode(9))]);
  @override
  Stream<BarcodeCapture?> get barcodesStream => captures.stream;
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const ColoredBox(color: Colors.black);
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    starts++;
    final result = startResult == null || startResult!.isCompleted
        ? attributes
        : await startResult!.future;
    running = true;
    return result;
  }

  @override
  Future<void> stop() async {
    stops++;
    running = false;
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

class ScannerPhotoPicker extends FilePicker {
  final result = Completer<FilePickerResult?>();
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
  }) => result.future;
}
