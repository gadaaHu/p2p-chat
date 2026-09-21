import hashlib
import json
import time
import uuid
from typing import Any

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

from app.security import b64e


class DeviceFixture:
    def __init__(self):
        self.device_id = uuid.uuid4().hex[:16]
        self.ed_private = Ed25519PrivateKey.generate()
        self.x_private = X25519PrivateKey.generate()
        self.ed_public = b64e(self.ed_private.public_key().public_bytes_raw())
        self.x_public = b64e(self.x_private.public_key().public_bytes_raw())

    def register(self, client) -> None:
        message = (
            f"register:{self.device_id}:{self.ed_public}:{self.x_public}".encode()
        )
        r = client.post(
            "/v1/register",
            json={
                "device_id": self.device_id,
                "pubkey_ed25519": self.ed_public,
                "pubkey_x25519": self.x_public,
                "signature": b64e(self.ed_private.sign(message)),
            },
        )
        assert r.status_code == 201, r.text

    def headers(
        self,
        method: str,
        path: str,
        body: bytes = b"",
    ) -> dict[str, str]:
        ts = int(time.time())
        body_hash = hashlib.sha256(body).hexdigest()
        signed = f"{method}|{path}|{self.device_id}|{ts}|{body_hash}".encode()
        return {
            "X-Device-Id": self.device_id,
            "X-Timestamp": str(ts),
            "X-Signature": b64e(self.ed_private.sign(signed)),
        }

    def post_json(self, client, path: str, payload: Any) -> Any:
        body = json.dumps(payload).encode()
        headers = self.headers("POST", path, body)
        headers["Content-Type"] = "application/json"
        return client.post(path, content=body, headers=headers)

    def get(self, client, path: str) -> Any:
        headers = self.headers("GET", path)
        return client.get(path, headers=headers)