/// Tunables and magic values that are shared across the app. Anything
/// protocol-related lives here so it is impossible to have two files
/// disagree on the wire format or a bound.
class AppConstants {
  AppConstants._();

  // ─── Wire format ──────────────────────────────────────────────────────
  static const envelopeVersion = 3;
  static const blobVersionTag = 'p2p1';

  // ─── Ratchet ──────────────────────────────────────────────────────────
  static const maxSkippedKeys = 500;
  static const maxSkipWindow = 1000;

  // ─── Nonce ────────────────────────────────────────────────────────────
  static const nonceCounterBatchSize = 1000;
  static const noncePrefixBytes = 4;
  static const nonceCounterBytes = 8;

  // ─── Outbound queue ───────────────────────────────────────────────────
  static const outboundBaseBackoffMs = 2000;
  static const outboundMaxBackoffMs = 300 * 1000;
  static const outboundExpiryMs = 7 * 24 * 3600 * 1000;
  static const outboundMaxAttempts = 200;

  // ─── Read receipts ────────────────────────────────────────────────────
  static const readFlushDelayMs = 800;

  // ─── Prekeys ──────────────────────────────────────────────────────────
  static const spkRotateDays = 7;
  static const opkBatchSize = 100;
  static const opkReplenishThreshold = 20;
  static const spkRetainVersions = 3;

  // ─── Safety numbers ───────────────────────────────────────────────────
  static const safetyNumberGroups = 12;
  static const safetyNumberDigitsPerGroup = 5;

  // ─── Message storage ──────────────────────────────────────────────────
  static const maxMessagesPerConversation = 5000;
  static const maxDedupeEntries = 1000;

  // ─── Replay guard ─────────────────────────────────────────────────────
  static const replayWindowSize = 256;

  // ─── WebRTC ───────────────────────────────────────────────────────────
  static const iceGatheringTimeout = Duration(seconds: 15);
  static const dataChannelOpenTimeout = Duration(seconds: 30);
  static const dataChannelLabel = 'chat';

  // ─── Pairing ──────────────────────────────────────────────────────────
  static const pairingTimeout = Duration(minutes: 3);
}