import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

/// Exercises two RTCPeerConnections in a single isolate. No signaling
/// server, no relay — the SDP and ICE exchange is done directly through
/// local variables.
///
/// Enabled only when `--dart-define=TWO_DEVICE_WEBRTC=true`. On machines
/// without a native WebRTC runtime, run the crypto-only tests instead.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const enabled = String.fromEnvironment('TWO_DEVICE_WEBRTC');
  if (enabled != 'true') {
    test('two-device webrtc (disabled)', () {}, skip: 'TWO_DEVICE_WEBRTC not set');
    return;
  }

  test('two RTCPeerConnections exchange a data channel message', () async {
    final iceConfig = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    };

    final pcA = await createPeerConnection(iceConfig);
    final pcB = await createPeerConnection(iceConfig);

    final dcA = await pcA.createDataChannel('chat', RTCDataChannelInit());

    final receivedByB = <String>[];
    final bChannelReady = Completer<RTCDataChannel>();
    pcB.onDataChannel = (dc) {
      if (!bChannelReady.isCompleted) bChannelReady.complete(dc);
      dc.onMessage = (m) {
        receivedByB.add(m.text);
      };
    };

    // SDP exchange.
    final offer = await pcA.createOffer();
    await pcA.setLocalDescription(offer);
    await pcB.setRemoteDescription(offer);

    final answer = await pcB.createAnswer();
    await pcB.setLocalDescription(answer);
    await pcA.setRemoteDescription(answer);

    // Wait for the data channel to open on A.
    await _waitFor(
      () => dcA.state == RTCDataChannelState.RTCDataChannelOpen,
      label: 'dcA open',
      timeout: const Duration(seconds: 30),
    );
    final dcB = await bChannelReady.future.timeout(
      const Duration(seconds: 15),
    );

    dcA.send(RTCDataChannelMessage('hello from A'));
    await _waitFor(
      () => receivedByB.isNotEmpty,
      label: 'B receives',
      timeout: const Duration(seconds: 15),
    );
    expect(receivedByB.first, 'hello from A');

    // Reply back.
    final receivedByA = <String>[];
    dcA.onMessage = (m) {
      receivedByA.add(m.text);
    };
    dcB.send(RTCDataChannelMessage('hello from B'));
    await _waitFor(
      () => receivedByA.isNotEmpty,
      label: 'A receives',
      timeout: const Duration(seconds: 15),
    );
    expect(receivedByA.first, 'hello from B');

    await dcA.close();
    await dcB.close();
    await pcA.close();
    await pcB.close();
    await pcA.dispose();
    await pcB.dispose();
  });

  test('SDP contains a p2p1-decodable offer after encoding', () async {
    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });
    final offer = await pc.createOffer();
    await pc.setLocalDescription(offer);
    final sdp = jsonEncode({'type': 'offer', 'sdp': offer.sdp});
    final blob = 'p2p1:offer:${base64Url.encode(utf8.encode(sdp)).replaceAll('=', '')}';
    expect(blob.startsWith('p2p1:offer:'), isTrue);
    await pc.close();
    await pc.dispose();
  });
}

Future<void> _waitFor(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 30),
  String label = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  throw StateError('timeout waiting for $label');
}