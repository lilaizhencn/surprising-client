import 'package:integration_test/integration_test.dart';
import '../test/mobile_account_parity_test.dart' as parity;

// Financial and security mutations use local fixtures on the native runner.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  parity.main();
}
