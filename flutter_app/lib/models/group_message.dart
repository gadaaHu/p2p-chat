
class GroupMessage {
  final String messageId;
  final String groupId;
  final String senderDeviceId;
  final String keyId; // which sender key version encrypted this
  final int senderSeq; // monotonic per (sender, group)
  final int sentAtMs;
  final String content;

  const GroupMessage({
    required this.messageId,
    required this.groupId,
    required this.senderDeviceId,
    required this.keyId,
    required this.senderSeq,
    required this.sentAtMs,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'type': 'group-msg',
        'group_id': groupId,
        'message_id': messageId,
        'sender': senderDeviceId,
        'key_id': keyId,
        'sender_seq': senderSeq,
        'sent_at': sentAtMs,
        'content': content,
      };
}