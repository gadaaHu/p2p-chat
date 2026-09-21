# Changelog

## [Unreleased]

### Fixed

- Serialize nonce allocation per key to prevent reuse under concurrency.
- Derive pairwise `counter` from ratchet state instead of a parallel counter,
  so app restarts do not trip the receiver's replay guard.
- Delete ratchet sessions when an identity is forgotten or rotated.

### Added

- Alembic migrations for the relay schema.
- Structured logging on every signaling transition.
- Concurrent nonce test, counter-restart test.
- Integration test runs in CI on `ubuntu-22.04` under `xvfb-run`.

## [0.1.0]

### Added

- X3DH + Double Ratchet for 1:1 sessions.
- Group chat with per-sender chain ratchet.
- Read receipts and unread tracking.
- Outbound queue with exponential backoff.
- Offline relay for chat envelopes.
- Safety numbers, TOFU pinning, explicit rotation UX.

### Breaking

- Envelope v3. v1 and v2 are rejected.
- `KeyExchangeService` removed; sessions come from X3DH + Double Ratchet.
