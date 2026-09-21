/// A rendered chat message. Distinct from `EncryptedEnvelope` (the wire
/// form) and `OutboundMessage` (the delivery-state record). This is what
/// the UI binds to.
class Message {
  /// Equals `EncryptedEnvelope.messageId` for both incoming and outgoing.
  /// The UI uses this to look up outbound state for sent messages.
  final String id;

  final String conversationId; // peer device id, or group id
  final bool isGroup;
  final String? senderDeviceId; // null for messages we sent
  final String text;
  final bool isMe;
  final DateTime timestamp;

  const Message({
    required this.id,
    required this.conversationId,
    required this.isGroup,
    required this.senderDeviceId,
    required this.text,
    required this.isMe,
    required this.timestamp,
  });

  Message copyWith({String? text}) => Message(
        id: id,
        conversationId: conversationId,
        isGroup: isGroup,
        senderDeviceId: senderDeviceId,
        text: text ?? this.text,
        isMe: isMe,
        timestamp: timestamp,
      );
}