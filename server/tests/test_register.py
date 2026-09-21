from tests.helpers import DeviceFixture


def test_register_succeeds(client):
    d = DeviceFixture()
    d.register(client)

    r = client.get("/v1/version")
    assert r.status_code == 200


def test_register_is_idempotent(client):
    d = DeviceFixture()
    d.register(client)
    d.register(client)  # same key, same id


def test_register_rejects_wrong_signature(client):
    d = DeviceFixture()
    r = client.post(
        "/v1/register",
        json={
            "device_id": d.device_id,
            "pubkey_ed25519": d.ed_public,
            "pubkey_x25519": d.x_public,
            "signature": "A" * 88,
        },
    )
    assert r.status_code == 401