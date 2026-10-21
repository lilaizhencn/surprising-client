import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/sensitive_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('screen_protector');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'does not reveal balances until native screenshot protection is active',
    (tester) async {
      final enabled = Completer<void>();
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        if (call.method == 'preventScreenshotOn') await enabled.future;
        return null;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: SensitiveScreen(child: Text('private balance')),
        ),
      );
      expect(find.text('private balance'), findsNothing);
      enabled.complete();
      await tester.pumpAndSettle();
      expect(find.text('private balance'), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: Text('public page')));
      await tester.pumpAndSettle();
      expect(calls, ['preventScreenshotOn', 'preventScreenshotOff']);
    },
  );

  testWidgets(
    'native failure keeps sensitive balances hidden and supports retry',
    (tester) async {
      var fail = true;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'preventScreenshotOn' && fail) {
          throw PlatformException(code: 'not_ready');
        }
        return null;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: SensitiveScreen(child: Text('private balance')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('private balance'), findsNothing);
      expect(find.text('安全保护未启用'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('private balance'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'iOS also shields background snapshots and restores the window on exit',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final calls = <String>[];
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call.method);
        return null;
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: SensitiveScreen(child: Text('private balance')),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, ['preventScreenshotOn', 'protectDataLeakageWithColor']);
      await tester.pumpWidget(const MaterialApp(home: Text('public page')));
      await tester.pumpAndSettle();
      expect(calls, [
        'preventScreenshotOn',
        'protectDataLeakageWithColor',
        'preventScreenshotOff',
        'protectDataLeakageWithColorOff',
      ]);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('closing either overlapping route keeps the other protected', (
    tester,
  ) async {
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    Widget routes({required bool first}) => MaterialApp(
      home: Stack(
        children: [
          if (first)
            const SensitiveScreen(key: ValueKey(1), child: Text('first')),
          const SensitiveScreen(key: ValueKey(2), child: Text('second')),
        ],
      ),
    );
    await tester.pumpWidget(routes(first: true));
    await tester.pumpAndSettle();
    expect(find.text('first'), findsOneWidget);
    expect(find.text('second'), findsOneWidget);
    expect(calls, ['preventScreenshotOn']);
    await tester.pumpWidget(routes(first: false));
    await tester.pumpAndSettle();
    expect(find.text('second'), findsOneWidget);
    expect(calls, ['preventScreenshotOn']);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(calls, ['preventScreenshotOn', 'preventScreenshotOff']);
  });

  testWidgets('closing while enable is pending releases after native enable', (
    tester,
  ) async {
    final enabled = Completer<void>();
    final calls = <String>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'preventScreenshotOn') await enabled.future;
      return null;
    });
    await tester.pumpWidget(
      const MaterialApp(home: SensitiveScreen(child: Text('secret'))),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(calls, ['preventScreenshotOn']);
    enabled.complete();
    await tester.pumpAndSettle();
    expect(find.text('secret'), findsNothing);
    expect(calls, ['preventScreenshotOn', 'preventScreenshotOff']);
  });
}
