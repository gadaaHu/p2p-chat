import 'dart:convert';

import 'encrypted_envelope.dart';

/// The lifecycle of a message we sent.
enum MessageState {
  /// Built locally. No peer has acknowledged custody.
  queued,

  /// P2P send succeeded, or the message reached the peer's data channel.
  /// Waiting for a delivery receipt.
  relayed,

  /// Peer confirmed decrypt + persist via a signed receipt.
  delivered,

  /// Peer confirmed the message was displayed.
  read,

  /// TTL expired, or the peer rejected the message as poison.
  failed,

  /// Peer rejected our identity. Requires user action.
  blocked,
}

/// A record of a message we are responsible for delivering. Persisted
/// per message so a crash on one cannot corrupt another.
///
/// For group messages, one logical message produces N rows, one per
/// recipient. They share a `logicalId`; the UI aggregates over it.
class OutboundMessage {
  final String messageId;
  final String peerDeviceId;

  /// Preview text. The authoritative ciphertext is in [envelope].
  /// Stored for the UI and for local search; the plaintext never leaves
  /// the device.
  final String plaintext;

  final EncryptedEnvelope envelope;
  final int createdAt;
  final MessageState state;

  /// Number of delivery attempts. Reset to 0 on successful send.
  final int attempts;

  /// Next time to attempt delivery, unix milliseconds. Only meaningful
  /// while state == queued.
  final int nextAttemptAt;

  final String? lastError;
  final int? deliveredAt;

  /// Set for group fan-out. Multiple rows share this ID (one per
  /// recipient). Null for 1:1 messages.
  final String? logicalId;

  /// The recipient this fan-out row is for. Null for 1:1.
  final String? fanoutRecipientId;

  const OutboundMessage({
    required this.messageId,
    required this.peerDeviceId,
    required this.plaintext,
    required this.envelope,
    required this.createdAt,
    required this.state,
    required this.attempts,
    required this.nextAttemptAt,
    this.lastError,
    this.deliveredAt,
    this.logicalId,
    this.fanoutRecipientId,
  });

  OutboundMessage copyWith({
    MessageState? state,
    int? attempts,
    int? nextAttemptAt,
    String? lastError,
    bool clearError = false,
    int? deliveredAt,
  }) =>
      OutboundMessage(
        messageId: messageId,
        peerDeviceId: peerDeviceId,
        plaintext: plaintext,
        envelope: envelope,
        createdAt: createdAt,
        state: state ?? this.state,
        attempts: attempts ?? this.attempts,
        nextAttemptAt: nextAttemptAt ?? this.nextAttemptAt,
        lastError: clearError ? null : (lastError ?? this.lastError),
        deliveredAt: deliveredAt ?? this.deliveredAt,
        logicalId: logicalId,
        fanoutRecipientId: fanoutRecipientId,
      );

  bool get isTerminal =>
      state == MessageState.read ||
      state == MessageState.failed ||
      state == MessageState.blocked;

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'peer': peerDeviceId,
        'plaintext': plaintext,
        'envelope': envelope.toJson(),
        'created_at': createdAt,
        'state': state.name,
        'attempts': attempts,
        'next_attempt_at': nextAttemptAt,
        if (lastError != null) 'last_error': lastError,
        if (deliveredAt != null) 'delivered_at': deliveredAt,
        if (logicalId != null) 'logical_id': logicalId,
        if (fanoutRecipientId != null) 'fanout_recipient': fanoutRecipientId,
      };

  static OutboundMessage fromJson(Map<String, dynamic> j) => OutboundMessage(
        messageId: j['message_id'] as String,
        peerDeviceId: j['peer'] as String,
        plaintext: j['plaintext'] as String,
        envelope: EncryptedEnvelope.fromJson(
          j['envelope'] as Map<String, dynamic>,
        ),
        createdAt: j['created_at'] as int,
        state: MessageState.values.byName(j['state'] as String),
        attempts: j['attempts'] as int,
        nextAttemptAt: j['next_attempt_at'] as int,
        lastError: j['last_error'] as String?,
        deliveredAt: j['delivered_at'] as int?,
        logicalId: j['logical_id'] as String?,
        fanoutRecipientId: j['fanout_recipient'] as String?,
      );

  /// Aggregated delivery status across all rows sharing a [logicalId].
  /// Used by group message status rendering.
  static GroupDeliverySummary summarize(List<OutboundMessage> rows) {
    var delivered = 0;
    var read = 0;
    var failed = 0;
    var blocked = 0;
    for (final m in rows) {
      switch (m.state) {
        case MessageState.read:
          read++;
          delivered++;
          break;
        case MessageState.delivered:
          delivered++;
          break;
        case MessageState.failed:
          failed++;
          break;
        case MessageState.blocked:
          blocked++;
          break;
        case MessageState.queued:
        case MessageState.relayed:
          break;
      }
    }
    return GroupDeliverySummary(
      total: rows.length,
      delivered: delivered,
      read: read,
      failed: failed,
      blocked: blocked,
    );
  }

  static String encodeList(List<OutboundMessage> rows) =>
      jsonEncode(rows.map((m) => m.toJson()).toList());

  static List<OutboundMessage> decodeList(String raw) {
    final list = jsonDecode(raw) as List;
    return list
        .map((e) => OutboundMessage.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}

class GroupDeliverySummary {
  final int total;
  final int delivered;
  final int read;
  final int failed;
  final int blocked;

  const GroupDeliverySummary({
    required this.total,
    required this.delivered,
    required this.read,
    required this.failed,
    required this.blocked,
  });

  bool get allRead => read == total && total > 0;
  bool get allDelivered => delivered == total && total > 0;
  bool get anyFailure => failed > 0 || blocked > 0;
}