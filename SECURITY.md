# Security

## Threat model

**In scope**

- Compromised relay (active MITM, replay, reorder, drop)
- Passive network observer
- Malicious peer attempting impersonation
- Peer re-injecting old messages
- Client flooding the relay

**Out of scope**

- Compromised endpoint (malware on device)
- Traffic analysis (message size and timing metadata visible to relay)
- Network-layer DoS
- User error (pasting wrong safety number)
- OS-level side channels

## What the relay sees

- `from`, `to`, `message_id`, `kind` (offer / answer / ice / chat / bye)
- Ciphertext length and timing
- Public prekey material on session init

## What the relay does not see

- Message plaintext
- Whether a message is chat, receipt, sender-key distribution, or group content
- Group membership
- Sender keys
- Read or delivered state

## Primitives

- Ed25519 — signatures, identity
- X25519 — X3DH, DH ratchet
- AES-256-GCM — message encryption (12-byte nonce, 16-byte tag)
- HKDF-SHA256 — root key derivation
- HMAC-SHA256 — chain key derivation
- SHA-512 — safety numbers

## Invariants (each backed by a test)

1. No `(key, nonce)` reuse. Concurrent encryption safe.
2. Replay is rejected by a bounded sliding window.
3. Dedupe survives a crash between persist and ACK.
4. X3DH initiator and responder agree on `SK`.
5. Double Ratchet handles out-of-order and interleaved messages.
6. A key change is never silently accepted.
7. `read` is only reachable from `delivered`.
8. Messages are persisted before ACK.
9. Nonces are never reused under concurrent encryption.
10. `counter` derives from ratchet state, so restarts do not break the
    receiver's replay guard.

## Reporting

<security@example.invalid> (PGP key in `docs/PGP.txt`). No public issues.
