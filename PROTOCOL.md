# p2p_chat Protocol v3

## 1. Envelope

```json
{
  "v": 3,
  "message_id": "<hex>",
  "from": "<device_id>",
  "to": "<device_id>",
  "nonce": "<base64 12>",
  "ct": "<base64>",
  "tag": "<base64 16>",
  "counter": <int>,
  "sig": "<base64 64>",
  "ratchet": { "dh": "<base64>", "n": <int>, "pn": <int> },
  "prekey":  { "ik": "<base64>", "ek": "<base64>",
               "spk_id": <int>, "opk_id": <int|null> }
}
```

`prekey` is present only on the initiator's first message. `ratchet` is always present.

## 2. Canonical header

Fields are length-prefixed (4-byte big-endian) and concatenated:

```
message_id || from || to || nonce || counter
  || ratchet.dh || ratchet.n || ratchet.pn
  [ || prekey.ik || prekey.ek || prekey.spk_id || prekey.opk_id ]
```

This byte string is:

- signed with Ed25519 by the sender
- passed as AES-GCM AAD

Tampering any field invalidates both the signature and the tag.

## 3. X3DH

Bundle from `GET /v1/prekeys/{device_id}`:

```
IK_ed (Ed25519), IK_x (X25519), SPK_x, SPK_sig, [OPK_x]
```

Verify: `Ed25519_verify(IK_ed, "spk:" + base64(SPK_x), SPK_sig)`.

Secret:

```
DH1 = DH(IKa, SPKb)
DH2 = DH(EKa, IKb)
DH3 = DH(EKa, SPKb)
DH4 = DH(EKa, OPKb)   if OPKb present
SK  = HKDF-SHA256(0xFF*32 || DH1 || DH2 || DH3 || DH4)
```

`SK` seeds the Double Ratchet.

## 4. Double Ratchet

Standard Signal construction.

- Root chain: `(RK, CK) = KDF_RK(RK, DH(DHs, DHr))`
- Chain: `(CK, MK) = KDF_CK(CK)` using HMAC-SHA256 with constants 0x01 and 0x02.
- Skip cache: bounded to 500 keys, LRU.
- Maximum skipped messages per chain: 1000.

## 5. Groups

Each member owns a sender key per group generation. The chain advances per
message using `KDF_CK`. Membership changes bump `epoch`; the sender key
rotates; the old key decrypts only messages sent before the change.

Sender-key distribution and group-state updates travel inside pairwise
envelopes as plaintext frames:

```
{ "type": "sender-key",  "group_id": ..., "key_id": ..., "key": ..., "version": ... }
{ "type": "group-state", "group_id": ..., "epoch": ..., "members": [...] }
{ "type": "group-msg",   "group_id": ..., "key_id": ..., "sender_seq": ...,
  "ct": ..., "nonce": ..., "tag": ... }
```

## 6. Receipts

```
{ "type": "receipt", "ack_for": ["<message_id>"], "ack_at": <unix_ms> }
{ "type": "read",    "ack_for": ["<message_id>", ...], "ack_at": <unix_ms> }
```

Receipts are signed and encrypted like chat messages.

## 7. Relay API

Signature scheme for every request:

```
signed = METHOD "|" path "|" device_id "|" ts "|" sha256_hex(body)
X-Signature = Ed25519(identity_key, signed)
```

Headers: `X-Device-Id`, `X-Timestamp` (unix seconds), `X-Signature`.
Timestamp must be within ±120s of server time.

| Method | Path | Purpose |
| --- | --- | --- |
| POST | `/v1/register` | Publish identity keys |
| POST | `/v1/prekeys` | Upload SPK + OPKs |
| GET | `/v1/prekeys/{id}` | Fetch bundle |
| GET | `/v1/prekeys/{id}/count` | Own OPK status |
| POST | `/v1/signaling` | Send SDP / ICE / chat |
| GET | `/v1/signaling/{id}?since=N` | Poll inbox |
| POST | `/v1/signaling/{id}/ack?signal_id=X` | Idempotent delete |

TTLs: SDP 5 min, ICE 60 s, chat 7 days.
Rate limits per kind per device per minute: SDP 10, ICE 200, chat 30.

## 8. State machines

### Outbound message

```
queued → relayed → delivered → read
   │        │
   └────────┴────→ failed | blocked
```

- `queued` — not yet accepted by relay or peer
- `relayed` — relay has custody, or P2P send succeeded
- `delivered` — peer confirmed decrypt + persist
- `read` — peer confirmed display
- `failed` — TTL expired
- `blocked` — peer rejected our identity

`read` is only reachable from `delivered`.

### Identity pin

```
unknown → pinned (TOFU)
pinned  → verified (user compared safety number)
pinned  → changed  (key mismatch, requires user action)
```

On `changed`, sessions are invalidated, queued messages are blocked.

## 9. Nonce strategy

- Pairwise envelopes: per-peer counter with batch reservation. 1000 values
  reserved per persist. Never reuses `(key, nonce)` across crashes because
  the batch is persisted before its first use.
- Group messages: random 12-byte nonce per message. Sender key rotation
  bounds the birthday risk.

## 10. Version history

- v1 — initial pairwise. Not shipped.
- v2 — Double Ratchet added. Not shipped.
- v3 — X3DH prekeys added. Current.
