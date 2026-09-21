from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey

from app.security import b64e
from tests.helpers import DeviceFixture


def _make_spk(fixture: DeviceFixture) -> tuple[int, str, str]:
    kp = X25519PrivateKey.generate()
    pub = b64e(kp.public_key().public_bytes_raw())
    sig = b64e(fixture.ed_private.sign(f"spk:{pub}".encode()))
    return 1, pub, sig


def _make_opks(n: int) -> list[dict]:
    return [
        {
            "opk_id": i,
            "public": b64e(
                X25519PrivateKey.generate().public_key().public_bytes_raw()
            ),
        }
        for i in range(1, n + 1)
    ]


def test_upload_and_fetch_bundle(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    spk_id, spk_pub, spk_sig = _make_spk(b)
    r = b.post_json(
        client,
        "/v1/prekeys",
        {
            "spk_id": spk_id,
            "spk_public": spk_pub,
            "spk_signature": spk_sig,
            "opks": _make_opks(3),
        },
    )
    assert r.status_code == 201, r.text

    first = a.get(client, f"/v1/prekeys/{b.device_id}").json()
    assert first["spk_public"] == spk_pub
    assert first["opk_id"] == 1

    second = a.get(client, f"/v1/prekeys/{b.device_id}").json()
    assert second["opk_id"] == 2

    third = a.get(client, f"/v1/prekeys/{b.device_id}").json()
    assert third["opk_id"] == 3

    fourth = a.get(client, f"/v1/prekeys/{b.device_id}").json()
    assert fourth["opk_id"] is None


def test_bad_spk_signature_rejected(client):
    a = DeviceFixture()
    a.register(client)

    spk_id, spk_pub, _ = _make_spk(a)
    bad_sig = b64e(a.ed_private.sign(b"not-the-spk"))

    r = a.post_json(
        client,
        "/v1/prekeys",
        {
            "spk_id": spk_id,
            "spk_public": spk_pub,
            "spk_signature": bad_sig,
            "opks": [],
        },
    )
    assert r.status_code == 400


def test_opk_count_is_private(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    r = a.get(client, f"/v1/prekeys/{b.device_id}/count")
    assert r.status_code == 403