import 'package:flutter_test/flutter_test.dart';
import 'package:p2p_chat/models/signaling_blob.dart';

void main() {
  group('SignalingBlob', () {
    test('offer round-trip', () {
      const payload = 'v=0\r\no=- 123 2 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n';
      final blob = SignalingBlob(kind: BlobKind.offer, payload: payload);
      final decoded = SignalingBlob.tryDecode(blob.encode());
      expect(decoded, isNotNull);
      expect(decoded!.kind, BlobKind.offer);
      expect(decoded.payload, payload);
    });

    test('answer round-trip', () {
      const payload = 'v=0\r\ns=-\r\n';
      final blob = SignalingBlob(kind: BlobKind.answer, payload: payload);
      final decoded = SignalingBlob.tryDecode(blob.encode());
      expect(decoded!.kind, BlobKind.answer);
      expect(decoded.payload, payload);
    });

    test('ice round-trip', () {
      const payload =
          '{"candidate":"candidate:1 1 UDP 2122252543 192.168.1.1 50000 typ host","sdpMid":"0","sdpMLineIndex":0}';
      final blob = SignalingBlob(kind: BlobKind.ice, payload: payload);
      final decoded = SignalingBlob.tryDecode(blob.encode());
      expect(decoded!.kind, BlobKind.ice);
      expect(decoded.payload, payload);
    });

    test('rejects wrong version tag', () {
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

    test('rejects missing parts', () {
      expect(SignalingBlob.tryDecode('p2p1:offer'), isNull);
    });

    test('rejects extra parts', () {
      expect(SignalingBlob.tryDecode('p2p1:offer:AAAA:BBBB'), isNull);
    });

    test('handles payload containing colons', () {
      const payload = 'v=0\nfoo:bar:baz:qux';
      final blob = SignalingBlob(kind: BlobKind.offer, payload: payload);
      final decoded = SignalingBlob.tryDecode(blob.encode());
      expect(decoded!.payload, payload);
    });

    test('handles payload containing newlines', () {
      const payload = 'line1\nline2\r\nline3';
      final blob = SignalingBlob(kind: BlobKind.offer, payload: payload);
      final decoded = SignalingBlob.tryDecode(blob.encode());
      expect(decoded!.payload, payload);
    });

    test('encode has no padding', () {
      final blob = SignalingBlob(kind: BlobKind.offer, payload: 'a');
      expect(blob.encode().contains('='), isFalse);
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

      final notJson = SignalingBlob(kind: BlobKind.ice, payload: 'not-json');
      expect(notJson.decodeIce(), isNull);
    });

    test('decodeSdp validates shape', () {
      final good = SignalingBlob(
        kind: BlobKind.offer,
        payload: '{"type":"offer","sdp":"v=0"}',
      );
      expect(good.decodeSdp(), isNotNull);

      final bad = SignalingBlob(
        kind: BlobKind.offer,
        payload: '{"type":"offer"}',
      );
      expect(bad.decodeSdp(), isNull);
    });

    test('equality and hashCode', () {
      const a = SignalingBlob(kind: BlobKind.offer, payload: 'x');
      const b = SignalingBlob(kind: BlobKind.offer, payload: 'x');
      const c = SignalingBlob(kind: BlobKind.offer, payload: 'y');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}