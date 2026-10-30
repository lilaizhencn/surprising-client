import 'i18n/client_messages.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:screen_protector/screen_protector.dart';

/// The withdrawal route owns native capture protection until the flow is closed.
/// Balances are not mounted before native protection has been enabled.
class SensitiveScreen extends StatefulWidget {
  const SensitiveScreen({required this.child, super.key});
  final Widget child;
  @override
  State<SensitiveScreen> createState() => _SensitiveScreenState();
}

class _SensitiveScreenState extends State<SensitiveScreen> {
  bool protected = false, failed = false;
  bool protecting = false;
  final lease = Object();
  final isIos = defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    unawaited(_protect());
  }

  Future<void> _protect() async {
    if (protecting || protected) return;
    protecting = true;
    setState(() => failed = false);
    try {
      await _WindowProtection.acquire(lease, isIos: isIos);
      if (mounted) setState(() => protected = true);
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      protecting = false;
    }
  }

  @override
  void dispose() {
    unawaited(_WindowProtection.release(lease, isIos: isIos));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => protected
      ? widget.child
      : Scaffold(
          appBar: AppBar(title: const LText('提币')),
          body: Center(
            child: failed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.shield_outlined, size: 40),
                      const SizedBox(height: 16),
                      const LText('安全保护未启用'),
                      TextButton(onPressed: _protect, child: const LText('重试')),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        );
}

/// Capture protection belongs to the native window, which can contain several
/// protected routes. Serialize changes so a closing route cannot expose another.
abstract final class _WindowProtection {
  static final _owners = <Object>{};
  static Future<void>? _tail;

  static Future<void> _enqueue(Future<void> Function() action) {
    final previous = _tail;
    final completed = Completer<void>();
    _tail = completed.future;
    unawaited(() async {
      try {
        if (previous != null) await previous.catchError((Object _) {});
        await action();
        completed.complete();
      } catch (error, stack) {
        completed.completeError(error, stack);
      } finally {
        if (identical(_tail, completed.future)) _tail = null;
      }
    }());
    return completed.future;
  }

  static Future<void> acquire(Object owner, {required bool isIos}) =>
      _enqueue(() async {
        if (_owners.contains(owner)) return;
        if (_owners.isEmpty) {
          try {
            await ScreenProtector.preventScreenshotOn();
            if (isIos) {
              await ScreenProtector.protectDataLeakageWithColor(Colors.black);
            }
          } catch (_) {
            await _disable(isIos: isIos);
            rethrow;
          }
        }
        _owners.add(owner);
      });

  static Future<void> release(Object owner, {required bool isIos}) =>
      _enqueue(() async {
        if (_owners.remove(owner) && _owners.isEmpty) {
          await _disable(isIos: isIos);
        }
      });

  static Future<void> _disable({required bool isIos}) async {
    await ScreenProtector.preventScreenshotOff().catchError((Object _) {});
    if (isIos) {
      await ScreenProtector.protectDataLeakageWithColorOff().catchError(
        (Object _) {},
      );
    }
  }
}
