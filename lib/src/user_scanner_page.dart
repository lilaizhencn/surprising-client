import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'api.dart';
import 'app_state.dart';
import 'exchange_widgets.dart';
import 'models.dart';

String userQrCode(int userId) => 'surprising://user/$userId';

bool isUserQrCode(String value) {
  if (!RegExp(r'^surprising://user/[1-9][0-9]{0,18}$').hasMatch(value)) {
    return false;
  }
  final id = int.tryParse(value.substring('surprising://user/'.length));
  return id != null && id > 0;
}

class UserScannerPage extends StatefulWidget {
  const UserScannerPage({required this.state, super.key});
  final AppState state;
  @override
  State<UserScannerPage> createState() => _UserScannerPageState();
}

class _UserScannerPageState extends State<UserScannerPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final TabController tabs = TabController(length: 2, vsync: this);
  final camera = MobileScannerController(
    autoStart: false,
    formats: [BarcodeFormat.qrCode],
  );
  bool busy = false, foreground = true, selectingPhoto = false;
  bool disposed = false;
  Future<void> cameraOperation = Future<void>.value();
  Completer<bool>? photoResume;
  int generation = 0;
  String? identity, error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    tabs.addListener(_syncCamera);
    identity = widget.state.session?.accessToken;
    widget.state.addListener(_identityChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
  }

  void _identityChanged() {
    if (!mounted) return;
    final next = widget.state.session?.accessToken;
    if (next != identity) {
      identity = next;
      generation++;
      busy = false;
      error = null;
      if (photoResume?.isCompleted == false) photoResume!.complete(false);
      _syncCamera();
    }
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    if (foreground && photoResume?.isCompleted == false) {
      photoResume!.complete(true);
    }
    _syncCamera();
  }

  Future<bool> _resumePhoto() async {
    if (foreground) return true;
    final pending = photoResume = Completer<bool>();
    try {
      return await pending.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => false,
      );
    } finally {
      if (identical(photoResume, pending)) photoResume = null;
    }
  }

  Future<void> _syncCamera() {
    // A native start can still be waiting for permission when a tab, lifecycle
    // or route changes. Stop only after that start has finished.
    return cameraOperation = cameraOperation
        .then((_) async {
          if (disposed) return;
          final active =
              foreground &&
              tabs.index == 0 &&
              !busy &&
              !selectingPhoto &&
              widget.state.isLoggedIn;
          if (active) {
            await camera.start();
          } else {
            await camera.stop();
          }
        })
        .catchError((Object _) {});
  }

  Future<void> _read(String value) async {
    if (busy ||
        !foreground ||
        selectingPhoto ||
        !widget.state.isLoggedIn ||
        tabs.index != 0) {
      return;
    }
    if (!isUserQrCode(value)) {
      setState(() => error = '请扫描 Surprising 用户二维码');
      return;
    }
    final owner = identity, request = ++generation;
    setState(() {
      busy = true;
      error = null;
    });
    _syncCamera();
    try {
      final profile = await widget.state.api.post('/api/v1/users/scan', {
        'qrCode': value,
      });
      if (!mounted ||
          generation != request ||
          identity != owner ||
          !foreground ||
          tabs.index != 0) {
        return;
      }
      final id = asInt(profile['userId']);
      final name = asString(profile['displayName']);
      if (id <= 0 || userQrCode(id) != value || name.isEmpty) {
        throw const FormatException('用户信息暂不可用');
      }
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (context) => AnimatedBuilder(
          animation: widget.state,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
            child: identity != owner
                ? const Text('请重新登录')
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: Text(
                          name.characters.first,
                          style: TextStyle(
                            fontSize: 26,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      SelectableText('UID $id'),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('完成'),
                      ),
                    ],
                  ),
          ),
        ),
      );
    } catch (failure) {
      if (mounted && generation == request && identity == owner) {
        setState(
          () => error = failure is ApiException && failure.statusCode == 404
              ? '用户暂不可用'
              : '识别失败，请重试',
        );
      }
    } finally {
      if (mounted && generation == request) {
        setState(() => busy = false);
        _syncCamera();
      }
    }
  }

  Future<void> _photo() async {
    if (busy || selectingPhoto) return;
    selectingPhoto = true;
    final owner = identity;
    try {
      await _syncCamera();
      final selection = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );
      // Activity results may arrive before the app resumes. Keep the selected
      // image until foreground processing is possible, rather than dropping it.
      if (!mounted || owner != identity || !await _resumePhoto()) return;
      if (!mounted || owner != identity || tabs.index != 0) return;
      final path = selection?.files.single.path;
      if (path == null) return;
      final result = await camera.analyzeImage(
        path,
        formats: [BarcodeFormat.qrCode],
      );
      if (!mounted || owner != identity || !await _resumePhoto()) return;
      if (!mounted || owner != identity) return;
      final code = result?.barcodes
          .map((barcode) => barcode.rawValue)
          .whereType<String>()
          .firstOrNull;
      selectingPhoto = false;
      if (code == null) {
        setState(() => error = '图片中未找到二维码');
      } else {
        await _read(code);
      }
    } catch (_) {
      if (mounted && owner == identity) setState(() => error = '无法读取图片，请重试');
    } finally {
      selectingPhoto = false;
      _syncCamera();
    }
  }

  @override
  void dispose() {
    disposed = true;
    if (photoResume?.isCompleted == false) photoResume!.complete(false);
    generation++;
    widget.state.removeListener(_identityChanged);
    WidgetsBinding.instance.removeObserver(this);
    tabs.removeListener(_syncCamera);
    tabs.dispose();
    unawaited(
      cameraOperation
          .then((_) async {
            await camera.stop();
            await camera.dispose();
          })
          .catchError((Object _) {}),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return Scaffold(
      backgroundColor: exchangeBackground(context),
      appBar: AppBar(
        title: const Text('扫一扫'),
        backgroundColor: exchangeBackground(context),
        bottom: TabBar(
          controller: tabs,
          tabs: const [
            Tab(text: '扫一扫'),
            Tab(text: '我的二维码'),
          ],
        ),
      ),
      body: !state.isLoggedIn
          ? const Center(child: Text('请先登录'))
          : TabBarView(
              controller: tabs,
              children: [
                Column(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              MobileScanner(
                                controller: camera,
                                useAppLifecycleState: false,
                                onDetect: (capture) {
                                  if (selectingPhoto) return;
                                  final value = capture.barcodes
                                      .map((barcode) => barcode.rawValue)
                                      .whereType<String>()
                                      .firstOrNull;
                                  if (value != null) unawaited(_read(value));
                                },
                                errorBuilder: (context, _) => Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.no_photography_outlined,
                                        size: 44,
                                      ),
                                      const SizedBox(height: 16),
                                      const Text('请允许相机访问'),
                                      TextButton(
                                        onPressed: _syncCamera,
                                        child: const Text('重试'),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (busy) const CircularProgressIndicator(),
                              IgnorePointer(
                                child: Container(
                                  width: 220,
                                  height: 220,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 8,
                        ),
                        child: Text(
                          error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            onPressed: busy
                                ? null
                                : () => unawaited(
                                    camera.toggleTorch().catchError(
                                      (Object _) {},
                                    ),
                                  ),
                            tooltip: '手电筒',
                            icon: const Icon(Icons.flashlight_on_outlined),
                          ),
                          TextButton.icon(
                            onPressed: busy ? null : _photo,
                            icon: const Icon(Icons.photo_library_outlined),
                            label: const Text('相册'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                ListView(
                  padding: const EdgeInsets.all(28),
                  children: [
                    const SizedBox(height: 40),
                    Text(
                      state.session!.user.name,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 30),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: QrImageView(
                          data: userQrCode(state.userId!),
                          size: 240,
                          backgroundColor: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SelectableText(
                      'UID ${state.userId}',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
