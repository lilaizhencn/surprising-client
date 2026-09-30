import 'package:integration_test/integration_test.dart';
import '../test/account_display_test.dart' as account_tests;

// Exercise the same non-empty account fixtures and failure cases on a native
// runner. Network/security mutations remain mocked; production GETs are checked
// separately by tool/account_readonly_smoke.dart.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  account_tests.main();
}
