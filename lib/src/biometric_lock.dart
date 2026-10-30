import 'i18n/client_messages.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'app_state.dart';

/// Lives above the Navigator so nested account routes and bottom sheets are
/// covered too. A canceled prompt stays locked until an explicit retry or a
/// subsequent foreground entry.
class BiometricLockGate extends StatefulWidget {
  const BiometricLockGate({
    required this.state,
    required this.child,
    required this.onUsePassword,
    super.key,
  });

  final AppState state;
  final Widget child;
  final Future<void> Function() onUsePassword;

  @override
  State<BiometricLockGate> createState() => _BiometricLockGateState();
}

class _BiometricLockGateState extends State<BiometricLockGate>
    with WidgetsBindingObserver {
  late AppLifecycleState _lifecycle;
  bool _attemptedThisEntry = false;
  bool _scheduled = false;
  bool _usingPassword = false;

  bool get _foreground => _lifecycle == AppLifecycleState.resumed;
  bool get _background =>
      _lifecycle == AppLifecycleState.hidden ||
      _lifecycle == AppLifecycleState.paused ||
      _lifecycle == AppLifecycleState.detached;

  @override
  void initState() {
    super.initState();
    _lifecycle =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    widget.state.addListener(_stateChanged);
    widget.state.updateBiometricAppVisibility(foreground: _foreground);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateVisibility();
    });
    _scheduleUnlock();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycle = state;
    if (_background && !widget.state.biometricUnlocking) {
      _attemptedThisEntry = false;
    }
    _updateVisibility();
    if (mounted) setState(() {});
    _scheduleUnlock();
  }

  void _updateVisibility() => widget.state.updateBiometricAppVisibility(
    foreground: _foreground,
    lockSession: _background,
  );

  void _stateChanged() {
    if (_background && !widget.state.biometricUnlocking) {
      _attemptedThisEntry = false;
    }
    // Enabling biometrics may finish while the application is backgrounded.
    _updateVisibility();
    _scheduleUnlock();
    if (mounted) setState(() {});
  }

  void _scheduleUnlock() {
    if (!_foreground ||
        _attemptedThisEntry ||
        _scheduled ||
        _usingPassword ||
        !widget.state.canUnlockBiometricSession ||
        widget.state.biometricUnlocking) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!mounted ||
          !_foreground ||
          _attemptedThisEntry ||
          _usingPassword ||
          !widget.state.canUnlockBiometricSession ||
          widget.state.biometricUnlocking) {
        return;
      }
      _attemptedThisEntry = true;
      unawaited(widget.state.unlockBiometricSession());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.state.removeListener(_stateChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final locked = state.requiresBiometricUnlock || _usingPassword;
    final obscured = locked || (state.biometricLoginEnabled && !_foreground);
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: obscured,
          child: ExcludeFocus(excluding: obscured, child: widget.child),
        ),
        if (obscured)
          ScaffoldMessenger(
            child: Scaffold(
              body: SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(28),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.fingerprint,
                            size: 64,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 24),
                          LText(
                            '验证身份以解锁',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          const LText(
                            '请使用设备生物识别，保护你的交易账户',
                            textAlign: TextAlign.center,
                          ),
                          if (locked) ...[
                            if (state.biometricUnlockError != null) ...[
                              const SizedBox(height: 20),
                              LText(
                                state.biometricUnlockError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 28),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed:
                                    !_foreground ||
                                        !state.canUnlockBiometricSession ||
                                        state.biometricUnlocking ||
                                        _usingPassword
                                    ? null
                                    : () => unawaited(
                                        state.unlockBiometricSession(),
                                      ),
                                icon: state.biometricUnlocking
                                    ? const SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.fingerprint),
                                label: LText(
                                  state.biometricUnlocking ? '正在验证…' : '验证解锁',
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed:
                                  !_foreground ||
                                      state.biometricUnlocking ||
                                      _usingPassword
                                  ? null
                                  : () async {
                                      setState(() => _usingPassword = true);
                                      try {
                                        await widget.onUsePassword();
                                      } catch (_) {
                                        state.biometricSessionLocked = true;
                                        state.biometricUnlockError =
                                            '无法切换登录方式，请重试';
                                      } finally {
                                        if (mounted) {
                                          setState(
                                            () => _usingPassword = false,
                                          );
                                        }
                                      }
                                    },
                              child: const LText('使用账号密码登录'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
