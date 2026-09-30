// Reads production asset/security views. No transfer, withdrawal, key creation,
// password change, enrollment, revocation or verification-setting mutation.
import 'dart:io';
import 'package:surprising_client/src/api.dart';
import 'package:surprising_client/src/models.dart';

Future<void> main() async {
  final echo = stdin.echoMode;
  late String identifier, password;
  try {
    stdin.echoMode = false;
    stdout.writeln('Enter account and password on separate lines (hidden):');
    identifier = stdin.readLineSync() ?? '';
    password = stdin.readLineSync() ?? '';
  } finally {
    stdin.echoMode = echo;
  }
  final http = HttpClient();
  final api = ApiClient(const AppConfig(), httpClient: http);
  var failed = 0;
  try {
    final session = await api.login(username: identifier, password: password);
    api.setSession(session);
    stdout.writeln('LOGIN succeeded');
    Future<void> read(String label, Future<String> Function() request) async {
      try {
        stdout.writeln('$label: ${await request()}');
      } catch (error) {
        failed++;
        stdout.writeln(
          '$label: FAILED ${error is ApiException ? 'HTTP ${error.statusCode}' : error.runtimeType}',
        );
      }
    }

    await Future.wait([
      read(
        'Funding portfolio',
        () async =>
            'assets=${(await api.walletPortfolio(session.user.userId)).assets.length}',
      ),
      read(
        'Funding records',
        () async =>
            'rows=${(await api.walletOrders(session.user.userId)).length}',
      ),
      read('MFA', () async {
        final value = await api.mfaStatus();
        return 'status present=${value.containsKey('enabled') || value.containsKey('enrolled')}';
      }),
      read(
        'Security scenes',
        () async => 'rows=${(await api.securityScenes()).length}',
      ),
      read('API keys', () async => 'rows=${(await api.apiKeys()).length}'),
      read('KYC', () async => 'status=${(await api.kycStatus())['status']}'),
      read(
        'KYC documents',
        () async => 'rows=${(await api.kycDocuments()).length}',
      ),
      read(
        'Login verification',
        () async => 'methods=${(await api.loginVerificationMethods()).length}',
      ),
      read('Sessions', () async {
        final value = await api.userSessions();
        return 'rows=${asList(value['sessions']).length} hasMore=${value['hasMore']}';
      }),
      read('Login history', () async {
        final value = await api.loginHistory();
        return 'rows=${asList(value['logs']).length} hasMore=${value['hasMore']}';
      }),
      for (final currency in ['USD', 'CNY'])
        read('USDT/$currency', () async {
          final rate = await api.exchangeRateConversion(
            fromCurrency: 'USDT',
            toCurrency: currency,
          );
          return 'positive finite rate=${rate.isFinite && rate > 0}';
        }),
    ]);
    stdout.writeln('READ-ONLY CHECK: failures=$failed');
    if (failed > 0) exitCode = 1;
  } catch (error) {
    stderr.writeln(
      'CHECK FAILED: ${error is ApiException ? 'HTTP ${error.statusCode}' : error.runtimeType}',
    );
    exitCode = 1;
  } finally {
    http.close(force: true);
  }
}
