import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/models/signaling_blob.dart';

void main() {
  test('round-trip offer', () {
    const payload = 'v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\n...';
    final blob = SignalingBlob(kind: BlobKind.offer, payload: payload);
    final encoded = blob.encode();
    final decoded = SignalingBlob.tryDecode(encoded);
    expect(decoded, isNotNull);
    expect(decoded!.kind, BlobKind.offer);
    expect(decoded.payload, payload);
  });

  test('round-trip ice', () {
    const payload = '{"candidate":"candidate:1 1 UDP ...","sdpMid":"0"}';
    final blob = SignalingBlob(kind: BlobKind.ice, payload: payload);
    final decoded = SignalingBlob.tryDecode(blob.encode());
    expect(decoded, isNotNull);
    expect(decoded!.kind, BlobKind.ice);
    expect(decoded.payload, payload);
  });

  test('rejects wrong version', () {
    expect(SignalingBlob.tryDecode('p2p2:offer:AAAA'), isNull);
  });

  test('rejects unknown kind', () {
    expect(SignalingBlob.tryDecode('p2p1:banana:AAAA'), isNull);
  });

  test('rejects malformed base64', () {
    expect(SignalingBlob.tryDecode('p2p1:offer:!!!'), isNull);
  });

  test('rejects empty', () {
    expect(SignalingBlob.tryDecode(''), isNull);
  });

  test('rejects without enough parts', () {
    expect(SignalingBlob.tryDecode('p2p1:offer'), isNull);
  });

  test('survives payloads with colons', () {
    const payload = 'v=0\nfoo:bar:baz';
    final blob = SignalingBlob(kind: BlobKind.answer, payload: payload);
    final decoded = SignalingBlob.tryDecode(blob.encode());
    expect(decoded!.payload, payload);
  });

  test('decodeIce returns null for non-ice kind', () {
    final blob = SignalingBlob(kind: BlobKind.offer, payload: '{}');
    expect(blob.decodeIce(), isNull);
  });

  test('decodeIce validates shape', () {
    final good = SignalingBlob(
      kind: BlobKind.ice,
      payload: '{"candidate":"c"}',
    );
    expect(good.decodeIce(), isNotNull);

    final bad = SignalingBlob(
      kind: BlobKind.ice,
      payload: '{"candidate":123}',
    );
    expect(bad.decodeIce(), isNull);
  });

  test('encode has no padding', () {
    final blob = SignalingBlob(kind: BlobKind.offer, payload: 'a');
    final encoded = blob.encode();
    expect(encoded.contains('='), isFalse);
  });
}