# p2p_chat

End-to-end encrypted messaging over WebRTC with a FastAPI relay for offline delivery.

The relay never sees plaintext. Every message is X3DH + Double Ratchet encrypted
and Ed25519 signed. Group chat uses per-sender symmetric ratchets. Identity is
pinned on first contact, verified by comparing safety numbers.

## Wire protocol

- Envelope version: **v3**
- 1:1: X3DH → Double Ratchet, AES-256-GCM, Ed25519 signatures
- Groups: sender-key chain ratchet, epoch-guarded membership
- Identity: TOFU pin + safety number, explicit rotation UX

See [`PROTOCOL.md`](PROTOCOL.md) and [`SECURITY.md`](SECURITY.md).

## Quickstart

Server:

```bash
cd server
python -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
alembic upgrade head
uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Client:

```bash
cd flutter_app
flutter pub get
flutter test
flutter run --dart-define=RELAY_BASE_URL=http://127.0.0.1:8000
```

## Status

Alpha. Wire format may change before 1.0.

## License

MIT
