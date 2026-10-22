import 'package:flutter_test/flutter_test.dart';
import 'package:surprising_client/src/models.dart';
import 'package:surprising_client/src/private_snapshot_recovery.dart';

void main() {
  testWidgets(
    'initial subscriptions wait once and unavailable products pause',
    (tester) async {
      final requests = <ProductMode>[];
      final recovery = PrivateSnapshotRecovery(
        ready: (_) => false,
        resubscribe: requests.add,
        reconnect: () {},
      );
      recovery.awaitSnapshot(ProductMode.spot);
      recovery.awaitSnapshot(ProductMode.spot);
      recovery.awaitSnapshot(ProductMode.option);
      recovery.pause(ProductMode.option);
      expect(requests, isEmpty);
      await tester.pump(const Duration(seconds: 3));
      expect(requests, [ProductMode.spot]);
      recovery.dispose();
    },
  );

  testWidgets(
    'private baseline recovery coalesces per product and stops on a valid snapshot',
    (tester) async {
      var ready = false;
      final requests = <ProductMode>[];
      var reconnects = 0;
      final recovery = PrivateSnapshotRecovery(
        ready: (_) => ready,
        resubscribe: requests.add,
        reconnect: () => reconnects++,
      );
      recovery.observe(ProductMode.spot);
      recovery.observe(ProductMode.spot);
      recovery.observe(ProductMode.linear);
      expect(requests, [ProductMode.spot, ProductMode.linear]);
      await tester.pump(const Duration(seconds: 3));
      expect(requests, hasLength(4));
      ready = true;
      recovery.observe(ProductMode.spot);
      recovery.observe(ProductMode.linear);
      await tester.pump(const Duration(minutes: 1));
      expect(requests, hasLength(4));
      expect(reconnects, 0);
      recovery.dispose();
    },
  );

  testWidgets(
    'missing private baselines reconnect once after bounded backoff',
    (tester) async {
      var requests = 0, reconnects = 0;
      final recovery = PrivateSnapshotRecovery(
        ready: (_) => false,
        resubscribe: (_) => requests++,
        reconnect: () => reconnects++,
      );
      recovery.observe(ProductMode.spot);
      recovery.observe(ProductMode.linear);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 6));
      expect(requests, 6);
      await tester.pump(const Duration(seconds: 12));
      expect(reconnects, 1);
      await tester.pump(const Duration(minutes: 1));
      expect(reconnects, 1);
      recovery.dispose();
    },
  );

  testWidgets(
    'account reset and disposal cancel all previous recovery callbacks',
    (tester) async {
      var callbacks = 0;
      final recovery = PrivateSnapshotRecovery(
        ready: (_) => false,
        resubscribe: (_) => callbacks++,
        reconnect: () => callbacks++,
      );
      recovery.observe(ProductMode.spot);
      recovery.reset();
      await tester.pump(const Duration(minutes: 1));
      expect(callbacks, 1);
      recovery.observe(ProductMode.linear);
      recovery.dispose();
      await tester.pump(const Duration(minutes: 1));
      expect(callbacks, 2);
    },
  );
}
