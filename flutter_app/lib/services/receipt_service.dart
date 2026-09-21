import 'dart:convert';
import 'dart:typed_data';

import '../models/message_receipt.dart';

class ReceiptService {
  ReceiptService();

  Uint8List buildDeliveryPlaintext(String messageId) {
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'type': 'receipt',
      'ack_for': [messageId],
      'ack_at': DateTime.now().millisecondsSinceEpoch,
    })));
  }

  Uint8List buildReadPlaintext(List<String> messageIds) {
    return Uint8List.fromList(utf8.encode(jsonEncode({
      'type': 'read',
      'ack_for': messageIds,
      'ack_at': DateTime.now().millisecondsSinceEpoch,
    })));
  }

  MessageReceipt? parse(Uint8List plaintext) => MessageReceipt.tryParse(plaintext);
}