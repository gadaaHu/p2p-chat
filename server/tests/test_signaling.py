import uuid

from tests.helpers import DeviceFixture


def test_send_poll_ack_roundtrip(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    signal_id = uuid.uuid4().hex
    r = a.post_json(
        client,
        "/v1/signaling",
        {
            "to_device_id": b.device_id,
            "signal_id": signal_id,
            "kind": "offer",
            "payload": '{"sdp":"v=0"}',
        },
    )
    assert r.status_code == 201, r.text

    r = b.get(client, f"/v1/signaling/{b.device_id}")
    assert r.status_code == 200
    signals = r.json()["signals"]
    assert len(signals) == 1
    assert signals[0]["signal_id"] == signal_id

    headers = b.headers(
        "POST", f"/v1/signaling/{b.device_id}/ack",
    )
    r = client.post(
        f"/v1/signaling/{b.device_id}/ack?signal_id={signal_id}",
        headers=headers,
    )
    assert r.json() == {"ok": True, "deleted": True}

    # Second ack is idempotent.
    headers = b.headers("POST", f"/v1/signaling/{b.device_id}/ack")
    r = client.post(
        f"/v1/signaling/{b.device_id}/ack?signal_id={signal_id}",
        headers=headers,
    )
    assert r.json() == {"ok": True, "deleted": False}


def test_cannot_poll_another_inbox(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    r = a.get(client, f"/v1/signaling/{b.device_id}")
    assert r.status_code == 403


def test_cannot_ack_another_inbox(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    signal_id = uuid.uuid4().hex
    a.post_json(
        client,
        "/v1/signaling",
        {
            "to_device_id": b.device_id,
            "signal_id": signal_id,
            "kind": "offer",
            "payload": "{}",
        },
    )

    headers = a.headers("POST", f"/v1/signaling/{b.device_id}/ack")
    r = client.post(
        f"/v1/signaling/{b.device_id}/ack?signal_id={signal_id}",
        headers=headers,
    )
    assert r.status_code == 403


def test_sender_spoofing_rejected(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    body = b.post_json(
        client,
        "/v1/signaling",
        {
            "to_device_id": b.device_id,
            "signal_id": uuid.uuid4().hex,
            "kind": "offer",
            "payload": "{}",
        },
    )
    # b signs its own request, but claims X-Device-Id=a
    assert body.status_code == 401


def test_payload_too_large(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    r = a.post_json(
        client,
        "/v1/signaling",
        {
            "to_device_id": b.device_id,
            "signal_id": uuid.uuid4().hex,
            "kind": "chat",
            "payload": "x" * 100_000,
        },
    )
    assert r.status_code == 413