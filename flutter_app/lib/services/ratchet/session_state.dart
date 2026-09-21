import 'dart:convert';
import 'dart:typed_data';

class SkippedKey {
  final Uint8List dhPublic; // the DHr at the time of skip
  final int n;              // message number
  final Uint8List messageKey;

  const SkippedKey({
    required this.dhPublic,
    required this.n,
    required this.messageKey,
  });

  String get id => '${base64Encode(dhPublic)}|$n';
}

class RatchetSession {
  /// Our current DH key pair (private + public).
  final Uint8List dhSelfPrivate;
  final Uint8List dhSelfPublic;

  /// Their current DH public key. Null before the first received message.
  final Uint8List? dhRemote;

  final Uint8List rootKey;

  /// Sending chain key. Null until the first DH ratchet from our side.
  final Uint8List? chainKeySend;

  /// Receiving chain key. Null until the first received message.
  final Uint8List? chainKeyRecv;

  final int nSend;
  final int nRecv;
  final int pn;

  /// Bounded skipped-key cache. Keyed on (dhPublic, n).
  final Map<String, SkippedKey> skipped;

  /// Message numbers of skipped keys, in insertion order. Used for LRU
  /// eviction when the cache exceeds [maxSkipped].
  final List<String> skippedOrder;

  static const maxSkipped = 500;

  const RatchetSession({
    required this.dhSelfPrivate,
    required this.dhSelfPublic,
    required this.dhRemote,
    required this.rootKey,
    required this.chainKeySend,
    required this.chainKeyRecv,
    required this.nSend,
    required this.nRecv,
    required this.pn,
    required this.skipped,
    required this.skippedOrder,
  });

  RatchetSession copyWith({
    Uint8List? dhSelfPrivate,
    Uint8List? dhSelfPublic,
    Uint8List? dhRemote,
    bool clearDhRemote = false,
    Uint8List? rootKey,
    Uint8List? chainKeySend,
    bool clearChainKeySend = false,
    Uint8List? chainKeyRecv,
    bool clearChainKeyRecv = false,
    int? nSend,
    int? nRecv,
    int? pn,
    Map<String, SkippedKey>? skipped,
    List<String>? skippedOrder,
  }) =>
      RatchetSession(
        dhSelfPrivate: dhSelfPrivate ?? this.dhSelfPrivate,
        dhSelfPublic: dhSelfPublic ?? this.dhSelfPublic,
        dhRemote: clearDhRemote ? null : (dhRemote ?? this.dhRemote),
        rootKey: rootKey ?? this.rootKey,
        chainKeySend:
            clearChainKeySend ? null : (chainKeySend ?? this.chainKeySend),
        chainKeyRecv:
            clearChainKeyRecv ? null : (chainKeyRecv ?? this.chainKeyRecv),
        nSend: nSend ?? this.nSend,
        nRecv: nRecv ?? this.nRecv,
        pn: pn ?? this.pn,
        skipped: skipped ?? this.skipped,
        skippedOrder: skippedOrder ?? this.skippedOrder,
      );

  Map<String, dynamic> toJson() => {
        'dh_self_priv': base64Encode(dhSelfPrivate),
        'dh_self_pub': base64Encode(dhSelfPublic),
        if (dhRemote != null) 'dh_remote': base64Encode(dhRemote!),
        'root_key': base64Encode(rootKey),
        if (chainKeySend != null) 'ck_send': base64Encode(chainKeySend!),
        if (chainKeyRecv != null) 'ck_recv': base64Encode(chainKeyRecv!),
        'n_send': nSend,
        'n_recv': nRecv,
        'pn': pn,
        'skipped': {
          for (final k in skipped.values)
            k.id: {
              'dh': base64Encode(k.dhPublic),
              'n': k.n,
              'mk': base64Encode(k.messageKey),
            },
        },
        'skipped_order': skippedOrder,
      };

  static RatchetSession fromJson(Map<String, dynamic> j) {
    final skipped = <String, SkippedKey>{};
    (j['skipped'] as Map<String, dynamic>? ?? {}).forEach((id, v) {
      final m = v as Map<String, dynamic>;
      skipped[id] = SkippedKey(
        dhPublic: base64Decode(m['dh'] as String),
        n: m['n'] as int,
        messageKey: base64Decode(m['mk'] as String),
      );
    });
    return RatchetSession(
      dhSelfPrivate: base64Decode(j['dh_self_priv'] as String),
      dhSelfPublic: base64Decode(j['dh_self_pub'] as String),
      dhRemote: j['dh_remote'] == null
          ? null
          : base64Decode(j['dh_remote'] as String),
      rootKey: base64Decode(j['root_key'] as String),
      chainKeySend: j['ck_send'] == null
          ? null
          : base64Decode(j['ck_send'] as String),
      chainKeyRecv: j['ck_recv'] == null
          ? null
          : base64Decode(j['ck_recv'] as String),
      nSend: j['n_send'] as int,
      nRecv: j['n_recv'] as int,
      pn: j['pn'] as int,
      skipped: skipped,
      skippedOrder: (j['skipped_order'] as List).cast<String>(),
    );
  }
}