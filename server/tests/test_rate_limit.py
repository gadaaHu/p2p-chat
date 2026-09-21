from tests.helpers import DeviceFixture
import uuid


def test_ice_rate_limit_generous(client):
    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    # ICE limit is 200/min. 50 must all succeed.
    for _ in range(50):
        r = a.post_json(
            client,
            "/v1/signaling",
            {
                "to_device_id": b.device_id,
                "signal_id": uuid.uuid4().hex,
                "kind": "ice",
                "payload": "{}",
            },
        )
        assert r.status_code == 201


def test_sdp_rate_limit_strict(client):
    from app.config import settings

    a = DeviceFixture()
    b = DeviceFixture()
    a.register(client)
    b.register(client)

    # Exceed the SDP limit and confirm a 429.
    for _ in range(settings.rate_limit_sdp_per_min):
        r = a.post_json(
            client,
            "/v1/signaling",
            {
                "to_device_id": b.device_id,
                "signal_id": uuid.uuid4().hex,
                "kind": "offer",
                "payload": "{}",
            },
        )
        assert r.status_code == 201

    r = a.post_json(
        client,
        "/v1/signaling",
        {
            "to_device_id": b.device_id,
            "signal_id": uuid.uuid4().hex,
            "kind": "offer",
            "payload": "{}",
        },
    )
    assert r.status_code == 429