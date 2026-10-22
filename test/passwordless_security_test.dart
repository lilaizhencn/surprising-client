import 'support/authentication.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/app.dart';
import 'package:surprising_client/src/app_state.dart';
import 'package:surprising_client/src/models.dart';
import 'account_display_test.dart' show AccountApi, session;

Future<void> openSecurity(WidgetTester tester, AppState state) async {
  await tester.pumpWidget(
    AppScope(
      notifier: state,
      child: const MaterialApp(home: Scaffold(body: SecuritySheet())),
    ),
  );
  await tester.pumpAndSettle();
}

Finder input(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  test(
    'primary metadata cannot default an unknown account to passwordless',
    () {
      for (final invalid in <Map<String, dynamic>>[
        {},
        {'passwordRequired': false},
        {'passwordRequired': false, 'reauthenticationRequired': false},
        {
          'passwordRequired': false,
          'reauthenticationRequired': true,
          'authenticatedUntil': 'invalid',
        },
      ]) {
        expect(
          () => PrimaryAuthenticationContext.fromJson(invalid),
          throwsFormatException,
        );
      }
    },
  );

  testWidgets(
    'fresh passwordless account binds a new contact without a password and still submits its code',
    (tester) async {
      final api = PasswordlessApi();
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await openSecurity(tester, state);
      await tester.ensureVisible(find.text('启用/绑定').first);
      await tester.tap(find.text('启用/绑定').first);
      await tester.pumpAndSettle();
      expect(input('登录密码'), findsNothing);
      expect(api.binds, isEmpty);
      await tester.enterText(input('邮箱'), 'new@example.test');
      await tester.tap(find.widgetWithText(FilledButton, '发送验证码'));
      await tester.pumpAndSettle();
      expect(api.binds.single, {
        'method': 'EMAIL',
        'password': '',
        'destination': 'new@example.test',
      });
      final code = input('邮箱验证码').first;
      await tester.ensureVisible(code);
      await tester.enterText(code, '123456');
      await tester.ensureVisible(find.text('确认绑定'));
      await tester.tap(find.text('确认绑定'));
      await tester.pumpAndSettle();
      expect(api.confirmed, {
        'method': 'EMAIL',
        'password': '',
        'code': '123456',
      });
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'expired primary authentication requests a new login before issuing a code',
    (tester) async {
      final api = PasswordlessApi()..expired = true;
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await openSecurity(tester, state);
      expect(find.text('重新登录验证身份'), findsOneWidget);
      await tester.ensureVisible(find.text('启用/绑定').first);
      await tester.tap(find.text('启用/绑定').first);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('请重新登录后继续安全设置'), findsOneWidget);
      expect(api.binds, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a late primary context cannot open a dialog after account logout',
    (tester) async {
      final api = PasswordlessApi();
      final state = AppState(
        initialSession: session,
        sessionStore: MemorySessionStore(),
        offline: true,
        apiClient: api,
      );
      addTearDown(state.dispose);
      await openSecurity(tester, state);
      api.pendingPrimary = Completer<PrimaryAuthenticationContext>();
      await tester.ensureVisible(find.text('启用/绑定').first);
      await tester.tap(find.text('启用/绑定').first);
      await tester.pump();
      await state.logout();
      await tester.pump();
      api.pendingPrimary!.complete(api.context);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(api.binds, isEmpty);
      expect(find.text('登录已失效，请重新登录'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class PasswordlessApi extends AccountApi {
  bool expired = false, bound = false;
  Completer<PrimaryAuthenticationContext>? pendingPrimary;
  final binds = <Map<String, String?>>[];
  Map<String, String>? confirmed;
  PrimaryAuthenticationContext get context => PrimaryAuthenticationContext(
    passwordRequired: false,
    reauthenticationRequired: expired,
    authenticatedUntil: DateTime.now().add(Duration(minutes: expired ? -1 : 5)),
  );
  @override
  Future<PrimaryAuthenticationContext> primaryAuthentication() async =>
      pendingPrimary?.future ?? context;
  @override
  Future<Map<String, dynamic>> mfaStatus() async => {'enabled': false};
  @override
  Future<List<Map<String, dynamic>>> loginVerificationMethods() async => [
    {
      'type': 'EMAIL',
      'bound': bound,
      'enabled': bound,
      'destination': bound ? 'n***@example.test' : null,
    },
    {'type': 'PHONE', 'bound': false, 'enabled': false, 'destination': null},
    {'type': 'TOTP', 'bound': false, 'enabled': false, 'destination': null},
  ];
  @override
  Future<Map<String, dynamic>> beginLoginMethod({
    required String method,
    required String currentPassword,
    required bool enabled,
    String? destination,
  }) async {
    binds.add({
      'method': method,
      'password': currentPassword,
      'destination': destination,
    });
    return {
      'challenge': {
        'challengeToken': 'c' * 43,
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 5))
            .toIso8601String(),
        'methods': [
          {'type': 'EMAIL', 'destination': 'n***@example.test'},
        ],
      },
    };
  }

  @override
  Future<void> confirmLoginMethod({
    required String method,
    required String currentPassword,
    required String challengeToken,
    String? emailCode,
    String? phoneCode,
    String? totpCode,
  }) async {
    expect(challengeToken, 'c' * 43);
    confirmed = {
      'method': method,
      'password': currentPassword,
      'code': emailCode ?? '',
    };
    bound = true;
  }
}
