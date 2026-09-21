import 'dart:convert';
import 'dart:typed_data';

/// The decrypted plaintext of a receipt envelope. Two shapes share one
/// envelope: `delivery` (single messageId) and `read` (batch of IDs).
class MessageReceipt {
  final String kind; // "receipt" | "read"
  final List<String> messageIds;
  final int atMs;

  const MessageReceipt({
    required this.kind,
    required this.messageIds,
    required this.atMs,
  });

  bool get isRead => kind == 'read';

  Map<String, dynamic> toJson() => {
        'type': kind,
        'ack_for': messageIds,
        'ack_at': atMs,
      };

  static MessageReceipt? tryParse(Uint8List plaintext) {
    try {
      final j = jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>;
      final type = j['type'];
      if (type != 'receipt' && type != 'read') return null;
      final ids = j['ack_for'];
      if (ids is! List) return null;
      final at = j['ack_at'];
      if (at is! int) return null;
      return MessageReceipt(
        kind: type as String,
        messageIds: ids.cast<String>(),
        atMs: at,
      );
    } catch (_) {
      return null;
    }
  }
}