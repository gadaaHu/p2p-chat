import json
import uuid

from tests.helpers import DeviceFixture


def test_chat_envelope_delivered_then_removed(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    mid = uuid.uuid4().hex
    r = a.post_json(
        client,
        "/v1/signaling",
        {
            "to_device_id": b.device_id,
            "signal_id": mid,
            "kind": "chat",
            "payload": json.dumps({"message_id": mid, "content": "hi"}),
        },
    )
    assert r.status_code == 201

    signals = b.get(client, f"/v1/signaling/{b.device_id}").json()["signals"]
    assert len(signals) == 1
    assert signals[0]["kind"] == "chat"

    headers = b.headers("POST", f"/v1/signaling/{b.device_id}/ack")
    client.post(
        f"/v1/signaling/{b.device_id}/ack?signal_id={mid}", headers=headers,
    )

    signals = b.get(client, f"/v1/signaling/{b.device_id}").json()["signals"]
    assert signals == []


def test_chat_uses_long_ttl(client):
    from app.config import settings

    assert settings.chat_ttl_seconds > settings.ice_ttl_seconds * 100