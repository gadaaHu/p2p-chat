import 'dart:convert';
import 'dart:typed_data';

/// The wire format. Version 3.
///
/// Two parties exchange only these. The relay (if present in a future
/// version) sees `from`, `to`, `message_id`, and the ciphertext. It never
/// sees the plaintext, the group membership, or the message kind.
///
/// Layout:
///   - `nonce` — 12 bytes, base64
///   - `ciphertext` — AES-256-GCM output, no tag
///   - `tag` — 16-byte GCM tag, base64
///   - `counter` — monotonic per (sender, recipient) pair, used only for
///     diagnostics and for the outbound queue's dedupe key; actual replay
///     protection uses the ratchet header
///   - `signature` — Ed25519 over `canonicalHeader()`
///   - `ratchet` — Double Ratchet header, present on every v3 message
///   - `prekey` — X3DH header, present only on the initiator's first
///     message in a new session
class EncryptedEnvelope {
  static const version = 3;

  final String messageId;
  final String fromDeviceId;
  final String toDeviceId;
  final String nonce;
  final String ciphertext;
  final String tag;
  final int counter;
  final String signature;
  final Map<String, dynamic>? ratchet;
  final Map<String, dynamic>? prekey;

  const EncryptedEnvelope({
    required this.messageId,
    required this.fromDeviceId,
    required this.toDeviceId,
    required this.nonce,
    required this.ciphertext,
    required this.tag,
    required this.counter,
    required this.signature,
    this.ratchet,
    this.prekey,
  });

  bool get isSessionInit => prekey != null;

  Map<String, dynamic> toJson() => {
        'v': version,
        'message_id': messageId,
        'from': fromDeviceId,
        'to': toDeviceId,
        'nonce': nonce,
        'ct': ciphertext,
        'tag': tag,
        'counter': counter,
        'sig': signature,
        if (ratchet != null) 'ratchet': ratchet,
        if (prekey != null) 'prekey': prekey,
      };

  static EncryptedEnvelope fromJson(Map<String, dynamic> j) {
    final v = j['v'] as int? ?? 1;
    if (v != version) {
      throw FormatException('unsupported envelope version $v');
    }
    return EncryptedEnvelope(
      messageId: j['message_id'] as String,
      fromDeviceId: j['from'] as String,
      toDeviceId: j['to'] as String,
      nonce: j['nonce'] as String,
      ciphertext: j['ct'] as String,
      tag: j['tag'] as String,
      counter: j['counter'] as int,
      signature: j['sig'] as String,
      ratchet: j['ratchet'] as Map<String, dynamic>?,
      prekey: j['prekey'] as Map<String, dynamic>?,
    );
  }

  /// The byte string that the sender signs and the receiver verifies.
  /// It is also the AES-GCM associated data, so tampering any field
  /// invalidates both the signature and the tag.
  ///
  /// Every field is length-prefixed (4-byte big-endian) to remove any
  /// concatenation ambiguity. Adding or changing a field here is a
  /// protocol break: it invalidates every existing signature.
  Uint8List canonicalHeader() {
    final b = BytesBuilder();
    void add(String s) {
      final bytes = utf8.encode(s);
      final len = ByteData(4)..setUint32(0, bytes.length, Endian.big);
      b.add(len.buffer.asUint8List());
      b.add(bytes);
    }

    add(messageId);
    add(fromDeviceId);
    add(toDeviceId);
    add(nonce);
    add(counter.toString());

    if (ratchet != null) {
      add(ratchet!['dh'] as String);
      add((ratchet!['n'] as int).toString());
      add((ratchet!['pn'] as int).toString());
    }

    if (prekey != null) {
      add(prekey!['ik'] as String);
      add(prekey!['ek'] as String);
      add((prekey!['spk_id'] as int).toString());
      final opk = prekey!['opk_id'];
      if (opk != null) add(opk.toString());
    }

    return b.toBytes();
  }
}