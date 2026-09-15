import 'package:flutter_test/flutter_test.dart';
import 'package:hermes_android/core/services/bridge_client.dart';
import 'package:hermes_android/core/services/bridge_manager.dart';

void main() {
  test('memory is writable only from authenticated Bridge capabilities', () {
    BridgeState state(
      Map<String, dynamic> operations, {
      bool readOnly = false,
    }) {
      return BridgeState(
        status: BridgeStatus.connected,
        url: 'https://bridge.example',
        urlIsDerived: false,
        hasToken: true,
        caps: BridgeCapabilities.fromJson({
          'read_only': readOnly,
          'operations': operations,
        }),
      );
    }

    expect(bridgeMemoryWritable(state({'memory_write': true})), isTrue);
    expect(bridgeMemoryWritable(state({'memory_write': false})), isFalse);
    expect(
      bridgeMemoryWritable(state({'memory_write': true}, readOnly: true)),
      isFalse,
    );
    expect(
      bridgeMemoryWritable(
        const BridgeState(
          status: BridgeStatus.needsToken,
          url: 'https://bridge.example',
          urlIsDerived: false,
          hasToken: false,
          caps: BridgeCapabilities(online: true),
        ),
      ),
      isFalse,
    );
  });
}
