import 'package:integration_test/integration_test_driver.dart';

// flutter drive supports native Android AOT profile mode; flutter test does not.
Future<void> main() => integrationDriver(
  timeout: const Duration(minutes: 12),
  responseDataCallback: null,
);
